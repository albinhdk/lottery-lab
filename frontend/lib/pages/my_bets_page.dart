
import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../format.dart';
import '../models_bet.dart';
import '../theme.dart';
import '../widgets/bet_card.dart';
import '../widgets/bet_entry_form.dart';
import '../widgets/common.dart';

/// Personal bet ledger: record tickets, watch them settle automatically once
/// the issue is drawn, and see the running totals.
///
/// The page never suggests numbers or claims an edge: it only records what
/// the user bought and reports what the official draw gave back.
class MyBetsPage extends StatefulWidget {
  final AppState state;

  const MyBetsPage({super.key, required this.state});

  @override
  State<MyBetsPage> createState() => _MyBetsPageState();
}

class _MyBetsPageState extends State<MyBetsPage> {
  /// 0 = records, 1 = entry form, 2 = statistics.
  int _tab = 0;

  List<Bet> _bets = const [];
  BetSummary? _summary;
  bool _loading = true;
  bool _checking = false;
  String? _error;
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  String? _statusFilter;

  Api get api => widget.state.api;

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
      final results = await Future.wait([
        api.bets(page: _page, pageSize: 50, status: _statusFilter),
        api.betSummary(),
      ]);
      if (!mounted) return;
      final page = results[0] as Map<String, dynamic>;
      final summary = results[1] as BetSummary;
      setState(() {
        _bets = (page['items'] as List? ?? const [])
            .map((e) => Bet.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _page = (page['page'] as num?)?.toInt() ?? 1;
        _pages = (page['pages'] as num?)?.toInt() ?? 1;
        _total = (page['total'] as num?)?.toInt() ?? 0;
        _summary = summary;
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

  /// Runs the backend check, then reloads. Called on app start and whenever
  /// the page becomes visible, so a draw that landed while the app was closed
  /// is settled without the user pressing anything.
  Future<void> _checkAndReload({bool full = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    String? message;
    try {
      final result = await api.checkBets(full: full);
      // Report what actually happened: silently swallowing the result is
      // what made the button look broken.
      message = result.settled > 0
          ? '对奖完成：结算 ${result.settled} 注，中奖 ${result.won} 注'
          : '没有需要结算的注（待开奖 ${result.stillPending} 注）';
    } catch (e) {
      // A failed check must not block the ledger: the next sync retries.
      message = '对奖失败：$e';
    }
    await _load();
    if (!mounted) return;
    setState(() => _checking = false);
    _snack(message);
  }

  void _snack(String message) {
    // Guarded: the page can be hosted without a Scaffold ancestor, and a
    // failed toast must never break the re-check itself.
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 12)),
          behavior: SnackBarBehavior.floating,
          width: 300,
          backgroundColor: AppColors.surfaceHi,
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
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
                  values: const [0, 1, 2],
                  selected: _tab,
                  label: (v) => ['我的记录', '录入号码', '统计'][v],
                  onChanged: (v) async {
                    setState(() => _tab = v);
                    if (v == 0) await _load();
                  },
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                sizing: StackFit.expand,
                index: _tab,
                children: [
                  _recordsTab(),
                  BetEntryForm(
                    state: widget.state,
                    onSaved: () async {
                      setState(() => _tab = 0);
                      await _load();
                    },
                  ),
                  _statsTab(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Records
  // -------------------------------------------------------------------------

  Widget _recordsTab() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(26),
        child: LoadingBox(),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(26),
        child: ErrorBox(message: _error!, onRetry: _load),
      );
    }
    return RefreshIndicator(
      onRefresh: _checkAndReload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(26, 12, 26, 30),
        children: [
          _summaryBar(),
          const SizedBox(height: 18),
          _filterRow(),
          const SizedBox(height: 14),
          if (_bets.isEmpty)
            EmptyBox(
              icon: Icons.confirmation_number_outlined,
              title: _total == 0 ? '还没有购彩记录' : '没有符合条件的记录',
              subtitle: _total == 0
                  ? '切到「录入号码」，把买的彩票记下来。\n开奖后这里会自动显示中奖结果。'
                  : '换个筛选条件试试。',
            )
          else
            for (final bet in _bets) ...[
              BetCard(
                bet: bet,
                game: widget.state.games.firstWhere(
                  (g) => g.id == bet.game,
                  orElse: () => widget.state.games.first,
                ),
                onDelete: () => _delete(bet),
                onActualAmount: (amount) => _setActualAmount(bet, amount),
              ),
              const SizedBox(height: 12),
            ],
          if (_pages > 1) _pager(),
        ],
      ),
    );
  }

  Widget _summaryBar() {
    final s = _summary;
    if (s == null || s.total == 0) return const SizedBox.shrink();
    final net = s.net;
    return Panel(
      dense: true,
      title: '总账',
      subtitle: '共 ${s.total} 注 · 待开奖 ${s.pending} · 已结算 ${s.settled}',
      child: Row(
        children: [
          _MiniStat(label: '总投入', value: fmtMoney(s.cost), color: AppColors.text),
          _MiniStat(label: '总奖金', value: fmtMoney(s.payout), color: AppColors.accent),
          _MiniStat(
            label: '净收益',
            value: fmtSigned(net),
            color: net >= 0 ? AppColors.accent : AppColors.red,
          ),
        ],
      ),
    );
  }

  Widget _filterRow() {
    return Row(
      children: [
        ChoicePills<String?>(
          values: const [null, 'pending', 'won', 'lost'],
          selected: _statusFilter,
          label: (v) => switch (v) {
                'pending' => '待开奖',
                'won' => '已中奖',
                'lost' => '未中奖',
                _ => '全部',
              },
          onChanged: (v) async {
            setState(() {
              _statusFilter = v;
              _page = 1;
            });
            await _load();
          },
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _checking ? null : () => _checkAndReload(full: true),
          icon: _checking
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: AppColors.muted,
                  ),
                )
              : const Icon(Icons.refresh, size: 15),
          label: Text(
            _checking ? '对奖中…' : '重新对奖',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _pager() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: _page > 1
              ? () async {
                  setState(() => _page -= 1);
                  await _load();
                }
              : null,
          icon: const Icon(Icons.chevron_left, size: 20),
          color: AppColors.muted,
        ),
        Text(
          '第 $_page / $_pages 页',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        IconButton(
          onPressed: _page < _pages
              ? () async {
                  setState(() => _page += 1);
                  await _load();
                }
              : null,
          icon: const Icon(Icons.chevron_right, size: 20),
          color: AppColors.muted,
        ),
      ],
    );
  }

  Future<void> _delete(Bet bet) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceHi,
        title: const Text('删除这条记录？', style: TextStyle(fontSize: 15)),
        content: Text(
          '${bet.gameName} 第 ${bet.issue} 期，${bet.multiple} 倍。\n删除后无法恢复。',
          style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(fontSize: 12, color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.deleteBet(bet.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e', style: const TextStyle(fontSize: 12))),
      );
    }
  }

  Future<void> _setActualAmount(Bet bet, double? amount) async {
    try {
      await api.setActualAmount(bet.id, amount);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e', style: TextStyle(fontSize: 12))),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Statistics
  // -------------------------------------------------------------------------

  Widget _statsTab() {
    final s = _summary;
    if (s == null || s.total == 0) {
      return const Padding(
        padding: EdgeInsets.all(26),
        child: EmptyBox(
          icon: Icons.bar_chart_rounded,
          title: '还没有可统计的记录',
          subtitle: '录入几注之后，这里会按奖级汇总。',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 30),
      children: [
        Panel(
          title: '奖级分布',
          subtitle: '已结算 ${s.settled} 注，其中中奖 ${s.won} 注',
          child: Column(
            children: [
              if (s.byTier.isEmpty)
                const Text(
                  '还没有中奖记录。',
                  style: TextStyle(fontSize: 12, color: AppColors.faint),
                )
              else
                for (final t in s.byTier)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 150,
                          child: Text(
                            '${t.gameName} ${t.tierName}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        Text(
                          '${t.count} 注',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                        const Spacer(),
                        Text(
                          fmtMoney(t.payout),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          title: '说明',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NoteLine(
                text: '一、二等奖为浮动奖金。开奖后官方公布具体金额，'
                    '可在记录里把估算值改成实际到账。',
              ),
              _NoteLine(
                text: '当前估算部分合计 ${fmtMoney(s.estimatedPayout)} 元，'
                    '属于按长期均值推算，不代表实际到手。',
              ),
              _NoteLine(
                text: '记录与统计只反映已发生的结果，不能用来预测下一期，'
                    '也不会提高中奖概率。',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoteLine extends StatelessWidget {
  final String text;

  const _NoteLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14, color: AppColors.faint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.faint)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
