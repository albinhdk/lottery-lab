import 'dart:math';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Hand-picked ticket checker: choose a draw, tap the numbers, see the
/// matched balls, prize tier and amount.
class PrizeCheckPanel extends StatefulWidget {
  final GameInfo game;
  final Api api;

  const PrizeCheckPanel({super.key, required this.game, required this.api});

  @override
  State<PrizeCheckPanel> createState() => _PrizeCheckPanelState();
}

class _PrizeCheckPanelState extends State<PrizeCheckPanel> {
  final Set<int> _primary = {};
  final Set<int> _secondary = {};
  final Random _random = Random();

  List<Draw> _recent = const [];
  String? _issue;
  bool _loadingDraws = true;
  String? _loadError;

  bool _checking = false;
  String? _error;
  PrizeCheckResult? _result;

  GameInfo get g => widget.game;

  @override
  void initState() {
    super.initState();
    _loadDraws();
  }

  Future<void> _loadDraws() async {
    setState(() {
      _loadingDraws = true;
      _loadError = null;
    });
    try {
      final page = await widget.api.draws(game: g.id, pageSize: 100);
      final items = (page['items'] as List? ?? const [])
          .map((e) => Draw.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (!mounted) return;
      setState(() {
        _recent = items;
        _issue = items.isEmpty ? null : items.first.issue;
        _loadingDraws = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingDraws = false;
      });
    }
  }

  void _toggle(bool secondary, int number) {
    final selected = secondary ? _secondary : _primary;
    final limit = secondary ? g.secondaryCount : g.primaryCount;
    final label = secondary ? g.secondaryLabel : g.primaryLabel;
    if (!selected.contains(number) && selected.length >= limit) {
      _snack('$label最多选 $limit 个，请先取消一个');
      return;
    }
    setState(() {
      if (!selected.remove(number)) {
        selected.add(number);
      }
      _result = null;
      _error = null;
    });
  }

  void _randomPick() {
    final primary = _pick(g.primaryMax, g.primaryCount);
    final secondary = _pick(g.secondaryMax, g.secondaryCount);
    setState(() {
      _primary
        ..clear()
        ..addAll(primary);
      _secondary
        ..clear()
        ..addAll(secondary);
      _result = null;
      _error = null;
    });
  }

  List<int> _pick(int max, int count) {
    final pool = List<int>.generate(max, (i) => i + 1)..shuffle(_random);
    return pool.take(count).toList()..sort();
  }

  void _clear() {
    setState(() {
      _primary.clear();
      _secondary.clear();
      _result = null;
      _error = null;
    });
  }

  Future<void> _check() async {
    if (_checking) return;
    if (_primary.length != g.primaryCount ||
        _secondary.length != g.secondaryCount) {
      setState(() {
        _error =
            '请选满 ${g.primaryCount} 个${g.primaryLabel}和 ${g.secondaryCount} 个${g.secondaryLabel}';
      });
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final result = await widget.api.prizeCheck(
        game: g.id,
        issue: _issue,
        primary: _primary.toList()..sort(),
        secondary: _secondary.toList()..sort(),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _checking = false;
      });
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
        width: 280,
        backgroundColor: AppColors.surfaceHi,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 1100;
        final pad = constraints.maxWidth < 720 ? 12.0 : 26.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 30),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 440, child: _pickerPanel()),
                    const SizedBox(width: 18),
                    Expanded(child: _resultPanel()),
                  ],
                )
              : Column(
                  children: [
                    _pickerPanel(),
                    const SizedBox(height: 18),
                    _resultPanel(),
                  ],
                ),
        );
      },
    );
  }

  Widget _pickerPanel() {
    return Panel(
      title: '手选号码',
      subtitle: '选择期次并输入一注号码，核对命中与奖金',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingDraws)
            const LoadingBox()
          else if (_loadError != null)
            ErrorBox(message: _loadError!, onRetry: _loadDraws)
          else if (_recent.isEmpty)
            const EmptyBox(
              icon: Icons.cloud_off_outlined,
              title: '暂无开奖数据',
              subtitle: '请先同步历史数据，再回来验奖。',
            )
          else ...[
            const SectionLabel('开奖期次', trailing: '最近 100 期'),
            const SizedBox(height: 8),
            _issuePicker(),
            const SizedBox(height: 18),
            SectionLabel(
              g.primaryLabel,
              trailing: '${_primary.length}/${g.primaryCount}',
            ),
            const SizedBox(height: 8),
            _numberGrid(false),
            const SizedBox(height: 16),
            SectionLabel(
              g.secondaryLabel,
              trailing: '${_secondary.length}/${g.secondaryCount}',
            ),
            const SizedBox(height: 8),
            _numberGrid(true),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _randomPick,
                  icon: const Icon(Icons.casino_outlined, size: 16),
                  label: const Text('随机一注', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.backspace_outlined, size: 15),
                  label: const Text('清空', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: _checking ? '计算中…' : '计算奖金',
                icon: Icons.calculate_outlined,
                loading: _checking,
                onPressed: _check,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.red, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              '仅核对已开奖号码，不会提高中奖概率。',
              style: TextStyle(fontSize: 10.5, color: AppColors.faint, height: 1.6),
            ),
          ],
        ],
      ),
    );
  }

  Widget _issuePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _issue,
          isExpanded: true,
          dropdownColor: AppColors.surfaceHi,
          icon: const Icon(Icons.expand_more, size: 18, color: AppColors.muted),
          style: const TextStyle(fontSize: 12.5, color: AppColors.text),
          items: [
            for (final draw in _recent)
              DropdownMenuItem(
                value: draw.issue,
                child: Text('第 ${draw.issue} 期 · ${draw.date}'),
              ),
          ],
          onChanged: (value) => setState(() {
            _issue = value;
            _result = null;
            _error = null;
          }),
        ),
      ),
    );
  }

  Widget _numberGrid(bool secondary) {
    final max = secondary ? g.secondaryMax : g.primaryMax;
    final selected = secondary ? _secondary : _primary;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var n = 1; n <= max; n++)
          _PickBall(
            key: ValueKey('${secondary ? 'secondary' : 'primary'}-$n'),
            number: n,
            secondary: secondary,
            selected: selected.contains(n),
            onTap: () => _toggle(secondary, n),
          ),
      ],
    );
  }

  Widget _resultPanel() {
    final result = _result;
    if (result == null) {
      return Panel(
        title: '验奖结果',
        child: EmptyBox(
          icon: Icons.fact_check_outlined,
          title: '输入号码后计算',
          subtitle: '选好期次，点选 ${g.primaryCount} 个${g.primaryLabel}和 '
              '${g.secondaryCount} 个${g.secondaryLabel}，\n再点“计算奖金”。',
        ),
      );
    }

    final won = result.won;
    return Panel(
      title: '验奖结果',
      subtitle: '第 ${result.issue} 期 · ${result.date}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: won
                  ? AppColors.accent.withValues(alpha: 0.08)
                  : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: won
                    ? AppColors.accent.withValues(alpha: 0.35)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  won ? Icons.emoji_events_rounded : Icons.sentiment_neutral_outlined,
                  size: 28,
                  color: won ? AppColors.accent : AppColors.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.tierName,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: won ? AppColors.accent : AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '命中 ${g.primaryLabel} ${result.primaryHits}/${g.primaryCount} · '
                        '${g.secondaryLabel} ${result.secondaryHits}/${g.secondaryCount}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                if (won)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${result.estimated ? '约 ' : ''}${fmtMoney(result.amount)} 元',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                      Text(
                        result.estimated ? '浮动奖金估算' : '固定奖金',
                        style: const TextStyle(fontSize: 10, color: AppColors.faint),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionLabel('开奖号码'),
          const SizedBox(height: 8),
          _balls(
            result.drawPrimary,
            result.drawSecondary,
            result.matchedPrimary,
            result.matchedSecondary,
          ),
          const SizedBox(height: 16),
          const SectionLabel('你的号码'),
          const SizedBox(height: 8),
          _balls(
            result.ticketPrimary,
            result.ticketSecondary,
            result.matchedPrimary,
            result.matchedSecondary,
          ),
          const SizedBox(height: 8),
          const Text(
            '暗色号码为未命中。',
            style: TextStyle(fontSize: 10.5, color: AppColors.faint),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 15, color: AppColors.faint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.prizeNote,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.faint,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '本功能仅核对已开奖号码，不构成任何购彩建议。',
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.faint.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _balls(
    List<int> primary,
    List<int> secondary,
    List<int> matchedPrimary,
    List<int> matchedSecondary,
  ) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final n in primary)
          _resultBall(n, secondary: false, matched: matchedPrimary.contains(n)),
        if (secondary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(width: 1, height: 22, color: AppColors.border),
          ),
        for (final n in secondary)
          _resultBall(n, secondary: true, matched: matchedSecondary.contains(n)),
      ],
    );
  }

  Widget _resultBall(int number, {required bool secondary, required bool matched}) {
    if (matched) {
      return Ball(number: number, secondary: secondary, size: 30);
    }
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        number.toString().padLeft(2, '0'),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: AppColors.faint,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
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
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors[1].withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
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
