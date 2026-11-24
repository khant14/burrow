import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../widgets/common.dart';

class PaletteAction {
  const PaletteAction({
    required this.title,
    required this.icon,
    required this.run,
    this.subtitle,
    this.section = 'Actions',
    this.shortcut,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final String section;
  final String? shortcut;
  final Widget? trailing;
  final VoidCallback run;
}

Future<void> showCommandPalette(
  BuildContext context,
  List<PaletteAction> actions,
) async {
  final chosen = await showFadeDialog<PaletteAction>(
    context,
    (ctx) => Padding(
      padding: const EdgeInsets.only(top: 96),
      child: _Palette(actions: actions),
    ),
    align: Alignment.topCenter,
  );
  chosen?.run();
}

class _Palette extends StatefulWidget {
  const _Palette({required this.actions});
  final List<PaletteAction> actions;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  int _sel = 0;

  List<PaletteAction> get _matches {
    final q = _query.text.toLowerCase().trim();
    if (q.isEmpty) return widget.actions;
    final words = q.split(RegExp(r'\s+'));
    return widget.actions.where((a) {
      final hay = '${a.section} ${a.title} ${a.subtitle ?? ''}'.toLowerCase();
      return words.every(hay.contains);
    }).toList();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final n = _matches.length;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _sel = n == 0 ? 0 : (_sel + 1) % n);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _sel = n == 0 ? 0 : (_sel - 1 + n) % n);
    } else if (e.logicalKey == LogicalKeyboardKey.enter) {
      if (n > 0) Navigator.pop(context, _matches[_sel]);
    } else if (e.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = _matches;
    final rows = <Widget>[];
    String? section;
    for (var i = 0; i < items.length; i++) {
      final a = items[i];
      if (a.section != section) {
        section = a.section;
        rows.add(SectionLabel(section));
      }
      rows.add(
        HoverRow(
          selected: i == _sel,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          onTap: () => Navigator.pop(context, a),
          child: Row(
            children: [
              Icon(a.icon, size: 16, color: i == _sel ? c.accent : c.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: a.title,
                        style: TextStyle(color: c.text, fontSize: 13.5),
                      ),
                      if (a.subtitle != null)
                        TextSpan(
                          text: '   ${a.subtitle}',
                          style: TextStyle(color: c.faint, fontSize: 12.5),
                        ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (a.trailing != null) a.trailing!,
              if (a.shortcut != null) Kbd(a.shortcut!),
            ],
          ),
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Focus(
        onKeyEvent: _onKey,
        child: Container(
          width: 640,
          constraints: const BoxConstraints(maxHeight: 480),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 19, color: c.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        autofocus: true,
                        onChanged: (_) => setState(() => _sel = 0),
                        onSubmitted: (_) {
                          if (_matches.isNotEmpty) {
                            Navigator.pop(context, _matches[_sel]);
                          }
                        },
                        style: TextStyle(fontSize: 16, color: c.text),
                        decoration: const InputDecoration(
                          hintText: 'Where to?',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const Kbd('esc'),
                  ],
                ),
              ),
              const Divider(),
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          'Nothing down this tunnel. Try a host name, a snippet, or "theme".',
                          style: TextStyle(color: c.muted, fontSize: 13),
                        ),
                      )
                    : ListView(
                        controller: _scroll,
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        children: rows,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
