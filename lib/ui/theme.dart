/// 主题：移植 Web 版 styles.css 的设计变量（暖纸色 + 墨绿主色）
///
/// v1.3.0 起支持深色模式：语义色通过 ThemeExtension（GuiwuThemeColors）
/// 提供，widget 内一律用 `context.gc.xxx` 取色；GColors 保留为浅色常量，
/// 仅用于主题内部、无 context 的场景（如发布包错误页）。
library;

import 'package:material_ui/material_ui.dart';

/// 语义色集合（亮 / 暗两套实例）
class GuiwuColors {
  const GuiwuColors({
    required this.bg,
    required this.bgDeep,
    required this.surface,
    required this.surfaceSoft,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.muted2,
    required this.line,
    required this.lineStrong,
    required this.primary,
    required this.primaryDeep,
    required this.primaryWeak,
    required this.accent,
    required this.accentWeak,
    required this.danger,
    required this.dangerWeak,
    required this.amber,
    required this.amberWeak,
    required this.blue,
    required this.blueWeak,
  });

  final Color bg;
  final Color bgDeep;
  final Color surface;
  final Color surfaceSoft;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color muted2;
  final Color line;
  final Color lineStrong;
  final Color primary;
  final Color primaryDeep;
  final Color primaryWeak;
  final Color accent;
  final Color accentWeak;
  final Color danger;
  final Color dangerWeak;
  final Color amber;
  final Color amberWeak;
  final Color blue;
  final Color blueWeak;

  /// 状态 tone → 主色（徽章、图标用）
  Color toneColor(String tone) => switch (tone) {
        'green' => primary,
        'amber' => amber,
        'blue' => blue,
        'gray' => muted,
        _ => primary,
      };

  /// 状态 tone → 弱底色
  Color toneWeakColor(String tone) => switch (tone) {
        'green' => primaryWeak,
        'amber' => amberWeak,
        'blue' => blueWeak,
        'gray' => bgDeep,
        _ => primaryWeak,
      };
}

/// 浅色（原 Web 版暖纸色）
const GuiwuColors kLightColors = GuiwuColors(
  bg: Color(0xFFF5F2ED),
  bgDeep: Color(0xFFEFEAE2),
  surface: Color(0xFFFFFFFF),
  surfaceSoft: Color(0xFFFAF8F5),
  ink: Color(0xFF24221E),
  inkSoft: Color(0xFF4F4A42),
  muted: Color(0xFF8B8377),
  muted2: Color(0xFFA9A196),
  line: Color(0xFFE9E3D9),
  lineStrong: Color(0xFFDDD5C8),
  primary: Color(0xFF2E6B5E),
  primaryDeep: Color(0xFF24554B),
  primaryWeak: Color(0xFFE8F0EC),
  accent: Color(0xFFC97C4E),
  accentWeak: Color(0xFFF7ECE3),
  danger: Color(0xFFB3453A),
  dangerWeak: Color(0xFFF9E9E7),
  amber: Color(0xFFB07D2A),
  amberWeak: Color(0xFFF8F0DD),
  blue: Color(0xFF3F6EA8),
  blueWeak: Color(0xFFE9F0F8),
);

/// 深色（暖炭色）
const GuiwuColors kDarkColors = GuiwuColors(
  bg: Color(0xFF1C1B18),
  bgDeep: Color(0xFF23221E),
  surface: Color(0xFF26241F),
  surfaceSoft: Color(0xFF2E2C26),
  ink: Color(0xFFEAE5DC),
  inkSoft: Color(0xFFC9C3B8),
  muted: Color(0xFF9C948A),
  muted2: Color(0xFF7D766C),
  line: Color(0xFF38352E),
  lineStrong: Color(0xFF454136),
  primary: Color(0xFF7FC0AC),
  primaryDeep: Color(0xFF5FA391),
  primaryWeak: Color(0xFF24443B),
  accent: Color(0xFFE0A87E),
  accentWeak: Color(0xFF3F2F22),
  danger: Color(0xFFE08A80),
  dangerWeak: Color(0xFF432B27),
  amber: Color(0xFFD9B15E),
  amberWeak: Color(0xFF3D3423),
  blue: Color(0xFF8FB4E0),
  blueWeak: Color(0xFF26313F),
);

/// GColors：浅色常量（无 context 场景使用：主题构造、发布包错误页等）
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

/// ThemeExtension：把语义色挂到 ThemeData 上
class GuiwuThemeColors extends ThemeExtension<GuiwuThemeColors> {
  const GuiwuThemeColors({required this.c});

  final GuiwuColors c;

  @override
  GuiwuThemeColors copyWith({GuiwuColors? c}) =>
      GuiwuThemeColors(c: c ?? this.c);

  @override
  GuiwuThemeColors lerp(covariant GuiwuThemeColors? other, double t) {
    // 不做中间插值：直接取目标色，避免模式切换时的过渡闪烁
    return other ?? this;
  }
}

/// widget 内取语义色：`context.gc.ink`
extension BuildContextGC on BuildContext {
  GuiwuColors get gc => Theme.of(this).extension<GuiwuThemeColors>()!.c;
}

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

ThemeData buildGuiwuTheme({bool dark = false}) {
  final c = dark ? kDarkColors : kLightColors;

  final scheme = ColorScheme.fromSeed(seedColor: GColors.primary).copyWith(
    primary: c.primary,
    onPrimary: dark ? kDarkColors.surface : Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    error: c.danger,
    brightness: dark ? Brightness.dark : Brightness.light,
  );

  TextStyle bodyStyle(double fontSize, Color color,
          {FontWeight? weight, double? height}) =>
      TextStyle(fontSize: fontSize, color: color, fontWeight: weight, height: height);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [GuiwuThemeColors(c: c)],
    scaffoldBackgroundColor: c.bg,
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: c.inkSoft, size: 20),
    textTheme: TextTheme(
      headlineSmall: bodyStyle(22, c.ink, weight: FontWeight.w700),
      titleMedium: bodyStyle(15, c.ink, weight: FontWeight.w600),
      bodyMedium: bodyStyle(14, c.ink),
      bodySmall: bodyStyle(12.5, c.inkSoft),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceSoft,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: c.muted2, fontSize: 13.5),
      labelStyle: TextStyle(color: c.muted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.primary, width: 1.6),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(fontSize: 13.5, color: c.ink),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      barrierColor: Colors.black38,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? c.primaryDeep : GColors.ink,
      contentTextStyle: TextStyle(
        color: dark ? kDarkColors.surface : Colors.white,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.primaryWeak,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? c.primary : c.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? c.primary : c.muted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: dark ? kDarkColors.surface : Colors.white,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.primary,
        side: BorderSide(color: c.lineStrong),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.surfaceSoft,
        foregroundColor: c.inkSoft,
        side: BorderSide(color: c.lineStrong),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
