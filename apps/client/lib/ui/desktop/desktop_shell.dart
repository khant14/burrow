import 'dart:io';

import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/host.dart';
import '../../state/app_state.dart';
import '../../state/workspace.dart';
import '../theme.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/host_editor.dart';
import '../widgets/settings.dart';
import '../widgets/terminal_pane.dart';
import 'command_palette.dart';

/// Desktop layout. The command palette is the main way around; the sidebar of
/// burrows is a quiet map you can hide (⌘B), and tabs only appear once you dig in.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  late final Workspace ws = Scope.of(context).workspace;
  late final AppState app = Scope.of(context).app;
  bool _paletteOpen = false;
  bool _sidebar = true;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ws.askPassword = (h) => askPassword(context, h.label);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Global shortcuts run before the terminal sees the key. ⌘ on Apple platforms, Ctrl+Shift elsewhere.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    if (!isAppShortcut(e)) return false;
    const digits = [
      PhysicalKeyboardKey.digit1,
      PhysicalKeyboardKey.digit2,
      PhysicalKeyboardKey.digit3,
      PhysicalKeyboardKey.digit4,
      PhysicalKeyboardKey.digit5,
      PhysicalKeyboardKey.digit6,
      PhysicalKeyboardKey.digit7,
      PhysicalKeyboardKey.digit8,
      PhysicalKeyboardKey.digit9,
    ];
    final key = e.physicalKey;
    final tab = digits.indexOf(key);
    if (tab >= 0) {
      ws.focus(tab);
    } else {
      _command(key);
    }
    return true;
  }

  DateTime _lastAt = DateTime(0);
  PhysicalKeyboardKey? _lastKey;

  /// Runs an app command. The macOS menu bar and the key handler can both see
  /// the same ⌘ press, so a repeat within a moment is dropped.
  void _command(PhysicalKeyboardKey key) {
    final now = DateTime.now();
    if (key == _lastKey && now.difference(_lastAt).inMilliseconds < 150) return;
    _lastKey = key;
    _lastAt = now;
    if (key == PhysicalKeyboardKey.keyK || key == PhysicalKeyboardKey.keyT) {
      openPalette();
    } else if (key == PhysicalKeyboardKey.keyD) {
      ws.split();
    } else if (key == PhysicalKeyboardKey.keyW) {
      ws.closeActive();
    } else if (key == PhysicalKeyboardKey.keyN) {
      editHost(context, compact: false);
    } else if (key == PhysicalKeyboardKey.keyB) {
      toggleSidebar();
    } else if (key == PhysicalKeyboardKey.comma) {
      showSettings(context, compact: false);
    }
  }

  PlatformMenuItem _item(
    String label,
    PhysicalKeyboardKey key,
    LogicalKeyboardKey shortcut,
  ) => PlatformMenuItem(
    label: label,
    shortcut: SingleActivator(shortcut, meta: true),
    onSelected: () => _command(key),
  );

  /// Standard macOS menus, so the app behaves like a Mac app from the menu bar.
  List<PlatformMenuItem> _menus() => [
    PlatformMenu(
      label: 'Burrow',
      menus: [
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            _item(
              'Settings…',
              PhysicalKeyboardKey.comma,
              LogicalKeyboardKey.comma,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
      ],
    ),
    PlatformMenu(
      label: 'File',
      menus: [
        PlatformMenuItemGroup(
          members: [
            _item(
              'New Host…',
              PhysicalKeyboardKey.keyN,
              LogicalKeyboardKey.keyN,
            ),
            _item('Go To…', PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            _item(
              'Split Pane',
              PhysicalKeyboardKey.keyD,
              LogicalKeyboardKey.keyD,
            ),
            _item(
              'Close Pane',
              PhysicalKeyboardKey.keyW,
              LogicalKeyboardKey.keyW,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'View',
      menus: [
        _item(
          'Toggle Sidebar',
          PhysicalKeyboardKey.keyB,
          LogicalKeyboardKey.keyB,
        ),
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.toggleFullScreen,
        ),
      ],
    ),
    const PlatformMenu(
      label: 'Window',
      menus: [
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.minimizeWindow,
        ),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
        ),
      ],
    ),
  ];

  void toggleSidebar() => setState(() => _sidebar = !_sidebar);

  Future<void> openPalette() async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    await showCommandPalette(context, _actions());
    _paletteOpen = false;
  }

  List<PaletteAction> _actions() {
    final active = ws.active;
    return [
      for (final h in app.hosts)
        PaletteAction(
          section: 'Hosts',
          title: h.label,
          subtitle: h.group.isEmpty ? h.address : '${h.group}  ·  ${h.address}',
          icon: Icons.arrow_outward,
          trailing: HealthBadge(h.id, spark: false),
          run: () => ws.open(h),
        ),
      if (active != null)
        for (final s in app.snippets)
          PaletteAction(
            section: 'Snippets  ·  runs in ${active.active.host.label}',
            title: s.name,
            subtitle: s.command,
            icon: Icons.play_arrow_outlined,
            run: () => active.active.run(s.command),
          ),
      if (active != null) ...[
        for (var i = 0; i < ws.tabs.length; i++)
          PaletteAction(
            section: 'Open tunnels',
            title: ws.tabs[i].active.host.label,
            subtitle: ws.tabs[i].panes.length > 1
                ? '${ws.tabs[i].panes.length} panes'
                : null,
            icon: Icons.subdirectory_arrow_right,
            shortcut: i < 9 ? '$modKey${i + 1}' : null,
            run: () => ws.focus(i),
          ),
        PaletteAction(
          section: 'Burrow',
          title: 'Split this tunnel',
          icon: Icons.vertical_split_outlined,
          shortcut: '${modKey}D',
          run: ws.split,
        ),
        PaletteAction(
          section: 'Burrow',
          title: 'Close this pane',
          icon: Icons.close,
          shortcut: '${modKey}W',
          run: ws.closeActive,
        ),
      ],
      PaletteAction(
        section: 'Burrow',
        title: 'Add a host',
        icon: Icons.add,
        shortcut: '${modKey}N',
        run: () => editHost(context, compact: false),
      ),
      if (AppState.canImportSshConfig)
        PaletteAction(
          section: 'Burrow',
          title: 'Import ~/.ssh/config',
          icon: Icons.download_outlined,
          run: _import,
        ),
      PaletteAction(
        section: 'Burrow',
        title: _sidebar ? 'Hide the sidebar' : 'Show the sidebar',
        icon: Icons.view_sidebar_outlined,
        shortcut: '${modKey}B',
        run: () => toggleSidebar(),
      ),
      PaletteAction(
        section: 'Burrow',
        title: app.themeMode == ThemeMode.light
            ? 'Switch to Loam (dark)'
            : 'Switch to Sand (light)',
        icon: Icons.contrast,
        run: () => app.setThemeMode(
          app.themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
        ),
      ),
      PaletteAction(
        section: 'Burrow',
        title: 'Settings',
        // Terminal themes live only in Settings, where they can be previewed.
        subtitle: 'Themes, terminal colors, font size',
        icon: Icons.tune,
        shortcut: '$modKey,',
        run: () => showSettings(context, compact: false),
      ),
    ];
  }

  Future<void> _import() async {
    String? text;
    if (isMac) {
      final user = Platform.environment['USER'];
      final f = await openFile(
        initialDirectory: user == null ? null : '/Users/$user/.ssh',
        confirmButtonText: 'Import',
      );
      if (f == null || !mounted) return;
      text = await f.readAsString();
      if (!mounted) return;
    }
    final n = app.importSshConfig(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 360,
        content: Text(
          n == 0
              ? 'Nothing new in ~/.ssh/config. You already have them all.'
              : 'Brought in $n host${n == 1 ? '' : 's'} from ~/.ssh/config'
                    '${isMac ? '. Add each key in the host settings.' : ''}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shell = _build(context);
    return isMac ? PlatformMenuBar(menus: _menus(), child: shell) : shell;
  }

  Widget _build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      // Wide layout also runs on phones in landscape and on tablets: keep clear of
      // the status bar, notch and navigation bar, with the header colour behind them.
      backgroundColor: c.sidebar,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([ws, app]),
          builder: (context, _) => Column(
            children: [
              _Header(shell: this),
              Expanded(
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: kFast,
                      curve: Curves.easeOut,
                      width: _sidebar ? 264 : 0,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: 264,
                          maxWidth: 264,
                          child: _Sidebar(shell: this),
                        ),
                      ),
                    ),
                    if (_sidebar) VerticalDivider(width: 1, color: c.border),
                    Expanded(
                      child: Column(
                        children: [
                          if (ws.tabs.isNotEmpty) _TabStrip(ws: ws),
                          Expanded(
                            child: ws.tabs.isEmpty
                                ? _EmptyState(shell: this)
                                : IndexedStack(
                                    index: ws.activeIndex,
                                    sizing: StackFit.expand,
                                    children: [
                                      for (var i = 0; i < ws.tabs.length; i++)
                                        _TabBody(ws: ws, index: i),
                                    ],
                                  ),
                          ),
                          if (ws.tabs.isNotEmpty) _StatusBar(ws: ws),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top bar: the mark, and the palette front and centre.
class _Header extends StatelessWidget {
  const _Header({required this.shell});
  final _DesktopShellState shell;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          // Always visible, so a hidden sidebar is one click from coming back.
          IconButton(
            tooltip:
                '${shell._sidebar ? 'Hide' : 'Show'} the sidebar  ${modKey}B',
            onPressed: shell.toggleSidebar,
            icon: Icon(
              shell._sidebar ? Icons.menu_open : Icons.menu,
              size: 19,
              color: shell._sidebar ? c.text : c.muted,
            ),
          ),
          const SizedBox(width: 6),
          const BurrowMark(size: 26),
          const SizedBox(width: 10),
          const Heading('Burrow', size: 19),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: HoverRow(
                    onTap: shell.openPalette,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Container(
                      decoration: const BoxDecoration(),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 17, color: c.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Where to?  ',
                                    style: TextStyle(
                                      color: c.text,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Hosts, snippets, anything',
                                    style: TextStyle(
                                      color: c.faint,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Kbd('${modKey}K'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => showSettings(context, compact: false),
            icon: Icon(Icons.tune, size: 18, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({required this.shell});
  final _DesktopShellState shell;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final Set<String> _collapsed = {};

  void _menu(Host h, Offset at) async {
    final shell = widget.shell;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      color: context.c.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: context.c.border),
      ),
      items: const [
        PopupMenuItem(
          value: 'open',
          height: 34,
          child: Text('Open tunnel', style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          value: 'split',
          height: 34,
          child: Text('Open beside', style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          value: 'edit',
          height: 34,
          child: Text('Edit…', style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 34,
          child: Text('Remove', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'open':
        shell.ws.open(h);
      case 'split':
        shell.ws.active == null ? shell.ws.open(h) : shell.ws.split(h);
      case 'edit':
        editHost(context, host: h, compact: false);
      case 'delete':
        shell.app.removeHost(h);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shell = widget.shell;
    final groups = shell.app.grouped();
    return Container(
      color: c.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 10, 4),
            child: Row(
              children: [
                Expanded(child: Heading('Burrows', size: 15)),
                IconButton(
                  tooltip: 'Add a host  ${modKey}N',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => editHost(context, compact: false),
                  icon: Icon(Icons.add, size: 17, color: c.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: shell.app.hosts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Text(
                      'Empty for now. Your hosts will live here.',
                      style: TextStyle(
                        color: c.faint,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                    children: [
                      for (final e in groups.entries) ...[
                        GestureDetector(
                          onTap: () => setState(
                            () => _collapsed.contains(e.key)
                                ? _collapsed.remove(e.key)
                                : _collapsed.add(e.key),
                          ),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                              child: Row(
                                children: [
                                  AnimatedRotation(
                                    turns: _collapsed.contains(e.key)
                                        ? -0.25
                                        : 0,
                                    duration: kFast,
                                    child: Icon(
                                      Icons.expand_more,
                                      size: 15,
                                      color: c.faint,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      e.key.isEmpty ? 'Unsorted' : e.key,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: c.muted,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${e.value.length}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.faint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: kFast,
                          alignment: Alignment.topCenter,
                          child: _collapsed.contains(e.key)
                              ? const SizedBox(width: double.infinity)
                              : Column(
                                  children: [
                                    for (final h in e.value) _hostRow(h),
                                  ],
                                ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _hostRow(Host h) {
    final c = context.c;
    final ws = widget.shell.ws;
    final status = ws.statusFor(h);
    final isActive = ws.active?.active.host.id == h.id;
    return HoverRow(
      selected: isActive,
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
      onTap: () {
        // Jump to an open tunnel for this host, or dig a new one.
        final i = ws.tabs.indexWhere(
          (t) => t.panes.any((p) => p.host.id == h.id),
        );
        i >= 0 ? ws.focus(i) : ws.open(h);
      },
      onSecondaryTapDown: (d) => _menu(h, d.globalPosition),
      child: Row(
        children: [
          StatusDot(status),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  h.address,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.faint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          HealthBadge(h.id),
        ],
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.ws});
  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 38,
      padding: const EdgeInsets.only(left: 8, top: 6),
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < ws.tabs.length; i++)
            _Tab(
              tab: ws.tabs[i],
              active: i == ws.activeIndex,
              onTap: () => ws.focus(i),
              onClose: () => ws.closeTab(i),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });
  final WorkspaceTab tab;
  final bool active;
  final VoidCallback onTap, onClose;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.tab.active;
    final title = widget.tab.panes.length > 1
        ? '${s.host.label} +${widget.tab.panes.length - 1}'
        : s.host.label;
    // Tabs are tunnel mouths: arched tops, joined to the terminal below.
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTertiaryTapUp: (_) => widget.onClose(),
        child: AnimatedContainer(
          duration: kFast,
          margin: const EdgeInsets.only(right: 4),
          constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: widget.active
                ? c.bg
                : (_hover
                      ? c.hover.withValues(alpha: 0.6)
                      : Colors.transparent),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: widget.active
                ? Border(
                    top: BorderSide(color: c.border),
                    left: BorderSide(color: c.border),
                    right: BorderSide(color: c.border),
                  )
                : null,
          ),
          child: Row(
            children: [
              StatusDot(s.status, size: 6),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: widget.active ? c.text : c.muted,
                    fontWeight: widget.active
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedOpacity(
                duration: kFast,
                opacity: _hover || widget.active ? 1 : 0,
                child: InkResponse(
                  onTap: widget.onClose,
                  radius: 12,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 13, color: c.faint),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({required this.ws, required this.index});
  final Workspace ws;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tab = ws.tabs[index];
    final children = <Widget>[];
    for (var i = 0; i < tab.panes.length; i++) {
      if (i > 0) children.add(VerticalDivider(width: 1, color: c.border));
      final focused =
          tab.panes.length > 1 && i == tab.focused && index == ws.activeIndex;
      children.add(
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: TerminalPane(
                  session: tab.panes[i],
                  focused: i == tab.focused && index == ws.activeIndex,
                  onFocus: () => ws.focus(index, i),
                ),
              ),
              // Thin ember line marks the focused pane in a split.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: AnimatedOpacity(
                  duration: kFast,
                  opacity: focused ? 1 : 0,
                  child: Container(
                    height: 1.5,
                    color: c.accent.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.ws});
  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ws.active?.active;
    if (s == null) return const SizedBox.shrink();
    final style = TextStyle(fontSize: 11.5, color: c.faint);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          StatusDot(s.status, size: 6),
          const SizedBox(width: 8),
          Text(switch (s.status) {
            SessionStatus.connecting => 'Digging…',
            SessionStatus.connected => 'Tunnel open',
            SessionStatus.closed => 'Tunnel closed',
            SessionStatus.failed => "Couldn't reach host",
          }, style: style.copyWith(color: c.muted)),
          const SizedBox(width: 10),
          Text(
            '${s.host.address}:${s.host.port}',
            style: style.copyWith(fontFamily: kMono, fontSize: 11),
          ),
          const Spacer(),
          HealthBadge(s.host.id, spark: false),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.shell});
  final _DesktopShellState shell;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final noHosts = shell.app.hosts.isEmpty;
    return Container(
      color: c.bg,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BurrowIllustration(
              noHosts ? Scene.welcome : Scene.quiet,
              width: 360,
            ),
            const SizedBox(height: 28),
            Heading(
              noHosts ? 'Make yourself at home' : 'All quiet down here',
              size: 28,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 420,
              child: Text(
                noHosts
                    ? 'Burrow keeps your servers close. Bring in the hosts you already have, or add your first one.'
                    : 'Press ${modKey}K and type a host name to open a tunnel. Everything else lives there too.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: c.muted),
              ),
            ),
            const SizedBox(height: 26),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (noHosts && AppState.canImportSshConfig) ...[
                  OutlinedButton.icon(
                    onPressed: shell._import,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Import ~/.ssh/config'),
                  ),
                  const SizedBox(width: 10),
                ],
                if (noHosts)
                  FilledButton.icon(
                    onPressed: () => editHost(context, compact: false),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add a host'),
                  )
                else
                  FilledButton.icon(
                    onPressed: shell.openPalette,
                    icon: const Icon(Icons.search, size: 16),
                    label: Text('Where to?   ${modKey}K'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
