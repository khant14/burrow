import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'common.dart';

const kPrivacyPolicyUrl =
    'https://github.com/khant14/burrow/blob/main/docs/PRIVACY.md';

/// Appearance settings: app theme, terminal theme, font size.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context).app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = context.c;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            const Heading('Make it yours', size: 20),
            const SizedBox(height: 16),
            _label(context, 'App theme'),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: c.hover,
                selectedForegroundColor: c.text,
                foregroundColor: c.muted,
                side: BorderSide(color: c.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('Loam')),
                ButtonSegment(value: ThemeMode.light, label: Text('Sand')),
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (s) => app.setThemeMode(s.first),
            ),
            const SizedBox(height: 20),
            _label(context, 'Terminal theme'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final t in BurrowTerminalTheme.all)
                  _Swatch(
                    theme: t,
                    selected: t.id == app.terminalThemeId,
                    onTap: () => app.setTerminalTheme(t.id),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _label(context, 'Font size  ·  ${app.fontSize.round()} pt'),
            Slider(
              value: app.fontSize,
              min: 10,
              max: 22,
              divisions: 12,
              activeColor: c.accent,
              inactiveColor: c.border,
              onChanged: app.setFontSize,
              semanticFormatterCallback: (v) => 'Font size ${v.round()} points',
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(kPrivacyPolicyUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                label: const Text('Privacy policy'),
              ),
            ),
            Text(
              'Burrow collects nothing. Hosts and settings stay on this device.',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ],
        );
      },
    );
  }

  Widget _label(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 12,
        color: context.c.muted,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });
  final BurrowTerminalTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme.theme;
    final c = context.c;
    return Semantics(
      button: true,
      selected: selected,
      label: '${theme.name} terminal theme',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            children: [
              AnimatedContainer(
                duration: kFast,
                width: 92,
                height: 56,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? c.accent : c.border,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r'$ ls',
                      style: TextStyle(
                        fontFamily: kMono,
                        fontSize: 10,
                        color: t.foreground,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        for (final col in [
                          t.red,
                          t.green,
                          t.yellow,
                          t.blue,
                          t.magenta,
                          t.cyan,
                        ])
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 3),
                            color: col,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                theme.name,
                style: TextStyle(
                  fontSize: 11.5,
                  color: selected ? c.text : c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSettings(BuildContext context, {required bool compact}) {
  if (compact) {
    return showModalBottomSheet(
      context: context,
      builder: (_) => const SafeArea(child: SettingsPanel()),
    );
  }
  return showFadeDialog(
    context,
    (ctx) => Material(
      type: MaterialType.transparency,
      child: Container(
        width: 460,
        decoration: BoxDecoration(
          color: ctx.c.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ctx.c.border),
        ),
        child: const SettingsPanel(),
      ),
    ),
  );
}
