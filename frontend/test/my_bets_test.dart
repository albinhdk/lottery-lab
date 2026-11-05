
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottery_lab_app/api.dart';
import 'package:lottery_lab_app/app_state.dart';
import 'package:lottery_lab_app/models.dart';
import 'package:lottery_lab_app/models_bet.dart';
import 'package:lottery_lab_app/pages/my_bets_page.dart';
import 'package:lottery_lab_app/theme.dart';

/// In-memory fake of the bet endpoints, so the ledger can be exercised
/// without a running backend.
class _FakeApi extends Api {
  _FakeApi() : super(base: 'http://127.0.0.1:9');

  /// Rows returned by the fake `/api/bets` endpoint. Named `stored` because
  /// `bets` is already the HTTP method under test.
  List<Bet> stored = [];
  int checkCalls = 0;
  int? deletedId;
  double? lastActualAmount;
  int? lastActualAmountId;

  /// What the fake `/api/bets/check` endpoint reports. Overridden by tests
  /// that need a settlement to happen.
  BetCheckResult checkResult = const BetCheckResult(
    settled: 0,
    won: 0,
    stillPending: 0,
    skipped: 0,
  );

  @override
  Future<Map<String, dynamic>> bets({
    String? game,
    String? status,
    int page = 1,
    int pageSize = 50,
  }) async {
    var items = stored;
    if (status == 'pending') {
      items = items.where((b) => b.pending).toList();
    } else if (status == 'won') {
      items = items.where((b) => b.won).toList();
    } else if (status == 'lost') {
      items = items.where((b) => b.status == BetStatus.lost).toList();
    }
    return {
      'items': items.map(_betJson).toList(),
      'page': page,
      'page_size': pageSize,
      'total': items.length,
      'pages': 1,
    };
  }

  @override
  Future<BetSummary> betSummary({String? game}) async {
    final settled = stored.where((b) => !b.pending).toList();
    return BetSummary(
      total: stored.length,
      pending: stored.where((b) => b.pending).length,
      won: stored.where((b) => b.won).length,
      lost: stored.where((b) => b.status == BetStatus.lost).length,
      cost: stored.fold<double>(0, (sum, b) => sum + b.cost),
      payout: settled.fold<double>(0, (sum, b) => sum + b.payout),
      net: 0,
      estimatedPayout: 0,
      byTier: const [],
    );
  }

  @override
  Future<BetCheckResult> checkBets({String? game, bool full = false}) async {
    checkCalls++;
    return checkResult;
  }

  @override
  Future<void> deleteBet(int id) async {
    deletedId = id;
    stored.removeWhere((b) => b.id == id);
  }

  @override
  Future<void> setActualAmount(int id, double? amount) async {
    lastActualAmountId = id;
    lastActualAmount = amount;
  }
}

Map<String, dynamic> _betJson(Bet b) {
  return {
    'id': b.id,
    'game': b.game,
    'game_name': b.gameName,
    'issue': b.issue,
    'date': b.date,
    'primary': b.primary,
    'secondary': b.secondary,
    'multiple': b.multiple,
    'note': b.note,
    'status': b.status.name,
    'tier': b.tier,
    'tier_name': b.tierName,
    'primary_hits': b.primaryHits,
    'secondary_hits': b.secondaryHits,
    'matched_primary': b.matchedPrimary,
    'matched_secondary': b.matchedSecondary,
    'amount': b.amount,
    'actual_amount': b.actualAmount,
    'estimated': b.estimated,
    'cost': b.cost,
    'payout': b.payout,
    'created_at': b.createdAt,
    'checked_at': b.checkedAt,
  };
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
  count: 100,
);

Bet _bet({
  required int id,
  required String issue,
  BetStatus status = BetStatus.pending,
  int tier = 0,
  String tierName = '未中奖',
  double amount = 0,
  double payout = 0,
}) {
  return Bet(
    id: id,
    game: 'ssq',
    gameName: '双色球',
    issue: issue,
    date: status == BetStatus.pending ? '' : '2026-11-01',
    primary: const [1, 5, 12, 18, 23, 30],
    secondary: const [7],
    multiple: 1,
    note: '',
    status: status,
    tier: tier,
    tierName: tierName,
    primaryHits: 0,
    secondaryHits: 0,
    matchedPrimary: const [],
    matchedSecondary: const [],
    amount: amount,
    actualAmount: null,
    estimated: tier == 1 || tier == 2,
    cost: 2,
    payout: payout,
    createdAt: '2026-11-01 10:00:00',
    checkedAt: null,
  );
}

/// [AppState] with the network parts stubbed out. `init()` is never called,
/// so no real connection is attempted.
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

void main() {
  testWidgets('empty ledger shows the entry hint', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MyBetsPage(state: _FakeState(api)..seed()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有购彩记录'), findsOneWidget);
  });

  testWidgets('pending bet shows the ticket and the stake', (tester) async {
    final api = _FakeApi()..stored = [_bet(id: 1, issue: '2026126')];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MyBetsPage(state: _FakeState(api)..seed()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('双色球 · 第 2026126 期'), findsOneWidget);
    // "待开奖" appears both in the status filter and on the card.
    expect(find.text('待开奖'), findsWidgets);
    expect(find.text('投入 2 元'), findsOneWidget);
  });

  testWidgets('winning bet shows tier, amount and matched balls', (tester) async {
    final api = _FakeApi()
      ..stored = [
        _bet(
          id: 2,
          issue: '2026125',
          status: BetStatus.won,
          tier: 3,
          tierName: '三等奖',
          amount: 3000,
          payout: 3000,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MyBetsPage(state: _FakeState(api)..seed()),
      ),
    );
    await tester.pumpAndSettle();
    // The tier name shows up in the status chip and the result banner.
    expect(find.text('三等奖'), findsWidgets);
    expect(find.text('3,000 元'), findsOneWidget);
    expect(find.text('投入 2 元 · 奖金 3,000 元'), findsOneWidget);
  });

  testWidgets('floating prize invites the real payout and stores it',
      (tester) async {
    final api = _FakeApi()
      ..stored = [
        _bet(
          id: 3,
          issue: '2026125',
          status: BetStatus.won,
          tier: 1,
          tierName: '一等奖',
          amount: 7000000,
          payout: 7000000,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MyBetsPage(state: _FakeState(api)..seed()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('填写实际到账'), findsOneWidget);

    await tester.tap(find.text('填写实际到账'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '6543210');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(api.lastActualAmountId, 3);
    expect(api.lastActualAmount, 6543210.0);
  });

  testWidgets('deleting a bet asks for confirmation first', (tester) async {
    final api = _FakeApi()..stored = [_bet(id: 4, issue: '2026126')];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MyBetsPage(state: _FakeState(api)..seed()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.text('删除这条记录？'), findsOneWidget);
    // Nothing is removed until the dialog is confirmed.
    expect(api.deletedId, isNull);

    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(api.deletedId, 4);
  });

  testWidgets('status filter narrows the list', (tester) async {
    final api = _FakeApi()
      ..stored = [
        _bet(id: 5, issue: '2026126'),
        _bet(id: 6, issue: '2026125', status: BetStatus.lost),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MyBetsPage(state: _FakeState(api)..seed()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('双色球 · 第 2026126 期'), findsOneWidget);
    expect(find.text('双色球 · 第 2026125 期'), findsOneWidget);

    // The filter pill lives in the filter row, the card chip is a Tag.
    await tester.tap(find.text('待开奖').first);
    await tester.pumpAndSettle();
    expect(find.text('双色球 · 第 2026126 期'), findsOneWidget);
    expect(find.text('双色球 · 第 2026125 期'), findsNothing);
  });

  testWidgets('statistics tab breaks the ledger down by tier', (tester) async {
    final api = _FakeApi()
      ..stored = [
        _bet(
          id: 7,
          issue: '2026125',
          status: BetStatus.won,
          tier: 3,
          tierName: '三等奖',
          amount: 3000,
          payout: 3000,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MyBetsPage(state: _FakeState(api)..seed()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    expect(find.text('奖级分布'), findsOneWidget);
  });

  testWidgets('re-check keeps every game\'s settled status', (tester) async {
    // Regression: recheck used to reset all games' rows while only one
    // game's draws were supplied, so the manual re-check button appeared to
    // do nothing (and lost the status it had already computed).
    final api = _FakeApi()
      ..stored = [
        _bet(
          id: 11,
          issue: '2026126',
          status: BetStatus.lost,
          tier: 0,
          tierName: '未中奖',
        ),
        Bet(
          id: 12,
          game: 'dlt',
          gameName: '超级大乐透',
          issue: '26125',
          date: '2026-11-02',
          primary: const [12, 13, 23, 25, 29],
          secondary: const [7, 10],
          multiple: 1,
          note: '',
          status: BetStatus.won,
          tier: 1,
          tierName: '一等奖',
          primaryHits: 5,
          secondaryHits: 2,
          matchedPrimary: const [12, 13, 23, 25, 29],
          matchedSecondary: const [7, 10],
          amount: 10000000,
          actualAmount: null,
          estimated: true,
          cost: 2,
          payout: 10000000,
          createdAt: '2026-11-01 10:00:00',
          checkedAt: '2026-11-02 21:00:00',
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MyBetsPage(state: _FakeState(api)..seed()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('未中奖'), findsWidgets);
    expect(find.text('一等奖'), findsWidgets);

    await tester.tap(find.text('重新对奖'));
    await tester.pumpAndSettle();

    // The check ran instead of failing silently.
    expect(api.checkCalls, greaterThan(0));
    // Both games' statuses survive the re-check: this is the regression.
    expect(find.text('未中奖'), findsWidgets);
    expect(find.text('一等奖'), findsWidgets);
  });

  testWidgets('a background settlement refreshes the ledger by itself',
      (tester) async {
    // Regression: the periodic prize check used to drop its result, so the
    // page kept showing 待开奖 until the next new issue happened to arrive.
    final api = _FakeApi()..stored = [_bet(id: 20, issue: '2026126')];
    final state = _FakeState(api)..seed();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MyBetsPage(state: state),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('待开奖'), findsWidgets);

    // The draw lands: the bet is settled in the database and the check
    // reports it, without the page being remounted.
    api.stored = [_bet(id: 20, issue: '2026126', status: BetStatus.lost)];
    api.checkResult = const BetCheckResult(
      settled: 1,
      won: 0,
      stillPending: 0,
      skipped: 0,
    );
    await state.checkBets();
    await tester.pumpAndSettle();

    expect(state.betsRevision, 1);
    expect(find.text('未中奖'), findsWidgets);
  });

  test('a check that settles nothing leaves the ledger alone', () async {
    final api = _FakeApi();
    final state = _FakeState(api)..seed();
    await state.checkBets();
    expect(api.checkCalls, 1);
    // No reload is queued: every poll would otherwise reset the user's
    // filters and scroll position for nothing.
    expect(state.betsRevision, 0);
  });

  test('Bet parses the backend payload including actual amount overrides', () {
    final bet = Bet.fromJson({
      'id': 9,
      'game': 'ssq',
      'game_name': '双色球',
      'issue': '2026125',
      'date': '2026-11-01',
      'primary': [1, 5, 12, 18, 23, 30],
      'secondary': [7],
      'multiple': 3,
      'note': '生日号',
      'status': 'won',
      'tier': 1,
      'tier_name': '一等奖',
      'primary_hits': 6,
      'secondary_hits': 1,
      'matched_primary': [1, 5, 12, 18, 23, 30],
      'matched_secondary': [7],
      'amount': 7000000,
      'actual_amount': 6543210,
      'estimated': true,
      'cost': 6,
      'payout': 19629630,
      'created_at': '2026-11-01 10:00:00',
      'checked_at': '2026-11-02 21:00:00',
    });
    expect(bet.won, isTrue);
    expect(bet.tier, 1);
    expect(bet.actualAmount, 6543210.0);
    // The recorded payout wins over the estimate.
    expect(bet.effectiveAmount, 6543210.0);
    expect(bet.payout, 19629630.0);
    expect(bet.multiple, 3);
    expect(bet.note, '生日号');
  });

  test('Bet defaults a missing actual amount to the estimate', () {
    final bet = Bet.fromJson({
      'id': 10,
      'status': 'won',
      'tier': 2,
      'amount': 150000,
      'payout': 150000,
    });
    expect(bet.actualAmount, isNull);
    expect(bet.effectiveAmount, 150000.0);
  });

  test('BetStatus parses every backend value and labels them', () {
    expect(BetStatus.fromJson('pending'), BetStatus.pending);
    expect(BetStatus.fromJson('won'), BetStatus.won);
    expect(BetStatus.fromJson('lost'), BetStatus.lost);
    // Anything unexpected is treated as pending, matching the backend.
    expect(BetStatus.fromJson('???'), BetStatus.pending);
    expect(BetStatus.pending.label, '待开奖');
    expect(BetStatus.won.label, '已中奖');
    expect(BetStatus.lost.label, '未中奖');
  });
}
