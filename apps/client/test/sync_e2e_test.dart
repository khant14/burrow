// End-to-end sync test: a real burrow-server and two (or three) app profiles.
//
// Build first, from the repo root:
//   cargo build -p rust_lib_burrow -p burrow-server
// Then, from apps/client:
//   flutter test test/sync_e2e_test.dart
// Skips itself when the binaries aren't built.
import 'dart:io';

import 'package:burrow/models/host.dart';
import 'package:burrow/src/rust/frb_generated.dart';
import 'package:burrow/state/app_state.dart';
import 'package:burrow/state/sync.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

final _root = Directory.current.parent.parent.path;
final _lib = File('$_root/target/debug/librust_lib_burrow.so');
final _server = File('$_root/target/debug/burrow-server');
const _port = 18431;
const _url = 'http://127.0.0.1:$_port';

Process? _proc;
late Directory _tmp;

Future<void> _startServer() async {
  _proc = await Process.start(
    _server.path,
    [],
    environment: {
      'BURROW_DB': '${_tmp.path}/server.db',
      'BURROW_ADDR': '127.0.0.1:$_port',
    },
  );
  for (var i = 0; i < 100; i++) {
    try {
      final s = await Socket.connect('127.0.0.1', _port);
      s.destroy();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  throw StateError('server did not start');
}

Future<void> _stopServer() async {
  _proc?.kill();
  await _proc?.exitCode;
  _proc = null;
}

class Device {
  Device._(this.app, this.sync);
  final AppState app;
  final SyncService sync;

  static Future<Device> open(String name) async {
    final app = await AppState.load(path: '${_tmp.path}/$name.json');
    return Device._(
      app,
      SyncService(app, secrets: MemorySecrets(), auto: false),
    );
  }

  Host add(String label) {
    final h = Host(id: newId(), label: label, hostname: '$label.lan');
    app.upsertHost(h);
    return h;
  }

  Host byLabel(String l) => app.hosts.firstWhere((h) => h.label == l);
  Set<String> get labels => app.hosts.map((h) => h.label).toSet();
}

void main() {
  final ready = _lib.existsSync() && _server.existsSync();

  setUpAll(() async {
    if (!ready) return;
    _tmp = Directory.systemTemp.createTempSync('burrow-sync');
    await RustLib.init(externalLibrary: ExternalLibrary.open(_lib.path));
    await _startServer();
  });
  tearDownAll(() async {
    if (!ready) return;
    await _stopServer();
    _tmp.deleteSync(recursive: true);
  });

  test('hosts sync between devices without losing local data', () async {
    const email = 'Someone@Example.com';
    const pw = 'correct horse battery';

    // Two devices that already have hosts before sync is turned on.
    final a = await Device.open('a');
    a.add('web');
    a.add('db');
    final b = await Device.open('b');
    b.add('nas');

    await a.sync.signIn(server: _url, email: email, password: pw, create: true);
    expect(a.sync.signedIn, isTrue);
    expect(a.sync.status, SyncStatus.idle);

    // Wrong password is refused and changes nothing.
    await expectLater(
      b.sync.signIn(server: _url, email: email, password: 'wrong password'),
      throwsA(anything),
    );
    expect(b.sync.signedIn, isFalse);
    expect(b.labels, {'nas'});

    // Joining merges: B keeps its own host and gains A's.
    await b.sync.signIn(
      server: '$_url/',
      email: 'someone@example.com',
      password: pw,
    );
    expect(b.labels, {'web', 'db', 'nas'});
    await a.sync.syncNow();
    expect(a.labels, {'web', 'db', 'nas'});

    // Edit on A shows up on B, fields intact.
    final web = a.byLabel('web')
      ..hostname = '10.0.0.5'
      ..port = 2222
      ..username = 'deploy'
      ..group = 'Prod';
    a.app.upsertHost(web);
    await a.sync.syncNow();
    await b.sync.syncNow();
    final webOnB = b.app.hosts.firstWhere((h) => h.id == web.id);
    expect(
      [webOnB.hostname, webOnB.port, webOnB.username, webOnB.group],
      ['10.0.0.5', 2222, 'deploy', 'Prod'],
    );

    // Delete on B removes it on A.
    b.app.removeHost(b.byLabel('nas'));
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(a.labels, {'web', 'db'});

    // Offline: changes queue up locally and nothing is lost.
    await _stopServer();
    final db = a.byLabel('db')..label = 'db-primary';
    a.app.upsertHost(db); // A edits db while offline
    a.add('cache'); // and adds a host
    await a.sync.syncNow();
    expect(a.sync.status, SyncStatus.offline);
    expect(a.labels, {'web', 'db-primary', 'cache'});
    // Meanwhile B (also offline) deletes db and edits web.
    b.app.removeHost(b.app.hosts.firstWhere((h) => h.id == db.id));
    final webB = b.app.hosts.firstWhere((h) => h.id == web.id)..label = 'web-b';
    await Future<void>.delayed(const Duration(milliseconds: 5));
    b.app.upsertHost(webB);
    await b.sync.syncNow();
    expect(b.sync.status, SyncStatus.offline);

    // Back online. B syncs first, then A.
    await _startServer();
    await b.sync.syncNow();
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(a.sync.status, SyncStatus.idle);
    expect(b.sync.status, SyncStatus.idle);
    // A's offline edit beat B's delete, A's new host arrived, B's edit arrived.
    expect(a.labels, {'web-b', 'db-primary', 'cache'});
    expect(b.labels, {'web-b', 'db-primary', 'cache'});

    // Both edit the same host; the later edit wins on both.
    final cacheA = a.byLabel('cache')..label = 'cache-a';
    a.app.upsertHost(cacheA);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final cacheB = b.byLabel('cache')..label = 'cache-b';
    b.app.upsertHost(cacheB);
    await a.sync.syncNow();
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(a.labels, contains('cache-b'));
    expect(b.labels, contains('cache-b'));

    // Restart: sign-in survives a reload of the profile.
    final a2 = Device._(
      await AppState.load(path: '${_tmp.path}/a.json'),
      a.sync,
    );
    expect(a2.app.syncConfig?.email, 'someone@example.com');
    expect(a2.labels, a.labels);

    // A brand-new device gets everything.
    final c = await Device.open('c');
    await c.sync.signIn(server: _url, email: email, password: pw);
    expect(c.labels, a.labels);

    // Signing out keeps hosts.
    final before = b.labels;
    await b.sync.signOut();
    expect(b.sync.signedIn, isFalse);
    expect(b.labels, before);

    // Deleting the account keeps hosts here and removes the account on the server.
    final keep = a.labels;
    await a.sync.deleteAccount();
    expect(a.sync.signedIn, isFalse);
    expect(a.labels, keep);
    await expectLater(
      Device.open('d')
          .then((d) => d.sync.signIn(server: _url, email: email, password: pw)),
      throwsA(anything),
    );
    // C still has its copy and reports the error instead of wiping anything.
    await c.sync.syncNow();
    expect(c.sync.status, SyncStatus.error);
    expect(c.labels, keep);
  }, skip: ready ? false : 'build rust_lib_burrow and burrow-server first');
}
