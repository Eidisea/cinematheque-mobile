import 'package:flutter/material.dart';

/// Staff app design tokens — the website admin's: neutral grays, a dark sidebar, white
/// panels with thin borders, Cinematheque purple only for primary buttons and links,
/// and semantic green / amber / red for states. Light only for now.
abstract final class StaffColors {
  static const brand = Color(0xFF580076); // primary buttons, links, avatar
  static const brandHover = Color(0xFF46005E);
  static const brandTint = Color(0xFFF5EEFA);
  static const gold = Color(0xFFEBBC00);
  static const ink = Color(0xFF141219);

  static const canvas = Color(0xFFF4F5F7);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF9FAFB); // table headers, group rows
  static const border = Color(0xFFE5E7EB);
  static const borderStrong = Color(0xFFD1D5DB);
  static const text = Color(0xFF111827);
  static const textMuted = Color(0xFF6B7280);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);

  // The dark sidebar
  static const sideBg = Color(0xFF111827);
  static const sideFg = Color(0xFFD1D5DB);
  static const sideMuted = Color(0xFF9CA3AF);
  static const sideActive = Color(0x1AFFFFFF);
  static const sideHover = Color(0x0FFFFFFF);
  static const count = Color(0xFFDC2626);

  // States
  static const success = Color(0xFF15803D);
  static const successTint = Color(0xFFECFDF3);
  static const successBorder = Color(0xFFBBF7D0);
  static const warning = Color(0xFFB45309);
  static const warningTint = Color(0xFFFFFBEB);
  static const warningBorder = Color(0xFFFDE68A);
  static const danger = Color(0xFFB91C1C);
  static const dangerTint = Color(0xFFFEF2F2);
  static const dangerBorder = Color(0xFFFECACA);
}

/// Booking references and seat labels, as the website sets them (Geist Mono there).
const staffMono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Consolas', 'Courier New']);

ThemeData buildStaffTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: StaffColors.brand,
    primary: StaffColors.brand,
    surface: StaffColors.surface,
    error: StaffColors.danger,
  );

  const radius = BorderRadius.all(Radius.circular(8));

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: StaffColors.canvas,
    dividerColor: StaffColors.border,
    dividerTheme: const DividerThemeData(color: StaffColors.border, thickness: 1, space: 1),
    textTheme: Typography.blackMountainView.apply(bodyColor: StaffColors.text, displayColor: StaffColors.text),
    cardTheme: const CardThemeData(
      color: StaffColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: StaffColors.border)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: StaffColors.surface,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: StaffColors.borderStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: StaffColors.borderStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: StaffColors.brand, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StaffColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 40),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: StaffColors.brand),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: StaffColors.surface,
      foregroundColor: StaffColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}
