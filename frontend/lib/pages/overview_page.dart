import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class OverviewPage extends StatefulWidget {
  final AppState state;

  const OverviewPage({super.key, required this.state});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _randomness;
  Map<String, dynamic>? _frequency;

  GameInfo? get game => widget.state.game;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = game;
    if (g == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.state.api.randomness(g.id, window: 500, simulations: 150),
        widget.state.api.frequency(g.id, 100),
      ]);
      if (!mounted) return;
      setState(() {
        _randomness = results[0];
        _frequency = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    if (g == null) {
      return const EmptyBox(
        icon: Icons.inbox_outlined,
        title: '未选择彩种',
        subtitle: '请在左侧选择一个彩种。',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 820;
        final pad = narrow ? 16.0 : 26.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, narrow ? 16 : 24, pad, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _coverageRow(g),
              const SizedBox(height: 16),
              if (narrow) ...[
                _latestPanel(g, narrow: true),
                const SizedBox(height: 16),
                _randomnessPanel(),
                const SizedBox(height: 16),
                _heatPanel(g),
                const SizedBox(height: 16),
                _methodPanel(g),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _latestPanel(g)),
                    const SizedBox(width: 18),
                    Expanded(flex: 5, child: _randomnessPanel()),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _heatPanel(g)),
                    const SizedBox(width: 18),
                    Expanded(flex: 5, child: _methodPanel(g)),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              _disclaimer(g),
            ],
          ),
        );
      },
    );
  }

  Widget _coverageRow(GameInfo g) {
    final odds = g.jackpotOdds;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1100 ? 4 : (width > 760 ? 2 : 1);
        final tiles = [
          StatTile(
            label: '历史期数',
            value: fmtInt(g.count),
            sub: '${g.firstDate ?? '—'} 至今',
            icon: Icons.storage_outlined,
            color: AppColors.blue,
          ),
          StatTile(
            label: '最新开奖',
            value: g.latest?.issue ?? '—',
            sub: g.latest?.date ?? '—',
            icon: Icons.event_available_outlined,
            color: AppColors.accent,
          ),
          StatTile(
            label: '一等奖概率',
            value: '1 / ${fmtInt(odds)}',
            sub: '${g.primaryCount} 个${g.primaryLabel} + ${g.secondaryCount} 个${g.secondaryLabel}',
            icon: Icons.casino_outlined,
            color: AppColors.purple,
          ),
          StatTile(
            label: '分析引擎',
            value: '9 项检验',
            sub: '卡方 · 游程 · 自相关 · 蒙特卡洛',
            icon: Icons.verified_outlined,
            color: AppColors.green,
          ),
        ];
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final t in tiles)
              SizedBox(width: (width - (columns - 1) * 16) / columns, child: t),
          ],
        );
      },
    );
  }

  Widget _latestPanel(GameInfo g, {bool narrow = false}) {
    final latest = g.latest;
    return Panel(
      title: '最新开奖',
      subtitle: '数据来自官方开奖接口',
      trailing: IconButton(
        onPressed: _load,
        icon: const Icon(Icons.refresh, size: 18),
        color: AppColors.muted,
        tooltip: '刷新',
      ),
      child: latest == null
          ? const EmptyBox(
              icon: Icons.event_busy_outlined,
              title: '暂无数据',
              subtitle: '点击右上角“同步数据”拉取历史开奖。',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (narrow) ...[
                  Row(
                    children: [
                      Text(
                        '第 ${latest.issue} 期',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        latest.date,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  BallRow(
                    primary: latest.primary,
                    secondary: latest.secondary,
                    size: 33,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      BallRow(
                        primary: latest.primary,
                        secondary: latest.secondary,
                        size: 40,
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '第 ${latest.issue} 期',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            latest.date,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _miniInfo('销售额', fmtMoney(latest.sales)),
                    _miniInfo('奖池', fmtMoney(latest.pool)),
                    Tag(
                      '${g.primaryLabel} ${g.primaryCount}/${g.primaryMax} · ${g.secondaryLabel} ${g.secondaryCount}/${g.secondaryMax}',
                      color: AppColors.blue,
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _miniInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.faint)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _randomnessPanel() {
    if (_loading) {
      return const Panel(
        title: '随机性体检',
        subtitle: '最近 500 期 · 9 项统计检验',
        child: LoadingBox(label: '正在运行蒙特卡洛校准…'),
      );
    }
    if (_error != null) {
      return Panel(
        title: '随机性体检',
        child: ErrorBox(message: _error!, onRetry: _load),
      );
    }
    final data = _randomness!;
    final tests = (data['tests'] as List).cast<Map<String, dynamic>>();
    final conclusion = data['conclusion'] as String? ?? '';
    final overallVerdict = data['overall_verdict'] as String? ?? 'pass';
    final pass = overallVerdict == 'pass';
    final color = pass ? AppColors.green : AppColors.accent;

    return Panel(
      title: '随机性体检',
      subtitle: '最近 ${data['total_draws']} 期 · ${data['test_count']} 项检验',
      trailing: Tag(pass ? '与随机一致' : '存在偏离', color: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  pass ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    conclusion,
                    style: const TextStyle(fontSize: 12, height: 1.65, color: AppColors.text),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final t in tests.where((t) => t['p_value'] != null).take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(
                      t['name'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ((t['p_value'] as num).toDouble()).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: AppColors.surfaceHi,
                        color: (t['p_value'] as num) < 0.05
                            ? AppColors.accent
                            : AppColors.blue.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 54,
                    child: Text(
                      'p=${fmtP((t['p_value'] as num).toDouble())}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => widget.state.selectPage(2),
              child: const Text('查看完整报告 →', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heatPanel(GameInfo g) {
    if (_loading || _frequency == null) {
      return const Panel(
        title: '近期热度',
        subtitle: '最近 100 期出现次数',
        child: LoadingBox(),
      );
    }
    final numbers =
        ((_frequency!['primary']['numbers'] as List).cast<Map<String, dynamic>>())
          ..sort((a, b) => (b['count'] as num).compareTo(a['count'] as num));
    final hot = numbers.take(6).toList();
    final cold = numbers.reversed.take(6).toList();
    final maxCount = (numbers.first['count'] as num).toDouble();

    return Panel(
      title: '近期热度',
      subtitle: '最近 100 期 ${g.primaryLabel}出现次数',
      trailing: Tag('仅描述，不是预测', color: AppColors.faint),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _heatColumn('热号', hot, maxCount, AppColors.accent)),
          const SizedBox(width: 24),
          Expanded(child: _heatColumn('冷号', cold, maxCount, AppColors.blue)),
        ],
      ),
    );
  }

  Widget _heatColumn(
    String title,
    List<Map<String, dynamic>> items,
    double maxCount,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title),
        const SizedBox(height: 10),
        for (final n in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Ball(number: (n['number'] as num).toInt(), size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ((n['count'] as num).toDouble() / maxCount).clamp(0.05, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceHi,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${n['count']}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _methodPanel(GameInfo g) {
    return Panel(
      title: '这台工具在做什么',
      subtitle: '用统计检验回答“有没有规律”，而不是承诺预测',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _methodRow(
            Icons.functions,
            '均匀性检验',
            '每个号码的理论出现概率相同；卡方检验衡量实际偏差是否超出随机波动。',
          ),
          _methodRow(
            Icons.timeline,
            '独立性检验',
            '和值自相关、游程、相邻期重号率，检查上一期是否影响下一期。',
          ),
          _methodRow(
            Icons.science_outlined,
            '走查回测',
            '每个策略在预测第 t 期时只能看到前 t−1 期，杜绝未来数据泄露。',
          ),
          _methodRow(
            Icons.balance,
            '随机基线',
            '所有策略都与纯随机选号对比命中率、Brier 分数与 ROI。',
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '预期结论：所有策略的命中率都会落在随机基线附近。这就是彩票的本质。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodRow(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _disclaimer(GameInfo g) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 17, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${g.name}每个号码组合的中奖概率完全相同。本工具展示的历史规律、热号冷号与策略回测，'
              '只用于检验“是否存在可利用的统计偏差”，不构成任何购彩建议。请理性购彩，量力而行。',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.65),
            ),
          ),
        ],
      ),
    );
  }
}
