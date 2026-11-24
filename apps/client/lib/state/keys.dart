import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Private keys pasted or imported into Burrow, kept in the system keychain.
/// Needed on iOS and the sandboxed Mac app, which can't read ~/.ssh.
class KeyStore {
  static const _s = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    // The legacy keychain works without a keychain-sharing entitlement.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static String _k(String hostId) => 'key:$hostId';

  static Future<String?> read(String hostId) async {
    try {
      return await _s.read(key: _k(hostId));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String hostId, String pem) =>
      _s.write(key: _k(hostId), value: pem.trim());

  static Future<void> delete(String hostId) async {
    try {
      await _s.delete(key: _k(hostId));
    } catch (_) {}
  }

  /// Loose check that pasted text is a private key, before saving it.
  static bool looksLikeKey(String text) =>
      text.contains('-----BEGIN') && text.contains('PRIVATE KEY-----');
}
