import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/lazy_indexed_stack.dart';

class AnalysisPage extends StatefulWidget {
  final AppState state;

  const AnalysisPage({super.key, required this.state});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  int _tab = 0;
  static const _tabs = ['频率分布', '遗漏分析', '组合结构', '随机性检验'];

  @override
  Widget build(BuildContext context) {
    final g = widget.state.game;
    if (g == null) return const SizedBox();
    final pages = [
      FrequencyTab(api: widget.state.api, game: g),
      GapsTab(api: widget.state.api, game: g),
      CombinationsTab(api: widget.state.api, game: g),
      RandomnessTab(api: widget.state.api, game: g),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        return Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(narrow ? 12 : 26, 12, narrow ? 12 : 26, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++) ...[
                      _TabButton(
                        label: _tabs[i],
                        selected: _tab == i,
                        onTap: () => setState(() => _tab = i),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: LazyIndexedStack(index: _tab, children: pages),
            ),
          ],
        );
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceHi : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.border : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.text : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Frequency
// ---------------------------------------------------------------------------

class FrequencyTab extends StatefulWidget {
  final Api api;
  final GameInfo game;

  const FrequencyTab({super.key, required this.api, required this.game});

  @override
  State<FrequencyTab> createState() => _FrequencyTabState();
}

class _FrequencyTabState extends State<FrequencyTab> {
  int _window = 100;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.frequency(widget.game.id, _window);
      if (!mounted) return;
      setState(() {
        _data = data;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 820;
        final pad = narrow ? 12.0 : 26.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 6, pad, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (narrow) ...[
                const Text(
                  '统计窗口',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                ChoicePills<int>(
                  values: const [30, 50, 100, 300, 0],
                  selected: _window,
                  label: (v) => v == 0 ? '全部历史' : '最近 $v 期',
                  onChanged: (v) {
                    setState(() => _window = v);
                    _load();
                  },
                ),
              ] else
                Row(
                  children: [
                    const Text(
                      '统计窗口',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(width: 12),
                    ChoicePills<int>(
                      values: const [30, 50, 100, 300, 0],
                      selected: _window,
                      label: (v) => v == 0 ? '全部历史' : '最近 $v 期',
                      onChanged: (v) {
                        setState(() => _window = v);
                        _load();
                      },
                    ),
                    const Spacer(),
                    Text(
                      '${widget.game.name} · ${widget.game.primaryLabel} ${widget.game.primaryMax} 选 ${widget.game.primaryCount}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.faint),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              if (_loading)
                const Panel(child: LoadingBox(label: '计算频率分布…'))
              else if (_error != null)
                Panel(child: ErrorBox(message: _error!, onRetry: _load))
              else ...[
                if (narrow) ...[
                  _distPanel(_data!['primary'], false),
                  const SizedBox(height: 16),
                  _distPanel(_data!['secondary'], true),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _distPanel(_data!['primary'], false)),
                      const SizedBox(width: 18),
                      Expanded(child: _distPanel(_data!['secondary'], true)),
                    ],
                  ),
                const SizedBox(height: 18),
                _heatmapPanel(_data!['primary'], false),
                const SizedBox(height: 18),
                _heatmapPanel(_data!['secondary'], true),
                const SizedBox(height: 18),
                _deviationPanel(_data!['primary'], false),
                const SizedBox(height: 18),
                const _NoteCard(
                  icon: Icons.info_outline,
                  text: '频率统计是描述性的：某个号码最近出现得多，不代表它“更可能”或“更不可能”继续出现。'
                      '卡方检验的 p 值衡量的是整体偏差是否超出随机波动，而不是某个号码的“趋势”。',
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _distPanel(dynamic block, bool secondary) {
    if (block == null) return const SizedBox();
    final b = block as Map<String, dynamic>;
    final color = secondary ? AppColors.blue : AppColors.accent;
    final p = (b['p_value'] as num).toDouble();
    return Panel(
      title: '${b['label']}分布',
      subtitle: '${b['total_draws']} 期 · 每个号码理论出现 ${b['expected_per_number']} 次',
      trailing: VerdictChip(_verdict(p)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _miniStat('χ²', '${b['chi_square']}', color),
              _miniStat('df', '${b['df']}', AppColors.muted),
              _miniStat('p 值', fmtP(p), p < 0.05 ? AppColors.accent : AppColors.green),
              _miniStat(
                '归一化熵',
                (b['normalized_entropy'] as num).toStringAsFixed(4),
                AppColors.purple,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            p < 0.05
                ? '整体频率偏离均匀分布，需结合窗口与历史阶段判断。'
                : '整体频率与均匀分布一致，未发现系统性偏好。',
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.faint)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heatmapPanel(dynamic block, bool secondary) {
    if (block == null) return const SizedBox();
    final b = block as Map<String, dynamic>;
    final numbers = (b['numbers'] as List).cast<Map<String, dynamic>>();
    return Panel(
      title: '${b['label']}频率热力图',
      subtitle: '数字为出现次数；颜色越暖表示高于期望，越冷表示低于期望',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tag('偏多', color: AppColors.accent),
          const SizedBox(width: 6),
          Tag('偏少', color: AppColors.blue),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth < 560 ? 6 : 11;
          final cell = (constraints.maxWidth - (cols - 1) * 8) / cols;
          final w = cell.clamp(42.0, 74.0);
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in numbers)
                _HeatCell(
                  number: (n['number'] as num).toInt(),
                  count: (n['count'] as num).toInt(),
                  z: (n['z'] as num).toDouble(),
                  gap: (n['current_gap'] as num).toInt(),
                  expected: (n['expected'] as num).toDouble(),
                  width: w,
                  secondary: secondary,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _deviationPanel(dynamic block, bool secondary) {
    if (block == null) return const SizedBox();
    final b = block as Map<String, dynamic>;
    final numbers = (b['numbers'] as List).cast<Map<String, dynamic>>()
      ..sort((a, c) => (c['z'] as num).compareTo(a['z'] as num));
    final top = numbers.take(5).toList();
    final bottom = numbers.reversed.take(5).toList();
    return Panel(
      title: '偏离最大的号码',
      subtitle: '按 z 分数排序（正=出现偏多，负=出现偏少）',
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              children: [
                _devColumn('高于期望', top, secondary),
                const SizedBox(height: 16),
                _devColumn('低于期望', bottom, secondary),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _devColumn('高于期望', top, secondary)),
              const SizedBox(width: 26),
              Expanded(child: _devColumn('低于期望', bottom, secondary)),
            ],
          );
        },
      ),
    );
  }

  Widget _devColumn(String title, List<Map<String, dynamic>> items, bool secondary) {
    final maxAbs = items
        .map((e) => (e['z'] as num).abs().toDouble())
        .fold(0.5, (a, b) => a > b ? a : b);
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
                Ball(number: (n['number'] as num).toInt(), size: 25, secondary: secondary),
                const SizedBox(width: 9),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ((n['z'] as num).abs().toDouble() / maxAbs).clamp(0.05, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceHi,
                      color: (n['z'] as num) >= 0 ? AppColors.accent : AppColors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  child: Text(
                    'z=${(n['z'] as num).toStringAsFixed(2)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HeatCell extends StatelessWidget {
  final int number;
  final int count;
  final double z;
  final int gap;
  final double expected;
  final double width;
  final bool secondary;

  const _HeatCell({
    required this.number,
    required this.count,
    required this.z,
    required this.gap,
    required this.expected,
    required this.width,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final base = secondary ? AppColors.blue : AppColors.accent;
    final alpha = (z.abs() / 3.0).clamp(0.03, 0.42);
    final bg = z >= 0
        ? base.withValues(alpha: alpha)
        : AppColors.blue.withValues(alpha: alpha);
    return Tooltip(
      message: '号码 $number\n出现 $count 次，理论 $expected 次\nz = ${z.toStringAsFixed(2)}\n当前遗漏 $gap 期',
      child: Container(
        width: width,
        height: 58,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: z.abs() > 2
                ? base.withValues(alpha: 0.55)
                : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              number.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: z.abs() > 2 ? Colors.white : AppColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10.5,
                color: z.abs() > 2 ? Colors.white70 : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gaps
// ---------------------------------------------------------------------------

class GapsTab extends StatefulWidget {
  final Api api;
  final GameInfo game;

  const GapsTab({super.key, required this.api, required this.game});

  @override
  State<GapsTab> createState() => _GapsTabState();
}

class _GapsTabState extends State<GapsTab> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.gaps(widget.game.id);
      if (!mounted) return;
      setState(() {
        _data = data;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = constraints.maxWidth < 720 ? 12.0 : 26.0;
        if (_loading) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: const Panel(child: LoadingBox(label: '计算遗漏…')),
          );
        }
        if (_error != null) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: Panel(child: ErrorBox(message: _error!, onRetry: _load)),
          );
        }
        final primary = _data!['primary'] as Map<String, dynamic>;
        final secondary = _data!['secondary'] as Map<String, dynamic>;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 6, pad, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _gapPanel(primary, false),
              const SizedBox(height: 18),
              _gapPanel(secondary, true),
              const SizedBox(height: 18),
              _NoteCard(
                icon: Icons.psychology_alt_outlined,
                text: '“遗漏 N 期”只说明过去 N 期没出现。若开奖独立，下一次出现的概率仍然是 '
                    '${widget.game.primaryCount}/${widget.game.primaryMax}，与遗漏多久无关——认为“该出了”是典型的赌徒谬误。'
                    '本页只做描述，不提供任何回补信号。',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _gapPanel(Map<String, dynamic> block, bool secondary) {
    final items = (block['numbers'] as List).cast<Map<String, dynamic>>()
      ..sort((a, b) => (b['current_gap'] as num).compareTo(a['current_gap'] as num));
    final maxGap = items.isEmpty
        ? 1.0
        : (items.first['current_gap'] as num).toDouble().clamp(1.0, 999.0);
    final color = secondary ? AppColors.blue : AppColors.accent;
    final top = items.take(12).toList();
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Panel(
      title: '${block['label']}当前遗漏',
      subtitle: '理论平均间隔 ${block['expected_gap']} 期 · 按当前遗漏降序',
      trailing: compact ? null : Tag('前 12 个号码', color: AppColors.faint),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in top)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Ball(
                    number: (n['number'] as num).toInt(),
                    size: 26,
                    secondary: secondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ((n['current_gap'] as num).toDouble() / maxGap)
                            .clamp(0.02, 1.0),
                        minHeight: 7,
                        backgroundColor: AppColors.surfaceHi,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 68,
                    child: Text(
                      '${n['current_gap']} 期',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.text),
                    ),
                  ),
                  if (!compact) ...[
                    SizedBox(
                      width: 78,
                      child: Text(
                        '均 ${n['avg_gap']}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
                      ),
                    ),
                    SizedBox(
                      width: 78,
                      child: Text(
                        '最大 ${n['max_gap']}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 10),
          const SectionLabel('全部号码遗漏', trailing: '上：号码 · 下：遗漏期数'),
          const SizedBox(height: 8),
          _GapGrid(items: items, secondary: secondary),
        ],
      ),
    );
  }
}

class _GapGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool secondary;

  const _GapGrid({required this.items, required this.secondary});

  @override
  Widget build(BuildContext context) {
    final maxGap = items.isEmpty
        ? 1.0
        : (items.first['current_gap'] as num).toDouble().clamp(1.0, 999.0);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final n in items)
          Tooltip(
            message: '号码 ${n['number']} · 当前遗漏 ${n['current_gap']} 期\n平均 ${n['avg_gap']} 期 · 历史最大 ${n['max_gap']} 期',
            child: Container(
              width: 44,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (secondary ? AppColors.blue : AppColors.accent).withValues(
                  alpha: 0.04 +
                      0.28 *
                          ((n['current_gap'] as num).toDouble() / maxGap).clamp(0.0, 1.0),
                ),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${n['number']}',
                    style: const TextStyle(fontSize: 9, color: AppColors.faint),
                  ),
                  Text(
                    '${n['current_gap']}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Combinations
// ---------------------------------------------------------------------------

class CombinationsTab extends StatefulWidget {
  final Api api;
  final GameInfo game;

  const CombinationsTab({super.key, required this.api, required this.game});

  @override
  State<CombinationsTab> createState() => _CombinationsTabState();
}

class _CombinationsTabState extends State<CombinationsTab> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.combinations(widget.game.id);
      if (!mounted) return;
      setState(() {
        _data = data;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 820;
        final pad = narrow ? 12.0 : 26.0;
        if (_loading) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: const Panel(child: LoadingBox(label: '计算组合结构…')),
          );
        }
        if (_error != null) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: Panel(child: ErrorBox(message: _error!, onRetry: _load)),
          );
        }
        final d = _data!;
        final sum = d['sum'] as Map<String, dynamic>;
        final stats = [
          _kv('观测均值', '${sum['mean']}', AppColors.accent),
          _kv('理论均值', '${sum['expected_mean']}', AppColors.muted),
          _kv('观测标准差', '${sum['sd']}', AppColors.accent),
          _kv('理论标准差', '${sum['expected_sd']}', AppColors.muted),
          _kv('χ² / df', '${sum['chi_square']} / ${sum['df']}', AppColors.blue),
          _kv('p 值', fmtP((sum['p_value'] as num).toDouble()), AppColors.green),
        ];
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 6, pad, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Panel(
                title: '和值分布',
                subtitle: '观测频数与精确组合分布对比 · 共 ${d['total_draws']} 期',
                trailing: VerdictChip(_verdict((sum['p_value'] as num).toDouble())),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        if (c.maxWidth < 520) {
                          final w = (c.maxWidth - 20) / 3;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 12,
                            children: [
                              for (final s in stats)
                                SizedBox(width: w, child: s),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            for (final s in stats) Expanded(child: s),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 220,
                      child: _SumChart(
                        bins: (sum['bins'] as List).cast<Map<String, dynamic>>(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        _LegendDot(color: AppColors.accent, label: '实际'),
                        SizedBox(width: 16),
                        _LegendDot(color: AppColors.blue, label: '理论期望'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (narrow) ...[
                _comparePanel('奇偶结构', d['odd_even']),
                const SizedBox(height: 16),
                _comparePanel('大小结构', d['big_small']),
                const SizedBox(height: 16),
                _comparePanel('连号组数', d['consecutive']),
                const SizedBox(height: 16),
                _comparePanel('跨度分布', d['span']),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _comparePanel('奇偶结构', d['odd_even'])),
                    const SizedBox(width: 18),
                    Expanded(child: _comparePanel('大小结构', d['big_small'])),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _comparePanel('连号组数', d['consecutive'])),
                    const SizedBox(width: 18),
                    Expanded(child: _comparePanel('跨度分布', d['span'])),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              _comparePanel('AC 值（号码离散度）', d['ac']),
              const SizedBox(height: 18),
              const _NoteCard(
                icon: Icons.grid_view_outlined,
                text: '和值、奇偶、大小、跨度、AC 值都是组合的“形状”。它们的历史分布与精确组合数高度吻合，'
                    '说明开奖并没有偏好某种形状；按“均衡形态”选号只会让号码看起来正常，不会提高中奖率。',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.faint)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _comparePanel(String title, dynamic raw) {
    if (raw == null) return const SizedBox();
    final block = raw as Map<String, dynamic>;
    final bins = (block['bins'] as List).cast<Map<String, dynamic>>();
    final maxV = bins.fold<double>(
      1,
      (m, b) {
        final o = (b['observed'] as num).toDouble();
        final e = (b['expected'] as num).toDouble();
        return [m, o, e].reduce((a, b) => a > b ? a : b);
      },
    );
    return Panel(
      title: title,
      trailing: VerdictChip(_verdict((block['p_value'] as num).toDouble())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final b in bins)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      b['label'] as String? ?? '',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _barRow((b['observed'] as num).toDouble(), maxV, AppColors.accent),
                        const SizedBox(height: 3),
                        _barRow((b['expected'] as num).toDouble(), maxV, AppColors.blue),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${b['observed']}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.text),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${b['expected']}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 10, color: AppColors.faint),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'χ²=${block['chi_square']} · df=${block['df']} · p=${fmtP((block['p_value'] as num).toDouble())}',
            style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
          ),
        ],
      ),
    );
  }

  Widget _barRow(double value, double max, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: (value / max).clamp(0.0, 1.0),
        minHeight: 5,
        backgroundColor: AppColors.surfaceHi,
        color: color,
      ),
    );
  }
}

class _SumChart extends StatelessWidget {
  final List<Map<String, dynamic>> bins;

  const _SumChart({required this.bins});

  @override
  Widget build(BuildContext context) {
    final maxY = bins.fold<double>(1, (m, b) {
      final o = (b['observed'] as num).toDouble();
      final e = (b['expected'] as num).toDouble();
      return [m, o, e].reduce((a, b) => a > b ? a : b);
    });
    return BarChart(
      BarChartData(
        maxY: maxY * 1.15,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: AppColors.border.withValues(alpha: 0.6),
            strokeWidth: 0.6,
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceHi,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final b = bins[group.x];
              final label = rodIndex == 0 ? '实际' : '期望';
              return BarTooltipItem(
                '${b['label']}\n$label ${rod.toY.toStringAsFixed(0)}',
                const TextStyle(color: AppColors.text, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: const TextStyle(fontSize: 9.5, color: AppColors.faint),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= bins.length) return const SizedBox();
                if (i % 2 != 0) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${bins[i]['label']}'.split('-').first,
                    style: const TextStyle(fontSize: 9, color: AppColors.faint),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < bins.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 3,
              barRods: [
                BarChartRodData(
                  toY: (bins[i]['observed'] as num).toDouble(),
                  color: AppColors.accent,
                  width: 7,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
                BarChartRodData(
                  toY: (bins[i]['expected'] as num).toDouble(),
                  color: AppColors.blue.withValues(alpha: 0.7),
                  width: 7,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Randomness
// ---------------------------------------------------------------------------

class RandomnessTab extends StatefulWidget {
  final Api api;
  final GameInfo game;

  const RandomnessTab({super.key, required this.api, required this.game});

  @override
  State<RandomnessTab> createState() => _RandomnessTabState();
}

class _RandomnessTabState extends State<RandomnessTab> {
  int _window = 500;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.randomness(
        widget.game.id,
        window: _window,
        simulations: 200,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 820;
        final pad = narrow ? 12.0 : 26.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 6, pad, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (narrow) ...[
                const Text('分析窗口', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 8),
                ChoicePills<int>(
                  values: const [300, 500, 1000, 0],
                  selected: _window,
                  label: (v) => v == 0 ? '全部历史' : '最近 $v 期',
                  onChanged: (v) {
                    setState(() => _window = v);
                    _load();
                  },
                ),
              ] else
                Row(
                  children: [
                    const Text('分析窗口', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    const SizedBox(width: 12),
                    ChoicePills<int>(
                      values: const [300, 500, 1000, 0],
                      selected: _window,
                      label: (v) => v == 0 ? '全部历史' : '最近 $v 期',
                      onChanged: (v) {
                        setState(() => _window = v);
                        _load();
                      },
                    ),
                    const Spacer(),
                    const Tag('蒙特卡洛 200 次校准', color: AppColors.blue),
                  ],
                ),
              const SizedBox(height: 16),
              if (_loading)
                const Panel(child: LoadingBox(label: '运行 9 项统计检验与蒙特卡洛模拟…'))
              else if (_error != null)
                Panel(child: ErrorBox(message: _error!, onRetry: _load))
              else ...[
                _summaryPanel(),
                const SizedBox(height: 18),
                _testsPanel(),
                const SizedBox(height: 18),
                _notePanel(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _summaryPanel() {
    final d = _data!;
    final tests = (d['tests'] as List).cast<Map<String, dynamic>>();
    final pValues = tests
        .where((t) => t['p_value'] != null)
        .map((t) => (t['p_value'] as num).toDouble())
        .toList();
    final significant = (d['significant_count'] as num).toInt();
    final overallVerdict = d['overall_verdict'] as String? ?? 'pass';
    final pass = overallVerdict == 'pass';
    final color = pass ? AppColors.green : AppColors.accent;
    return Panel(
      title: '总体结论',
      subtitle: '${d['total_draws']} 期 · ${d['test_count']} 项检验 · 期望假阳性 ${d['expected_false_positives']} 项',
      trailing: VerdictChip(overallVerdict),
      tint: color.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d['conclusion'] as String? ?? '',
            style: const TextStyle(fontSize: 13, height: 1.7),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _summaryStat('显著项', '$significant', color),
              _summaryStat(
                '整体 p 值',
                fmtP((d['overall_p'] as num?)?.toDouble()),
                color,
              ),
              _summaryStat(
                '最小 p 值',
                pValues.isEmpty
                    ? '—'
                    : fmtP(pValues.reduce((a, b) => a < b ? a : b)),
                AppColors.purple,
              ),
              _summaryStat(
                '窗口',
                _window == 0 ? '全部' : '$_window 期',
                AppColors.muted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.faint)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _testsPanel() {
    final tests = (_data!['tests'] as List).cast<Map<String, dynamic>>();
    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      title: '检验明细',
      subtitle: 'p 值越小越可疑；p<0.05 记为“关注”，p<0.01 记为“异常”',
      child: Column(
        children: [
          if (MediaQuery.sizeOf(context).width >= 700) ...[
            const _TestHeader(),
            const Divider(height: 1, color: AppColors.border),
          ],
          for (final t in tests)
            _TestRow(
              test: t,
              narrow: MediaQuery.sizeOf(context).width < 700,
            ),
        ],
      ),
    );
  }

  Widget _notePanel() {
    return _NoteCard(
      icon: Icons.science_outlined,
      text: '${_data!['note'] ?? ''}\n\n'
          '关于多重比较：同时做 9 项检验时，即使数据完全随机，出现 1 项 p<0.05 的概率也约为 37%。'
          '因此单个“显著”结果不能当作规律，需要看效应量、样本外复现和多重比较校正。',
    );
  }
}

class _TestHeader extends StatelessWidget {
  const _TestHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 10.5, color: AppColors.faint, letterSpacing: 0.3);
    return const SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(width: 150, child: Text('检验项目', style: style)),
          Expanded(child: Text('方法', style: style)),
          SizedBox(width: 74, child: Text('统计量', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 86, child: Text('p 值', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 66, child: Text('判定', style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _TestRow extends StatelessWidget {
  final Map<String, dynamic> test;
  final bool narrow;

  const _TestRow({required this.test, this.narrow = false});

  @override
  Widget build(BuildContext context) {
    final p = (test['p_value'] as num?)?.toDouble();
    final color = p == null
        ? AppColors.blue
        : p < 0.01
            ? AppColors.red
            : p < 0.05
                ? AppColors.accent
                : AppColors.green;
    final name = test['name'] as String? ?? '';
    final method = test['method'] as String? ?? '';
    final detail = test['detail'] as String?;
    final verdict = test['verdict'] as String? ?? 'info';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    VerdictChip(verdict, compact: true),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  method,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '统计量 ${test['statistic']}',
                      style: const TextStyle(fontSize: 11, color: AppColors.text),
                    ),
                    const Spacer(),
                    Text(
                      p == null ? 'p —' : 'p ${fmtP(p)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                if (detail != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.faint, height: 1.5),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        method,
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                    SizedBox(
                      width: 74,
                      child: Text(
                        '${test['statistic']}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.text,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 86,
                      child: Text(
                        p == null ? '—' : fmtP(p),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 66,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: VerdictChip(verdict, compact: true),
                      ),
                    ),
                  ],
                ),
                if (detail != null) ...[
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.only(right: 80),
                    child: Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.faint,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

class _NoteCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NoteCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.blue),
          const SizedBox(width: 12),
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
}

String _verdict(double p) {
  if (p < 0.01) return 'fail';
  if (p < 0.05) return 'warn';
  return 'pass';
}
