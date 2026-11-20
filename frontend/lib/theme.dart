import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0A0E15);
  static const surface = Color(0xFF121824);
  static const surfaceAlt = Color(0xFF19212F);
  static const surfaceHi = Color(0xFF202A3B);
  static const border = Color(0xFF243044);
  static const text = Color(0xFFE9EEF7);
  // muted / faint 是提示与次要文字，在深色底上必须保持 WCAG AA 对比度
  // （对 bg/surface 均 ≥ 4.5:1），否则暗色主题下"看不清"。
  static const muted = Color(0xFFA3B1C6);
  static const faint = Color(0xFF8496AE);
  static const accent = Color(0xFFF2B84B);
  static const accentDeep = Color(0xFFE8942B);
  static const blue = Color(0xFF5B9CFF);
  static const blueDeep = Color(0xFF3B6FE0);
  static const green = Color(0xFF3DDC97);
  static const red = Color(0xFFFF6B6B);
  static const purple = Color(0xFF9B8CFF);
  static const cyan = Color(0xFF4FD1C5);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'NotoSansSC',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.blue,
      surface: AppColors.surface,
      error: AppColors.red,
      onPrimary: Color(0xFF241800),
      onSurface: AppColors.text,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    dividerColor: AppColors.border,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
        'Segoe UI',
      ],
    ),
    // 提示条（SnackBar）的底色与文字色必须在主题里定：SnackBar 默认用
    // ColorScheme.inverseSurface / onInverseSurface，而本主题只覆盖了少数
    // 几个 colorScheme 字段，剩下的默认反色是"深色文字"——放在自定义的深色
    // 底上就成了深色叠深色，几乎看不见。
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHi,
      contentTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 12.5,
        height: 1.45,
      ),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      elevation: 8,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceHi,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.faint, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    ),
  );
}

TextStyle monoStyle({
  double size = 13,
  FontWeight weight = FontWeight.w600,
  Color color = AppColors.text,
}) {
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
