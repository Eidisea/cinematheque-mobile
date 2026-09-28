import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cinematheque Centre Davao — customer design tokens.
///
/// Carried over from the Laravel site and FDCP's Cinematheque pages:
///   warm paper background + ink text, Davao GOLD as the accent (FDCP marks Davao in
///   gold), FDCP purple/magenta for dates and emphasis. Light mode only for now.
abstract final class CustomerColors {
  // Brand
  static const ink = Color(0xFF141219);
  static const purple = Color(0xFF580076);
  static const magenta = Color(0xFFE200A9);
  static const gold = Color(0xFFEBBC00);
  static const gold600 = Color(0xFFCC8500); // FDCP eyebrow gold
  static const gold300 = Color(0xFFFFCC00);
  static const goldText = Color(0xFF8A5A00); // gold that passes contrast on light surfaces

  // Surfaces
  static const background = Color(0xFFFAF9F7); // warm paper
  static const surface = Colors.white;
  static const stub = Color(0xFFFFF7E1); // cream ticket stub (FDCP)
  static const goldTint = Color(0xFFFFF3CC);
  static const purpleTint = Color(0xFFF5F2FF);
  static const heroTint = Color(0xFFF6F2FB); // Laravel hero

  // Lines & text
  static const border = Color(0xFFE7E4EC);
  static const borderStrong = Color(0xFFD3CFDB);
  static const perforation = Color(0xFFE9C766);
  static const muted = Color(0xFF5B5566);
  static const faint = Color(0xFF8E8796);

  // Status
  static const success = Color(0xFF1F6F50);
  static const successTint = Color(0xFFE6F2EC);
  static const warning = Color(0xFF9A4A06);
  static const warningTint = Color(0xFFFDF1E3);
  static const danger = Color(0xFFB42318);
  static const dangerTint = Color(0xFFFDECEA);
  static const neutralTint = Color(0xFFF1EFEC);

  static const goldGradient = LinearGradient(colors: [gold600, gold300]);
  static const dateGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [purple, magenta],
  );
}

/// Spacing scale (4-pt rhythm).
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
  // Editorial pages (About): room between sections and between chapters.
  static const section = 64.0;
  static const chapter = 96.0;

  /// Side margin of every screen.
  static const gutter = 20.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const easeOut = Cubic(0.2, 0.7, 0.2, 1);

  /// Honour the phone's "remove animations" accessibility setting.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// One type scale for the whole customer app, instead of per-screen numbers.
/// Display sizes are Oswald (condensed titles, mostly uppercase); reading text is Poppins.
abstract final class TypeScale {
  static const numeral = 64.0; // big years on the About timeline
  static const hero = 58.0; // the About opening title
  static const xl = 44.0; // tab heroes ("NOW SHOWING")
  static const l = 34.0; // page and chapter titles
  static const m = 26.0; // statements, institution names
  static const s = 20.0; // section headings, lead lines
  static const xs = 17.0; // small display: list titles, milestone years
}

/// Text styles that the Material text theme doesn't cover.
abstract final class CcdType {
  static const _oswald = 'Oswald';

  /// Oswald is a variable font: the weight is set through its "wght" axis.
  static TextStyle display(double size, {Color color = CustomerColors.ink, double weight = 600, double spacing = 0.4}) =>
      TextStyle(
        fontFamily: _oswald,
        fontSize: size,
        height: 1.08,
        letterSpacing: spacing,
        color: color,
        fontWeight: weight >= 600 ? FontWeight.w600 : FontWeight.w500,
        fontVariations: [FontVariation.weight(weight)],
      );

  /// Gold, uppercase, widely spaced label above titles (FDCP / Laravel "eyebrow").
  static const eyebrow = TextStyle(
    fontFamily: 'Poppins',
    fontSize: 11,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: CustomerColors.goldText,
  );

  /// Money is set in Oswald: Poppins has no ₱ glyph.
  static TextStyle money(double size, {Color color = CustomerColors.ink}) => display(size, color: color, spacing: 0.2);

  static const meta = TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.45, color: CustomerColors.muted);

  /// Long-form reading text (About): larger and more open than UI text.
  static const reading = TextStyle(fontFamily: 'Poppins', fontSize: 16, height: 1.65, color: CustomerColors.ink);
  static const readingMuted = TextStyle(fontFamily: 'Poppins', fontSize: 16, height: 1.65, color: CustomerColors.muted);
}

ThemeData buildCustomerTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: CustomerColors.ink,
    onPrimary: Colors.white,
    primaryContainer: CustomerColors.goldTint,
    onPrimaryContainer: CustomerColors.ink,
    secondary: CustomerColors.gold600,
    onSecondary: CustomerColors.ink,
    secondaryContainer: CustomerColors.goldTint,
    onSecondaryContainer: CustomerColors.ink,
    tertiary: CustomerColors.purple,
    onTertiary: Colors.white,
    error: CustomerColors.danger,
    onError: Colors.white,
    surface: CustomerColors.surface,
    onSurface: CustomerColors.ink,
    onSurfaceVariant: CustomerColors.muted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: CustomerColors.background,
    surfaceContainer: CustomerColors.background,
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: CustomerColors.neutralTint,
    outline: CustomerColors.borderStrong,
    outlineVariant: CustomerColors.border,
    shadow: Color(0xFF141219),
    surfaceTint: Colors.transparent, // no tinted "elevation" wash
  );

  const fieldRadius = BorderRadius.all(Radius.circular(Radii.md));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Poppins');
  final text = base.textTheme.apply(bodyColor: CustomerColors.ink, displayColor: CustomerColors.ink).copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.55),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
      );

  return base.copyWith(
    scaffoldBackgroundColor: CustomerColors.background,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: CustomerColors.ink,
      selectionColor: Color(0x55EBBC00),
      selectionHandleColor: CustomerColors.gold600,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: CustomerColors.background,
      foregroundColor: CustomerColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark, // dark status-bar icons on the light app
      titleTextStyle: text.titleMedium?.copyWith(fontSize: 17),
    ),
    dividerTheme: const DividerThemeData(color: CustomerColors.border, thickness: 1, space: 1),
    cardTheme: const CardThemeData(
      color: CustomerColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        side: BorderSide(color: CustomerColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CustomerColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: CustomerColors.muted),
      floatingLabelStyle: const TextStyle(color: CustomerColors.goldText, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: CustomerColors.faint),
      border: const OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: CustomerColors.border)),
      enabledBorder: const OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: CustomerColors.border)),
      focusedBorder: const OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: CustomerColors.gold600, width: 1.6)),
      errorBorder: const OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: CustomerColors.danger)),
      focusedErrorBorder: const OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: CustomerColors.danger, width: 1.6)),
      disabledBorder: const OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: CustomerColors.border)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CustomerColors.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: CustomerColors.neutralTint,
        disabledForegroundColor: CustomerColors.faint,
        minimumSize: const Size(0, 52),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.md))),
        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CustomerColors.ink,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: CustomerColors.borderStrong),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.md))),
        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CustomerColors.goldText,
        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: CustomerColors.surface,
      selectedColor: CustomerColors.ink,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: CustomerColors.ink),
      secondaryLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
      side: const BorderSide(color: CustomerColors.border),
      shape: const StadiumBorder(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: CustomerColors.ink,
      contentTextStyle: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 14, height: 1.4),
      actionTextColor: CustomerColors.gold300,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: CustomerColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      titleTextStyle: CcdType.display(22),
      contentTextStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14.5, height: 1.5, color: CustomerColors.ink),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: CustomerColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? CustomerColors.ink : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? CustomerColors.gold : null),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: CustomerColors.gold600),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: CustomerColors.goldText,
      collapsedIconColor: CustomerColors.muted,
      shape: Border(),
      collapsedShape: Border(),
    ),
  );
}
