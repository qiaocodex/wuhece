/// 主题：移植 Web 版 styles.css 的设计变量（暖纸色 + 墨绿主色）
library;

import 'package:material_ui/material_ui.dart';

class GColors {
  GColors._();

  static const bg = Color(0xFFF5F2ED);
  static const bgDeep = Color(0xFFEFEAE2);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFFAF8F5);
  static const ink = Color(0xFF24221E);
  static const inkSoft = Color(0xFF4F4A42);
  static const muted = Color(0xFF8B8377);
  static const muted2 = Color(0xFFA9A196);
  static const line = Color(0xFFE9E3D9);
  static const lineStrong = Color(0xFFDDD5C8);
  static const primary = Color(0xFF2E6B5E);
  static const primaryDeep = Color(0xFF24554B);
  static const primaryWeak = Color(0xFFE8F0EC);
  static const accent = Color(0xFFC97C4E);
  static const accentWeak = Color(0xFFF7ECE3);
  static const danger = Color(0xFFB3453A);
  static const dangerWeak = Color(0xFFF9E9E7);
  static const amber = Color(0xFFB07D2A);
  static const amberWeak = Color(0xFFF8F0DD);
  static const blue = Color(0xFF3F6EA8);
  static const blueWeak = Color(0xFFE9F0F8);
}

/// 状态 tone → 颜色（徽章、图标用）
Color toneColor(String tone) => switch (tone) {
      'green' => GColors.primary,
      'amber' => GColors.amber,
      'blue' => GColors.blue,
      'gray' => GColors.muted,
      _ => GColors.primary,
    };

Color toneWeakColor(String tone) => switch (tone) {
      'green' => GColors.primaryWeak,
      'amber' => GColors.amberWeak,
      'blue' => GColors.blueWeak,
      'gray' => GColors.bgDeep,
      _ => GColors.primaryWeak,
    };

/// `#c97c4e` → Color（解析失败回退灰色）
Color hexToColor(String? hex, [String fallback = '#9a9a9a']) {
  final source = (hex != null && hex.isNotEmpty) ? hex : fallback;
  final code = source.replaceAll('#', '').trim();
  if (code.length != 6) return hexToColor(fallback);
  final value = int.tryParse(code, radix: 16);
  if (value == null) return hexToColor(fallback);
  return Color(0xFF000000 | value);
}

/// Color → `#rrggbb`（分类颜色存储用）
String colorToHex(Color color) {
  final c = color.withValues(alpha: 1);
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  String p(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${p(r)}${p(g)}${p(b)}';
}

/// 宽屏判定（侧栏 / 底部导航切换）
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 960;

/// 表单弹窗宽屏判定
bool isFormWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 720;

ThemeData buildGuiwuTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: GColors.primary).copyWith(
    primary: GColors.primary,
    onPrimary: Colors.white,
    surface: GColors.surface,
    onSurface: GColors.ink,
    error: GColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: GColors.bg,
    dividerTheme: const DividerThemeData(color: GColors.line, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: GColors.inkSoft, size: 20),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: GColors.ink),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GColors.ink),
      bodyMedium: TextStyle(fontSize: 14, color: GColors.ink),
      bodySmall: TextStyle(fontSize: 12.5, color: GColors.inkSoft),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GColors.surfaceSoft,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: GColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: GColors.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: GColors.primary, width: 1.6),
      ),
      hintStyle: const TextStyle(color: GColors.muted2, fontSize: 13.5),
      labelStyle: const TextStyle(color: GColors.muted, fontSize: 13),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(fontSize: 13.5, color: GColors.ink),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: GColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      barrierColor: Colors.black38,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: GColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GColors.surface,
      indicatorColor: GColors.primaryWeak,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? GColors.primary : GColors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? GColors.primary : GColors.muted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GColors.primary,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GColors.primary,
        side: const BorderSide(color: GColors.lineStrong),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: GColors.primary,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GColors.surfaceSoft,
        foregroundColor: GColors.inkSoft,
        side: const BorderSide(color: GColors.lineStrong),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
