import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottery_lab_app/api.dart';
import 'package:lottery_lab_app/models.dart';
import 'package:lottery_lab_app/pages/prize_check_panel.dart';
import 'package:lottery_lab_app/theme.dart';

class _FakeApi extends Api {
  _FakeApi() : super(base: 'http://127.0.0.1:9');

  List<int>? lastPrimary;
  List<int>? lastSecondary;

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
          'game': 'dlt',
          'issue': '26124',
          'date': '2026-10-31',
          'primary': [1, 2, 3, 4, 5],
          'secondary': [6, 7],
        },
      ],
      'page': 1,
      'page_size': pageSize,
      'total': 1,
      'pages': 1,
    };
  }

  @override
  Future<PrizeCheckResult> prizeCheck({
    required String game,
    String? issue,
    required List<int> primary,
    required List<int> secondary,
  }) async {
    lastPrimary = List.of(primary);
    lastSecondary = List.of(secondary);
    return const PrizeCheckResult(
      game: 'dlt',
      gameName: '超级大乐透',
      issue: '26124',
      date: '2026-10-31',
      tierName: '一等奖',
      prizeNote: '一、二等奖为浮动奖金。',
      tier: 1,
      amount: 10000000,
      cost: 2,
      estimated: true,
      primaryHits: 5,
      secondaryHits: 2,
      drawPrimary: [1, 2, 3, 4, 5],
      drawSecondary: [6, 7],
      ticketPrimary: [1, 2, 3, 4, 5],
      ticketSecondary: [6, 7],
      matchedPrimary: [1, 2, 3, 4, 5],
      matchedSecondary: [6, 7],
    );
  }
}

const _game = GameInfo(
  id: 'dlt',
  name: '超级大乐透',
  primaryLabel: '前区',
  primaryCount: 5,
  primaryMax: 35,
  secondaryLabel: '后区',
  secondaryCount: 2,
  secondaryMax: 12,
  price: 2,
  prizeNote: '一、二等奖为浮动奖金。',
  count: 2942,
);

Future<void> _pumpPanel(
  WidgetTester tester,
  Size size,
  _FakeApi api,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: PrizeCheckPanel(game: _game, api: api)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickAllNumbers(WidgetTester tester) async {
  for (var n = 1; n <= 5; n++) {
    final ball = find.byKey(ValueKey('primary-$n'));
    await tester.ensureVisible(ball);
    await tester.tap(ball);
    await tester.pump();
  }
  for (var n = 6; n <= 7; n++) {
    final ball = find.byKey(ValueKey('secondary-$n'));
    await tester.ensureVisible(ball);
    await tester.tap(ball);
    await tester.pump();
  }
}

void main() {
  testWidgets('hand-picked ticket shows prize result', (tester) async {
    final api = _FakeApi();
    await _pumpPanel(tester, const Size(1400, 1000), api);
    await _pickAllNumbers(tester);

    final button = find.text('计算奖金');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(api.lastPrimary, [1, 2, 3, 4, 5]);
    expect(api.lastSecondary, [6, 7]);
    expect(find.text('一等奖'), findsOneWidget);
    expect(find.textContaining('1000.0 万'), findsOneWidget);
    expect(find.text('第 26124 期 · 2026-10-31'), findsWidgets);
  });

  testWidgets('mobile layout fits and still calculates', (tester) async {
    final api = _FakeApi();
    await _pumpPanel(tester, const Size(390, 844), api);
    await _pickAllNumbers(tester);

    final button = find.text('计算奖金');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(api.lastPrimary, [1, 2, 3, 4, 5]);
    expect(find.text('一等奖'), findsOneWidget);
  });
}
