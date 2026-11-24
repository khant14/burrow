import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import '../models/host.dart';
import '../src/rust/api/ssh.dart';
import 'app_state.dart';

enum SessionStatus { connecting, connected, closed, failed }

/// One SSH shell bound to one terminal buffer.
class TerminalSession extends ChangeNotifier {
  TerminalSession(this.host, this._password) {
    terminal.onOutput = (data) =>
        _ssh?.write(data: utf8.encode(_applyCtrl(data)));
    terminal.onResize = (w, h, _, _) => _ssh?.resize(cols: w, rows: h);
    connect();
  }

  final Host host;
  final String? _password;
  final terminal = Terminal(maxLines: 10000);
  final focusNode = FocusNode();
  final id = newId();
  SessionStatus status = SessionStatus.connecting;
  String? error;
  SshSession? _ssh;
  StreamSubscription<String>? _sub;

  Future<void> connect() async {
    _set(SessionStatus.connecting);
    error = null;
    try {
      final ssh = await SshSession.connect(
        target: SshTarget(
          host: host.hostname,
          port: host.port,
          username: host.username,
          password: host.auth == AuthMethod.password ? _password : null,
          keyPath: host.auth == AuthMethod.key
              ? expandHome(host.keyPath ?? '')
              : null,
        ),
        cols: terminal.viewWidth,
        rows: terminal.viewHeight,
      );
      if (_disposed) return ssh.close();
      _ssh = ssh;
      ssh.resize(cols: terminal.viewWidth, rows: terminal.viewHeight);
      _set(SessionStatus.connected);
      _sub = ssh
          .output()
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            terminal.write,
            onDone: () {
              _ssh = null;
              _set(SessionStatus.closed);
            },
          );
    } catch (e) {
      error = friendlyError(e.toString());
      _set(SessionStatus.failed);
    }
  }

  void run(String command) => terminal.textInput('$command\r');

  /// Mobile key bar: when set, the next typed character is sent as Ctrl plus that character.
  bool ctrlLatched = false;

  void toggleCtrl() {
    ctrlLatched = !ctrlLatched;
    notifyListeners();
  }

  String _applyCtrl(String data) {
    if (!ctrlLatched || data.length != 1) return data;
    ctrlLatched = false;
    notifyListeners();
    final code = data.toUpperCase().codeUnitAt(0);
    // Ctrl+@..Ctrl+_ map to 0x00..0x1F.
    return code >= 0x40 && code <= 0x5F
        ? String.fromCharCode(code - 0x40)
        : data;
  }

  bool _disposed = false;

  void _set(SessionStatus s) {
    if (_disposed) return;
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    focusNode.dispose();
    _sub?.cancel();
    _ssh?.close();
    super.dispose();
  }
}

/// A tab holds one or more panes split side by side.
class WorkspaceTab {
  WorkspaceTab(TerminalSession first) : panes = [first];
  final List<TerminalSession> panes;
  int focused = 0;
  TerminalSession get active => panes[focused];
}

typedef PasswordPrompt = Future<String?> Function(Host host);

class Workspace extends ChangeNotifier {
  final List<WorkspaceTab> tabs = [];
  int activeIndex = 0;

  /// Set by the shell so the workspace can ask for a password.
  PasswordPrompt? askPassword;

  WorkspaceTab? get active => tabs.isEmpty ? null : tabs[activeIndex];

  Future<TerminalSession?> _start(Host host) async {
    String? pw;
    if (host.auth == AuthMethod.password) {
      pw = await askPassword?.call(host);
      if (pw == null) return null;
    }
    final s = TerminalSession(host, pw)..addListener(notifyListeners);
    return s;
  }

  Future<TerminalSession?> open(Host host) async {
    final s = await _start(host);
    if (s == null) return null;
    tabs.add(WorkspaceTab(s));
    activeIndex = tabs.length - 1;
    _changed();
    return s;
  }

  /// Splits the active tab, opening [host] (or the active pane's host) beside it.
  Future<void> split([Host? host]) async {
    final tab = active;
    if (tab == null) return;
    final s = await _start(host ?? tab.active.host);
    if (s == null) return;
    tab.panes.add(s);
    tab.focused = tab.panes.length - 1;
    _changed();
  }

  void focus(int tab, [int? pane]) {
    if (tab < 0 || tab >= tabs.length) return;
    activeIndex = tab;
    if (pane != null) tabs[tab].focused = pane;
    _changed();
  }

  void closeTab(int i) {
    for (final p in tabs[i].panes) {
      p.dispose();
    }
    tabs.removeAt(i);
    activeIndex = activeIndex.clamp(0, tabs.isEmpty ? 0 : tabs.length - 1);
    _changed();
  }

  /// Closes the focused pane, or the tab when it is the last pane.
  void closeActive() {
    final tab = active;
    if (tab == null) return;
    if (tab.panes.length == 1) return closeTab(activeIndex);
    tab.panes.removeAt(tab.focused).dispose();
    tab.focused = tab.focused.clamp(0, tab.panes.length - 1);
    _changed();
  }

  /// Notifies, then moves keyboard focus to the active pane once it is laid out.
  void _changed() {
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => active?.active.focusNode.requestFocus(),
    );
  }

  SessionStatus? statusFor(Host h) {
    SessionStatus? best;
    for (final t in tabs) {
      for (final p in t.panes) {
        if (p.host.id != h.id) continue;
        if (p.status == SessionStatus.connected) return p.status;
        best ??= p.status;
      }
    }
    return best;
  }
}

/// Turns low-level connection errors into something a person can act on.
String friendlyError(String raw) {
  final r = raw.toLowerCase();
  if (r.contains('refused')) return 'Nothing answered on that port. Is SSH running there?';
  if (r.contains('authentication failed')) return "The server didn't accept those credentials.";
  if (r.contains('could not load private key')) return "Couldn't read that private key. Check the path and passphrase.";
  if (r.contains('timed out') || r.contains('unreachable') || r.contains('no route')) {
    return 'No way through to that host. Check the address or your network.';
  }
  if (r.contains('failed to lookup') || r.contains('name or service not known') || r.contains('nodename')) {
    return "Couldn't find that host name.";
  }
  return raw;
}
