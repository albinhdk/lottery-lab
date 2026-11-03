import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'prize_check_panel.dart';

class TicketsPage extends StatefulWidget {
  final AppState state;

  const TicketsPage({super.key, required this.state});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  List<StrategyInfo> _strategies = [];
  String? _selected;
  int _count = 5;
  bool _loadingStrategies = true;
  bool _generating = false;
  String? _error;
  Map<String, dynamic>? _result;

  /// 0 = strategy generator, 1 = hand-picked prize checker.
  int _mode = 0;
  bool _checkerOpened = false;

  GameInfo? get game => widget.state.game;

  @override
  void initState() {
    super.initState();
    _loadStrategies();
  }

  Future<void> _loadStrategies() async {
    try {
      final list = await widget.state.api.strategies();
      if (!mounted) return;
      setState(() {
        _strategies = list;
        _selected = list.any((s) => s.id == 'balanced') ? 'balanced' : list.first.id;
        _loadingStrategies = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingStrategies = false;
      });
    }
  }

  Future<void> _generate() async {
    final g = game;
    final s = _selected;
    if (g == null || s == null || _generating) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final data = await widget.state.api.tickets(
        game: g.id,
        strategy: s,
        count: _count,
      );
      if (!mounted) return;
      setState(() {
        _result = data;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _generating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    if (g == null) return const SizedBox();
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = constraints.maxWidth < 720 ? 12.0 : 26.0;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 16, pad, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ChoicePills<int>(
                  values: const [0, 1],
                  selected: _mode,
                  label: (v) => v == 0 ? '智能选号' : '手选验奖',
                  onChanged: _switchMode,
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                sizing: StackFit.expand,
                index: _mode,
                children: [
                  _generator(g),
                  _checkerOpened
                      ? PrizeCheckPanel(game: g, api: widget.state.api)
                      : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _switchMode(int value) {
    if (value == _mode) return;
    setState(() {
      _mode = value;
      if (value == 1) _checkerOpened = true;
    });
  }

  Widget _generator(GameInfo g) {
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
                    SizedBox(width: 380, child: _configPanel(g)),
                    const SizedBox(width: 18),
                    Expanded(child: _resultPanel(g)),
                  ],
                )
              : Column(
                  children: [
                    _configPanel(g),
                    const SizedBox(height: 18),
                    _resultPanel(g),
                  ],
                ),
        );
      },
    );
  }

  Widget _configPanel(GameInfo g) {
    return Column(
      children: [
        Panel(
          title: '选号策略',
          subtitle: '不同规则会给出不同的号码，但概率完全相同',
          child: _loadingStrategies
              ? const LoadingBox()
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < _strategies.length; i++)
                          _StrategyRadio(
                            strategy: _strategies[i],
                            selected: _selected == _strategies[i].id,
                            onTap: () =>
                                setState(() => _selected = _strategies[i].id),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 18),
        Panel(
          title: '生成设置',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('注数'),
              const SizedBox(height: 8),
              ChoicePills<int>(
                values: const [1, 3, 5, 10],
                selected: _count,
                label: (v) => '$v 注',
                onChanged: (v) => setState(() => _count = v),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: _generating ? '生成中…' : '生成号码',
                  icon: Icons.auto_awesome_outlined,
                  loading: _generating,
                  onPressed: _selected == null ? null : _generate,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '一等奖概率：1 / ${fmtInt(g.jackpotOdds)}\n'
                '每注 ${g.price.toStringAsFixed(0)} 元，期望回报为负。',
                style: const TextStyle(fontSize: 11, color: AppColors.faint, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultPanel(GameInfo g) {
    if (_error != null) {
      return Panel(
        title: '生成结果',
        child: ErrorBox(message: _error!, onRetry: _result == null ? null : _generate),
      );
    }
    if (_result == null) {
      return Panel(
        title: '生成结果',
        child: EmptyBox(
          icon: Icons.confirmation_number_outlined,
          title: '还没有生成号码',
          subtitle: '选择一种策略和注数，点击“生成号码”。\n'
              '请把它当作一个随机号码生成器，而不是预测。',
        ),
      );
    }
    final tickets = (_result!['tickets'] as List).cast<Map<String, dynamic>>();
    final description = _result!['description'] as String? ?? '';
    return Panel(
      title: '${_result!['strategy_label']} · ${tickets.length} 注',
      subtitle: description,
      trailing: TextButton.icon(
        onPressed: () => _copyAll(tickets, g),
        icon: const Icon(Icons.copy_all_outlined, size: 15),
        label: const Text('全部复制', style: TextStyle(fontSize: 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth < 330
                  ? constraints.maxWidth
                  : 316.0;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (var i = 0; i < tickets.length; i++)
                    _TicketCard(
                      width: cardWidth,
                      index: i + 1,
                      primary: (tickets[i]['primary'] as List)
                          .cast<num>()
                          .map((e) => e.toInt())
                          .toList(),
                      secondary: (tickets[i]['secondary'] as List)
                          .cast<num>()
                          .map((e) => e.toInt())
                          .toList(),
                      onCopy: () => _copyOne(tickets[i], g),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _result!['disclaimer'] as String? ?? '',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTicket(Map<String, dynamic> t, GameInfo g) {
    final p = (t['primary'] as List).cast<num>().map((e) => e.toInt().toString().padLeft(2, '0')).join(' ');
    final s = (t['secondary'] as List).cast<num>().map((e) => e.toInt().toString().padLeft(2, '0')).join(' ');
    return '${g.primaryLabel} $p | ${g.secondaryLabel} $s';
  }

  void _copyOne(Map<String, dynamic> t, GameInfo g) {
    Clipboard.setData(ClipboardData(text: _formatTicket(t, g)));
    _snack('已复制');
  }

  void _copyAll(List<Map<String, dynamic>> tickets, GameInfo g) {
    final text = [
      '${g.name} · ${_result!['strategy_label']}',
      for (var i = 0; i < tickets.length; i++)
        '${i + 1}. ${_formatTicket(tickets[i], g)}',
    ].join('\n');
    Clipboard.setData(ClipboardData(text: text));
    _snack('已复制 ${tickets.length} 注');
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
        width: 220,
        backgroundColor: AppColors.surfaceHi,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _StrategyRadio extends StatelessWidget {
  final StrategyInfo strategy;
  final bool selected;
  final VoidCallback onTap;

  const _StrategyRadio({
    required this.strategy,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.08)
                : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 17,
                color: selected ? AppColors.accent : AppColors.faint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strategy.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? AppColors.text : AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      strategy.description,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.faint, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final int index;
  final List<int> primary;
  final List<int> secondary;
  final VoidCallback onCopy;
  final double width;

  const _TicketCard({
    required this.index,
    required this.primary,
    required this.secondary,
    required this.onCopy,
    this.width = 316,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '第 $index 注',
                style: const TextStyle(fontSize: 11, color: AppColors.faint),
              ),
              const Spacer(),
              InkWell(
                onTap: onCopy,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.copy_outlined, size: 15, color: AppColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BallRow(primary: primary, secondary: secondary, size: 31),
        ],
      ),
    );
  }
}
