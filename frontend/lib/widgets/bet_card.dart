
import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../models_bet.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// One recorded bet. Shows the ticket, its status, and — once the issue is
/// drawn — the matched balls, tier and payout.
class BetCard extends StatelessWidget {
  final Bet bet;
  final GameInfo game;
  final VoidCallback onDelete;
  final ValueChanged<double?> onActualAmount;

  const BetCard({
    super.key,
    required this.bet,
    required this.game,
    required this.onDelete,
    required this.onActualAmount,
  });

  @override
  Widget build(BuildContext context) {
    final won = bet.won;
    final pending = bet.pending;
    return Panel(
      dense: true,
      tint: won ? AppColors.accent.withValues(alpha: 0.06) : null,
      title: '${bet.gameName} · 第 ${bet.issue} 期',
      subtitle: pending
          ? '待开奖'
          : '${bet.date} · 命中 ${game.primaryLabel} ${bet.primaryHits}/${game.primaryCount}'
              ' · ${game.secondaryLabel} ${bet.secondaryHits}/${game.secondaryCount}',
      trailing: _StatusChip(bet: bet),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BallRow(primary: bet.primary, secondary: bet.secondary, size: 30),
          if (bet.multiple > 1 || bet.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (bet.multiple > 1) Tag('${bet.multiple} 倍', color: AppColors.blue),
                if (bet.note.isNotEmpty) Tag(bet.note),
              ],
            ),
          ],
          if (!pending) ...[
            const SizedBox(height: 12),
            _ResultRow(bet: bet, game: game, onActualAmount: onActualAmount),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                pending
                    ? '投入 ${fmtMoney(bet.cost)} 元'
                    : '投入 ${fmtMoney(bet.cost)} 元 · 奖金 ${fmtMoney(bet.payout)} 元',
                style: const TextStyle(fontSize: 11, color: AppColors.faint),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('删除', style: TextStyle(fontSize: 11.5)),
                style: TextButton.styleFrom(foregroundColor: AppColors.faint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Bet bet;

  const _StatusChip({required this.bet});

  @override
  Widget build(BuildContext context) {
    if (bet.pending) {
      return const Tag('待开奖', color: AppColors.blue);
    }
    if (bet.won) {
      return Tag(bet.tierName, color: AppColors.accent);
    }
    return const Tag('未中奖', color: AppColors.faint);
  }
}

class _ResultRow extends StatelessWidget {
  final Bet bet;
  final GameInfo game;
  final ValueChanged<double?> onActualAmount;

  const _ResultRow({
    required this.bet,
    required this.game,
    required this.onActualAmount,
  });

  @override
  Widget build(BuildContext context) {
    if (!bet.won) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          '这一注未中奖。开奖是独立随机事件，结果不代表选号方法有问题。',
          style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.6),
        ),
      );
    }

    final editable = bet.estimated;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                bet.tierName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
              const Spacer(),
              Text(
                '${bet.estimated ? '约 ' : ''}${fmtMoney(bet.effectiveAmount)} 元',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MatchedBalls(bet: bet),
          const SizedBox(height: 8),
          Text(
            bet.actualAmount != null
                ? '已按实际到账 ${fmtMoney(bet.actualAmount)} 元计入。'
                : '一、二等奖为浮动奖金，当前按长期均值估算；'
                    '到账后点下方改成实际金额。',
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6),
          ),
          if (editable) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _editAmount(context),
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('填写实际到账', style: TextStyle(fontSize: 11.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editAmount(BuildContext context) async {
    final controller = TextEditingController(
      text: bet.actualAmount?.toStringAsFixed(0) ?? '',
    );
    final result = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceHi,
        title: const Text('实际到账金额', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '留空则恢复为估算值。单位为元。',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                suffixText: '元',
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('取消', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                Navigator.pop(context, null);
                return;
              }
              final value = double.tryParse(text);
              if (value == null || value < 0) {
                Navigator.pop(context, double.nan);
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('保存', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
    if (result == null) {
      onActualAmount(null);
    } else if (!result.isNaN) {
      onActualAmount(result);
    }
  }
}

class _MatchedBalls extends StatelessWidget {
  final Bet bet;

  const _MatchedBalls({required this.bet});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final n in bet.primary)
          _ball(n, secondary: false, matched: bet.matchedPrimary.contains(n)),
        if (bet.secondary.isNotEmpty)
          Container(width: 1, height: 22, color: AppColors.border),
        for (final n in bet.secondary)
          _ball(n, secondary: true, matched: bet.matchedSecondary.contains(n)),
      ],
    );
  }

  Widget _ball(int number, {required bool secondary, required bool matched}) {
    if (matched) {
      return Ball(number: number, secondary: secondary, size: 28);
    }
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        number.toString().padLeft(2, '0'),
        style: const TextStyle(fontSize: 11, color: AppColors.faint),
      ),
    );
  }
}
