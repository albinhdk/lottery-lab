import 'package:flutter_test/flutter_test.dart';
import 'package:lottery_lab_app/api.dart';
import 'package:lottery_lab_app/app_state.dart';
import 'package:lottery_lab_app/models.dart';

/// Records what `/api/sync` was asked for and answers with a canned payload,
/// so the toolbar button's fetch scope can be asserted without a backend.
class _FakeApi extends Api {
  _FakeApi() : super(base: 'http://127.0.0.1:9');

  /// Latest issue `/api/games` reports, i.e. what the app already knows.
  String gamesLatestIssue = '2026126';

  /// Latest issue the sync response reports.
  String latestIssue = '2026126';

  /// When set, `/api/sync` fails the way a dead backend would.
  bool failSync = false;

  String? lastMode;
  String? lastGame;

  @override
  Future<List<GameInfo>> games() async => [_game(gamesLatestIssue)];

  @override
  Future<Map<String, dynamic>> sync(String game, {String mode = 'recent'}) async {
    lastGame = game;
    lastMode = mode;
    if (failSync) throw Exception('connection refused');
    return {
      'game': game,
      'fetched': 30,
      'written': 0,
      'total': 640,
      'latest': {
        'game': game,
        'issue': latestIssue,
        'date': '2026-11-03',
        'primary': [1, 5, 12, 18, 23, 30],
        'secondary': [7],
      },
      'bets_settled': 0,
      'bets_won': 0,
    };
  }
}

GameInfo _game(String latestIssue) {
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
      issue: latestIssue,
      date: '2026-11-03',
      primary: const [1, 5, 12, 18, 23, 30],
      secondary: const [7],
    ),
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
    games = [_game(fake.gamesLatestIssue)];
    gameId = 'ssq';
    loading = false;
    error = null;
    notifyListeners();
  }
}

void main() {
  test('the toolbar button only checks the newest page', () async {
    // Regression: it used to ask for a full re-sync every time, which crawls
    // every page and takes many seconds — exactly when the user is waiting to
    // see whether the draw landed.
    final api = _FakeApi();
    final state = _FakeState(api)..seed();
    await state.syncCurrent();
    expect(api.lastGame, 'ssq');
    expect(api.lastMode, 'recent');
  });

  test('the repair button asks for the full history', () async {
    final api = _FakeApi();
    final state = _FakeState(api)..seed();
    await state.syncCurrent(mode: 'full');
    expect(api.lastMode, 'full');
  });

  test('an unchanged latest issue is reported as already up to date', () async {
    final api = _FakeApi();
    final state = _FakeState(api)..seed();
    await state.syncCurrent();
    expect(state.toast, contains('已是最新'));
    expect(state.toast, contains('第 2026126 期'));
  });

  test('a new issue is reported with its number', () async {
    final api = _FakeApi()
      ..gamesLatestIssue = '2026125'
      ..latestIssue = '2026126';
    final state = _FakeState(api)..seed();
    await state.syncCurrent();
    expect(state.toast, contains('已更新到第 2026126 期'));
  });

  test('a failed sync surfaces the error instead of a false success', () async {
    final api = _FakeApi()..failSync = true;
    final state = _FakeState(api)..seed();
    await state.syncCurrent(mode: 'official');
    expect(state.toast, startsWith('同步失败'));
    expect(state.syncing, isFalse);
  });
}
