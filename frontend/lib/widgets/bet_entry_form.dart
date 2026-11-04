
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/bet_entry.dart';
import '../widgets/common.dart';

/// Entry form for new bets. One draft per ticket, an issue picker that lists
/// recent draws plus the suggested next issue, and an optional "追号" that
/// expands one ticket into N consecutive issues.
class BetEntryForm extends StatefulWidget {
  final AppState state;
  final VoidCallback onSaved;

  const BetEntryForm({super.key, required this.state, required this.onSaved});

  @override
  State<BetEntryForm> createState() => _BetEntryFormState();
}

class _BetEntryFormState extends State<BetEntryForm> {
  final Random _random = Random();

  String? _gameId;
  String? _issue;
  List<String> _issues = const [];
  String? _nextIssue;
  bool _loadingIssues = true;
  String? _issueError;

  /// Number of consecutive issues to buy with the same numbers. 1 = single.
  int _chase = 1;

  final List<_Draft> _drafts = [];
  bool _saving = false;
  String? _error;

  GameInfo? get game {
    for (final g in widget.state.games) {
      if (g.id == _gameId) return g;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _gameId = widget.state.gameId ?? widget.state.games.first.id;
    _drafts.add(_Draft.empty());
    _loadIssues();
  }

  Future<void> _loadIssues() async {
    final g = game;
    if (g == null) return;
    setState(() {
      _loadingIssues = true;
      _issueError = null;
    });
    try {
      final page = await widget.state.api.draws(game: g.id, pageSize: 60);
      final items = (page['items'] as List? ?? const [])
          .map((e) => Draw.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (!mounted) return;
      setState(() {
        _issues = items.map((d) => d.issue).toList();
        // Default to the issue that has not been drawn yet.
        _nextIssue = widget.state.apiNextIssue(g.id);
        _issue = _nextIssue ??
            (_issues.isNotEmpty ? _issues.first : null);
        _loadingIssues = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _issueError = e.toString();
        _loadingIssues = false;
      });
    }
  }

  void _switchGame(String id) {
    if (id == _gameId) return;
    setState(() {
      _gameId = id;
      _issue = null;
      _issues = const [];
      for (final d in _drafts) {
        d.reset();
      }
    });
    _loadIssues();
  }

  void _addDraft() {
    setState(() => _drafts.add(_Draft.empty()));
  }

  void _removeDraft(int index) {
    if (_drafts.length <= 1) return;
    setState(() => _drafts.removeAt(index));
  }

  void _randomize(_Draft draft) {
    final g = game;
    if (g == null) return;
    setState(() {
      draft.primary = _pick(g.primaryMax, g.primaryCount);
      draft.secondary = _pick(g.secondaryMax, g.secondaryCount);
    });
  }

  List<int> _pick(int max, int count) {
    final pool = List<int>.generate(max, (i) => i + 1)..shuffle(_random);
    return pool.take(count).toList()..sort();
  }

  /// Expands the drafts into one bet per (draft, issue). With 追号 the same
  /// numbers are bought for [chase] consecutive issues starting at [_issue].
  List<Map<String, dynamic>> _buildPayload() {
    final targets = _targetIssues();
    final out = <Map<String, dynamic>>[];
    for (final draft in _drafts) {
      for (final issue in targets) {
        out.add({
          'issue': issue,
          'primary': draft.primary,
          'secondary': draft.secondary,
          'multiple': draft.multiple,
          'note': draft.note,
        });
      }
    }
    return out;
  }

  List<String> _targetIssues() {
    final start = _issue;
    if (start == null || start.isEmpty) return const [];
    if (_chase <= 1) return [start];
    final issues = <String>[];
    var current = start;
    for (var i = 0; i < _chase; i++) {
      issues.add(current);
      final next = _nextIssueAfter(current);
      if (next == null) break;
      current = next;
    }
    return issues;
  }

  /// Advances an issue string by one, using each game's numbering scheme.
  String? _nextIssueAfter(String issue) {
    final g = game;
    if (g == null) return null;
    final digits = issue.replaceAll(RegExp(r'[^0-9]'), '');
    final yearLen = g.id == 'ssq' ? 4 : 2;
    if (digits.length != yearLen + 3) return null;
    final year = int.tryParse(digits.substring(0, yearLen));
    final seq = int.tryParse(digits.substring(yearLen));
    if (year == null || seq == null) return null;
    if (seq >= 999) {
      final nextYear = (year + 1) % pow(10, yearLen).toInt();
      return '${nextYear.toString().padLeft(yearLen, '0')}001';
    }
    return '${year.toString().padLeft(yearLen, '0')}${(seq + 1).toString().padLeft(3, '0')}';
  }

  int get _totalBets => _drafts.length * _targetIssues().length;

  double get _totalCost {
    final g = game;
    if (g == null) return 0;
    var sum = 0.0;
    for (final draft in _drafts) {
      sum += g.price * draft.multiple * _targetIssues().length;
    }
    return sum;
  }

  Future<void> _save() async {
    final g = game;
    if (g == null || _saving) return;
    final issue = _issue;
    if (issue == null || issue.isEmpty) {
      setState(() => _error = '请先选择期号');
      return;
    }
    for (final draft in _drafts) {
      if (draft.primary.length != g.primaryCount ||
          draft.secondary.length != g.secondaryCount) {
        setState(() => _error = '还有号码没选满');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.state.api.createBets(
        game: g.id,
        bets: _buildPayload(),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      widget.onSaved();
      final parts = <String>[
        if (result.inserted > 0) '已保存 ${result.inserted} 注',
        if (result.duplicates > 0) '跳过重复 ${result.duplicates} 注',
        if (result.checked.won > 0) '其中中奖 ${result.checked.won} 注',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty ? '没有新增记录' : parts.join('，'),
            style: const TextStyle(fontSize: 12),
          ),
          behavior: SnackBarBehavior.floating,
          width: 300,
          backgroundColor: AppColors.surfaceHi,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    if (g == null) return const SizedBox.shrink();
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
                    SizedBox(width: 400, child: _configPanel(g)),
                    const SizedBox(width: 18),
                    Expanded(child: _draftsPanel(g)),
                  ],
                )
              : Column(
                  children: [
                    _configPanel(g),
                    const SizedBox(height: 18),
                    _draftsPanel(g),
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
          title: '彩种与期号',
          subtitle: '默认选下一期；补录往期就改这里',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('彩种'),
              const SizedBox(height: 8),
              ChoicePills<String>(
                values: [for (final item in widget.state.games) item.id],
                selected: g.id,
                label: (id) {
                  for (final item in widget.state.games) {
                    if (item.id == id) return item.name;
                  }
                  return id;
                },
                onChanged: _switchGame,
              ),
              const SizedBox(height: 18),
              if (_loadingIssues)
                const LoadingBox()
              else if (_issueError != null)
                ErrorBox(message: _issueError!, onRetry: _loadIssues)
              else if (_issues.isEmpty && _nextIssue == null)
                const EmptyBox(
                  icon: Icons.cloud_off_outlined,
                  title: '暂无开奖数据',
                  subtitle: '请先同步历史数据。',
                )
              else ...[
                const SectionLabel('开奖期次'),
                const SizedBox(height: 8),
                _issueDropdown(),
                const SizedBox(height: 18),
                const SectionLabel('追号', trailing: '同一注连买多期'),
                const SizedBox(height: 8),
                ChoicePills<int>(
                  values: const [1, 2, 3, 5, 10],
                  selected: _chase,
                  label: (v) => v == 1 ? '不追号' : '$v 期',
                  onChanged: (v) => setState(() => _chase = v),
                ),
                if (_chase > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    '将生成 ${_drafts.length} 注 × $_chase 期 = $_totalBets 条记录，'
                    '各自独立对奖。',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.muted,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          title: '合计',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${_drafts.length} 注 × ${_targetIssues().length} 期',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                  const Spacer(),
                  Text(
                    '${fmtMoney(_totalCost)} 元',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: _saving ? '保存中…' : '保存记录',
                  icon: Icons.bookmark_add_outlined,
                  loading: _saving,
                  onPressed: _save,
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
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.red,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '记录只用于你自己核对，不代表任何选号建议。',
                style: TextStyle(fontSize: 10.5, color: AppColors.faint, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _issueDropdown() {
    final items = <DropdownMenuItem<String>>[];
    if (_nextIssue != null) {
      items.add(DropdownMenuItem(
        value: _nextIssue,
        child: Text('第 $_nextIssue 期（下一期，未开奖）'),
      ));
    }
    for (final issue in _issues) {
      items.add(DropdownMenuItem(
        value: issue,
        child: Text('第 $issue 期（已开奖）'),
      ));
    }
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
          items: items,
          onChanged: (value) => setState(() => _issue = value),
        ),
      ),
    );
  }

  Widget _draftsPanel(GameInfo g) {
    return Column(
      children: [
        for (var i = 0; i < _drafts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: BetDraftCard(
              index: i + 1,
              primary: _drafts[i].primary,
              secondary: _drafts[i].secondary,
              primaryCount: g.primaryCount,
              secondaryCount: g.secondaryCount,
              primaryMax: g.primaryMax,
              secondaryMax: g.secondaryMax,
              primaryLabel: g.primaryLabel,
              secondaryLabel: g.secondaryLabel,
              multiple: _drafts[i].multiple,
              note: _drafts[i].note,
              canRemove: _drafts.length > 1,
              onPrimaryChanged: (v) => setState(() => _drafts[i].primary = v),
              onSecondaryChanged: (v) => setState(() => _drafts[i].secondary = v),
              onMultipleChanged: (v) => setState(() => _drafts[i].multiple = v),
              onNoteChanged: (v) => setState(() => _drafts[i].note = v),
              onRemove: () => _removeDraft(i),
              onRandom: () => _randomize(_drafts[i]),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _drafts.length >= 20 ? null : _addDraft,
          icon: const Icon(Icons.add, size: 16),
          label: Text('再加一注（${_drafts.length}/20）', style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _Draft {
  List<int> primary = [];
  List<int> secondary = [];
  int multiple = 1;
  String note = '';

  _Draft.empty();

  void reset() {
    primary = [];
    secondary = [];
    multiple = 1;
    note = '';
  }
}
