/// Açık, sakin arayüz: mavi vurgu, yeşil = çalışıyor.
library;

import 'package:flutter/material.dart';

abstract final class C {
  static const bg = Color(0xFFF4F6FA);
  static const panel = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFEEF2F8);
  static const line = Color(0xFFE0E6EF);
  static const text = Color(0xFF172033);
  static const text2 = Color(0xFF566176);
  static const text3 = Color(0xFF8792A6);
  static const blue = Color(0xFF2563EB);
  static const green = Color(0xFF0E9F6E);
  static const amber = Color(0xFFD97706);
  static const red = Color(0xFFDC3F4A);
  static const heart = Color(0xFFE5487A);
  static const gold = Color(0xFFD98E04);
}

const kFont = 'Poppins';
const kMono = 'PlexMono';

TextStyle mono(double size, {Color color = C.text, FontWeight w = FontWeight.w500}) =>
    TextStyle(fontFamily: kMono, fontSize: size, color: color, fontWeight: w, height: 1.1);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: kFont,
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.light(
      primary: C.blue,
      onPrimary: Colors.white,
      surface: C.surface,
      onSurface: C.text,
      error: C.red,
    ),
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text, fontFamily: kFont),
    dividerColor: C.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: border(C.line),
      enabledBorder: border(C.line),
      focusedBorder: border(C.blue, 1.6),
      hintStyle: const TextStyle(color: C.text3, fontSize: 13.5),
      labelStyle: const TextStyle(color: C.text2, fontSize: 13.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: kFont, fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        side: const BorderSide(color: C.line),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: kFont, fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: C.text2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: kFont, fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: C.line)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : C.text3),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.blue : C.line),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: const WidgetStatePropertyAll(BorderSide(color: C.line)),
        backgroundColor:
            WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.blue.withValues(alpha: 0.18) : C.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.blue : C.text2),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: kFont, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: C.text, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.text,
      contentTextStyle: const TextStyle(color: Colors.white, fontFamily: kFont, fontSize: 13.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: C.line)),
      width: 460,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(C.text3.withValues(alpha: 0.5)),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(8),
    ),
  );
}
