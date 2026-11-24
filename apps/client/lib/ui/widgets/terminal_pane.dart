import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import '../../state/workspace.dart';
import '../theme.dart';
import 'art.dart';
import 'common.dart';

final bool isDesktop =
    Platform.isMacOS || Platform.isLinux || Platform.isWindows;

/// A terminal with a quiet overlay for connecting / closed / failed states.
class TerminalPane extends StatelessWidget {
  const TerminalPane({
    super.key,
    required this.session,
    this.focused = true,
    this.onFocus,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 8, 8),
    this.focusNode,
  });

  final TerminalSession session;
  final bool focused;
  final VoidCallback? onFocus;
  final EdgeInsets padding;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context).app;
    return ListenableBuilder(
      listenable: Listenable.merge([session, app]),
      builder: (context, _) {
        final theme = BurrowTerminalTheme.byId(app.terminalThemeId).theme;
        return Listener(
          onPointerDown: (_) => onFocus?.call(),
          child: Container(
            color: theme.background,
            child: Stack(
              children: [
                Positioned.fill(
                  child: TerminalView(
                    session.terminal,
                    key: ValueKey(session.id),
                    theme: theme,
                    focusNode: focusNode ?? session.focusNode,
                    // Desktop reads raw key events; the IME path drops or repeats keys there.
                    hardwareKeyboardOnly: isDesktop,
                    onKeyEvent: (_, e) => isAppShortcut(e)
                        ? KeyEventResult.skipRemainingHandlers
                        : KeyEventResult.ignored,
                    autofocus: focused,
                    padding: padding,
                    keyboardAppearance: Theme.of(context).brightness,
                    textStyle: TerminalStyle(
                      fontFamily: kMono,
                      fontSize: app.fontSize,
                      height: 1.25,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: session.status == SessionStatus.connected,
                    child: AnimatedOpacity(
                      duration: kFast,
                      opacity: session.status == SessionStatus.connected
                          ? 0
                          : 1,
                      child: _Overlay(session: session, bg: theme.background),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.session, required this.bg});
  final TerminalSession session;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = session.status;
    final name = session.host.label;
    if (s == SessionStatus.connecting) {
      // Signature moment: a quiet tunnel animation instead of a spinner.
      return Container(
        color: bg,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TunnelLoader(size: 92),
            const SizedBox(height: 18),
            Heading(
              'Digging a tunnel to $name',
              size: 18,
              align: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '${session.host.address}:${session.host.port}',
              style: TextStyle(fontSize: 12, color: c.muted, fontFamily: kMono),
            ),
          ],
        ),
      );
    }
    final failed = s == SessionStatus.failed;
    // While closed, keep the scrollback visible under a light scrim.
    return Container(
      color: failed ? bg : bg.withValues(alpha: 0.6),
      alignment: failed ? Alignment.center : Alignment.bottomCenter,
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Heading(
              failed ? "Couldn't reach $name" : 'Tunnel to $name closed',
              size: 17,
              align: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              failed
                  ? (session.error ?? 'Unknown error')
                  : 'The shell exited. Your scrollback is still here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: session.connect,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(failed ? 'Try again' : 'Reopen tunnel'),
            ),
          ],
        ),
      ),
    );
  }
}
