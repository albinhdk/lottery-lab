/// 开奖日程。
///
/// 双色球每周二、四、日 21:15 开奖，超级大乐透每周一、三、六 21:10 开奖，
/// 均为北京时间。节假日官方可能调整开奖安排，实际开奖日期以同步到的历史
/// 数据为准——这里的日程只用于展示"这一期什么时候开奖"，不参与任何统计
/// 计算，也不用于预测号码。
///
/// 所有 DateTime 都是"UTC 标记、字段即北京墙上时间"的表示：这样跨时区
/// 比较也正确，且不依赖设备时区数据库（Android 内置进程没有 Context，
/// Web 与桌面端时区也各不相同）。

library;

import 'package:flutter/material.dart';

import '../format.dart' show fmtIsoDate;
import '../theme.dart' show AppColors;

const String _weekdayChars = '一二三四五六日';

class DrawSchedule {
  /// 开奖日，取值 `DateTime.monday`..`DateTime.sunday`（1..7）。
  final Set<int> days;

  final int hour;
  final int minute;

  const DrawSchedule({
    required this.days,
    required this.hour,
    required this.minute,
  });

  /// 例如「每周二、四、日 21:15」。
  String get label =>
      '每周${[for (final d in days.toList()..sort()) _weekdayChars[d - 1]].join('、')} $timeLabel';

  /// 例如「21:15」。
  String get timeLabel => _hhmm(hour, minute);

  bool isDrawDay(DateTime day) => days.contains(day.weekday);

  /// [day] 所在日期的开奖时刻（UTC 标记的北京墙上时间）。
  DateTime momentOn(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day, hour, minute);

  /// [from] 之后第一个开奖时刻（严格晚于 [from]）。
  DateTime nextDrawAfter(DateTime from) {
    for (var i = 0; i < 8; i++) {
      final day = addDays(from, i);
      if (!isDrawDay(day)) continue;
      final moment = momentOn(day);
      if (moment.isAfter(from)) return moment;
    }
    // 每个彩种每周至少开奖三次，循环必然已经返回；这里只是满足返回值。
    return momentOn(addDays(from, 8));
  }

  /// 今天是否已过开奖时间（北京墙上时间）。
  bool drawnToday(DateTime now) =>
      isDrawDay(now) && !momentOn(now).isAfter(now);
}

const Map<String, DrawSchedule> _schedules = {
  'ssq': DrawSchedule(days: {2, 4, 7}, hour: 21, minute: 15),
  'dlt': DrawSchedule(days: {1, 3, 6}, hour: 21, minute: 10),
};

DrawSchedule? drawScheduleFor(String gameId) => _schedules[gameId];

/// 当前北京时间（UTC 标记，字段即北京墙上时间）。
DateTime nowBeijing() => DateTime.now().toUtc().add(const Duration(hours: 8));

/// 纯日期加减：不走 Duration，避免设备本地时区的夏令时把日期算偏。
DateTime addDays(DateTime day, int count) =>
    DateTime.utc(day.year, day.month, day.day + count);

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _hhmm(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// 「今天 21:15」/「明天 21:15」/「11月14日 21:15」。
String formatDrawMoment(DateTime moment, {required DateTime now}) {
  final time = _hhmm(moment.hour, moment.minute);
  if (isSameDate(moment, now)) return '今天 $time';
  if (isSameDate(moment, addDays(now, 1))) return '明天 $time';
  return '${moment.month}月${moment.day}日 $time';
}

/// 期号在预计什么时候开奖。
///
/// 期号只在该彩种已开奖之后才存在，[nextIssue] 就是即将开奖的那一期；
/// 之后的每一期依次顺延一个开奖日，追号记录因此能各自显示自己的开奖
/// 时间。期号早于最新已开奖期（补录的旧票）时无法定位，退回每周日程。
/// 没有已知日程的彩种返回 null。
///
/// [nextIssue] 那一期必须从**最新已开奖的那一期**（[lastDrawDate]）往后
/// 推一期，不能从 now 往后推：开奖时间刚过、官方数据还没同步进来的那几
/// 分钟里，now 已经越过今天的开奖时刻，从 now 推会把整条期号链错后一期
/// （11-15 该开的期号被显示成 11-17）。没有历史日期时才退回 now。
String? issueDrawLabel(
  String gameId,
  String issue, {
  String? nextIssue,
  String? lastDrawDate,
  DateTime? now,
}) {
  final schedule = _schedules[gameId];
  if (schedule == null) return null;
  final nowTime = now ?? nowBeijing();
  final seq = _issueSeq(issue);
  final nextSeq = nextIssue == null ? null : _issueSeq(nextIssue);
  // 定位不到具体时刻（没有 nextIssue、或补录的旧票早于最新一期）时退回
  // 每周日程，至少还告诉用户这个彩种每周哪几天开奖。
  if (seq == null || nextSeq == null || seq < nextSeq) return schedule.label;
  var moment = _anchorMoment(schedule, lastDrawDate, nowTime);
  for (var i = 0; i < seq - nextSeq && i < 30; i++) {
    moment = schedule.nextDrawAfter(moment);
  }
  return formatDrawMoment(moment, now: nowTime);
}

/// nextIssue 那一期的开奖时刻。
DateTime _anchorMoment(
  DrawSchedule schedule,
  String? lastDrawDate,
  DateTime now,
) {
  final last = lastDrawDate == null || lastDrawDate.isEmpty
      ? null
      : DateTime.tryParse(
          lastDrawDate.length >= 10 ? lastDrawDate.substring(0, 10) : lastDrawDate,
        );
  if (last == null) return schedule.nextDrawAfter(now);
  final moment = schedule.nextDrawAfter(schedule.momentOn(last));
  // 锚点算出来的时刻允许略微早于 now：开奖时刻刚过、官方数据还没同步的那
  // 几分钟里，它就是今天这一期，必须照实显示"今天"。但历史日期过旧（库里
  // 长期没同步）时它可能落后好几周，此时的日期已经没有意义，改按"下一期还
  // 没开"来显示。一个开奖周期间隔最多 3 天，用 3 天作为分界。
  if (!moment.isBefore(now.subtract(const Duration(days: 3)))) return moment;
  return schedule.nextDrawAfter(now);
}

/// 期号序号：双色球「2026126」与大乐透「26126」都按整数比较即可。
int? _issueSeq(String issue) {
  final digits = issue.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

/// 打开页面时是否该主动拉一次最新一页，让「今日开奖」立刻显示当天号码。
///
/// 只有今天已过开奖时间、而库里最新一期还不是今天时才需要；今天没到开奖
/// 时间或今天不开奖时拉了也没有新数据。
bool shouldFetchTodaysDraw(
  DrawSchedule schedule,
  String? latestDate,
  DateTime now,
) {
  if (latestDate == null || latestDate.isEmpty) return false;
  if (latestDate == fmtIsoDate(now)) return false;
  return schedule.drawnToday(now);
}

/// 开奖状态行：图标、颜色与文案。
class DrawStatus {
  final IconData icon;
  final Color color;
  final String text;

  const DrawStatus({required this.icon, required this.color, required this.text});
}

/// 顶部「今日开奖」卡片底部那行状态说明。
DrawStatus drawStatusFor({
  required DrawSchedule schedule,
  required bool todayDrawn,
  required DateTime now,
  String? nextIssue,
}) {
  if (todayDrawn) {
    return DrawStatus(
      icon: Icons.check_circle_outline,
      color: AppColors.green,
      text: '今日开奖号码已更新（${schedule.timeLabel} 开奖）',
    );
  }
  if (schedule.isDrawDay(now)) {
    if (!schedule.drawnToday(now)) {
      final issue =
          nextIssue == null || nextIssue.isEmpty ? '下一期' : '第 $nextIssue 期';
      return DrawStatus(
        icon: Icons.schedule_outlined,
        color: AppColors.accent,
        text: '$issue 今天 ${schedule.timeLabel} 开奖，开奖后自动更新',
      );
    }
    return const DrawStatus(
      icon: Icons.cloud_sync_outlined,
      color: AppColors.accent,
      text: '已过今日开奖时间，正在获取官方数据…',
    );
  }
  return DrawStatus(
    icon: Icons.event_outlined,
    color: AppColors.muted,
    text: '今天不开奖 · 下次开奖：'
        '${formatDrawMoment(schedule.nextDrawAfter(now), now: now)}',
  );
}
