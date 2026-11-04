# 第三方资产归属

本项目包含下列非本项目原创的资产。它们**不**随项目源码一起适用 MIT 许可，
需按各自原始许可使用。下表说明每一项的来源与许可。

## 1. Noto Sans SC 字体子集

| 项 | 值 |
|---|---|
| 文件 | `frontend/assets/fonts/NotoSansSC-Regular.ttf`、`frontend/assets/fonts/NotoSansSC-Bold.ttf` |
| 上游项目 | [Noto Sans SC](https://github.com/notofonts/noto-cjk)（Google Fonts） |
| 许可 | [SIL Open Font License 1.1](https://openfontlicense.org/) |
| 本项目的改动 | 由 `tools/subset_font.py` 做字符子集化，仅保留源码字符与 GB2312 一级字库，以减小包体 |
| 许可影响 | 子集仍属衍生作品，OFL 1.1 允许嵌入与再分发，但**禁止单独售卖字体本身**，且不得更改保留字体名称（Reserved Font Name）。若重新生成子集，请保留本表及 `frontend/README.md` 中的说明 |

## 2. 公开彩票开奖数据

| 项 | 值 |
|---|---|
| 来源 | 中国福利彩票官方网站 `cwl.gov.cn`；中国体育彩票官方接口 `webapi.sporttery.cn`；`datachart.500.com` 历史表（双色球 2003–2012 补缺） |
| 分发形式 | `frontend/assets/lottery.db`（APK 种子数据库，由 `tools/refresh_seed_db.py` 从运行时数据库导出）与 `frontend/assets/lottery_seed.json` |
| 性质 | 客观事实数据（开奖号码与期号），不含原创性表达 |
| 使用约束 | 仅供个人统计学习与数据分析。本项目不对数据的准确性、完整性、时效性作任何担保，也不代表数据提供方认可本项目。使用、再分发该数据前请自行确认其网站的 robots 规则与使用条款 |

## 3. Rust / Dart 依赖

`backend/Cargo.toml` 与 `frontend/pubspec.yaml` 的全部第三方依赖均在各自上游许可下分发，
许可文本随包发布。构建可复现版本请使用仓库中已提交的 `backend/Cargo.lock` 与
`frontend/pubspec.lock`。

## 4. 图标

`docs/icon.png` 与 Android 自适应图标由 `tools/make_icons.py` 程序化生成，属本项目原创，
适用 MIT 许可。
