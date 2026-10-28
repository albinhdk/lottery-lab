# 彩票实验室 · Lottery Lab

一个**不承诺预测**的彩票数据分析与回测工具。后端 Rust，前端 Flutter（Windows 桌面 + Web）。

支持中国福利彩票「双色球」与中国体育彩票「超级大乐透」，内置 2003 年至今的官方历史数据同步、频率/遗漏/组合结构分析、9 项随机性检验，以及 8 个选号策略的严格走查回测。

> 彩票开奖是独立随机事件。任何选号方法都不会提高中奖概率。本工具的价值在于**用统计检验回答“到底有没有规律”**，并把结果诚实地摆出来。

![数据概览](docs/overview.png)

| 频率热力图 | 策略回测 |
|---|---|
| ![频率分布](docs/frequency.png) | ![策略回测](docs/backtest.png) |

| 手机 · 数据概览 | 手机 · 历史开奖 |
|---|---|
| ![手机概览](docs/mobile-overview.png) | ![手机历史](docs/mobile-history.png) |

---

## 功能

### 数据
- 双色球：福彩官方接口（2013 至今）+ 500.com 历史表补齐 2003–2012，共 3520 期
- 超级大乐透：体彩官方接口，2007 年至今 2940 期
- 本地 SQLite 缓存，支持一键同步、按期号检索、日期范围筛选、分页浏览、CSV 导出

### 统计
- **频率分布**：每个号码的出现次数、z 分数、当前遗漏、平均/最大间隔、χ² 均匀性检验、归一化熵
- **遗漏分析**：当前遗漏排序、理论平均间隔、历史最大遗漏
- **组合结构**：和值分布与精确组合分布对比、奇偶、大小、连号、跨度、AC 值
- **随机性检验（9 项）**：号码均匀性、和值分布拟合、和值均值 z 检验、一阶自相关、游程检验、相邻期重号、号码间隔几何分布、Shannon 熵、蒙特卡洛校准
- **多重比较校正**：9 项检验同时进行时，用二项分布计算“至少出现这么多显著项”的整体概率，避免把正常的假阳性当成规律

### 回测
- 8 个策略：随机基线、热号、冷号、遗漏回补、频率加权、共现马尔可夫、在线逻辑回归、结构均衡选号
- **严格走查**：预测第 t 期时只使用前 t−1 期数据，无未来数据泄露
- 指标：平均命中 vs 理论期望、z 值、p 值、ROI 及自助法 95% 置信区间、Brier 分数 vs 随机基线、奖级分布、累计盈亏曲线
- 结果会明确告诉你：没有任何策略能稳定跑赢随机基线

### 选号
- 按策略生成号码，支持一次多注、一键复制
- 生成结果附带概率说明与免责声明

---

## 技术栈

| 层 | 技术 |
|---|---|
| 后端 | Rust 2024 · axum 0.8 · rusqlite（bundled） · reqwest · rand/ChaCha8 |
| 前端 | Flutter 3.47 · Dart 3.13 · fl_chart · http |
| 数据 | SQLite（WAL 模式，`backend/data/lottery.db`） |
| 字体 | Noto Sans SC 子集（内置，约 1.2 MB/字重，SIL OFL） |

---

## 快速开始（Windows）

### 环境
- Rust 1.85+（`cargo --version`）
- Flutter 3.35+，并启用 Windows 桌面支持（`flutter doctor`）
- Visual Studio 2022 生成工具（Flutter Windows 构建需要）

### 运行

```bat
:: 1. 启动后端（首次启动会自动同步历史数据，约 30 秒）
cd backend
cargo run

:: 2. 另开一个终端，启动桌面应用
cd frontend
flutter run -d windows
```

或者直接双击根目录的 `run.bat`：它会启动后端并打开已构建的桌面程序（若尚未构建则回退到 `flutter run`）。

### 构建发布版

```bat
build.bat
```

产物：
- 后端：`backend/target/release/lottery_lab_backend.exe`
- 桌面端：`frontend/build/windows/x64/runner/Release/lottery_lab_app.exe`

### Web 模式

```bat
cd frontend
flutter build web --release
```

后端启动时会自动把 `frontend/build/web` 挂到 `http://127.0.0.1:8787/`，浏览器直接打开即可。

### Android APK

1. 电脑端启动后端（默认监听 `0.0.0.0:8787`，手机才能访问）：
   ```bat
   cd backend
   cargo run
   ```
   首次运行 Windows 防火墙会询问，请允许「专用网络」访问。
2. 手机与电脑连接同一个 Wi-Fi。
3. 安装 `frontend/build/app/outputs/flutter-apk/app-release.apk`。
4. 打开 App，点右上角齿轮，填写电脑的局域网地址（例如 `http://192.168.1.10:8787`），点「保存并连接」。
   构建时已预填本机当时的局域网地址，IP 变化后在 App 内改即可。

> 手机端使用底部导航，桌面/Web 使用左侧栏；两套布局共用同一份代码。
> APK 使用 debug 签名，适合自己安装测试；上架应用商店需要换成正式签名。

---

## 配置

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `LOTTERY_DB` | `data/lottery.db` | SQLite 路径（相对后端工作目录） |
| `LOTTERY_ADDR` | `0.0.0.0:8787` | 监听地址（默认对局域网开放，手机 APK 才能连接；仅本机使用可设为 `127.0.0.1:8787`） |
| `LOTTERY_WEB_DIR` | `../frontend/build/web` | Web 构建目录 |
| `API_BASE`（Flutter 编译期） | `http://127.0.0.1:8787` | `flutter build web --dart-define=API_BASE=...` |

---

## API 一览

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/health` | 健康检查 |
| GET | `/api/games` | 彩种定义、期数、最新一期 |
| GET | `/api/draws?game=&page=&page_size=&q=&from=&to=` | 历史开奖分页 |
| GET | `/api/draws/{game}/{issue}` | 单期详情 |
| GET | `/api/draws/export?game=` | CSV 导出 |
| GET | `/api/stats/frequency?game=&window=` | 频率分布 |
| GET | `/api/stats/gaps?game=` | 遗漏 |
| GET | `/api/stats/combinations?game=` | 组合结构 |
| GET | `/api/stats/randomness?game=&window=&simulations=` | 随机性检验 |
| GET | `/api/strategies` | 策略列表 |
| POST | `/api/backtest` | 走查回测 |
| POST | `/api/tickets` | 生成号码 |
| POST | `/api/sync` | 同步官方数据 |
| POST | `/api/import` | 导入 CSV（`issue,date,primary,secondary`，号码空格分隔） |

回测请求示例：

```json
{
  "game": "ssq",
  "strategies": ["random", "hot", "cold", "overdue", "weighted", "markov", "logistic", "balanced"],
  "train_window": 500,
  "test_size": 300,
  "tickets_per_draw": 1,
  "seed": 42
}
```

---

## 数据说明与已知现象

- **一、二等奖为浮动奖金**。回测按双色球一等奖 700 万、二等奖 15 万，大乐透一等奖 1000 万、二等奖 15 万估算；三至六/九等奖为官方固定奖金。因此 ROI 只具有量级参考意义。
- **大乐透 2014 年前后的分布差异**：2007–2013 年前区号码明显偏向大号（χ²≈234，df=34），2014 年后恢复正常（χ²≈33.5）。这更可能是历史摇奖设备/规则变更，而不是可利用的规律。工具在「随机性检验」页提供了窗口切换（最近 300/500/1000 期/全部历史），并会在结论中提示非平稳性。
- **数据源**：福彩 `cwl.gov.cn`、体彩 `webapi.sporttery.cn`、500.com 历史表。网络失败时可在界面点「同步数据」重试。

---

## 测试

```bash
# 后端：统计函数、组合分布、策略合法性、回测基线
cd backend && cargo test

# 前端：组件与概率公式
cd frontend && flutter test
cd frontend && flutter analyze
```

当前状态：后端 14 个单元测试全部通过，前端 2 个测试通过，`flutter analyze` 无告警。

---

## 目录结构

```
lottery-lab/
├── backend/                  # Rust API 服务
│   ├── src/
│   │   ├── main.rs           # 启动、静态文件、自动同步
│   │   ├── routes.rs         # REST 路由
│   │   ├── db.rs             # SQLite 封装
│   │   ├── models.rs         # Draw / Prediction
│   │   ├── config.rs         # 彩种定义、奖级表
│   │   ├── sources.rs        # 官方数据抓取与 500.com 解析
│   │   ├── stats.rs          # 卡方、正态、gamma、游程、二项分布
│   │   ├── analysis.rs       # 频率、遗漏、组合结构、随机性检验
│   │   ├── strategies.rs     # 8 个策略
│   │   └── backtest.rs       # 走查回测与指标
│   └── data/lottery.db       # 运行时生成
├── frontend/                 # Flutter 应用
│   └── lib/
│       ├── main.dart         # 侧边栏 + 页面框架
│       ├── api.dart          # HTTP 客户端
│       ├── app_state.dart    # 全局状态
│       ├── models.dart       # 数据模型
│       ├── theme.dart        # 深色主题
│       ├── pages/            # 概览 / 历史 / 分析 / 回测 / 选号
│       └── widgets/          # 球、面板、徽标等
├── docs/                     # 截图
├── run.bat                   # 启动后端 + 桌面端
└── build.bat                 # 构建发布版
```

---

## 免责声明

本项目仅用于统计学习与数据分析，不构成任何购彩建议。彩票具有随机性与负期望，请理性购彩、量力而行；未成年人不得购买彩票。
