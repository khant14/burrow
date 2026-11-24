import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// An arch: straight sides with a semicircular top, open at the bottom.
Path archPath(Rect r) {
  final w = r.width;
  return Path()
    ..moveTo(r.left, r.bottom)
    ..lineTo(r.left, r.top + w / 2)
    ..arcTo(Rect.fromLTWH(r.left, r.top, w, w), math.pi, math.pi, false)
    ..lineTo(r.right, r.bottom);
}

/// The Burrow mark: a tunnel entrance in three nested arches on a ground line.
class BurrowMark extends StatelessWidget {
  const BurrowMark({super.key, this.size = 24, this.tile = true});
  final double size;

  /// Draws the mark on a rounded soil tile, as in the app icon.
  final bool tile;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _MarkPainter(context.c, tile),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.c, this.tile);
  final BurrowColors c;
  final bool tile;

  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width;
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(u * 0.26)),
        Paint()..color = c.accent,
      );
    }
    final ink = tile ? c.onAccent : c.accent;
    final ground = u * (tile ? 0.74 : 0.86);
    final pad = u * (tile ? 0.2 : 0.06);
    // Outer arch, filled, then the dark mouth inside it.
    final outer = Rect.fromLTRB(pad, u * (tile ? 0.2 : 0.08), u - pad, ground);
    canvas.drawPath(archPath(outer)..close(), Paint()..color = ink);
    final mouth = outer.deflate(u * 0.12);
    canvas.drawPath(
      archPath(Rect.fromLTRB(mouth.left, mouth.top, mouth.right, ground))
        ..close(),
      Paint()..color = tile ? c.accent : c.bg,
    );
    final core = mouth.deflate(u * 0.09);
    canvas.drawPath(
      archPath(Rect.fromLTRB(core.left, core.top, core.right, ground))..close(),
      Paint()..color = ink.withValues(alpha: 0.85),
    );
    // Ground line.
    canvas.drawLine(
      Offset(u * 0.1, ground),
      Offset(u * 0.9, ground),
      Paint()
        ..color = ink
        ..strokeWidth = u * 0.07
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.c != c || old.tile != tile;
}

/// Connecting animation: arches drift toward you, like moving down a tunnel.
class TunnelLoader extends StatefulWidget {
  const TunnelLoader({super.key, this.size = 64});
  final double size;

  @override
  State<TunnelLoader> createState() => _TunnelLoaderState();
}

class _TunnelLoaderState extends State<TunnelLoader>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _TunnelPainter(_ctrl, context.c),
    ),
  );
}

class _TunnelPainter extends CustomPainter {
  _TunnelPainter(this.t, this.c) : super(repaint: t);
  final Animation<double> t;
  final BurrowColors c;

  @override
  void paint(Canvas canvas, Size s) {
    final center = Offset(s.width / 2, s.height * 0.62);
    const rings = 5;
    for (var i = 0; i < rings; i++) {
      // Each ring grows from the vanishing point; ease so it accelerates as it nears.
      final p = (t.value + i / rings) % 1.0;
      final e = Curves.easeIn.transform(p);
      final w = s.width * (0.12 + 0.88 * e);
      final h = w * 0.95;
      final r = Rect.fromCenter(
        center: center.translate(0, -h * 0.12),
        width: w,
        height: h,
      );
      final fade = math.sin(p * math.pi); // in, then out
      canvas.drawPath(
        archPath(r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + 1.4 * e
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(
            c.clay,
            c.accent,
            e,
          )!.withValues(alpha: 0.85 * fade),
      );
    }
    // The light at the end of the tunnel.
    canvas.drawCircle(
      center.translate(0, -s.height * 0.04),
      s.width * 0.05,
      Paint()
        ..color = c.accent
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_TunnelPainter old) => old.c != c;
}

enum Scene { welcome, quiet, empty }

/// Empty-state illustrations: a cross-section of ground with burrows below.
class BurrowIllustration extends StatelessWidget {
  const BurrowIllustration(this.scene, {super.key, this.width = 320});
  final Scene scene;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * 0.5),
    painter: _ScenePainter(scene, context.c),
  );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.c);
  final Scene scene;
  final BurrowColors c;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final groundY = h * 0.32;

    // Soil, fading out toward the bottom and sides.
    final soilRect = Rect.fromLTRB(0, groundY, w, h);
    canvas.drawRect(
      soilRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.6),
          radius: 1.0,
          colors: [c.soil, c.soil.withValues(alpha: 0)],
        ).createShader(soilRect),
    );

    // Soil speckles, deterministic so the picture is stable.
    final rnd = math.Random(7);
    final speck = Paint()..color = c.faint.withValues(alpha: 0.35);
    for (var i = 0; i < 40; i++) {
      final x = w * (0.1 + 0.8 * rnd.nextDouble());
      final y = groundY + (h - groundY) * (0.1 + 0.7 * rnd.nextDouble());
      canvas.drawCircle(Offset(x, y), 0.6 + rnd.nextDouble(), speck);
    }

    // Ground line with a few grass tufts.
    final line = Paint()
      ..color = c.muted.withValues(alpha: 0.6)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.06, groundY), Offset(w * 0.94, groundY), line);
    for (final x in [0.18, 0.24, 0.71, 0.84]) {
      for (final d in [-3.0, 0.0, 3.0]) {
        canvas.drawLine(
          Offset(w * x + d, groundY),
          Offset(w * x + d * 1.6, groundY - 6 - d.abs()),
          line,
        );
      }
    }

    // Entrance arch on the surface.
    final ex = w * 0.42;
    final entrance = Rect.fromLTWH(ex - 16, groundY - 26, 32, 26);
    canvas.drawPath(archPath(entrance)..close(), Paint()..color = c.clay);
    canvas.drawPath(
      archPath(entrance.deflate(6).translate(0, 3))..close(),
      Paint()..color = c.bg,
    );

    // Tunnels: a winding path down from the entrance to chambers.
    final tunnel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c.bg;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = c.clay.withValues(alpha: 0.35);

    final chambers = switch (scene) {
      Scene.welcome => [
        Offset(w * 0.22, h * 0.78),
        Offset(w * 0.58, h * 0.66),
        Offset(w * 0.8, h * 0.86),
      ],
      Scene.quiet => [Offset(w * 0.68, h * 0.76)],
      Scene.empty => <Offset>[],
    };
    final path = Path()..moveTo(ex, groundY);
    path.cubicTo(
      ex,
      groundY + h * 0.18,
      ex - w * 0.08,
      h * 0.58,
      ex + w * 0.02,
      h * 0.62,
    );
    final junction = Offset(ex + w * 0.02, h * 0.62);
    for (final ch in chambers) {
      path.moveTo(junction.dx, junction.dy);
      path.quadraticBezierTo(
        (junction.dx + ch.dx) / 2,
        (junction.dy + ch.dy) / 2 + 12,
        ch.dx,
        ch.dy,
      );
    }
    canvas.drawPath(path, edge);
    canvas.drawPath(path, tunnel);

    // Chambers, each holding a tiny server with a status light.
    for (var i = 0; i < chambers.length; i++) {
      final ch = chambers[i];
      final room = Rect.fromCenter(center: ch, width: 46, height: 26);
      canvas.drawRRect(
        RRect.fromRectAndRadius(room.inflate(3), const Radius.circular(16)),
        Paint()..color = c.clay.withValues(alpha: 0.35),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(room, const Radius.circular(14)),
        Paint()..color = c.bg,
      );
      final box = Rect.fromCenter(
        center: ch.translate(0, 2),
        width: 16,
        height: 11,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(2)),
        Paint()..color = c.muted,
      );
      canvas.drawCircle(
        box.topRight.translate(-3.5, 3.5),
        1.6,
        Paint()..color = i == 0 || scene == Scene.quiet ? c.success : c.accent,
      );
    }

    // A small lantern glow at the end of an empty tunnel.
    if (scene == Scene.empty) {
      canvas.drawCircle(
        Offset(ex + w * 0.02, h * 0.62),
        10,
        Paint()
          ..color = c.accent.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        Offset(ex + w * 0.02, h * 0.62),
        3,
        Paint()..color = c.accent,
      );
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.scene != scene || old.c != c;
}

/// Tiny latency history, drawn inline in host rows.
class Sparkline extends StatelessWidget {
  const Sparkline(this.samples, {super.key, this.width = 34, this.height = 12});

  /// Round-trip times in ms; null marks a failed check.
  final List<int?> samples;
  final double width, height;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, height),
    painter: _SparkPainter(samples, context.c),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.samples, this.c);
  final List<int?> samples;
  final BurrowColors c;

  @override
  void paint(Canvas canvas, Size s) {
    if (samples.length < 2) return;
    final ok = samples.whereType<int>();
    final maxV = ok.isEmpty ? 1 : math.max(ok.reduce(math.max), 20);
    final dx = s.width / (samples.length - 1);
    final p = Path();
    var started = false;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i];
      if (v == null) {
        canvas.drawCircle(
          Offset(i * dx, s.height - 1),
          1.2,
          Paint()..color = c.danger,
        );
        started = false;
        continue;
      }
      final pt = Offset(i * dx, s.height - 1 - (v / maxV) * (s.height - 2));
      started ? p.lineTo(pt.dx, pt.dy) : p.moveTo(pt.dx, pt.dy);
      started = true;
    }
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeJoin = StrokeJoin.round
        ..color = c.muted.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}
