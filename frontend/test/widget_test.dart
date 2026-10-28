import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottery_lab_app/models.dart';
import 'package:lottery_lab_app/widgets/common.dart';

void main() {
  testWidgets('Ball renders zero-padded number', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Ball(number: 4, size: 32)),
      ),
    );
    expect(find.text('04'), findsOneWidget);
  });

  test('jackpot odds match known values', () {
    final ssq = GameInfo(
      id: 'ssq',
      name: '双色球',
      primaryLabel: '红球',
      primaryCount: 6,
      primaryMax: 33,
      secondaryLabel: '蓝球',
      secondaryCount: 1,
      secondaryMax: 16,
      price: 2,
      prizeNote: '',
      count: 0,
    );
    expect(ssq.jackpotOdds, 17721088);

    final dlt = GameInfo(
      id: 'dlt',
      name: '大乐透',
      primaryLabel: '前区',
      primaryCount: 5,
      primaryMax: 35,
      secondaryLabel: '后区',
      secondaryCount: 2,
      secondaryMax: 12,
      price: 2,
      prizeNote: '',
      count: 0,
    );
    expect(dlt.jackpotOdds, 21425712);
  });
}
