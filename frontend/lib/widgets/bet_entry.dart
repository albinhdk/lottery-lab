
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models_bet.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Tappable number grid used to enter a ticket. Mirrors the picker in the
/// hand-check panel but drives a [Bet] draft instead of a prize check.
class NumberPicker extends StatelessWidget {
  final List<int> selectedPrimary;
  final List<int> selectedSecondary;
  final int primaryCount;
  final int secondaryCount;
  final int primaryMax;
  final int secondaryMax;
  final String primaryLabel;
  final String secondaryLabel;
  final ValueChanged<List<int>> onPrimaryChanged;
  final ValueChanged<List<int>> onSecondaryChanged;

  const NumberPicker({
    super.key,
    required this.selectedPrimary,
    required this.selectedSecondary,
    required this.primaryCount,
    required this.secondaryCount,
    required this.primaryMax,
    required this.secondaryMax,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          primaryLabel,
          trailing: '${selectedPrimary.length}/$primaryCount',
        ),
        const SizedBox(height: 8),
        _grid(false),
        const SizedBox(height: 18),
        SectionLabel(
          secondaryLabel,
          trailing: '${selectedSecondary.length}/$secondaryCount',
        ),
        const SizedBox(height: 8),
        _grid(true),
      ],
    );
  }

  Widget _grid(bool secondary) {
    final max = secondary ? secondaryMax : primaryMax;
    final selected = secondary ? selectedSecondary : selectedPrimary;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var n = 1; n <= max; n++)
          _PickBall(
            key: ValueKey('${secondary ? 's' : 'p'}-$n'),
            number: n,
            secondary: secondary,
            selected: selected.contains(n),
            onTap: () => _toggle(secondary, n),
          ),
      ],
    );
  }

  void _toggle(bool secondary, int number) {
    final selected = List<int>.of(secondary ? selectedSecondary : selectedPrimary);
    final limit = secondary ? secondaryCount : primaryCount;
    if (!selected.contains(number) && selected.length >= limit) {
      return;
    }
    if (!selected.remove(number)) {
      selected.add(number);
      selected.sort();
    }
    if (secondary) {
      onSecondaryChanged(selected);
    } else {
      onPrimaryChanged(selected);
    }
  }
}

/// Shown for a single bet inside the entry form.
class BetDraftCard extends StatelessWidget {
  final int index;
  final List<int> primary;
  final List<int> secondary;
  final int primaryCount;
  final int secondaryCount;
  final int primaryMax;
  final int secondaryMax;
  final String primaryLabel;
  final String secondaryLabel;
  final int multiple;
  final String note;
  final bool canRemove;
  final ValueChanged<List<int>> onPrimaryChanged;
  final ValueChanged<List<int>> onSecondaryChanged;
  final ValueChanged<int> onMultipleChanged;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onRemove;
  final VoidCallback onRandom;

  const BetDraftCard({
    super.key,
    required this.index,
    required this.primary,
    required this.secondary,
    required this.primaryCount,
    required this.secondaryCount,
    required this.primaryMax,
    required this.secondaryMax,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.multiple,
    required this.note,
    required this.canRemove,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
    required this.onMultipleChanged,
    required this.onNoteChanged,
    required this.onRemove,
    required this.onRandom,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      dense: true,
      title: '第 $index 注',
      trailing: Row(
        children: [
          TextButton.icon(
            onPressed: onRandom,
            icon: const Icon(Icons.casino_outlined, size: 15),
            label: const Text('随机', style: TextStyle(fontSize: 12)),
          ),
          if (canRemove)
            TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('删除', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BallRow(primary: primary, secondary: secondary, size: 30),
          const SizedBox(height: 16),
          NumberPicker(
            selectedPrimary: primary,
            selectedSecondary: secondary,
            primaryCount: primaryCount,
            secondaryCount: secondaryCount,
            primaryMax: primaryMax,
            secondaryMax: secondaryMax,
            primaryLabel: primaryLabel,
            secondaryLabel: secondaryLabel,
            onPrimaryChanged: onPrimaryChanged,
            onSecondaryChanged: onSecondaryChanged,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('倍数', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(width: 10),
              ChoicePills<int>(
                values: const [1, 2, 3, 5, 10],
                selected: multiple,
                label: (v) => '$v 倍',
                onChanged: onMultipleChanged,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // A TextField needs a Material ancestor; Panel is a plain Container.
          Material(
            color: Colors.transparent,
            child: TextField(
              controller: TextEditingController(text: note),
              onChanged: onNoteChanged,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: '备注（可选）',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.faint),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Copyable plain-text form of one ticket, e.g. for pasting into a note.
String formatBet(Bet bet, {String? primaryLabel, String? secondaryLabel}) {
  final p = bet.primary.map((e) => e.toString().padLeft(2, '0')).join(' ');
  final s = bet.secondary.map((e) => e.toString().padLeft(2, '0')).join(' ');
  final pl = primaryLabel ?? '号码';
  final sl = secondaryLabel ?? '特别号';
  return '${bet.gameName} 第${bet.issue}期 $pl $p | $sl $s'
      '${bet.multiple > 1 ? ' (${bet.multiple}倍)' : ''}';
}

void copyBet(BuildContext context, Bet bet, {String? pl, String? sl}) {
  Clipboard.setData(ClipboardData(text: formatBet(bet, primaryLabel: pl, secondaryLabel: sl)));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('已复制', style: TextStyle(fontSize: 12)),
      behavior: SnackBarBehavior.floating,
      width: 200,
      backgroundColor: AppColors.surfaceHi,
      duration: Duration(seconds: 2),
    ),
  );
}

class _PickBall extends StatelessWidget {
  final int number;
  final bool secondary;
  final bool selected;
  final VoidCallback onTap;

  const _PickBall({
    super.key,
    required this.number,
    required this.secondary,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = secondary
        ? [AppColors.blue, AppColors.blueDeep]
        : [const Color(0xFFF8C767), AppColors.accentDeep];
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? null : AppColors.surfaceAlt,
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                )
              : null,
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        child: Text(
          number.toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? (secondary ? Colors.white : const Color(0xFF2B1B00))
                : AppColors.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
