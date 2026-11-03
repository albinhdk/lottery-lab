import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'embedded_backend_result.dart';

typedef _StartNative = Int32 Function(Pointer<Utf8> dbPath);
typedef _StartDart = int Function(Pointer<Utf8> dbPath);

const String _libraryName = 'liblottery_lab_backend.so';
const String _seedAsset = 'assets/lottery.db';

/// Starts the Rust backend inside the Android app process and returns the
/// loopback address it listens on. The database lives in app-private storage,
/// seeded from the bundled history on first launch.
Future<EmbeddedBackendResult> startEmbeddedBackend() async {
  if (!Platform.isAndroid) {
    return const EmbeddedBackendResult(error: '内置引擎仅在 Android 上启用');
  }

  try {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final database = File('${directory.path}${Platform.pathSeparator}lottery.db');
    await _ensureSeed(database);

    final library = DynamicLibrary.open(_libraryName);
    final start = library.lookupFunction<_StartNative, _StartDart>(
      'lottery_lab_start',
    );
    final path = database.path.toNativeUtf8();
    final port = start(path);
    malloc.free(path);

    if (port <= 0) {
      return const EmbeddedBackendResult(
        error: '内置引擎启动失败，请查看 logcat 或改用远程服务器',
      );
    }
    return EmbeddedBackendResult(base: 'http://127.0.0.1:$port');
  } catch (error) {
    return EmbeddedBackendResult(error: '内置引擎启动失败：$error');
  }
}

Future<void> _ensureSeed(File database) async {
  if (await database.exists() && await database.length() > 4096) {
    return;
  }
  try {
    final data = await rootBundle.load(_seedAsset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await database.parent.create(recursive: true);
    await database.writeAsBytes(bytes, flush: true);
  } catch (_) {
    // No seed asset: the server starts with an empty database and syncs
    // from the official sources in the background.
  }
}
