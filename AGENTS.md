# AGENTS.md — Lottery Lab

## 项目定位

彩票统计分析与回测工具，**不是预测器**。任何 UI 文案都不得暗示能提高中奖概率。后端 Rust（axum + SQLite），前端 Flutter（Windows/Web/Android），无 Node 构建链。Android APK 内置同一套 Rust 后端与历史数据库，离线可用。

## 架构

- `backend/src/`
  - `main.rs` — 独立服务：启动、静态文件服务、自动同步调度
  - `lib.rs` — 共享 `build_router` / `spawn_auto_sync`：空库全量同步，之后定时增量拉取最新一期
  - `embedded.rs` — C ABI `lottery_lab_start`，在 Android App 进程内启动 loopback 服务
  - `routes.rs` — REST 路由与错误处理
  - `db.rs` — SQLite（WAL），`Mutex<Connection>`，按 game 隔离
  - `prize.rs` — 手选号码验奖：命中数 → 奖级 / 奖金（复用 `config::prize`）
  - `bets.rs` — 购彩记录（`bets` 表与 `draws` 共享连接）、自动对奖、总账统计
  - `sources.rs` — 福彩官方 JSON、体彩官方 JSON、500.com HTML 解析
  - `stats.rs` — 卡方/正态/gamma/游程/二项分布等数学函数
  - `analysis.rs` — 频率、遗漏、组合结构、9 项随机性检验
  - `strategies.rs` — 8 个策略，`StrategyRunner::predict_variant` 支持多注轮换
  - `backtest.rs` — 严格走查回测、Brier、自助法 ROI 区间
- `frontend/lib/`
  - `main.dart` — 侧边栏 + `IndexedStack` 页面框架
  - `app_state.dart` — 全局状态、内置引擎/远程服务器模式切换
  - `embedded/` — Dart FFI 加载 `liblottery_lab_backend.so`，复制种子 DB 并取得 loopback 端口
  - `pages/` — overview / history / analysis / backtest / tickets / my_bets
  - `widgets/common.dart` — Panel、Ball、StatTile、VerdictChip 等
  - `widgets/bet_card.dart` / `bet_entry_form.dart` / `bet_entry.dart` — 记录卡片、录入表单、号码选择器
  - `models_bet.dart` — Bet / BetStatus / BetSummary 等模型
- `frontend/assets/lottery.db` — 打包进 APK 的种子数据库（`tools/refresh_seed_db.py` 生成）
- `frontend/android/app/src/main/jniLibs/<abi>/` — 交叉编译产物（`tools/build_android_backend.py` 生成）

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
10. **数据服务可在 App 内切换**。Android 默认启动内置引擎（`embedded/`，loopback 随机端口），`Api.defaultBase` 只作为回退；`AppState.setApiBase` / `useEmbeddedBackend` 会持久化 `api_mode` 与远程地址并递增 `dataRevision` 让页面重挂载。后端默认监听 `0.0.0.0:8787`，Android 明文 HTTP 已在 manifest 中开启。
11. **后端与前端 API 契约**以 `README.md` 的表格为准；修改字段时同步更新 Dart 解析。
12. **Android 后端是嵌入式的，不是可选的 UI 演示**。`lottery_lab_start` 在 App 进程内启动完整 axum 服务；不要把它改回“只连电脑”的模式，也不要手工替换 `jniLibs` 里的 `.so`，统一用 `tools/build_android_backend.py` 重新生成。
13. **种子数据库只在缺失时复制**。`embedded_backend_io.dart` 只在 App 私有目录没有 `lottery.db` 时从 assets 复制；不要改成每次启动覆盖，否则用户同步的新数据会丢失。
14. **移动端同步走 webpki 根证书**。`sources.rs` 的 reqwest 使用 `tls_backend_preconfigured` + `webpki-roots`，因为 Android 内置进程没有初始化 `rustls-platform-verifier` 的 JNI Context；改回默认 TLS 会在手机上 panic。
15. **图标由脚本生成**。Android 自适应图标、Web 图标、Windows `.ico` 都来自 `tools/make_icons.py`；不要用 Flutter 默认图标覆盖。
16. **自动同步是常驻的增量任务**。`spawn_auto_sync` 在空库时全量同步，之后只抓官方第一页（`sources::fetch_recent`，30 期）并 upsert；不要把定时检查改回全量翻页。轮询间隔按**北京时间**分档（`lib.rs` 的 `DRAW_WINDOW_*`）：20:00–24:00 开奖窗口内 2 分钟一次，其余时间 10 分钟一次；用固定偏移 +08:00 而不是读本机时区，这样服务器跑在任何时区都对，也不需要时区数据库（Android 内置进程没有 Context）。`LOTTERY_SYNC_INTERVAL_SECS` 可强制指定固定间隔（最小 60 秒）。手动同步分三档：`POST /api/sync` 的 `mode` 为 `recent`（默认，只拉最新一页，顶栏「同步数据」用）、`official`（全部官方页）、`full`（含 500.com 补 2003–2012，「历史开奖」页的「全量重新同步」用）；旧的 `full: true` 字段仍被识别为 `full`。前端每 2 分钟静默刷新 `/api/games`，只有最新期号变化时才递增 `dataRevision` 重挂页面，避免打断正在看的分析/回测结果；自动对奖的结果走独立的 `betsRevision`，只让「我的彩票」页自己刷新。
17. **自动对奖挂在同步之后**。`sync_once` 写入新开奖后立刻调用 `db.check_pending_bets`，用最近 400 期做 (game, issue) → draw 查找并结算该期所有 `pending` 注；纯本地计算、不请求网络、不改 `draws`。已结算的注不会被重算，所以用户手填的 `actual_amount` 不会丢。前端在启动、`didChangeAppLifecycleState(resumed)` 和每 5 分钟的兜底定时器里调 `POST /api/bets/check`，覆盖"App 关着时开奖了"的情况。
18. **`bets` 与 `draws` 共享同一个连接**。`Db::open` 把 `Arc<Mutex<Connection>>` 交给 `BetStore::new`，不要为 `bets` 另开连接：WAL 下单库多写连接会引入锁竞争，而且自动对奖需要和同步写在同一把锁里。
19. **购彩记录只记账，不推荐**。`bets` 表存用户买了什么、中没中；任何文案都不能把它包装成"提高中奖概率"的手段。一、二等奖默认按 `config::prize` 的估值填充并标 `estimated`，只有用户主动填 `actual_amount` 才按实付计账。
20. **`TextField` 在 `Panel` 里必须包 `Material`**。`Panel` 是普通 `Container`，没有 Material 祖先时 `TextField` 直接抛异常（备注输入框踩过）。

## 命令

```bash
cd backend && cargo test && cargo run
cd frontend && flutter analyze && flutter test && flutter run -d windows
cd frontend && flutter build web --release   # 后端会自动挂载 build/web
python tools/subset_font.py                  # 重新生成中文字体子集
python tools/make_icons.py                   # 重新生成 App 图标
python tools/refresh_seed_db.py              # 刷新 APK 种子数据库
python tools/build_android_backend.py        # 交叉编译 Android 内置后端
build_android.bat                            # 一键构建 APK
```

## 数据

- 双色球：2013+ 福彩官方；2003–2012 由 500.com 补齐。
- 大乐透：体彩官方 2007+，销售额/奖池来自 `totalSaleAmount` / `poolBalanceAfterdraw`。
- 运行时 DB：`backend/data/lottery.db`（已 gitignore）。
- APK 种子 DB：`frontend/assets/lottery.db`（由 `tools/refresh_seed_db.py` 从运行时 DB 导出，提交到仓库）。

## Android 构建注意事项

- 内置后端需要 Rust Android target（`aarch64-linux-android` / `armv7-linux-androideabi` / `x86_64-linux-android`）和 NDK；`tools/build_android_backend.py` 会自动定位 NDK 并设置 `CC`/`AR`/linker 环境变量。
- `liblottery_lab_backend.so` 必须保持 16 KB 页对齐（NDK 28 默认满足）。Google Play 上架前用 `llvm-readelf -l` 检查 LOAD 段对齐是否为 `0x4000`。
- Kotlin 增量编译已在 `frontend/android/gradle.properties` 中关闭（`kotlin.incremental=false`）：当 Pub 缓存目录与项目目录不在同一个盘时，Kotlin 增量编译会报 “different roots”。把项目和缓存放到同一盘后可重新打开。
- 构建 APK 时如果 Gradle 依赖下载卡住，给 Gradle 加代理：`JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=<host> -Dhttp.proxyPort=<port> -Dhttps.proxyHost=<host> -Dhttps.proxyPort=<port>" flutter build apk --release`。
- APK 默认使用 debug 签名，可直接安装测试；上架需配置正式签名。
- 通用 APK 约 79 MB；只给自己手机装可用 `flutter build apk --release --target-platform android-arm64` 生成单 ABI 包。
