import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottery_lab_app/api.dart';
import 'package:lottery_lab_app/app_state.dart';
import 'package:lottery_lab_app/models.dart';
import 'package:lottery_lab_app/pages/overview_page.dart';
import 'package:lottery_lab_app/theme.dart';
import 'package:lottery_lab_app/widgets/common.dart';

/// Answers the two stats endpoints the overview page loads, plus the sync the
/// page may fire on its own, so no backend is needed.
class _FakeApi extends Api {
  _FakeApi() : super(base: 'http://127.0.0.1:9');

  int syncCalls = 0;

  /// What `/api/games` reports as the newest stored draw.
  String latestDate = '2026-11-01';

  @override
  Future<Map<String, dynamic>> randomness(
    String game, {
    int window = 500,
    int simulations = 200,
  }) async {
    return {
      'tests': const [],
      'conclusion': '与随机一致',
      'overall_verdict': 'pass',
      'total_draws': 500,
      'test_count': 9,
    };
  }

  @override
  Future<Map<String, dynamic>> frequency(String game, int window) async {
    return {
      'primary': {
        'numbers': [
          for (var n = 1; n <= 33; n++) {'number': n, 'count': 10},
        ],
      },
      'secondary': {
        'numbers': [
          for (var n = 1; n <= 16; n++) {'number': n, 'count': 10},
        ],
      },
    };
  }

  @override
  Future<List<GameInfo>> games() async => [_game(latestDate: latestDate)];

  @override
  Future<Map<String, dynamic>> sync(String game, {String mode = 'recent'}) async {
    syncCalls++;
    return {
      'game': game,
      'fetched': 30,
      'written': 0,
      'total': 640,
      'latest': {
        'game': game,
        'issue': '2026126',
        'date': '2026-11-12',
        'primary': [4, 6, 10, 15, 26, 27],
        'secondary': [11],
      },
      'bets_settled': 0,
      'bets_won': 0,
    };
  }
}

GameInfo _game({required String latestDate}) {
  return GameInfo(
    id: 'ssq',
    name: '双色球',
    primaryLabel: '红球',
    primaryCount: 6,
    primaryMax: 33,
    secondaryLabel: '蓝球',
    secondaryCount: 1,
    secondaryMax: 16,
    price: 2,
    prizeNote: '一、二等奖为浮动奖金。',
    count: 640,
    latest: Draw(
      game: 'ssq',
      issue: latestDate == '2026-11-12' ? '2026126' : '2026125',
      date: latestDate,
      primary: const [4, 6, 10, 15, 26, 27],
      secondary: const [11],
    ),
    nextIssue: '2026126',
  );
}

class _FakeState extends AppState {
  final _FakeApi fake;

  _FakeState(this.fake);

  @override
  Api get api => fake;

  void seed({required String latestDate}) {
    fake.latestDate = latestDate;
    games = [_game(latestDate: latestDate)];
    gameId = 'ssq';
    loading = false;
    error = null;
    notifyListeners();
  }
}

void main() {
  // 2026-11-12 是周四（双色球开奖日）。
  final thursdayMorning = DateTime.utc(2026, 11, 12, 10, 0);
  final thursdayNight = DateTime.utc(2026, 11, 12, 22, 0);

  Widget host(OverviewPage page, {double width = 1280}) => MaterialApp(
        theme: buildTheme(),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: 1600, child: page),
        ),
      );

  testWidgets('today\'s draw leads the page with its numbers',
      (tester) async {
    final api = _FakeApi();
    final state = _FakeState(api)..seed(latestDate: '2026-11-12');
    await tester.pumpWidget(
      host(OverviewPage(state: state, clock: () => thursdayNight)),
    );
    await tester.pumpAndSettle();
    expect(find.text('今日开奖'), findsOneWidget);
    expect(find.text('今日开奖号码已更新（21:15 开奖）'), findsOneWidget);
    // 当天号码已经在了，不需要再拉一次。
    expect(api.syncCalls, 0);
  });

  testWidgets('a draw day before the draw announces tonight\'s draw',
      (tester) async {
    final api = _FakeApi();
    final state = _FakeState(api)..seed(latestDate: '2026-11-01');
    await tester.pumpWidget(
      host(OverviewPage(state: state, clock: () => thursdayMorning)),
    );
    await tester.pumpAndSettle();
    // 顶部卡片是页面里第一个 Panel；概览统计磁贴同样带「最新开奖」字样。
    expect(
      find.descendant(
        of: find.byType(Panel).first,
        matching: find.text('最新开奖'),
      ),
      findsOneWidget,
    );
    expect(find.text('第 2026126 期 今天 21:15 开奖，开奖后自动更新'), findsOneWidget);
    expect(api.syncCalls, 0);
  });

  testWidgets('opening after the draw time pulls the newest page once',
      (tester) async {
    final api = _FakeApi();
    final state = _FakeState(api)..seed(latestDate: '2026-11-01');
    await tester.pumpWidget(
      host(OverviewPage(state: state, clock: () => thursdayNight)),
    );
    await tester.pumpAndSettle();
    expect(api.syncCalls, 1);
    expect(find.text('已过今日开奖时间，正在获取官方数据…'), findsOneWidget);

    // 页面因同步而重挂后，不会再次触发拉取。
    await tester.pumpWidget(
      host(OverviewPage(state: state, clock: () => thursdayNight)),
    );
    await tester.pumpAndSettle();
    expect(api.syncCalls, 1);
  });

  testWidgets('a non-draw day points at the next draw', (tester) async {
    final api = _FakeApi();
    final state = _FakeState(api)..seed(latestDate: '2026-11-01');
    // 2026-11-11 是周三，双色球不开奖，下一期是明天（周四）。
    final wednesdayNoon = DateTime.utc(2026, 11, 11, 12, 0);
    await tester.pumpWidget(
      host(OverviewPage(state: state, clock: () => wednesdayNoon)),
    );
    await tester.pumpAndSettle();
    expect(find.text('今天不开奖 · 下次开奖：明天 21:15'), findsOneWidget);
    expect(api.syncCalls, 0);
  });

  testWidgets('the narrow layout still leads with today\'s draw',
      (tester) async {
    final api = _FakeApi();
    final state = _FakeState(api)..seed(latestDate: '2026-11-12');
    await tester.pumpWidget(
      host(
        OverviewPage(state: state, clock: () => thursdayNight),
        width: 390,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('今日开奖'), findsOneWidget);
    expect(find.text('今日开奖号码已更新（21:15 开奖）'), findsOneWidget);
  });
}
