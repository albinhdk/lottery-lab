import 'package:flutter_test/flutter_test.dart';
import 'package:lottery_lab_app/draw_schedule.dart';

void main() {
  // 2026-11-12 是周四。
  final thursdayMorning = DateTime.utc(2026, 11, 12, 10, 0);
  final thursdayNight = DateTime.utc(2026, 11, 12, 22, 0);

  group('DrawSchedule', () {
    test('labels match the official draw days and times', () {
      expect(drawScheduleFor('ssq')!.label, '每周二、四、日 21:15');
      expect(drawScheduleFor('dlt')!.label, '每周一、三、六 21:10');
      expect(drawScheduleFor('unknown'), isNull);
    });

    test('next draw is today when the draw time has not passed', () {
      expect(
        drawScheduleFor('ssq')!.nextDrawAfter(thursdayMorning),
        DateTime.utc(2026, 11, 12, 21, 15),
      );
    });

    test('next draw skips to the next draw day afterwards', () {
      expect(
        drawScheduleFor('ssq')!.nextDrawAfter(thursdayNight),
        DateTime.utc(2026, 11, 15, 21, 15),
      );
      // 大乐透周四不开奖，下一期是周六。
      expect(
        drawScheduleFor('dlt')!.nextDrawAfter(thursdayMorning),
        DateTime.utc(2026, 11, 14, 21, 10),
      );
    });

    test('drawnToday only turns true once the draw time passed', () {
      final ssq = drawScheduleFor('ssq')!;
      expect(ssq.drawnToday(DateTime.utc(2026, 11, 12, 20, 0)), isFalse);
      expect(ssq.drawnToday(DateTime.utc(2026, 11, 12, 21, 15)), isTrue);
      expect(ssq.drawnToday(thursdayNight), isTrue);
      // 周三对双色球不是开奖日。
      expect(ssq.drawnToday(DateTime.utc(2026, 11, 11, 22, 0)), isFalse);
    });

    test('formatDrawMoment uses today/tomorrow for the near dates', () {
      final schedule = drawScheduleFor('ssq')!;
      expect(
        formatDrawMoment(schedule.nextDrawAfter(thursdayMorning), now: thursdayMorning),
        '今天 21:15',
      );
      expect(
        formatDrawMoment(schedule.nextDrawAfter(thursdayNight), now: thursdayNight),
        '11月15日 21:15',
      );
      // 周六早上看，下一期是"明天"（周日）。
      final saturdayMorning = DateTime.utc(2026, 11, 14, 9, 0);
      expect(
        formatDrawMoment(schedule.nextDrawAfter(saturdayMorning), now: saturdayMorning),
        '明天 21:15',
      );
    });
  });

  group('issueDrawLabel', () {
    test('places the upcoming issue on its draw moment', () {
      expect(
        issueDrawLabel('ssq', '2026126', nextIssue: '2026126', now: thursdayMorning),
        '今天 21:15',
      );
      expect(
        issueDrawLabel('dlt', '26125', nextIssue: '26125', now: thursdayMorning),
        '11月14日 21:10',
      );
    });

    test('chased issues each land on their own draw day', () {
      // 追号第二期：周日 21:15。
      expect(
        issueDrawLabel('ssq', '2026127', nextIssue: '2026126', now: thursdayMorning),
        '11月15日 21:15',
      );
      // 追号第三期：下周二 21:15。
      expect(
        issueDrawLabel('ssq', '2026128', nextIssue: '2026126', now: thursdayMorning),
        '11月17日 21:15',
      );
    });

    test('the next issue counts from the last drawn date, not from now', () {
      // Regression: 2026-11-15（周日）21:15 开奖，但官方数据晚到几分钟。这段
      // 时间里 now 已经越过今天的开奖时刻，若从 now 往后推，2026126 就会被
      // 显示成 11月17日（下周二）——用户看到的正是这个错。
      final justAfterDraw = DateTime.utc(2026, 11, 15, 21, 16);
      expect(
        issueDrawLabel(
          'ssq',
          '2026126',
          nextIssue: '2026126',
          lastDrawDate: '2026-11-12',
          now: justAfterDraw,
        ),
        '今天 21:15',
      );
      // 追号的下一期顺延到周二。
      expect(
        issueDrawLabel(
          'ssq',
          '2026127',
          nextIssue: '2026126',
          lastDrawDate: '2026-11-12',
          now: justAfterDraw,
        ),
        '11月17日 21:15',
      );
    });

    test('a stale history date falls back to the next draw after now', () {
      // 库里长期没同步时，从旧日期推出来的时刻已经过去，按"下一期还没开"显示。
      expect(
        issueDrawLabel(
          'ssq',
          '2026126',
          nextIssue: '2026126',
          lastDrawDate: '2026-10-01',
          now: thursdayMorning,
        ),
        '今天 21:15',
      );
    });

    test('a backfilled older issue falls back to the weekly schedule', () {
      expect(
        issueDrawLabel('ssq', '2026125', nextIssue: '2026126', now: thursdayMorning),
        '每周二、四、日 21:15',
      );
    });

    test('missing history or unknown game degrades gracefully', () {
      expect(
        issueDrawLabel('ssq', '2026126', now: thursdayMorning),
        '每周二、四、日 21:15',
      );
      expect(issueDrawLabel('unknown', '2026126'), isNull);
    });
  });

  test('nowBeijing reads as Beijing wall clock', () {
    final now = nowBeijing();
    // UTC 标记，因此跨时区比较也正确。
    expect(now.isUtc, isTrue);
    final utcNow = DateTime.now().toUtc();
    final diff = now.difference(utcNow).inMinutes;
    expect(diff, greaterThanOrEqualTo(479));
    expect(diff, lessThanOrEqualTo(481));
  });

  group('shouldFetchTodaysDraw', () {
    final ssq = drawScheduleFor('ssq')!;

    test('fetches once the draw time passed but the draw is not stored', () {
      expect(shouldFetchTodaysDraw(ssq, '2026-11-01', thursdayNight), isTrue);
    });

    test('stays quiet before the draw time', () {
      expect(shouldFetchTodaysDraw(ssq, '2026-11-01', thursdayMorning), isFalse);
    });

    test('stays quiet when today is already stored', () {
      expect(
        shouldFetchTodaysDraw(ssq, '2026-11-12', DateTime.utc(2026, 11, 12, 22, 0)),
        isFalse,
      );
    });

    test('stays quiet on a non-draw day and without history', () {
      expect(
        shouldFetchTodaysDraw(ssq, '2026-11-11', DateTime.utc(2026, 11, 11, 22, 0)),
        isFalse,
      );
      expect(shouldFetchTodaysDraw(ssq, null, thursdayNight), isFalse);
      expect(shouldFetchTodaysDraw(ssq, '', thursdayNight), isFalse);
    });
  });

  group('drawStatusFor', () {
    final ssq = drawScheduleFor('ssq')!;

    test('reports today as drawn once the numbers are in', () {
      final status = drawStatusFor(
        schedule: ssq,
        todayDrawn: true,
        now: thursdayNight,
      );
      expect(status.text, '今日开奖号码已更新（21:15 开奖）');
    });

    test('announces the upcoming draw before it happens', () {
      final status = drawStatusFor(
        schedule: ssq,
        todayDrawn: false,
        now: thursdayMorning,
        nextIssue: '2026126',
      );
      expect(status.text, '第 2026126 期 今天 21:15 开奖，开奖后自动更新');
    });

    test('says the official data is on its way after the draw time', () {
      final status = drawStatusFor(
        schedule: ssq,
        todayDrawn: false,
        now: thursdayNight,
        nextIssue: '2026126',
      );
      expect(status.text, '已过今日开奖时间，正在获取官方数据…');
    });

    test('points at the next draw on a non-draw day', () {
      // 2026-11-11 是周三，双色球不开奖，下一期是明天（周四）。
      final wednesday = DateTime.utc(2026, 11, 11, 12, 0);
      final status = drawStatusFor(
        schedule: ssq,
        todayDrawn: false,
        now: wednesday,
      );
      expect(status.text, '今天不开奖 · 下次开奖：明天 21:15');
    });

    test('works without a suggested issue', () {
      final status = drawStatusFor(
        schedule: ssq,
        todayDrawn: false,
        now: thursdayMorning,
      );
      expect(status.text, '下一期 今天 21:15 开奖，开奖后自动更新');
    });
  });
}
