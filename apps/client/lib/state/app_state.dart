import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../models/host.dart';
import 'keys.dart';
import '../src/rust/api/sync.dart';
import '../models/ssh_config.dart';

String newId() {
  final r = Random.secure();
  return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
}

/// Hosts, snippets and preferences. Persisted as JSON in the app support dir.
/// TODO(M2): move into the encrypted Rust vault.
class AppState extends ChangeNotifier {
  AppState._(this._file);

  final File? _file;

  /// Per-host sync bookkeeping: last local change (ms) and whether it still needs pushing.
  final Map<String, ({int updatedAt, bool dirty})> syncMeta = {};

  /// Hosts deleted here but not yet pushed. Kept only while sync is on.
  final Map<String, int> tombstones = {};

  /// Set while signed in to a sync server. Secrets live in the keychain, not here.
  SyncConfig? syncConfig;
  final List<Host> hosts = [];
  final List<Snippet> snippets = [];
  ThemeMode themeMode = ThemeMode.system;
  String terminalThemeId = 'loam';
  double fontSize = 13;

  /// [path] overrides the store location (tests, or a second profile).
  static Future<AppState> load({String? path}) async {
    File? file;
    if (path != null) {
      file = File(path);
    } else {
      try {
        final dir = await getApplicationSupportDirectory();
        file = File('${dir.path}/burrow.json');
      } catch (_) {}
    }
    final s = AppState._(file);
    if (file != null && file.existsSync()) {
      try {
        final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        s.hosts.addAll(
          (j['hosts'] as List).map(
            (e) => Host.fromJson(e as Map<String, dynamic>),
          ),
        );
        s.snippets.addAll(
          (j['snippets'] as List).map(
            (e) => Snippet.fromJson(e as Map<String, dynamic>),
          ),
        );
        s.themeMode = ThemeMode.values.byName(
          j['themeMode'] as String? ?? 'system',
        );
        s.terminalThemeId = j['terminalTheme'] as String? ?? s.terminalThemeId;
        s.fontSize = (j['fontSize'] as num?)?.toDouble() ?? s.fontSize;
        final meta = j['syncMeta'] as Map<String, dynamic>? ?? const {};
        meta.forEach((id, v) {
          final m = v as Map<String, dynamic>;
          s.syncMeta[id] = (
            updatedAt: m['u'] as int? ?? 0,
            dirty: m['d'] as bool? ?? false,
          );
        });
        (j['tombstones'] as Map<String, dynamic>? ?? const {}).forEach(
          (id, t) => s.tombstones[id] = t as int,
        );
        final sc = j['sync'] as Map<String, dynamic>?;
        if (sc != null) s.syncConfig = SyncConfig.fromJson(sc);
      } catch (_) {}
    } else {
      s.snippets.addAll([
        Snippet(id: newId(), name: 'Disk usage', command: 'df -h'),
        Snippet(id: newId(), name: 'Top processes', command: 'top -o %CPU'),
        Snippet(
          id: newId(),
          name: 'Follow syslog',
          command: 'sudo journalctl -f',
        ),
      ]);
    }
    return s;
  }

  void _save() {
    notifyListeners();
    final f = _file;
    if (f == null) return;
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(
      jsonEncode({
        'hosts': hosts.map((h) => h.toJson()).toList(),
        'snippets': snippets.map((s) => s.toJson()).toList(),
        'themeMode': themeMode.name,
        'terminalTheme': terminalThemeId,
        'fontSize': fontSize,
        'syncMeta': {
          for (final e in syncMeta.entries)
            e.key: {'u': e.value.updatedAt, 'd': e.value.dirty},
        },
        'tombstones': tombstones,
        if (syncConfig != null) 'sync': syncConfig!.toJson(),
      }),
    );
  }

  /// Hosts grouped by folder, in insertion order; ungrouped hosts last.
  Map<String, List<Host>> grouped([String filter = '']) {
    final q = filter.toLowerCase();
    final out = <String, List<Host>>{};
    for (final h in hosts) {
      if (q.isNotEmpty &&
          !h.label.toLowerCase().contains(q) &&
          !h.hostname.toLowerCase().contains(q) &&
          !h.group.toLowerCase().contains(q)) {
        continue;
      }
      out.putIfAbsent(h.group, () => []).add(h);
    }
    final ungrouped = out.remove('');
    if (ungrouped != null) out[''] = ungrouped;
    return out;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  void _touch(String id) {
    // Strictly increasing per item, so an edit always sorts after what it replaced.
    final prev = syncMeta[id]?.updatedAt ?? 0;
    final t = _now();
    syncMeta[id] = (updatedAt: t > prev ? t : prev + 1, dirty: true);
    tombstones.remove(id);
  }

  void upsertHost(Host h) {
    final i = hosts.indexWhere((e) => e.id == h.id);
    i < 0 ? hosts.add(h) : hosts[i] = h;
    _touch(h.id);
    _save();
  }

  void removeHost(Host h) {
    hosts.removeWhere((e) => e.id == h.id);
    KeyStore.delete(h.id);
    final prev = syncMeta.remove(h.id)?.updatedAt ?? 0;
    if (syncConfig != null) {
      final t = _now();
      tombstones[h.id] = t > prev ? t : prev + 1;
    }
    _save();
  }

  // ---- Sync plumbing, driven by SyncService ----

  /// Every host plus pending deletes, as the sync engine expects them.
  List<SyncItem> syncSnapshot() => [
    for (final h in hosts)
      SyncItem(
        id: h.id,
        kind: 'host',
        data: jsonEncode(h.toJson()),
        updatedAt: syncMeta[h.id]?.updatedAt ?? 0,
        deleted: false,
        dirty: syncMeta[h.id]?.dirty ?? true,
      ),
    for (final e in tombstones.entries)
      SyncItem(
        id: e.key,
        kind: 'host',
        data: '',
        updatedAt: e.value,
        deleted: true,
        dirty: true,
      ),
  ];

  /// Applies a finished round. Items edited locally while the round ran are left alone.
  void applySyncRound(SyncRound r, List<SyncItem> snapshot) {
    final seen = {for (final s in snapshot) s.id: s.updatedAt};
    int? current(String id) => syncMeta[id]?.updatedAt ?? tombstones[id];
    bool untouched(String id) => current(id) == seen[id];
    for (final it in r.apply) {
      if (it.kind != 'host' || !untouched(it.id)) continue;
      if (it.deleted) {
        // A delete made on another device. The private key in this device's
        // keychain is left in place.
        hosts.removeWhere((h) => h.id == it.id);
        syncMeta.remove(it.id);
        tombstones.remove(it.id);
      } else {
        try {
          final h = Host.fromJson(jsonDecode(it.data) as Map<String, dynamic>);
          final i = hosts.indexWhere((e) => e.id == h.id);
          i < 0 ? hosts.add(h) : hosts[i] = h;
          syncMeta[h.id] = (updatedAt: it.updatedAt, dirty: false);
          tombstones.remove(h.id);
        } catch (_) {}
      }
    }
    for (final id in r.pushed) {
      if (!untouched(id)) continue;
      final m = syncMeta[id];
      if (m != null) syncMeta[id] = (updatedAt: m.updatedAt, dirty: false);
      tombstones.remove(id);
    }
    syncConfig = syncConfig?.copyWith(cursor: r.cursor, lastSyncedAt: _now());
    _save();
  }

  /// Turns sync on. Everything local is queued for upload, so nothing on this
  /// device is lost when joining an account that already has hosts.
  void startSync(SyncConfig c) {
    syncConfig = c;
    tombstones.clear();
    for (final h in hosts) {
      final m = syncMeta[h.id];
      syncMeta[h.id] = (updatedAt: m?.updatedAt ?? _now(), dirty: true);
    }
    _save();
  }

  /// Turns sync off. Hosts stay on this device.
  void stopSync() {
    syncConfig = null;
    tombstones.clear();
    _save();
  }

  static String get sshConfigPath =>
      '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? ''}/.ssh/config';

  /// The sandboxed Mac app can't see ~/.ssh, so it asks for the file instead.
  static bool get canImportSshConfig =>
      Platform.isMacOS ||
      ((Platform.isLinux || Platform.isWindows) &&
          File(sshConfigPath).existsSync());

  /// Returns how many new hosts were added. Reads ~/.ssh/config unless [text] is given.
  int importSshConfig([String? text]) {
    final parsed = parseSshConfig(
      text ?? File(sshConfigPath).readAsStringSync(),
      newId: newId,
    );
    final known = hosts.map((h) => h.label).toSet();
    final fresh = parsed.where((h) => !known.contains(h.label)).toList();
    hosts.addAll(fresh);
    for (final h in fresh) {
      _touch(h.id);
    }
    _save();
    return fresh.length;
  }

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _save();
  }

  void setTerminalTheme(String id) {
    terminalThemeId = id;
    _save();
  }

  void setFontSize(double v) {
    fontSize = v.clamp(10, 22);
    _save();
  }
}

/// Expands a leading `~` so the Rust side gets an absolute key path.
String expandHome(String path) {
  if (!path.startsWith('~')) return path;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return home + path.substring(1);
}

/// Where this device syncs to. Token and vault key are kept in the keychain.
class SyncConfig {
  const SyncConfig({
    required this.server,
    required this.email,
    this.cursor = 0,
    this.lastSyncedAt,
  });
  final String server;
  final String email;
  final int cursor;
  final int? lastSyncedAt;

  SyncConfig copyWith({int? cursor, int? lastSyncedAt}) => SyncConfig(
    server: server,
    email: email,
    cursor: cursor ?? this.cursor,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );

  Map<String, dynamic> toJson() => {
    'server': server,
    'email': email,
    'cursor': cursor,
    'lastSyncedAt': lastSyncedAt,
  };

  factory SyncConfig.fromJson(Map<String, dynamic> j) => SyncConfig(
    server: j['server'] as String,
    email: j['email'] as String,
    cursor: j['cursor'] as int? ?? 0,
    lastSyncedAt: j['lastSyncedAt'] as int?,
  );
}
