import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'app_state.dart';

/// Lightweight reachability: times a TCP connect to each host's SSH port.
/// No login, no credentials; it only tells you whether the door is open and how far away it is.
class HealthMonitor extends ChangeNotifier {
  HealthMonitor(this.app) {
    app.addListener(_kick);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => checkAll());
    checkAll();
  }

  final AppState app;
  late final Timer _timer;
  static const keep = 16;
  final Map<String, List<int?>> _samples = {};
  final Set<String> _inFlight = {};

  List<int?> samples(String hostId) => _samples[hostId] ?? const [];

  /// Latest round trip in ms, null when unreachable, or no entry when not checked yet.
  int? latest(String hostId) => samples(hostId).lastOrNull;
  bool checked(String hostId) => samples(hostId).isNotEmpty;

  void _kick() {
    // Check newly added hosts right away.
    for (final h in app.hosts) {
      if (!_samples.containsKey(h.id)) _check(h.id, h.hostname, h.port);
    }
  }

  void checkAll() {
    for (final h in app.hosts) {
      _check(h.id, h.hostname, h.port);
    }
  }

  Future<void> _check(String id, String host, int port) async {
    if (!_inFlight.add(id)) return;
    final sw = Stopwatch()..start();
    int? ms;
    try {
      final sock = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      ms = sw.elapsedMilliseconds;
      sock.destroy();
    } catch (_) {
      ms = null;
    }
    _inFlight.remove(id);
    final list = _samples.putIfAbsent(id, () => []);
    list.add(ms);
    if (list.length > keep) list.removeAt(0);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer.cancel();
    app.removeListener(_kick);
    super.dispose();
  }
}
