import 'host.dart';

/// Parses the parts of an OpenSSH client config that map to a Burrow host.
/// Wildcard patterns (`Host *`, `Host *.corp`) are skipped.
List<Host> parseSshConfig(String text, {required String Function() newId}) {
  final hosts = <Host>[];
  Host? current;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final m = RegExp(r'^(\S+)\s*[=\s]\s*(.+)$').firstMatch(line);
    if (m == null) continue;
    final key = m.group(1)!.toLowerCase();
    final value = m.group(2)!.trim().replaceAll('"', '');
    switch (key) {
      case 'host':
        current = null;
        final alias = value.split(RegExp(r'\s+')).first;
        if (alias.contains('*') ||
            alias.contains('?') ||
            alias.startsWith('!')) {
          continue;
        }
        current = Host(
          id: newId(),
          label: alias,
          hostname: alias,
          group: 'Imported',
        );
        hosts.add(current);
      case 'match':
        current = null;
      case 'hostname':
        current?.hostname = value;
      case 'user':
        current?.username = value;
      case 'port':
        current?.port = int.tryParse(value) ?? 22;
      case 'identityfile':
        current
          ?..auth = AuthMethod.key
          ..keyPath = value;
      case 'proxyjump':
        current?.jumpHost = value;
      case 'localforward':
        if (current != null) {
          current.forwards = [...current.forwards, 'L $value'];
        }
      case 'remoteforward':
        if (current != null) {
          current.forwards = [...current.forwards, 'R $value'];
        }
      case 'dynamicforward':
        if (current != null) {
          current.forwards = [...current.forwards, 'D $value'];
        }
    }
  }
  return hosts;
}
