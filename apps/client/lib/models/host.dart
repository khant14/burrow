enum AuthMethod { password, key }

class Host {
  Host({
    required this.id,
    required this.label,
    required this.hostname,
    this.port = 22,
    this.username = '',
    this.group = '',
    this.auth = AuthMethod.password,
    this.keyPath,
    this.jumpHost,
    this.forwards = const [],
  });

  final String id;
  String label;
  String hostname;
  int port;
  String username;
  String group;
  AuthMethod auth;
  String? keyPath;
  String? jumpHost;

  /// OpenSSH-style specs, e.g. `L 8080:localhost:80`.
  List<String> forwards;

  String get address => username.isEmpty ? hostname : '$username@$hostname';

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'hostname': hostname,
    'port': port,
    'username': username,
    'group': group,
    'auth': auth.name,
    'keyPath': keyPath,
    'jumpHost': jumpHost,
    'forwards': forwards,
  };

  factory Host.fromJson(Map<String, dynamic> j) => Host(
    id: j['id'] as String,
    label: j['label'] as String,
    hostname: j['hostname'] as String,
    port: j['port'] as int? ?? 22,
    username: j['username'] as String? ?? '',
    group: j['group'] as String? ?? '',
    auth: AuthMethod.values.byName(j['auth'] as String? ?? 'password'),
    keyPath: j['keyPath'] as String?,
    jumpHost: j['jumpHost'] as String?,
    forwards: (j['forwards'] as List?)?.cast<String>() ?? const [],
  );
}

class Snippet {
  Snippet({required this.id, required this.name, required this.command});
  final String id;
  String name;
  String command;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'command': command};
  factory Snippet.fromJson(Map<String, dynamic> j) => Snippet(
    id: j['id'] as String,
    name: j['name'] as String,
    command: j['command'] as String,
  );
}
