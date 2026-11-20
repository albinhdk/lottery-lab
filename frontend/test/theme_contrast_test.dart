import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:lottery_lab_app/theme.dart';

/// WCAG 2.1 relative luminance of an opaque color.
double _luminance(Color color) {
  double channel(int value) {
    final s = value / 255.0;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final argb = color.toARGB32();
  return 0.2126 * channel((argb >> 16) & 0xFF) +
      0.7152 * channel((argb >> 8) & 0xFF) +
      0.0722 * channel(argb & 0xFF);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // 暗色主题里"提示也是暗色的"就是 faint/muted 在深底色上对比度不足。
  const backgrounds = [
    AppColors.bg,
    AppColors.surface,
    AppColors.surfaceAlt,
    AppColors.surfaceHi,
  ];

  test('body and hint text stay readable on every dark surface', () {
    for (final bg in backgrounds) {
      expect(_contrast(AppColors.text, bg), greaterThanOrEqualTo(7),
          reason: '正文文字对 $bg 需要 AAA 级对比度');
      expect(_contrast(AppColors.muted, bg), greaterThanOrEqualTo(4.5),
          reason: '次要文字对 $bg 需要 AA 级对比度');
      expect(_contrast(AppColors.faint, bg), greaterThanOrEqualTo(4.5),
          reason: '提示文字对 $bg 需要 AA 级对比度');
    }
  });

  test('hint text in input fields is legible', () {
    // inputDecorationTheme 的 hintStyle 用的是 faint。
    expect(_contrast(AppColors.faint, AppColors.surfaceAlt),
        greaterThanOrEqualTo(4.5));
  });

  test('accent text keeps a clear margin over the surface', () {
    for (final bg in backgrounds) {
      expect(_contrast(AppColors.accent, bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.blue, bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.green, bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.red, bg), greaterThanOrEqualTo(4.5));
    }
  });

  test('snack bar text is readable on the snack bar background', () {
    // Regression: 提示条只给了 backgroundColor，文字色走 SnackBar 默认的
    // ColorScheme.onInverseSurface，而本主题没配反色，默认值是深色——深字压
    // 深底，"这个提示根本看不清"。现在底色和文字色都在 snackBarTheme 里，
    // 这里守住这一对。
    final theme = buildTheme();
    final snack = theme.snackBarTheme;
    final bg = snack.backgroundColor;
    final fg = snack.contentTextStyle?.color;
    expect(bg, isNotNull, reason: '提示条必须显式指定底色');
    expect(fg, isNotNull, reason: '提示条必须显式指定文字色');
    if (bg == null || fg == null) return;
    expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5),
        reason: '提示条文字对自身底色需要 AA 级对比度');
    // 也顺带确认提示条底色本身不是浅色，否则上面的对比度可能是靠浅底深字过的。
    expect(_luminance(bg), lessThan(0.2));
  });
}
