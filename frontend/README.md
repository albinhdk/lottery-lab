# Lottery Lab · Flutter 前端

这是「彩票实验室」的 Flutter 客户端（Windows 桌面 + Web）。完整说明见仓库根目录的 [README](../README.md)。

```bash
flutter pub get
flutter run -d windows     # 需要先启动 ../backend
flutter build web --release
```

中文字体 `assets/fonts/NotoSansSC-*.ttf` 是 Noto Sans SC 的子集，由 `../tools/subset_font.py` 生成。
