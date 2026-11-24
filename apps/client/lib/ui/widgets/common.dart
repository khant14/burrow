import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/app_state.dart';
import '../../state/health.dart';
import '../../state/sync.dart';
import '../../state/workspace.dart';
import 'art.dart';
import '../theme.dart';

/// Gives widgets access to app state without a state-management package.
class Scope extends InheritedWidget {
  const Scope({
    super.key,
    required this.app,
    required this.workspace,
    required this.health,
    required this.sync,
    required super.child,
  });
  final AppState app;
  final Workspace workspace;
  final HealthMonitor health;
  final SyncService sync;

  static Scope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Scope>()!;

  @override
  bool updateShouldNotify(Scope old) =>
      app != old.app || workspace != old.workspace;
}

final bool isMac = Platform.isMacOS;

/// iPad and Mac share the ⌘ shortcut layer.
final bool isApple = Platform.isMacOS || Platform.isIOS;
final String modKey = isApple ? '⌘' : 'Ctrl+Shift+';

/// True while the app's shortcut modifier is held (⌘ on macOS, Ctrl+Shift elsewhere).
/// Terminals ignore these keys so app shortcuts never leak into the shell.
bool get appModifierPressed {
  final k = HardwareKeyboard.instance;
  return isApple ? k.isMetaPressed : (k.isControlPressed && k.isShiftPressed);
}

/// Matched by physical key, since Shift changes the logical key (Shift+, is "<").
final _appKeys = {
  PhysicalKeyboardKey.keyK,
  PhysicalKeyboardKey.keyT,
  PhysicalKeyboardKey.keyD,
  PhysicalKeyboardKey.keyW,
  PhysicalKeyboardKey.keyN,
  PhysicalKeyboardKey.keyB,
  PhysicalKeyboardKey.comma,
  PhysicalKeyboardKey.digit1,
  PhysicalKeyboardKey.digit2,
  PhysicalKeyboardKey.digit3,
  PhysicalKeyboardKey.digit4,
  PhysicalKeyboardKey.digit5,
  PhysicalKeyboardKey.digit6,
  PhysicalKeyboardKey.digit7,
  PhysicalKeyboardKey.digit8,
  PhysicalKeyboardKey.digit9,
};

/// App shortcuts (palette, split, close, tab switch). Other ⌘ keys such as copy and paste reach the terminal.
bool isAppShortcut(KeyEvent e) =>
    appModifierPressed && _appKeys.contains(e.physicalKey);

class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key, this.size = 7});
  final SessionStatus? status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = switch (status) {
      SessionStatus.connected => c.success,
      SessionStatus.connecting => c.accent,
      SessionStatus.failed => c.danger,
      SessionStatus.closed || null => c.faint,
    };
    final label = switch (status) {
      SessionStatus.connected => 'Connected',
      SessionStatus.connecting => 'Connecting',
      SessionStatus.failed => 'Connection failed',
      SessionStatus.closed => 'Closed',
      null => 'Not connected',
    };
    return Semantics(
      label: label,
      child: AnimatedContainer(
        duration: kFast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: status == null ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: status == null
              ? Border.all(color: c.faint, width: 1.2)
              : null,
          boxShadow: status == SessionStatus.connected
              ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }
}

/// A row that highlights on hover, used in the sidebar and palette.
class HoverRow extends StatefulWidget {
  const HoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTapDown,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    this.radius = 6,
  });
  final Widget child;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool selected;
  final EdgeInsets padding;
  final double radius;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: widget.onTap != null,
      selected: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: AnimatedContainer(
            duration: kFast,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: widget.selected
                  ? c.hover
                  : (_hover
                        ? c.hover.withValues(alpha: 0.6)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: c.muted,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: context.c.faint,
      ),
    ),
  );
}

/// Fades a dialog in quickly, with no scale or bounce.
Future<T?> showFadeDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  Alignment align = Alignment.center,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: kFast,
    pageBuilder: (ctx, _, _) => Align(alignment: align, child: builder(ctx)),
    transitionBuilder: (_, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

Future<String?> askPassword(BuildContext context, String address) {
  final ctrl = TextEditingController();
  return showFadeDialog<String>(context, (ctx) {
    final c = ctx.c;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Heading('Knock knock', size: 20),
            const SizedBox(height: 4),
            Text(
              'Password for $address. Burrow keeps it for this session only.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Password'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                  child: const Text('Open tunnel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  });
}

/// Inline server health: latency and a tiny history, or "unreachable".
class HealthBadge extends StatelessWidget {
  const HealthBadge(this.hostId, {super.key, this.spark = true});
  final String hostId;
  final bool spark;

  @override
  Widget build(BuildContext context) {
    final h = Scope.of(context).health;
    final c = context.c;
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        if (!h.checked(hostId)) return const SizedBox.shrink();
        final ms = h.latest(hostId);
        return Semantics(
          label: ms == null ? 'Unreachable' : 'Latency $ms milliseconds',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spark && h.samples(hostId).whereType<int>().length > 1) ...[
                Sparkline(h.samples(hostId)),
                const SizedBox(width: 6),
              ],
              Text(
                ms == null ? 'down' : '$ms ms',
                style: TextStyle(
                  fontFamily: kMono,
                  fontSize: 10.5,
                  color: ms == null
                      ? c.danger
                      : (ms > 150 ? c.accent : c.faint),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Display heading in Fraunces, the Burrow voice.
class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.size = 24, this.align});
  final String text;
  final double size;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontFamily: kDisplay,
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.15,
        letterSpacing: -0.2,
        color: context.c.text,
      ),
    ),
  );
}
