import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';

import '../src/rust/api/sync.dart';
import 'app_state.dart';

/// Where the sync token and vault key are kept.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeychainSecrets implements SecretStore {
  static const _s = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) async {
    try {
      await _s.delete(key: key);
    } catch (_) {}
  }
}

class MemorySecrets implements SecretStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

enum SyncStatus { off, idle, syncing, offline, error }

/// Optional end-to-end-encrypted sync. Burrow works fully without it.
/// Signing out or deleting the account never removes hosts from this device.
class SyncService extends ChangeNotifier {
  SyncService(this.app, {SecretStore? secrets, this.auto = true})
    : _secrets = secrets ?? KeychainSecrets() {
    if (auto) app.addListener(_onLocalChange);
  }

  final AppState app;
  final SecretStore _secrets;
  final bool auto;
  static const _kToken = 'sync:token';
  static const _kVault = 'sync:vault';

  SyncAccount? _account;
  SyncStatus status = SyncStatus.off;
  String? error;
  Timer? _debounce;
  Timer? _periodic;
  Future<void>? _running;
  bool _again = false;
  int _lastChangeSeen = 0;
  bool _applying = false;

  bool get signedIn => _account != null;
  String? get email => app.syncConfig?.email;
  String? get server => app.syncConfig?.server;
  DateTime? get lastSynced {
    final t = app.syncConfig?.lastSyncedAt;
    return t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
  }

  /// Picks up a previous sign-in at launch.
  Future<void> restore() async {
    final c = app.syncConfig;
    if (c == null) return;
    final token = await _secrets.read(_kToken);
    final vault = await _secrets.read(_kVault);
    if (token == null || vault == null) {
      // Keychain was cleared; ask to sign in again but keep every host.
      app.stopSync();
      return;
    }
    _account = SyncAccount(
      server: c.server,
      email: c.email,
      token: token,
      vaultKey: vault,
    );
    _started();
    unawaited(syncNow());
  }

  /// Signs in, or creates an account when [create] is true, then syncs.
  Future<void> signIn({
    required String server,
    required String email,
    required String password,
    bool create = false,
  }) async {
    final a = create
        ? await syncRegister(server: server, email: email, password: password)
        : await syncLogin(server: server, email: email, password: password);
    await _secrets.write(_kToken, a.token);
    await _secrets.write(_kVault, a.vaultKey);
    _account = a;
    app.startSync(SyncConfig(server: a.server, email: a.email));
    _started();
    await syncNow();
  }

  void _started() {
    error = null;
    status = SyncStatus.idle;
    _lastChangeSeen = _changeStamp();
    _periodic?.cancel();
    if (auto) {
      _periodic = Timer.periodic(const Duration(seconds: 60), (_) => syncNow());
    }
    notifyListeners();
  }

  /// One pull-merge-push round. Concurrent calls coalesce into one extra round.
  Future<void> syncNow() async {
    if (_account == null) return;
    if (_running != null) {
      _again = true;
      return _running;
    }
    _running = _round();
    try {
      await _running;
    } finally {
      _running = null;
    }
    if (_again && _account != null) {
      _again = false;
      await syncNow();
    }
  }

  Future<void> _round() async {
    final a = _account!;
    status = SyncStatus.syncing;
    notifyListeners();
    final snapshot = app.syncSnapshot();
    try {
      final r = await syncRound(
        account: a,
        cursor: app.syncConfig?.cursor ?? 0,
        local: snapshot,
      );
      if (_account != a) return; // signed out meanwhile
      _applying = true;
      try {
        app.applySyncRound(r, snapshot);
      } finally {
        _applying = false;
      }
      _lastChangeSeen = _changeStamp();
      status = SyncStatus.idle;
      error = null;
    } catch (e) {
      final msg = e.toString();
      status = msg.contains("Can't reach")
          ? SyncStatus.offline
          : SyncStatus.error;
      error = msg;
    }
    notifyListeners();
  }

  /// A cheap fingerprint of pending local work, so our own writes don't retrigger sync.
  int _changeStamp() {
    var h = app.tombstones.length;
    for (final e in app.syncMeta.entries) {
      if (e.value.dirty) h = Object.hash(h, e.key, e.value.updatedAt);
    }
    return h;
  }

  void _onLocalChange() {
    if (_account == null || _applying) return;
    final stamp = _changeStamp();
    if (stamp == _lastChangeSeen) return;
    _lastChangeSeen = stamp;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  /// Stops syncing on this device. Hosts stay here and on the server.
  Future<void> signOut() async {
    _account = null;
    _debounce?.cancel();
    _periodic?.cancel();
    await _secrets.delete(_kToken);
    await _secrets.delete(_kVault);
    app.stopSync();
    status = SyncStatus.off;
    error = null;
    notifyListeners();
  }

  /// Deletes the account and all synced data on the server. Hosts on this
  /// device are kept.
  Future<void> deleteAccount() async {
    final a = _account;
    if (a == null) return;
    await syncDeleteAccount(server: a.server, token: a.token);
    await signOut();
  }

  @override
  void dispose() {
    app.removeListener(_onLocalChange);
    _debounce?.cancel();
    _periodic?.cancel();
    super.dispose();
  }
}
