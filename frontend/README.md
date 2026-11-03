# Lottery Lab · Flutter 前端

这是「彩票实验室」的 Flutter 客户端（Windows 桌面 + Web + Android）。完整说明见仓库根目录的 [README](../README.md)。

```bash
flutter pub get
flutter run -d windows     # 需要先启动 ../backend
flutter build web --release

# Android：先交叉编译内置后端，再构建 APK
python ../tools/build_android_backend.py
flutter build apk --release
```

Android 版通过 `lib/embedded/` 里的 Dart FFI 在 App 进程内启动 Rust 后端（`liblottery_lab_backend.so`），数据库从 `assets/lottery.db` 复制到 App 私有目录，离线可用；也可以在设置里切换到电脑上的远程后端。

中文字体 `assets/fonts/NotoSansSC-*.ttf` 是 Noto Sans SC 的子集，由 `../tools/subset_font.py` 生成。应用图标由 `../tools/make_icons.py` 生成。
