import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottery_lab_app/api.dart';
import 'package:lottery_lab_app/app_state.dart';
import 'package:lottery_lab_app/models.dart';
import 'package:lottery_lab_app/pages/history_page.dart';
import 'package:lottery_lab_app/theme.dart';

/// In-memory fake of the history endpoints, so the page can be laid out and
/// driven without a running backend.
class _FakeApi extends Api {
  _FakeApi() : super(base: 'http://127.0.0.1:9');

  String? lastMode;

  @override
  Future<Map<String, dynamic>> draws({
    required String game,
    int page = 1,
    int pageSize = 30,
    String? query,
    String? from,
    String? to,
  }) async {
    return {
      'items': [
        {
          'game': 'ssq',
          'issue': '2026126',
          'date': '2026-11-03',
          'primary': [1, 5, 12, 18, 23, 30],
          'secondary': [7],
          'sales': 350000000,
          'pool': 1200000000,
        },
      ],
      'page': page,
      'page_size': pageSize,
      'total': 640,
      'pages': 22,
    };
  }

  @override
  Future<List<GameInfo>> games() async => const [_game];

  @override
  Future<Map<String, dynamic>> sync(String game, {String mode = 'recent'}) async {
    lastMode = mode;
    return {
      'game': game,
      'fetched': 30,
      'written': 0,
      'total': 640,
      'latest': {
        'game': game,
        'issue': '2026126',
        'date': '2026-11-03',
        'primary': [1, 5, 12, 18, 23, 30],
        'secondary': [7],
      },
      'bets_settled': 0,
      'bets_won': 0,
    };
  }
}

const _game = GameInfo(
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
    issue: '2026126',
    date: '2026-11-03',
    primary: [1, 5, 12, 18, 23, 30],
    secondary: [7],
  ),
);

class _FakeState extends AppState {
  final _FakeApi fake;

  _FakeState(this.fake);

  @override
  Api get api => fake;

  void seed() {
    games = const [_game];
    gameId = 'ssq';
    loading = false;
    error = null;
    notifyListeners();
  }
}

Future<void> _pumpPage(WidgetTester tester, Size size, _FakeApi api) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: HistoryPage(state: _FakeState(api)..seed())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the toolbar row still fits at 390px', (tester) async {
    // The full-sync button joined the row next to export and refresh; a
    // RenderFlex overflow here would fail the pump.
    final api = _FakeApi();
    await _pumpPage(tester, const Size(390, 844), api);
    expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
    expect(find.text('共 640 期'), findsOneWidget);
  });

  testWidgets('the wide layout keeps every toolbar action', (tester) async {
    final api = _FakeApi();
    await _pumpPage(tester, const Size(1400, 1000), api);
    expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.text('共 640 期'), findsOneWidget);
  });

  testWidgets('the repair button asks the backend for the full history',
      (tester) async {
    final api = _FakeApi();
    await _pumpPage(tester, const Size(1400, 1000), api);
    await tester.tap(find.byIcon(Icons.cloud_download_outlined));
    await tester.pumpAndSettle();
    expect(api.lastMode, 'full');
  });
}
