import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

class Api {
  /// Used by desktop/web builds and as the fallback when the Android
  /// embedded engine cannot start. The Android app normally talks to the
  /// in-process backend on a loopback port instead.
  static String get defaultBase {
    const fromEnv = String.fromEnvironment('API_BASE');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'http://127.0.0.1:8787';
  }

  /// Accepts `host`, `host:port`, `http://host:port/` and returns a
  /// normalized URL without a trailing slash, or null when invalid.
  static String? normalizeBase(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    value = value.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    return value;
  }

  String base;
  final http.Client _client = http.Client();

  Api({String? base}) : base = base ?? defaultBase;

  void setBase(String value) {
    base = value;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final qp = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) qp[k] = v.toString();
    });
    return Uri.parse('$base$path').replace(queryParameters: qp);
  }

  dynamic _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    try {
      final body = jsonDecode(text);
      if (body is Map && body['error'] != null) {
        throw ApiException(body['error'].toString());
      }
    } catch (_) {}
    throw ApiException('请求失败 (${res.statusCode})');
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    try {
      final res = await _client
          .get(_uri(path, query))
          .timeout(const Duration(seconds: 60));
      return _decode(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('无法连接后端：$e');
    }
  }

  Future<dynamic> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final res = await _client
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return _decode(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('无法连接后端：$e');
    }
  }

  Future<List<GameInfo>> games() async {
    final data = await _get('/api/games') as Map<String, dynamic>;
    return (data['games'] as List)
        .map((e) => GameInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> draws({
    required String game,
    int page = 1,
    int pageSize = 30,
    String? query,
    String? from,
    String? to,
  }) async {
    return await _get('/api/draws', {
          'game': game,
          'page': page,
          'page_size': pageSize,
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
          if (from != null && from.isNotEmpty) 'from': from,
          if (to != null && to.isNotEmpty) 'to': to,
        })
        as Map<String, dynamic>;
  }

  String exportUrl(String game) => '$base/api/draws/export?game=$game';

  Future<Map<String, dynamic>> frequency(String game, int window) async {
    return await _get('/api/stats/frequency', {
          'game': game,
          'window': window,
        })
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> gaps(String game) async {
    return await _get('/api/stats/gaps', {'game': game})
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> combinations(String game) async {
    return await _get('/api/stats/combinations', {'game': game})
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> randomness(
    String game, {
    int window = 500,
    int simulations = 200,
  }) async {
    return await _get('/api/stats/randomness', {
          'game': game,
          'window': window,
          'simulations': simulations,
        })
        as Map<String, dynamic>;
  }

  Future<List<StrategyInfo>> strategies() async {
    final data = await _get('/api/strategies') as Map<String, dynamic>;
    return (data['strategies'] as List)
        .map((e) => StrategyInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> backtest(Map<String, dynamic> body) async {
    return await _post('/api/backtest', body,
            timeout: const Duration(seconds: 180))
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> tickets({
    required String game,
    required String strategy,
    required int count,
  }) async {
    return await _post('/api/tickets', {
      'game': game,
      'strategy': strategy,
      'count': count,
    }) as Map<String, dynamic>;
  }

  Future<PrizeCheckResult> prizeCheck({
    required String game,
    String? issue,
    required List<int> primary,
    required List<int> secondary,
  }) async {
    final data = await _post('/api/prize-check', {
      'game': game,
      if (issue != null && issue.isNotEmpty) 'issue': issue,
      'primary': primary,
      'secondary': secondary,
    }) as Map<String, dynamic>;
    return PrizeCheckResult.fromJson(data);
  }

  Future<Map<String, dynamic>> sync(String game) async {
    return await _post(
      '/api/sync',
      {'game': game, 'full': true},
      timeout: const Duration(seconds: 300),
    ) as Map<String, dynamic>;
  }
}
