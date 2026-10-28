import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _strategyColors = [
  AppColors.accent,
  AppColors.blue,
  AppColors.green,
  AppColors.purple,
  AppColors.cyan,
  AppColors.red,
  Color(0xFFFF9F43),
  Color(0xFFB8C0CC),
];

class BacktestPage extends StatefulWidget {
  final AppState state;

  const BacktestPage({super.key, required this.state});

  @override
  State<BacktestPage> createState() => _BacktestPageState();
}

class _BacktestPageState extends State<BacktestPage> {
  List<StrategyInfo> _strategies = [];
  final Set<String> _selected = {};
  int _trainWindow = 500;
  int _testSize = 300;
  int _tickets = 1;
  bool _loadingStrategies = true;
  bool _running = false;
  String? _error;
  Map<String, dynamic>? _result;

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
        _selected
          ..clear()
          ..addAll(list.map((e) => e.id));
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

  Future<void> _run() async {
    final g = game;
    if (g == null || _selected.isEmpty || _running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final data = await widget.state.api.backtest({
        'game': g.id,
        'strategies': _selected.toList(),
        'train_window': _trainWindow,
        'test_size': _testSize,
        'tickets_per_draw': _tickets,
        'seed': 42,
      });
      if (!mounted) return;
      setState(() {
        _result = data;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    if (g == null) return const SizedBox();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 1120;
        final pad = constraints.maxWidth < 720 ? 12.0 : 26.0;
        final config = _configPanel(g);
        final results = _resultsPanel(g);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 22, pad, 30),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 340, child: config),
                    const SizedBox(width: 18),
                    Expanded(child: results),
                  ],
                )
              : Column(
                  children: [
                    config,
                    const SizedBox(height: 18),
                    results,
                  ],
                ),
        );
      },
    );
  }

  Widget _configPanel(GameInfo g) {
    return Panel(
      title: '回测配置',
      subtitle: '严格走查：预测第 t 期时只使用前 t−1 期',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('策略'),
          const SizedBox(height: 8),
          if (_loadingStrategies)
            const LoadingBox()
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < _strategies.length; i++)
                      _StrategyCheck(
                        strategy: _strategies[i],
                        color: _strategyColors[i % _strategyColors.length],
                        checked: _selected.contains(_strategies[i].id),
                        onChanged: (v) {
                          setState(() {
                            if (v) {
                              _selected.add(_strategies[i].id);
                            } else {
                              _selected.remove(_strategies[i].id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          const SectionLabel('训练窗口'),
          const SizedBox(height: 8),
          ChoicePills<int>(
            values: const [200, 300, 500, 1000],
            selected: _trainWindow,
            label: (v) => '$v 期',
            onChanged: (v) => setState(() => _trainWindow = v),
          ),
          const SizedBox(height: 16),
          const SectionLabel('回测期数'),
          const SizedBox(height: 8),
          ChoicePills<int>(
            values: const [100, 200, 300, 500],
            selected: _testSize,
            label: (v) => '$v 期',
            onChanged: (v) => setState(() => _testSize = v),
          ),
          const SizedBox(height: 16),
          const SectionLabel('每期注数'),
          const SizedBox(height: 8),
          ChoicePills<int>(
            values: const [1, 2, 5],
            selected: _tickets,
            label: (v) => '$v 注',
            onChanged: (v) => setState(() => _tickets = v),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: _running ? '回测运行中…' : '开始回测',
              icon: Icons.play_arrow_rounded,
              loading: _running,
              onPressed: _selected.isEmpty ? null : _run,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '票价为 ${g.price.toStringAsFixed(0)} 元/注。一、二等奖按固定估值计算，'
              '三至${g.id == 'ssq' ? '六' : '九'}等奖为官方固定奖金。ROI 的 95% 置信区间由自助法给出。',
              style: const TextStyle(fontSize: 10.5, color: AppColors.faint, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsPanel(GameInfo g) {
    if (_error != null) {
      return Panel(
        title: '回测结果',
        child: ErrorBox(message: _error!, onRetry: _result == null ? null : _run),
      );
    }
    if (_running) {
      return const Panel(
        title: '回测结果',
        child: LoadingBox(label: '正在逐期走查 8 个策略，请稍候…'),
      );
    }
    if (_result == null) {
      return const Panel(
        title: '回测结果',
        child: EmptyBox(
          icon: Icons.science_outlined,
          title: '还没有运行回测',
          subtitle: '在左侧选择策略与窗口，然后点击“开始回测”。\n'
              '回测会把每个策略的命中率、ROI、Brier 分数与随机基线逐项对比。',
        ),
      );
    }
    final d = _result!;
    final results = (d['results'] as List).cast<Map<String, dynamic>>()
      ..sort((a, b) => (b['roi'] as num).compareTo(a['roi'] as num));
    return Column(
      children: [
        _verdictPanel(d),
        const SizedBox(height: 18),
        _tablePanel(d, results, g),
        const SizedBox(height: 18),
        _chartPanel(d, results),
        const SizedBox(height: 18),
        _explainPanel(g),
      ],
    );
  }

  Widget _verdictPanel(Map<String, dynamic> d) {
    final overallVerdict = d['overall_verdict'] as String? ?? 'pass';
    final pass = overallVerdict == 'pass';
    final color = pass ? AppColors.green : AppColors.accent;
    return Panel(
      title: '结论',
      subtitle:
          '${d['test_size']} 期走查 · ${d['test_start_issue']} → ${d['test_end_issue']} · 每期 ${d['tickets_per_draw']} 注 · 整体 p=${fmtP((d['overall_p'] as num?)?.toDouble())}',
      trailing: VerdictChip(overallVerdict),
      tint: color.withValues(alpha: 0.05),
      child: Text(
        d['verdict'] as String? ?? '',
        style: const TextStyle(fontSize: 13, height: 1.75),
      ),
    );
  }

  Widget _tablePanel(Map<String, dynamic> d, List<Map<String, dynamic>> results, GameInfo g) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      title: '策略对比',
      subtitle: '命中率与随机基线（期望 ${results.isEmpty ? '—' : results.first['expected_primary_hits']} 个）对比',
      trailing: Tag('按 ROI 排序', color: AppColors.faint),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 750,
          child: Column(
            children: [
              const _BtHeader(),
              const Divider(height: 1, color: AppColors.border),
              for (var i = 0; i < results.length; i++)
                _BtRow(
                  result: results[i],
                  color: _strategyColors[
                      _strategies.indexWhere((s) => s.id == results[i]['strategy']) %
                          _strategyColors.length],
                  game: g,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chartPanel(Map<String, dynamic> d, List<Map<String, dynamic>> results) {
    final series = <_Series>[];
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      final idx = _strategies.indexWhere((s) => s.id == r['strategy']);
      final color = _strategyColors[(idx < 0 ? i : idx) % _strategyColors.length];
      final cum = (r['cumulative'] as List).cast<Map<String, dynamic>>();
      series.add(_Series(
        label: r['label'] as String,
        color: color,
        spots: [
          for (final p in cum)
            FlSpot(
              (p['i'] as num).toDouble(),
              (p['cumulative'] as num).toDouble(),
            ),
        ],
      ));
    }
    if (series.isEmpty) return const SizedBox();
    var minY = 0.0;
    var maxY = 0.0;
    for (final s in series) {
      for (final p in s.spots) {
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
    }
    final pad = ((maxY - minY).abs() * 0.12).clamp(20.0, 100000.0);
    return Panel(
      title: '累计盈亏曲线',
      subtitle: '起点为 0；向下代表持续亏损。理论上所有策略都应围绕负期望波动。',
      child: Column(
        children: [
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                minX: 1,
                maxX: series.first.spots.isEmpty ? 2 : series.first.spots.last.x,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: AppColors.border.withValues(alpha: 0.55),
                    strokeWidth: 0.6,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 58,
                      getTitlesWidget: (value, meta) => Text(
                        _axisMoney(value),
                        style: const TextStyle(fontSize: 9.5, color: AppColors.faint),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${value.toInt()}',
                          style: const TextStyle(fontSize: 9.5, color: AppColors.faint),
                        ),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surfaceHi,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${series[s.barIndex].label}\n第 ${s.x.toInt()} 期 · ${s.y.toStringAsFixed(0)} 元',
                          TextStyle(
                            color: series[s.barIndex].color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  for (final s in series)
                    LineChartBarData(
                      spots: s.spots,
                      isCurved: false,
                      color: s.color,
                      barWidth: 1.8,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 3,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.label,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            d['prize_note'] as String? ?? '',
            style: const TextStyle(fontSize: 10.5, color: AppColors.faint, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _explainPanel(GameInfo g) {
    return Panel(
      title: '如何读这张表',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _explainRow(
            '平均命中',
            '每注猜中的${g.primaryLabel}个数。理论期望为 ${g.primaryCount}×${g.primaryCount}/${g.primaryMax} = '
                '${(g.primaryCount * g.primaryCount / g.primaryMax).toStringAsFixed(3)}。高于它不代表有效，'
                '要看 p 值与置信区间。',
          ),
          _explainRow(
            'p 值',
            '在“策略无效”的假设下，出现当前或更极端命中率的概率。p>0.05 表示与随机基线无显著差异。',
          ),
          _explainRow(
            'ROI',
            '（奖金 − 成本）/ 成本。彩票的期望回报率通常为负；正的 ROI 多半来自少数高奖级，'
                '95% 置信区间跨过 0 时更不能说明问题。',
          ),
          _explainRow(
            'Brier',
            '概率预测的均方误差，越低越好。随机基线把每个号码都设为 k/n，因此它的 Brier 是理论最优；'
                '确定性策略把概率压到 0 或 1/k，通常会明显更差。',
          ),
        ],
      ),
    );
  }

  Widget _explainRow(String label, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.7),
            ),
          ),
        ],
      ),
    );
  }

  String _axisMoney(double v) {
    final abs = v.abs();
    if (abs >= 10000) return '${(v / 10000).toStringAsFixed(1)}万';
    return v.toStringAsFixed(0);
  }
}

class _StrategyCheck extends StatelessWidget {
  final StrategyInfo strategy;
  final Color color;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _StrategyCheck({
    required this.strategy,
    required this.color,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: checked,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: color,
                checkColor: Colors.black,
                side: const BorderSide(color: AppColors.border, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strategy.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: checked ? AppColors.text : AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    strategy.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.faint, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Series {
  final String label;
  final Color color;
  final List<FlSpot> spots;

  const _Series({required this.label, required this.color, required this.spots});
}

class _BtHeader extends StatelessWidget {
  const _BtHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 10.5, color: AppColors.faint);
    return const SizedBox(
      height: 38,
      child: Row(
        children: [
          SizedBox(width: 140, child: Text('策略', style: style)),
          SizedBox(width: 108, child: Text('命中 / 期望', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 62, child: Text('z', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 72, child: Text('p 值', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 78, child: Text('ROI', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 132, child: Text('ROI 95% CI', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 88, child: Text('Brier', style: style, textAlign: TextAlign.right)),
          Expanded(child: Text('中奖注数', style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _BtRow extends StatelessWidget {
  final Map<String, dynamic> result;
  final Color color;
  final GameInfo game;

  const _BtRow({required this.result, required this.color, required this.game});

  @override
  Widget build(BuildContext context) {
    final p = (result['p_value'] as num).toDouble();
    final roi = (result['roi'] as num).toDouble();
    final ci = (result['roi_ci'] as List).cast<num>();
    final brier = (result['brier'] as num).toDouble();
    final uniform = (result['uniform_brier'] as num).toDouble();
    final profit = (result['profit'] as num).toDouble();
    final wins = (result['win_tickets'] as num).toInt();
    final tiers = (result['tier_counts'] as List).cast<Map<String, dynamic>>();
    final tierText = tiers
        .where((t) => (t['tier'] as num).toInt() > 0)
        .map((t) => '${t['name']}×${t['count']}')
        .join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    result['label'] as String? ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 108,
            child: Text(
              '${result['avg_primary_hits']} / ${result['expected_primary_hits']}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              '${result['primary_z']}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              fmtP(p),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: p < 0.05 ? AppColors.accent : AppColors.muted,
              ),
            ),
          ),
          SizedBox(
            width: 78,
            child: Text(
              fmtPct(roi),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: roi >= 0 ? AppColors.green : AppColors.red,
              ),
            ),
          ),
          SizedBox(
            width: 132,
            child: Text(
              '${fmtPct(ci[0].toDouble())} ~ ${fmtPct(ci[1].toDouble())}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              '${brier.toStringAsFixed(4)}\n${uniform.toStringAsFixed(4)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                height: 1.4,
                color: brier <= uniform ? AppColors.green : AppColors.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: '${tierText.isEmpty ? '未中奖' : tierText}\n盈亏 ${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(0)} 元',
              child: Text(
                '$wins 注',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
