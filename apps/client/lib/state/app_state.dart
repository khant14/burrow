import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../models/host.dart';
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
  final List<Host> hosts = [];
  final List<Snippet> snippets = [];
  ThemeMode themeMode = ThemeMode.dark;
  String terminalThemeId = 'loam';
  double fontSize = 13;

  static Future<AppState> load() async {
    File? file;
    try {
      final dir = await getApplicationSupportDirectory();
      file = File('${dir.path}/burrow.json');
    } catch (_) {}
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
          j['themeMode'] as String? ?? 'dark',
        );
        s.terminalThemeId = j['terminalTheme'] as String? ?? s.terminalThemeId;
        s.fontSize = (j['fontSize'] as num?)?.toDouble() ?? s.fontSize;
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

  void upsertHost(Host h) {
    final i = hosts.indexWhere((e) => e.id == h.id);
    i < 0 ? hosts.add(h) : hosts[i] = h;
    _save();
  }

  void removeHost(Host h) {
    hosts.removeWhere((e) => e.id == h.id);
    _save();
  }

  static String get sshConfigPath =>
      '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? ''}/.ssh/config';

  static bool get canImportSshConfig =>
      (Platform.isMacOS || Platform.isLinux || Platform.isWindows) &&
      File(sshConfigPath).existsSync();

  /// Returns how many new hosts were added.
  int importSshConfig() {
    final parsed = parseSshConfig(
      File(sshConfigPath).readAsStringSync(),
      newId: newId,
    );
    final known = hosts.map((h) => h.label).toSet();
    final fresh = parsed.where((h) => !known.contains(h.label)).toList();
    hosts.addAll(fresh);
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
