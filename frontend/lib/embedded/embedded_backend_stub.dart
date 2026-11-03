import 'embedded_backend_result.dart';

/// Web builds talk to the desktop backend instead of an in-process one.
Future<EmbeddedBackendResult> startEmbeddedBackend() async {
  return const EmbeddedBackendResult(error: '当前平台不支持内置引擎');
}
