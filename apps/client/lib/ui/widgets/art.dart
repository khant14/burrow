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
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(context.c, tile),
    ),
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
  );

  /// Honors Reduce Motion: the tunnel holds still instead of looping.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
      _ctrl.value = 0.35;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Connecting',
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _TunnelPainter(_ctrl, context.c),
      ),
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
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(width, width * 0.5),
      painter: _ScenePainter(scene, context.c),
    ),
  );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.c);
  final Scene scene;
  final BurrowColors c;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a fixed 360x180 canvas, then scaled, so details keep their proportions.
    canvas.scale(size.width / 360);
    const s = Size(360, 180);
    final w = s.width, h = s.height;
    final g = h * 0.3; // ground line
    final dark = c.bg.computeLuminance() < 0.2;
    final rnd = math.Random(7);

    // Everything is drawn in a layer, then faded out at the edges.
    canvas.saveLayer(Offset.zero & s, Paint());
    // Keep content off the outermost pixels, where the edge fade can leave a seam.
    canvas.clipRect(Rect.fromLTWH(2, 0, w - 4, h));

    // Sky: a low sun (or moon) with a soft halo, a few stars at night.
    final orb = Offset(w * 0.78, g * 0.42);
    final orbColor = dark ? c.text : c.accent;
    canvas.drawCircle(
      orb,
      h * 0.14,
      Paint()
        ..shader = RadialGradient(
          colors: [
            orbColor.withValues(alpha: dark ? 0.16 : 0.22),
            orbColor.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: orb, radius: h * 0.14)),
    );
    canvas.drawCircle(
      orb,
      h * 0.045,
      Paint()..color = orbColor.withValues(alpha: dark ? 0.85 : 0.75),
    );
    if (dark) {
      // Crescent: bite out of the moon with the sky colour.
      canvas.drawCircle(
        orb.translate(h * 0.02, -h * 0.012),
        h * 0.04,
        Paint()..color = c.bg,
      );
      final star = Paint()..color = c.text.withValues(alpha: 0.5);
      for (var i = 0; i < 9; i++) {
        canvas.drawCircle(
          Offset(
            w * (0.15 + 0.7 * rnd.nextDouble()),
            g * (0.12 + 0.55 * rnd.nextDouble()),
          ),
          0.5 + 0.7 * rnd.nextDouble(),
          star,
        );
      }
    }

    // Distant hills behind the ground line.
    final hills = Path()..moveTo(0, g);
    hills.cubicTo(
      w * 0.12,
      g - h * 0.1,
      w * 0.26,
      g - h * 0.1,
      w * 0.36,
      g - h * 0.03,
    );
    hills.cubicTo(
      w * 0.5,
      g - h * 0.16,
      w * 0.72,
      g - h * 0.13,
      w * 0.86,
      g - h * 0.04,
    );
    hills.cubicTo(
      w * 0.92,
      g - h * 0.07,
      w * 0.97,
      g - h * 0.05,
      w,
      g - h * 0.03,
    );
    hills
      ..lineTo(w, g)
      ..close();
    canvas.drawPath(
      hills,
      Paint()..color = c.soil.withValues(alpha: dark ? 0.55 : 0.45),
    );

    // Soil in three strata, each a little deeper in tone, with wavy tops.
    final deep = dark
        ? Color.lerp(c.soil, Colors.black, 0.35)!
        : Color.lerp(c.soil, c.clay, 0.22)!;
    Path band(double top, double amp, double phase) {
      final p = Path()..moveTo(0, top);
      for (var x = 0.0; x <= w; x += w / 40) {
        p.lineTo(x, top + math.sin(x / w * math.pi * 3 + phase) * amp);
      }
      return p
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
    }

    canvas.drawPath(band(g, 0, 0), Paint()..color = c.soil);
    canvas.drawPath(
      band(g + h * 0.2, 3, 0.6),
      Paint()..color = Color.lerp(c.soil, deep, 0.5)!,
    );
    canvas.drawPath(band(g + h * 0.44, 4, 2.1), Paint()..color = deep);

    // Speckles and pebbles, deterministic so the picture is stable.
    for (var i = 0; i < 70; i++) {
      final x = w * rnd.nextDouble();
      final y = g + 6 + (h - g - 6) * rnd.nextDouble();
      canvas.drawCircle(
        Offset(x, y),
        0.5 + rnd.nextDouble() * 0.9,
        Paint()..color = (i.isEven ? c.faint : c.clay).withValues(alpha: 0.35),
      );
    }
    // Sediment lines: short strokes that follow each stratum.
    final sed = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = c.muted.withValues(alpha: dark ? 0.18 : 0.22);
    for (var i = 0; i < 26; i++) {
      final x = w * rnd.nextDouble();
      final y = g + 10 + (h - g - 14) * rnd.nextDouble();
      final len = 6 + 14 * rnd.nextDouble();
      canvas.drawLine(Offset(x, y), Offset(x + len, y), sed);
    }

    // Grass tufts, with thin roots reaching into the soil.
    final blade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = c.success.withValues(alpha: 0.75);
    final root = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round
      ..color = c.muted.withValues(alpha: 0.3);
    for (final fx in [0.14, 0.22, 0.64, 0.74, 0.9]) {
      final x = w * fx;
      for (final d in [-4.0, -1.5, 1.5, 4.0]) {
        final tall = 7 + (4 - d.abs()) * 1.6;
        canvas.drawPath(
          Path()
            ..moveTo(x + d * 0.4, g)
            ..quadraticBezierTo(
              x + d * 0.6,
              g - tall * 0.6,
              x + d * 1.5,
              g - tall,
            ),
          blade,
        );
      }
      canvas.drawPath(
        Path()
          ..moveTo(x, g + 1)
          ..cubicTo(x - 4, g + 8, x + 5, g + 12, x + 1, g + 20),
        root,
      );
    }

    // Ground line over the strata.
    canvas.drawLine(
      Offset(0, g),
      Offset(w, g),
      Paint()
        ..color = c.muted.withValues(alpha: 0.5)
        ..strokeWidth = 1.2,
    );

    // Tunnels run level and straight, like a tidy network diagram:
    // a shaft down from the entrance, then corridors to arched rooms.
    final hollow = dark
        ? Color.lerp(c.bg, Colors.black, 0.35)!
        : Color.lerp(c.bg, c.soil, 0.2)!;
    final ex = w * 0.42;
    final l1 = h * 0.62, l2 = h * 0.86;
    // (x, floor level) for each room.
    final rooms = switch (scene) {
      Scene.welcome => [(w * 0.2, l1), (w * 0.64, l1), (w * 0.82, l2)],
      Scene.quiet => [(w * 0.7, l1)],
      Scene.empty => <(double, double)>[],
    };
    final path = Path()
      ..moveTo(ex, g)
      ..lineTo(ex, l1);
    for (final (x, level) in rooms) {
      path.moveTo(ex, l1);
      if (level == l1) {
        path.lineTo(x, l1);
      } else {
        final turn = x - w * 0.09;
        path
          ..lineTo(turn, l1)
          ..lineTo(turn, level)
          ..lineTo(x, level);
      }
    }
    if (scene == Scene.empty) {
      path
        ..moveTo(ex, l1)
        ..lineTo(w * 0.62, l1);
    }
    Paint stroke(double width, Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(path, stroke(16, c.clay.withValues(alpha: 0.28)));
    canvas.drawPath(path, stroke(11, hollow));

    // Rooms are arches, the same shape as the Burrow mark.
    for (var i = 0; i < rooms.length; i++) {
      final (x, level) = rooms[i];
      final floor = level + 5.5;
      final room = Rect.fromLTRB(x - 22, floor - 36, x + 22, floor);
      final rim = Rect.fromLTRB(
        room.left - 3,
        room.top - 3,
        room.right + 3,
        floor + 3,
      );
      canvas.drawPath(
        archPath(rim)..close(),
        Paint()..color = c.clay.withValues(alpha: 0.38),
      );
      canvas.drawPath(archPath(room)..close(), Paint()..color = hollow);
      canvas.drawPath(
        archPath(room)..close(),
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -0.2),
            radius: 0.75,
            colors: [
              c.accent.withValues(alpha: dark ? 0.3 : 0.24),
              c.accent.withValues(alpha: 0),
            ],
          ).createShader(room),
      );
      // A small lamp hangs from the top of each room.
      final lamp = Offset(x, room.top + 9);
      canvas.drawLine(
        Offset(x, room.top + 1),
        lamp,
        Paint()
          ..color = c.muted.withValues(alpha: 0.5)
          ..strokeWidth = 0.8,
      );
      canvas.drawCircle(lamp, 2, Paint()..color = c.accent);
      _server(
        canvas,
        Offset(x, floor - 10),
        online: i == 0 || scene == Scene.quiet,
      );
    }

    // An empty corridor ends in a lantern, waiting.
    if (scene == Scene.empty) _lantern(canvas, Offset(w * 0.62, l1));

    // Entrance: the Burrow arch on the surface.
    final arch = Rect.fromLTWH(ex - 19, g - 30, 38, 30);
    canvas.drawPath(archPath(arch)..close(), Paint()..color = c.clay);
    canvas.drawPath(
      archPath(Rect.fromLTRB(arch.left + 6, arch.top + 6, arch.right - 6, g))
        ..close(),
      Paint()..color = hollow,
    );
    canvas.drawPath(
      archPath(Rect.fromLTRB(arch.left + 11, arch.top + 11, arch.right - 11, g))
        ..close(),
      Paint()..color = c.accent.withValues(alpha: 0.55),
    );

    // Fade out at the sides and bottom so the scene sits softly on the page.
    final all = Offset.zero & s;
    canvas.drawRect(
      all,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          colors: [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0, 0.2, 0.8, 1],
        ).createShader(all),
    );
    canvas.drawRect(
      all,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0, 0.1, 0.93, 1],
        ).createShader(all),
    );
    canvas.restore();
  }

  /// A two-unit server rack with status lights.
  void _server(Canvas canvas, Offset at, {required bool online}) {
    final body = Rect.fromCenter(center: at, width: 20, height: 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body.translate(0, 1.5), const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(3)),
      Paint()..color = c.muted,
    );
    final slot = Paint()
      ..color = c.bg.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(body.left + 2, body.center.dy),
      Offset(body.right - 2, body.center.dy),
      slot,
    );
    for (final dy in [-4.5, 4.5]) {
      final y = body.center.dy + dy;
      canvas.drawLine(
        Offset(body.left + 4, y),
        Offset(body.left + 11, y),
        slot,
      );
      canvas.drawCircle(
        Offset(body.right - 4.5, y),
        1.6,
        Paint()..color = online ? c.success : c.accent,
      );
    }
  }

  void _lantern(Canvas canvas, Offset at) {
    canvas.drawCircle(
      at,
      14,
      Paint()
        ..color = c.accent.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(at, 3.5, Paint()..color = c.accent);
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
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(width, height),
      painter: _SparkPainter(samples, context.c),
    ),
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
