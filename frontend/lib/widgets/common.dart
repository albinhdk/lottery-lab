import 'package:flutter/material.dart';

import '../theme.dart';

class Panel extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final bool dense;

  const Panel({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.tint,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint ?? AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        gradient: tint == null
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF141B28), Color(0xFF10151F)],
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: TextStyle(
                          fontSize: dense ? 14 : 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            SizedBox(height: dense ? 14 : 18),
          ],
          child,
        ],
      ),
    );
  }
}

class Ball extends StatelessWidget {
  final int number;
  final bool secondary;
  final double size;
  final bool dim;

  const Ball({
    super.key,
    required this.number,
    this.secondary = false,
    this.size = 34,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = secondary
        ? [AppColors.blue, AppColors.blueDeep]
        : [const Color(0xFFF8C767), AppColors.accentDeep];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dim
              ? [colors[0].withValues(alpha: 0.28), colors[1].withValues(alpha: 0.28)]
              : colors,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: secondary ? 0.22 : 0.3),
          width: 0.8,
        ),
        boxShadow: dim
            ? null
            : [
                BoxShadow(
                  color: colors[1].withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Text(
        number.toString().padLeft(2, '0'),
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: secondary ? Colors.white : const Color(0xFF2B1B00),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class BallRow extends StatelessWidget {
  final List<int> primary;
  final List<int> secondary;
  final double size;

  const BallRow({
    super.key,
    required this.primary,
    required this.secondary,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final n in primary) Ball(number: n, size: size),
        if (secondary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 1,
              height: size * 0.7,
              color: AppColors.border,
            ),
          ),
        for (final n in secondary) Ball(number: n, secondary: true, size: size),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color color;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    required this.icon,
    this.color = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.faint),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VerdictChip extends StatelessWidget {
  final String verdict;
  final bool compact;

  const VerdictChip(this.verdict, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (verdict) {
      'pass' => ('通过', AppColors.green),
      'warn' => ('关注', AppColors.accent),
      'fail' => ('异常', AppColors.red),
      _ => ('信息', AppColors.blue),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;

  const Tag(this.text, {super.key, this.color = AppColors.muted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class LoadingBox extends StatelessWidget {
  final String? label;

  const LoadingBox({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.accent,
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: 14),
              Text(
                label!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorBox({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.text,
                height: 1.5,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('重试', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class EmptyBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyBox({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 46, horizontal: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.faint),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.6),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;

  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
            letterSpacing: 0.6,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(fontSize: 11.5, color: AppColors.faint),
          ),
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outlined;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
          )
        else if (icon != null)
          Icon(icon, size: 17),
        if (loading || icon != null) const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF241800),
        disabledBackgroundColor: AppColors.surfaceHi,
        disabledForegroundColor: AppColors.faint,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: child,
    );
  }
}

class ChoicePills<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  const ChoicePills({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          GestureDetector(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: v == selected
                    ? AppColors.accent.withValues(alpha: 0.14)
                    : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: v == selected
                      ? AppColors.accent.withValues(alpha: 0.6)
                      : AppColors.border,
                ),
              ),
              child: Text(
                label(v),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: v == selected ? FontWeight.w600 : FontWeight.w400,
                  color: v == selected ? AppColors.accent : AppColors.muted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
