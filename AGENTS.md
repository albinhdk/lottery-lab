# AGENTS.md — Lottery Lab

## 项目定位

彩票统计分析与回测工具，**不是预测器**。任何 UI 文案都不得暗示能提高中奖概率。后端 Rust（axum + SQLite），前端 Flutter（Windows/Web），无 Node 构建链。

## 架构

- `backend/src/`
  - `main.rs` — 启动、静态文件服务、首次启动自动同步
  - `routes.rs` — REST 路由与错误处理
  - `db.rs` — SQLite（WAL），`Mutex<Connection>`，按 game 隔离
  - `sources.rs` — 福彩官方 JSON、体彩官方 JSON、500.com HTML 解析
  - `stats.rs` — 卡方/正态/gamma/游程/二项分布等数学函数
  - `analysis.rs` — 频率、遗漏、组合结构、9 项随机性检验
  - `strategies.rs` — 8 个策略，`StrategyRunner::predict_variant` 支持多注轮换
  - `backtest.rs` — 严格走查回测、Brier、自助法 ROI 区间
- `frontend/lib/`
  - `main.dart` — 侧边栏 + `IndexedStack` 页面框架
  - `pages/` — overview / history / analysis / backtest / tickets
  - `widgets/common.dart` — Panel、Ball、StatTile、VerdictChip 等

## 必须保持的约束

1. **回测只能使用未来数据之前的历史**。`backtest.rs` 中 `history = &draws[..t]`，不要为了“效果更好”提前使用 `draws[t]`。
2. **随机性结论必须做多重比较校正**。`analysis::randomness` 用二项分布计算 `overall_p`，前端徽标看 `overall_verdict`，不要退回“有 1 项 p<0.05 就异常”。
3. **奖级表集中在 `config.rs`**。一、二等奖是估值，UI 必须显示 `prize_note`。
4. **大乐透 2014 年前存在分布异常**（前区偏大号）。这是数据/设备历史问题，不是可预测规律；相关说明在 randomness 的 `note` 字段，不要删。
5. **前端不要嵌套 Expanded 进 `Panel`**。`Panel` 内部 Column 是 `mainAxisSize.min`，在固定高度里放 `Expanded` 会导致列表高度为 0（历史页曾因此空白）。需要填满高度时直接用 `Container` + `Column` + `Expanded`。
6. **中文字体是子集**。`frontend/assets/fonts/NotoSansSC-*.ttf` 由 `tools/subset_font.py` 生成，覆盖源码字符 + GB2312 一级字库。新增生僻中文后重新运行该脚本，否则 Web 版会缺字。
7. **页面按需加载**。`main.dart` 用 `LazyIndexedStack`（首次访问才 build，之后保活），不要改回 `IndexedStack`，否则启动时会同时触发五个页面的 API 请求。
8. **Material 组件中文化**。`MaterialApp` 已配置 `flutter_localizations` 并强制 `zh_CN`；新增日期/时间选择器时保持该配置，否则内部文案会变英文。
9. **手机/桌面双布局**。`main.dart` 以 900px 为界：宽屏左侧栏，窄屏 AppBar + 底部导航。各页面用 `LayoutBuilder` 在窄屏堆叠卡片、隐藏次要列；改布局时同时验证 390×844。
10. **服务器地址可在 App 内修改**。`Api.defaultBase` 在 Android 上默认指向构建机局域网地址，桌面/Web 默认 `127.0.0.1`；`AppState.setApiBase` 会持久化到 SharedPreferences 并递增 `dataRevision` 让页面重挂载。后端默认监听 `0.0.0.0:8787`，Android 明文 HTTP 已在 manifest 中开启。
11. **后端与前端 API 契约**以 `README.md` 的表格为准；修改字段时同步更新 Dart 解析。

## 命令

```bash
cd backend && cargo test && cargo run
cd frontend && flutter analyze && flutter test && flutter run -d windows
cd frontend && flutter build web --release   # 后端会自动挂载 build/web
python tools/subset_font.py                  # 重新生成中文字体子集
```

## 数据

- 双色球：2013+ 福彩官方；2003–2012 由 500.com 补齐。
- 大乐透：体彩官方 2007+，销售额/奖池来自 `totalSaleAmount` / `poolBalanceAfterdraw`。
- 运行时 DB：`backend/data/lottery.db`（已 gitignore）。

## Android 构建注意事项

- 本机 Pub 缓存在 C 盘、项目在 D 盘，Kotlin 增量编译会报 “different roots”，因此 `frontend/android/gradle.properties` 设置了 `kotlin.incremental=false`。不要随意删掉，除非把项目/缓存放到同一盘。
- 构建 APK 时如果 Gradle 依赖下载卡住，给 Gradle 加代理：`JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7890 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7890" flutter build apk --release`。
- APK 默认使用 debug 签名，可直接安装测试；上架需配置正式签名。
