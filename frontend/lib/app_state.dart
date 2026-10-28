import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  static const String _apiBaseKey = 'api_base';

  final Api api = Api();

  List<GameInfo> games = [];
  String? gameId;
  int pageIndex = 0;
  bool loading = true;
  bool syncing = false;
  String? error;
  String? toast;
  String apiBase = Api.defaultBase;

  /// Bumped whenever the backend address changes so pages remount and
  /// reload against the new server.
  int dataRevision = 0;

  GameInfo? get game {
    for (final g in games) {
      if (g.id == gameId) return g;
    }
    return null;
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_apiBaseKey);
      if (saved != null) {
        final value = Api.normalizeBase(saved);
        if (value != null) {
          apiBase = value;
          api.setBase(value);
        }
      }
    } catch (_) {
      // Storage unavailable: fall back to the default address.
    }
    await refreshGames();
  }

  Future<void> refreshGames() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      games = await api.games();
      if (gameId == null || !games.any((g) => g.id == gameId)) {
        final withData = games.where((g) => g.count > 0).toList();
        gameId = withData.isNotEmpty
            ? withData.first.id
            : (games.isNotEmpty ? games.first.id : null);
      }
      loading = false;
    } catch (e) {
      error = e.toString();
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
    apiBase = value;
    api.setBase(value);
    dataRevision++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_apiBaseKey, value);
    } catch (_) {}
    await refreshGames();
    return error;
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

  Future<void> syncCurrent() async {
    final g = game;
    if (g == null || syncing) return;
    syncing = true;
    toast = null;
    notifyListeners();
    try {
      final result = await api.sync(g.id);
      final total = result['total'];
      final fetched = result['fetched'];
      toast = '${g.name} 同步完成：拉取 $fetched 期，当前共 $total 期';
      await refreshGames();
    } catch (e) {
      toast = '同步失败：$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
