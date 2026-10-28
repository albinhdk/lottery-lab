import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'pages/analysis_page.dart';
import 'pages/backtest_page.dart';
import 'pages/history_page.dart';
import 'pages/overview_page.dart';
import 'pages/tickets_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/lazy_indexed_stack.dart';
import 'widgets/server_settings.dart';

void main() {
  runApp(const LotteryLabApp());
}

class LotteryLabApp extends StatefulWidget {
  const LotteryLabApp({super.key});

  @override
  State<LotteryLabApp> createState() => _LotteryLabAppState();
}

class _LotteryLabAppState extends State<LotteryLabApp> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState();
    _state.init();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '彩票实验室 · Lottery Lab',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AnimatedBuilder(
        animation: _state,
        builder: (context, _) => _Shell(state: _state),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  final AppState state;

  const _Shell({required this.state});

  static const _titles = [
    ('数据概览', '历史覆盖、最新开奖与随机性体检'),
    ('历史开奖', '完整开奖记录，按期号检索与分页浏览'),
    ('统计分析', '频率、遗漏、组合结构与严格的随机性检验'),
    ('策略回测', '严格走查：每一期只用此前数据，与随机基线对比'),
    ('智能选号', '按策略生成号码；它不会提高中奖概率'),
  ];

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.games.isEmpty) {
      return const Scaffold(body: _Splash());
    }
    if (state.games.isEmpty) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ErrorBox(
                    message: state.error ?? '无法连接后端服务。\n请确认电脑上的后端已启动，并填写正确的服务器地址。',
                    onRetry: state.refreshGames,
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => showServerSettings(context, state),
                    icon: const Icon(Icons.settings_ethernet, size: 17),
                    label: Text('设置服务器地址（当前：${state.apiBase}）'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final game = state.game;
    final page = state.pageIndex;
    final revision = state.dataRevision;
    final pageWidgets = <Widget>[
      OverviewPage(key: ValueKey('overview-${game?.id}-$revision'), state: state),
      HistoryPage(key: ValueKey('history-${game?.id}-$revision'), state: state),
      AnalysisPage(key: ValueKey('analysis-${game?.id}-$revision'), state: state),
      BacktestPage(key: ValueKey('backtest-${game?.id}-$revision'), state: state),
      TicketsPage(key: ValueKey('tickets-${game?.id}-$revision'), state: state),
    ];
    final stack = LazyIndexedStack(
      key: ValueKey('stack-${game?.id}-$revision'),
      index: page,
      children: pageWidgets,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                _Sidebar(state: state),
                Container(width: 1, color: AppColors.border),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(
                        state: state,
                        title: _titles[page].$1,
                        subtitle: _titles[page].$2,
                      ),
                      Expanded(child: stack),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: _MobileAppBar(state: state),
          body: stack,
          bottomNavigationBar: _MobileNav(state: state),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.accentDeep],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.insights_rounded, color: Color(0xFF2B1B00), size: 32),
          ),
          const SizedBox(height: 22),
          const Text(
            '彩票实验室',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          const Text(
            '正在连接后端服务…',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          const SizedBox(height: 22),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class _MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  final AppState state;

  const _MobileAppBar({required this.state});

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF0C111A),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 14,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.accentDeep],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.insights_rounded, color: Color(0xFF2B1B00), size: 18),
          ),
          const SizedBox(width: 9),
          const Text(
            '彩票实验室',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      actions: [
        _GameMenu(state: state),
        _SyncButton(state: state, compact: true),
        IconButton(
          onPressed: () => showServerSettings(context, state),
          icon: const Icon(Icons.settings_outlined, size: 20),
          color: AppColors.muted,
          tooltip: '服务器设置',
        ),
        const SizedBox(width: 2),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }
}

class _MobileNav extends StatelessWidget {
  final AppState state;

  const _MobileNav({required this.state});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      height: 64,
      backgroundColor: const Color(0xFF0C111A),
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accent.withValues(alpha: 0.14),
      selectedIndex: state.pageIndex,
      onDestinationSelected: state.selectPage,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined, color: AppColors.faint),
          selectedIcon: Icon(Icons.dashboard, color: AppColors.accent),
          label: '概览',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_rounded, color: AppColors.faint),
          selectedIcon: Icon(Icons.history_rounded, color: AppColors.accent),
          label: '历史',
        ),
        NavigationDestination(
          icon: Icon(Icons.analytics_outlined, color: AppColors.faint),
          selectedIcon: Icon(Icons.analytics, color: AppColors.accent),
          label: '分析',
        ),
        NavigationDestination(
          icon: Icon(Icons.science_outlined, color: AppColors.faint),
          selectedIcon: Icon(Icons.science, color: AppColors.accent),
          label: '回测',
        ),
        NavigationDestination(
          icon: Icon(Icons.confirmation_number_outlined, color: AppColors.faint),
          selectedIcon: Icon(Icons.confirmation_number, color: AppColors.accent),
          label: '选号',
        ),
      ],
    );
  }
}

class _GameMenu extends StatelessWidget {
  final AppState state;

  const _GameMenu({required this.state});

  @override
  Widget build(BuildContext context) {
    final game = state.game;
    return PopupMenuButton<String>(
      onSelected: state.selectGame,
      color: AppColors.surfaceHi,
      tooltip: '切换彩种',
      itemBuilder: (context) => [
        for (final g in state.games)
          PopupMenuItem(
            value: g.id,
            child: Row(
              children: [
                Icon(
                  g.id == state.gameId ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 16,
                  color: g.id == state.gameId ? AppColors.accent : AppColors.faint,
                ),
                const SizedBox(width: 9),
                Text(g.name, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Text('${g.count} 期', style: const TextStyle(fontSize: 10.5, color: AppColors.faint)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              game?.name ?? '彩种',
              style: const TextStyle(fontSize: 11.5, color: AppColors.text),
            ),
            const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  final AppState state;
  final bool compact;

  const _SyncButton({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        onPressed: state.syncing ? null : () => _sync(context),
        icon: state.syncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
              )
            : const Icon(Icons.cloud_sync_outlined, size: 20),
        color: AppColors.muted,
        tooltip: '同步数据',
      );
    }
    return Tooltip(
      message: '从官方数据源重新同步历史开奖',
      child: PrimaryButton(
        label: state.syncing ? '同步中…' : '同步数据',
        icon: Icons.cloud_sync_outlined,
        loading: state.syncing,
        outlined: true,
        onPressed: state.syncing ? null : () => _sync(context),
      ),
    );
  }

  Future<void> _sync(BuildContext context) async {
    await state.syncCurrent();
    if (!context.mounted) return;
    final message = state.toast;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 12)),
          behavior: SnackBarBehavior.floating,
          width: 300,
          backgroundColor: AppColors.surfaceHi,
        ),
      );
    }
  }
}

class _Sidebar extends StatelessWidget {
  final AppState state;

  const _Sidebar({required this.state});

  @override
  Widget build(BuildContext context) {
    const navItems = [
      (Icons.dashboard_outlined, '数据概览'),
      (Icons.history_rounded, '历史开奖'),
      (Icons.analytics_outlined, '统计分析'),
      (Icons.science_outlined, '策略回测'),
      (Icons.confirmation_number_outlined, '智能选号'),
    ];

    return Container(
      width: 238,
      color: const Color(0xFF0C111A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.accent, AppColors.accentDeep],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    color: Color(0xFF2B1B00),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '彩票实验室',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'LOTTERY LAB',
                      style: TextStyle(fontSize: 9.5, color: AppColors.faint, letterSpacing: 1.8),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              '彩种',
              style: TextStyle(fontSize: 10.5, color: AppColors.faint, letterSpacing: 1.4),
            ),
          ),
          for (final g in state.games)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _GameTile(
                name: g.name,
                count: g.count,
                selected: g.id == state.gameId,
                onTap: () => state.selectGame(g.id),
              ),
            ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              '工作台',
              style: TextStyle(fontSize: 10.5, color: AppColors.faint, letterSpacing: 1.4),
            ),
          ),
          for (var i = 0; i < navItems.length; i++)
            _NavTile(
              icon: navItems[i].$1,
              label: navItems[i].$2,
              selected: state.pageIndex == i,
              onTap: () => state.selectPage(i),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 13, color: AppColors.accent),
                      SizedBox(width: 6),
                      Text(
                        '理性购彩',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    '开奖是独立随机事件。本工具只做统计分析与回测验证，不能预测号码，也不会提高中奖概率。',
                    style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final String name;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _GameTile({
    required this.name,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? AppColors.accent.withValues(alpha: 0.45) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.accent : AppColors.faint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.text : AppColors.muted,
                ),
              ),
            ),
            Text(
              '$count 期',
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? AppColors.accent : AppColors.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceHi : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? AppColors.border : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.accent : AppColors.faint,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.text : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final AppState state;
  final String title;
  final String subtitle;

  const _TopBar({
    required this.state,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final g = state.game;
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ],
          ),
          const Spacer(),
          if (g != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Text(
                    '最新 ${g.latest?.issue ?? '—'} · ${g.latest?.date ?? '—'}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            onPressed: () => showServerSettings(context, state),
            icon: const Icon(Icons.settings_outlined, size: 19),
            color: AppColors.muted,
            tooltip: '服务器设置（当前：${state.apiBase}）',
          ),
          const SizedBox(width: 4),
          _SyncButton(state: state),
        ],
      ),
    );
  }
}
