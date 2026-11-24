import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

/// Burrow design tokens: warm earth tones (loam, clay, sand) with an ember accent.
/// Deliberately warm, to stay clear of the cool navy/teal look of other SSH clients.
@immutable
class BurrowColors extends ThemeExtension<BurrowColors> {
  const BurrowColors({
    required this.bg,
    required this.surface,
    required this.sidebar,
    required this.raised,
    required this.hover,
    required this.border,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.clay,
    required this.soil,
    required this.success,
    required this.danger,
  });

  final Color bg, surface, sidebar, raised, hover, border, text, muted, faint;
  final Color accent, onAccent, success, danger;

  /// Secondary earth tone, used in the mark and illustrations.
  final Color clay;

  /// Deep underground tone for illustration fills.
  final Color soil;

  /// "Loam": dark, warm brown-black.
  static const dark = BurrowColors(
    bg: Color(0xFF15110D),
    surface: Color(0xFF1B1611),
    sidebar: Color(0xFF120F0B),
    raised: Color(0xFF221C16),
    hover: Color(0xFF2A231C),
    border: Color(0xFF30281F),
    text: Color(0xFFF1E7D8),
    muted: Color(0xFFAD9D89),
    faint: Color(0xFF706252),
    accent: Color(0xFFF2A541),
    onAccent: Color(0xFF241505),
    clay: Color(0xFFC46A3C),
    soil: Color(0xFF2B2119),
    success: Color(0xFF9CC07A),
    danger: Color(0xFFE2694F),
  );

  /// "Sand": light, warm paper.
  static const light = BurrowColors(
    bg: Color(0xFFF7F1E7),
    surface: Color(0xFFFCF8F2),
    sidebar: Color(0xFFEFE6D8),
    raised: Color(0xFFFFFCF7),
    hover: Color(0xFFE7DCCB),
    border: Color(0xFFE0D3C0),
    text: Color(0xFF2A2017),
    muted: Color(0xFF7B6A57),
    faint: Color(0xFFA9998A),
    accent: Color(0xFFC9781A),
    onAccent: Color(0xFFFFFAF2),
    clay: Color(0xFFB45A2E),
    soil: Color(0xFFE3D4BE),
    success: Color(0xFF5E8A3A),
    danger: Color(0xFFC0482F),
  );

  @override
  BurrowColors copyWith() => this;

  @override
  BurrowColors lerp(BurrowColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension BurrowThemeX on BuildContext {
  BurrowColors get c => Theme.of(this).extension<BurrowColors>()!;
}

const kMono = 'JetBrains Mono';
const kDisplay = 'Fraunces';
const kFast = Duration(milliseconds: 140);

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? BurrowColors.dark : BurrowColors.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: b,
      primary: c.accent,
      onPrimary: c.onAccent,
      surface: c.surface,
      onSurface: c.text,
      outline: c.border,
      error: c.danger,
    ),
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: c.border),
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.border,
    extensions: [c],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: c.hover,
    // Quick fades, no bounce, on every platform.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: BorderSide(color: c.accent)),
      labelStyle: TextStyle(color: c.muted, fontSize: 13),
      hintStyle: TextStyle(color: c.faint, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.muted,
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.raised,
      contentTextStyle: TextStyle(
        color: c.text,
        fontSize: 13,
        fontFamily: 'Inter',
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      textStyle: TextStyle(color: c.text, fontSize: 12),
    ),
  );
}

/// Curated terminal themes.
class BurrowTerminalTheme {
  const BurrowTerminalTheme(this.id, this.name, this.theme);
  final String id;
  final String name;
  final TerminalTheme theme;

  static BurrowTerminalTheme byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);

  static final all = [
    BurrowTerminalTheme(
      'loam',
      'Loam',
      _t(
        bg: 0xFF15110D,
        fg: 0xFFE9DECE,
        cursor: 0xFFF2A541,
        sel: 0x40F2A541,
        ansi: [
          0xFF2B2119,
          0xFFE2694F,
          0xFF9CC07A,
          0xFFF2C14E,
          0xFF83A9C4,
          0xFFCF8FA8,
          0xFF86C2AE,
          0xFFE9DECE,
        ],
        bright: [
          0xFF706252,
          0xFFF3876C,
          0xFFB6D696,
          0xFFFFD36E,
          0xFFA1C2DA,
          0xFFE3AAC0,
          0xFFA3D8C6,
          0xFFFFF7EA,
        ],
      ),
    ),
    BurrowTerminalTheme(
      'sandstone',
      'Sandstone',
      _t(
        bg: 0xFFF7F1E7,
        fg: 0xFF3A2D21,
        cursor: 0xFFC9781A,
        sel: 0x33C9781A,
        ansi: [
          0xFF3A2D21,
          0xFFB5442C,
          0xFF56803A,
          0xFF9C6A0E,
          0xFF3F6E8F,
          0xFF95507A,
          0xFF2F7F71,
          0xFFE0D3C0,
        ],
        bright: [
          0xFF8A7865,
          0xFFCF5A3F,
          0xFF6B9A4B,
          0xFFB98316,
          0xFF5486A8,
          0xFFAD6690,
          0xFF3F9A8A,
          0xFFFFFCF7,
        ],
      ),
    ),
    BurrowTerminalTheme(
      'moss',
      'Moss',
      _t(
        bg: 0xFF141710,
        fg: 0xFFDCE2CC,
        cursor: 0xFFB9CC6E,
        sel: 0x40B9CC6E,
        ansi: [
          0xFF262B1E,
          0xFFD9735A,
          0xFFA9C46C,
          0xFFE3C566,
          0xFF89A6B5,
          0xFFC496A8,
          0xFF8DC1A3,
          0xFFDCE2CC,
        ],
        bright: [
          0xFF5F6650,
          0xFFEB8D74,
          0xFFC1DA86,
          0xFFF3D782,
          0xFFA3BFCD,
          0xFFD8B0C0,
          0xFFA7D7BB,
          0xFFF4F7EA,
        ],
      ),
    ),
    BurrowTerminalTheme(
      'ember',
      'Ember',
      _t(
        bg: 0xFF1C0F0A,
        fg: 0xFFF0D9C4,
        cursor: 0xFFFF8A3D,
        sel: 0x40FF8A3D,
        ansi: [
          0xFF33201A,
          0xFFFF6A4D,
          0xFFB7C46C,
          0xFFFFB347,
          0xFF8FA7C9,
          0xFFD98FB0,
          0xFF7CC2A8,
          0xFFF0D9C4,
        ],
        bright: [
          0xFF7A5848,
          0xFFFF8A70,
          0xFFCDDA86,
          0xFFFFC870,
          0xFFABC0E0,
          0xFFEDA9C7,
          0xFF98D9C0,
          0xFFFFF1E4,
        ],
      ),
    ),
  ];

  static TerminalTheme _t({
    required int bg,
    required int fg,
    required int cursor,
    required int sel,
    required List<int> ansi,
    required List<int> bright,
  }) {
    Color c(int v) => Color(v);
    return TerminalTheme(
      cursor: c(cursor),
      selection: c(sel),
      foreground: c(fg),
      background: c(bg),
      black: c(ansi[0]),
      red: c(ansi[1]),
      green: c(ansi[2]),
      yellow: c(ansi[3]),
      blue: c(ansi[4]),
      magenta: c(ansi[5]),
      cyan: c(ansi[6]),
      white: c(ansi[7]),
      brightBlack: c(bright[0]),
      brightRed: c(bright[1]),
      brightGreen: c(bright[2]),
      brightYellow: c(bright[3]),
      brightBlue: c(bright[4]),
      brightMagenta: c(bright[5]),
      brightCyan: c(bright[6]),
      brightWhite: c(bright[7]),
      searchHitBackground: c(0xFFF5C451),
      searchHitBackgroundCurrent: c(0xFFF5A524),
      searchHitForeground: c(0xFF000000),
    );
  }
}
