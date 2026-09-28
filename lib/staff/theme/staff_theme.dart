import 'package:flutter/material.dart';

/// Staff app design tokens — a neutral SaaS dashboard look (gray canvas, white cards,
/// thin borders), deliberately different from the customer app. Cinematheque purple is
/// the accent; gold marks the active navigation item.
/// Light is the default. Dark mode and final typography come in Phase 12.
abstract final class StaffColors {
  static const brand = Color(0xFF580076);
  static const brandTint = Color(0xFFF4EBF8);
  static const gold = Color(0xFFEBBC00);
  static const canvas = Color(0xFFF9FAFB);
  static const surface = Colors.white;
  static const border = Color(0xFFE4E7EC);
  static const text = Color(0xFF101828);
  static const textMuted = Color(0xFF667085);
  static const danger = Color(0xFFB42318);
  static const dangerTint = Color(0xFFFEF3F2);
}

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
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: StaffColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: StaffColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: StaffColors.brand, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: StaffColors.surface,
      foregroundColor: StaffColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}
