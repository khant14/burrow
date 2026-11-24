import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import '../../models/host.dart';
import '../../state/workspace.dart';
import '../theme.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/host_editor.dart';
import '../widgets/settings.dart';
import '../widgets/terminal_pane.dart';

/// Phone layout: host list, then a full-screen terminal with a key bar.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  String _filter = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Scope.of(context).workspace.askPassword = (h) =>
        askPassword(context, h.label);
  }

  Future<void> _open(Host h) async {
    final ws = Scope.of(context).workspace;
    final i = ws.tabs.indexWhere((t) => t.panes.any((p) => p.host.id == h.id));
    final TerminalSession? s;
    if (i >= 0) {
      ws.focus(i);
      s = ws.tabs[i].active;
    } else {
      s = await ws.open(h);
    }
    if (s == null || !mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => MobileTerminal(session: s!)));
  }

  @override
  Widget build(BuildContext context) {
    final scope = Scope.of(context);
    final c = context.c;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.app, scope.workspace]),
      builder: (context, _) {
        final groups = scope.app.grouped(_filter);
        return Scaffold(
          // The search lives at the bottom, where thumbs are.
          bottomNavigationBar: scope.app.hosts.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      12 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _filter = v),
                      style: TextStyle(fontSize: 15, color: c.text),
                      decoration: InputDecoration(
                        hintText: 'Where to?',
                        fillColor: c.raised,
                        prefixIcon: Icon(
                          Icons.search,
                          size: 19,
                          color: c.accent,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.accent),
                        ),
                      ),
                    ),
                  ),
                ),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: c.bg,
                titleSpacing: 16,
                // Logo and name share one row, like the desktop header.
                title: const Row(
                  children: [
                    BurrowMark(size: 26),
                    SizedBox(width: 10),
                    Flexible(child: Heading('Burrow', size: 22, maxLines: 1)),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Add a host',
                    onPressed: () => editHost(context, compact: true),
                    icon: Icon(Icons.add, color: c.text, size: 22),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => showSettings(context, compact: true),
                    icon: Icon(Icons.tune, color: c.muted, size: 20),
                  ),
                ],
              ),
              if (scope.app.hosts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BurrowIllustration(Scene.welcome, width: 300),
                          const SizedBox(height: 24),
                          const Heading(
                            'Make yourself at home',
                            size: 24,
                            align: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add a server and Burrow will keep it close.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: c.muted,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: () => editHost(context, compact: true),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add a host'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList.list(
                  children: [
                    for (final e in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                        child: Text(
                          e.key.isEmpty ? 'Unsorted' : e.key,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.muted,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: c.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < e.value.length; i++) ...[
                              if (i > 0) Divider(indent: 44, color: c.border),
                              _HostTile(
                                host: e.value[i],
                                status: scope.workspace.statusFor(e.value[i]),
                                onTap: () => _open(e.value[i]),
                                onLongPress: () => editHost(
                                  context,
                                  host: e.value[i],
                                  compact: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HostTile extends StatelessWidget {
  const _HostTile({
    required this.host,
    required this.status,
    required this.onTap,
    required this.onLongPress,
  });
  final Host host;
  final SessionStatus? status;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = switch (status) {
      SessionStatus.connected => 'connected',
      SessionStatus.connecting => 'connecting',
      SessionStatus.failed => 'connection failed',
      SessionStatus.closed => 'closed',
      null => null,
    };
    return Semantics(
      button: true,
      label: [host.label, host.address, ?state].join(', '),
      onTapHint: 'Connect',
      onLongPressHint: 'Edit host',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          // 56px rows keep targets thumb-sized.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              StatusDot(status, size: 9),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      host.address,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.faint),
                    ),
                  ],
                ),
              ),
              HealthBadge(host.id),
            ],
          ),
        ),
      ),
    );
  }
}

class MobileTerminal extends StatefulWidget {
  const MobileTerminal({super.key, required this.session});
  final TerminalSession session;

  @override
  State<MobileTerminal> createState() => _MobileTerminalState();
}

class _MobileTerminalState extends State<MobileTerminal> {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.session;
    final app = Scope.of(context).app;
    return ListenableBuilder(
      listenable: Listenable.merge([s, app]),
      builder: (context, _) {
        final bg = BurrowTerminalTheme.byId(app.terminalThemeId)
            .theme
            .background;
        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            systemOverlayStyle: bg.computeLuminance() > 0.5
                ? SystemUiOverlayStyle.dark
                : SystemUiOverlayStyle.light,
            titleSpacing: 0,
            title: Row(
              children: [
                StatusDot(s.status, size: 7),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    s.host.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, color: c.muted),
                color: c.raised,
                onSelected: (v) {
                  if (v == 'close') {
                    final ws = Scope.of(context).workspace;
                    final i = ws.tabs.indexWhere((t) => t.panes.contains(s));
                    Navigator.pop(context);
                    if (i >= 0) ws.closeTab(i);
                  } else {
                    s.run(v);
                  }
                },
                itemBuilder: (_) => [
                  for (final sn in app.snippets)
                    PopupMenuItem(value: sn.command, child: Text(sn.name)),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'close',
                    child: Text('Disconnect'),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: TerminalPane(
                    session: s,
                    padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                  ),
                ),
                KeyBar(session: s, onAnyKey: () => s.focusNode.requestFocus()),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Swipeable row of keys phones don't have.
class KeyBar extends StatelessWidget {
  const KeyBar({super.key, required this.session, this.onAnyKey});
  final TerminalSession session;
  final VoidCallback? onAnyKey;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = session.terminal;
    void key(TerminalKey k) {
      HapticFeedback.selectionClick();
      t.keyInput(k, ctrl: session.ctrlLatched);
      if (session.ctrlLatched) session.toggleCtrl();
      onAnyKey?.call();
    }

    void text(String s) {
      HapticFeedback.selectionClick();
      t.textInput(s);
      onAnyKey?.call();
    }

    final keys = <Widget>[
      _Key(
        label: 'esc',
        semantic: 'Escape',
        onTap: () => key(TerminalKey.escape),
      ),
      _Key(
        label: 'ctrl',
        semantic: 'Control',
        active: session.ctrlLatched,
        onTap: () {
          HapticFeedback.selectionClick();
          session.toggleCtrl();
          onAnyKey?.call();
        },
      ),
      _Key(label: 'tab', semantic: 'Tab', onTap: () => key(TerminalKey.tab)),
      _Key(
        icon: Icons.keyboard_arrow_up,
        semantic: 'Up arrow',
        onTap: () => key(TerminalKey.arrowUp),
      ),
      _Key(
        icon: Icons.keyboard_arrow_down,
        semantic: 'Down arrow',
        onTap: () => key(TerminalKey.arrowDown),
      ),
      _Key(
        icon: Icons.keyboard_arrow_left,
        semantic: 'Left arrow',
        onTap: () => key(TerminalKey.arrowLeft),
      ),
      _Key(
        icon: Icons.keyboard_arrow_right,
        semantic: 'Right arrow',
        onTap: () => key(TerminalKey.arrowRight),
      ),
      for (final s in ['|', '/', '-', '~', ':', '*', r'$', '&'])
        _Key(label: s, mono: true, onTap: () => text(s)),
    ];
    // 56pt bar leaves 44pt keys, Apple's minimum touch target.
    final bar = Container(
      height: 56,
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        children: keys,
      ),
    );
    // Keys keep a fixed height, so cap how far large text grows inside them.
    return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: bar);
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    required this.onTap,
    this.active = false,
    this.mono = false,
    this.semantic,
  });
  final String? semantic;
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool active, mono;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      toggled: label == 'ctrl' ? active : null,
      label: semantic ?? label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: kFast,
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? c.accent : c.raised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: active ? c.accent : c.border),
            ),
            child: icon != null
                ? Icon(icon, size: 18, color: c.text)
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: mono ? kMono : null,
                      fontWeight: FontWeight.w500,
                      color: active ? c.onAccent : c.text,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
