import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HistoryPage extends StatefulWidget {
  final AppState state;

  const HistoryPage({super.key, required this.state});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  int _page = 1;
  static const int _pageSize = 30;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  DateTimeRange? _range;

  GameInfo? get game => widget.state.game;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    final g = game;
    if (g == null) return;
    if (page != null) _page = page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.state.api.draws(
        game: g.id,
        page: _page,
        pageSize: _pageSize,
        query: _search.text,
        from: _range == null ? null : fmtIsoDate(_range!.start),
        to: _range == null ? null : fmtIsoDate(_range!.end),
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

  void _onSearchChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 1;
      _load();
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2003, 1, 1),
      lastDate: now,
      initialDateRange: _range,
      helpText: '选择开奖日期范围',
      saveText: '确定',
      cancelText: '取消',
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _page = 1;
    _load();
  }

  void _clearRange() {
    setState(() => _range = null);
    _page = 1;
    _load();
  }

  Future<void> _export(GameInfo g) async {
    final ok = await launchUrl(
      Uri.parse(widget.state.api.exportUrl(g.id)),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法打开导出链接', style: TextStyle(fontSize: 12)),
          behavior: SnackBarBehavior.floating,
          width: 240,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    if (g == null) return const SizedBox();
    final items = (_data?['items'] as List? ?? const [])
        .map((e) => Draw.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (_data?['total'] as num?)?.toInt() ?? 0;
    final pages = (_data?['pages'] as num?)?.toInt() ?? 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final pad = narrow ? 12.0 : 26.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, narrow ? 12 : 22, pad, narrow ? 12 : 24),
          child: Column(
            children: [
              if (narrow) ...[
                _searchField(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _dateButton(),
                    if (_range != null)
                      IconButton(
                        onPressed: _clearRange,
                        icon: const Icon(Icons.close, size: 15),
                        tooltip: '清除日期范围',
                        color: AppColors.faint,
                      ),
                    const Spacer(),
                    _countText(total),
                    IconButton(
                      onPressed: () => _export(g),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      color: AppColors.muted,
                      tooltip: '导出 CSV',
                    ),
                    IconButton(
                      onPressed: _loading ? null : () => _load(),
                      icon: const Icon(Icons.refresh, size: 18),
                      color: AppColors.muted,
                      tooltip: '刷新',
                    ),
                  ],
                ),
              ] else
                Row(
                  children: [
                    SizedBox(width: 280, child: _searchField()),
                    const SizedBox(width: 10),
                    _dateButton(),
                    if (_range != null)
                      IconButton(
                        onPressed: _clearRange,
                        icon: const Icon(Icons.close, size: 15),
                        tooltip: '清除日期范围',
                        color: AppColors.faint,
                      ),
                    const Spacer(),
                    _countText(total),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => _export(g),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      color: AppColors.muted,
                      tooltip: '导出 CSV（在浏览器中下载）',
                    ),
                    IconButton(
                      onPressed: _loading ? null : () => _load(),
                      icon: const Icon(Icons.refresh, size: 18),
                      color: AppColors.muted,
                      tooltip: '刷新',
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  padding: EdgeInsets.fromLTRB(narrow ? 12 : 18, 8, narrow ? 12 : 18, 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF141B28), Color(0xFF10151F)],
                    ),
                  ),
                  child: Column(
                    children: [
                      _header(showMoney: !narrow),
                      const Divider(height: 1, color: AppColors.border),
                      Expanded(
                        child: _loading
                            ? const LoadingBox(label: '加载开奖记录…')
                            : _error != null
                                ? Center(
                                    child: ErrorBox(message: _error!, onRetry: _load),
                                  )
                                : items.isEmpty
                                    ? const EmptyBox(
                                        icon: Icons.search_off,
                                        title: '没有匹配的记录',
                                        subtitle: '换一个期号关键词或日期范围试试。',
                                      )
                                    : ListView.separated(
                                        itemCount: items.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1, color: AppColors.border),
                                        itemBuilder: (context, i) => _row(
                                          context,
                                          items[i],
                                          g,
                                          showMoney: !narrow,
                                        ),
                                      ),
                      ),
                      _footer(total, pages),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: _onSearchChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: '按期号搜索，如 2026',
        prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.faint),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _search.clear();
                  _page = 1;
                  _load();
                },
                icon: const Icon(Icons.close, size: 16),
                tooltip: '清除搜索',
              ),
        isDense: true,
      ),
    );
  }

  Widget _dateButton() {
    return OutlinedButton.icon(
      onPressed: _pickRange,
      icon: const Icon(Icons.date_range_outlined, size: 15),
      label: Text(
        _range == null
            ? '日期范围'
            : '${fmtIsoDate(_range!.start)} ~ ${fmtIsoDate(_range!.end)}',
        style: const TextStyle(fontSize: 11.5),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _range == null ? AppColors.muted : AppColors.accent,
        side: BorderSide(
          color: _range == null
              ? AppColors.border
              : AppColors.accent.withValues(alpha: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _countText(int total) {
    return Text(
      '共 ${fmtInt(total)} 期',
      style: const TextStyle(fontSize: 12, color: AppColors.muted),
    );
  }

  Widget _header({required bool showMoney}) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          if (showMoney) ...[
            _cell('期号', width: 92),
            _cell('开奖日期', width: 108),
            _cell('开奖号码', flex: 1),
            _cell('销售额', width: 110, align: TextAlign.right),
            _cell('奖池', width: 110, align: TextAlign.right),
          ] else ...[
            _cell('期号 / 日期', width: 86),
            _cell('开奖号码', flex: 1),
          ],
        ],
      ),
    );
  }

  Widget _cell(String text,
      {double? width, int? flex, TextAlign align = TextAlign.left}) {
    final child = Text(
      text,
      textAlign: align,
      style: const TextStyle(fontSize: 11, color: AppColors.faint, letterSpacing: 0.3),
    );
    if (flex != null) return Expanded(flex: flex, child: child);
    return SizedBox(width: width, child: child);
  }

  Widget _row(BuildContext context, Draw d, GameInfo g, {required bool showMoney}) {
    return InkWell(
      onTap: () => _showDetail(context, d, g),
      child: SizedBox(
        height: showMoney ? 64 : 58,
        child: Row(
          children: [
            if (showMoney) ...[
              SizedBox(
                width: 92,
                child: Text(
                  d.issue,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 108,
                child: Text(
                  d.date,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ),
              Expanded(
                child: BallRow(primary: d.primary, secondary: d.secondary, size: 27),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  fmtMoney(d.sales),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  fmtMoney(d.pool),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ),
            ] else ...[
              SizedBox(
                width: 86,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.issue,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.date,
                      style: const TextStyle(fontSize: 10, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: BallRow(primary: d.primary, secondary: d.secondary, size: 25),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _footer(int total, int pages) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Text(
            '第 $_page / ${pages < 1 ? 1 : pages} 页',
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(width: 12),
          const Text(
            '每页 30 期',
            style: TextStyle(fontSize: 11, color: AppColors.faint),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loading || _page <= 1 ? null : () => _load(page: _page - 1),
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一页',
          ),
          IconButton(
            onPressed: _loading || _page >= pages ? null : () => _load(page: _page + 1),
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一页',
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, Draw d, GameInfo g) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '第 ${d.issue} 期',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    d.date,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              BallRow(primary: d.primary, secondary: d.secondary, size: 38),
              const SizedBox(height: 22),
              _detailRow(g.primaryLabel, d.primary.map((e) => e.toString().padLeft(2, '0')).join('  ')),
              _detailRow(g.secondaryLabel, d.secondary.map((e) => e.toString().padLeft(2, '0')).join('  ')),
              const Divider(height: 28, color: AppColors.border),
              _detailRow('销售额', fmtMoney(d.sales)),
              _detailRow('奖池', fmtMoney(d.pool)),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
