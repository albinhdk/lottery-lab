import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'embedded/embedded_backend.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  static const String _apiBaseKey = 'api_base';
  static const String _apiModeKey = 'api_mode';
  static const String _modeEmbedded = 'embedded';
  static const String _modeRemote = 'remote';

  final Api api = Api();

  List<GameInfo> games = [];
  String? gameId;
  int pageIndex = 0;
  bool loading = true;
  bool syncing = false;
  String? error;
  String? toast;
  String apiBase = Api.defaultBase;
  String apiMode = _modeRemote;

  /// Loopback address of the in-process Android backend, when it started.
  String? embeddedBase;
  String? embeddedError;

  /// Last explicitly configured remote server, so switching back to the
  /// embedded engine does not lose it.
  String? lastRemoteBase;

  /// Bumped whenever the backend address changes so pages remount and
  /// reload against the new server.
  int dataRevision = 0;

  /// Bumped whenever the background prize check actually settled bets. The
  /// ledger listens to this so it can reload itself. `dataRevision` is
  /// deliberately not reused: bumping it would remount the analysis and
  /// backtest pages too, throwing away results the user is looking at.
  int betsRevision = 0;

  /// Suggested issue for a new bet, or null when unknown.
  String? apiNextIssue(String gameId) {
    for (final g in games) {
      if (g.id == gameId) return g.nextIssue;
    }
    return null;
  }

  GameInfo? get game {
    for (final g in games) {
      if (g.id == gameId) return g;
    }
    return null;
  }

  bool get hasEmbedded => embeddedBase != null;

  bool get embeddedSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get usesEmbedded => apiMode == _modeEmbedded && embeddedBase != null;

  String get apiBaseLabel => usesEmbedded ? '内置引擎（离线）' : apiBase;

  Future<void> init() async {
    String? savedMode;
    String? savedBase;
    try {
      final prefs = await SharedPreferences.getInstance();
      savedMode = prefs.getString(_apiModeKey);
      savedBase = prefs.getString(_apiBaseKey);
    } catch (_) {
      // Storage unavailable: fall back to the default address.
    }

    final embedded = await startEmbeddedBackend();
    embeddedBase = embedded.base;
    embeddedError = embedded.error;

    final remoteBase = savedBase == null ? null : Api.normalizeBase(savedBase);
    lastRemoteBase = remoteBase;
    if (savedMode == _modeRemote && remoteBase != null) {
      apiMode = _modeRemote;
      apiBase = remoteBase;
    } else if (embeddedBase != null) {
      apiMode = _modeEmbedded;
      apiBase = embeddedBase!;
    } else if (remoteBase != null) {
      apiMode = _modeRemote;
      apiBase = remoteBase;
    } else {
      apiMode = _modeRemote;
      apiBase = Api.defaultBase;
    }
    api.setBase(apiBase);
    await refreshGames();
  }

  /// Reloads the game list from the backend. When [silent] is true no
  /// loading state is shown; this is used by the periodic freshness poll.
  /// Pages are remounted (via [dataRevision]) only when a game's latest
  /// issue actually changed, so background refreshes don't reset the UI.
  Future<void> refreshGames({bool silent = false}) async {
    final previousLatest = {for (final g in games) g.id: g.latest?.issue};
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final next = await api.games();
      final changed =
          next.any((g) => previousLatest[g.id] != g.latest?.issue);
      games = next;
      if (gameId == null || !games.any((g) => g.id == gameId)) {
        final withData = games.where((g) => g.count > 0).toList();
        gameId = withData.isNotEmpty
            ? withData.first.id
            : (games.isNotEmpty ? games.first.id : null);
      }
      error = null;
      loading = false;
      if (changed) dataRevision++;
    } catch (e) {
      if (!silent) error = e.toString();
      loading = false;
    }
    notifyListeners();
  }

  /// Returns null on success, or a human-readable error message.
  Future<String?> setApiBase(String raw) async {
    final value = Api.normalizeBase(raw);
    if (value == null) {
      return '地址格式不正确，例如 http://192.168.1.10:8787';
    }
    apiMode = _modeRemote;
    apiBase = value;
    lastRemoteBase = value;
    api.setBase(value);
    dataRevision++;
    await _persist();
    await refreshGames();
    return error;
  }

  /// Switches back to the in-process backend. Returns null on success.
  Future<String?> useEmbeddedBackend() async {
    final value = embeddedBase;
    if (value == null) {
      return embeddedError ?? '内置引擎不可用';
    }
    apiMode = _modeEmbedded;
    apiBase = value;
    api.setBase(value);
    dataRevision++;
    await _persist();
    await refreshGames();
    return error;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_apiModeKey, apiMode);
      if (lastRemoteBase != null) {
        await prefs.setString(_apiBaseKey, lastRemoteBase!);
      } else {
        await prefs.remove(_apiBaseKey);
      }
    } catch (_) {}
  }

  void selectGame(String id) {
    if (gameId == id) return;
    gameId = id;
    notifyListeners();
  }

  void selectPage(int index) {
    if (pageIndex == index) return;
    pageIndex = index;
    notifyListeners();
  }

  /// Asks the backend to settle pending bets. Called on app start, on
  /// resume, and on a foreground timer, so a draw that landed while the app
  /// was closed is checked without the user pressing anything. When the
  /// check settles something, [betsRevision] is bumped so the ledger
  /// reloads — dropping the result used to leave the page showing 待开奖
  /// until the next new issue happened to arrive. Failures are ignored: the
  /// next sync retries and the ledger still renders.
  Future<void> checkBets() async {
    try {
      final result = await api.checkBets();
      if (result.settled > 0) {
        betsRevision++;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Pulls fresh data for the current game. [mode] is "recent" (only the
  /// newest official page — what the toolbar button wants) or "full" (every
  /// page plus the 2003–2012 backfill, the repair path).
  Future<void> syncCurrent({String mode = 'recent'}) async {
    final g = game;
    if (g == null || syncing) return;
    syncing = true;
    toast = null;
    notifyListeners();
    final before = g.latest?.issue;
    try {
      final result = await api.sync(g.id, mode: mode);
      final latest = result['latest'];
      final after =
          latest is Map<String, dynamic> ? latest['issue'] as String? : null;
      final fetched = result['fetched'];
      final total = result['total'];
      // Say what actually happened: "已是最新" is the common answer right
      // after a draw, and it used to be indistinguishable from a success.
      if (after != null && after != before) {
        toast = '${g.name} 已更新到第 $after 期'
            '（拉取 $fetched 期，当前共 $total 期）';
      } else {
        toast = '${g.name} 已是最新：第 ${after ?? before ?? '—'} 期'
            '（拉取 $fetched 期，当前共 $total 期）';
      }
      // Remount the pages so history/analysis/backtest pick up the new draws.
      dataRevision++;
      await refreshGames();
    } catch (e) {
      toast = '同步失败：$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
