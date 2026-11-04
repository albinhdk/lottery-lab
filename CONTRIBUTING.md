# 贡献指南

感谢你愿意参与「彩票实验室」。这个项目有两条不可退让的底线，请在动手前读一遍。

## 项目的定位：不是预测器

本项目**不承诺、不暗示、不追求**提高中奖概率。它存在的意义是用统计检验诚实地回答
「彩票开奖到底有没有可利用的规律」，并把结论原样呈现——包括「没有」这个结论。

因此，任何 PR 如果出现下列情况会被直接关闭：

- 文案暗示选号方法、策略、指标能提高中奖概率；
- 把随机性检验的显著性包装成「发现规律」；
- 在购彩记录功能上加入任何「推荐号码」性质的内容（该功能只记账，不推荐）。

## 不可破坏的技术约束

这些约束写在 `AGENTS.md` 里，是踩过坑换来的。改动相关代码前请先读：

1. **回测只能用未来数据之前的历史**。`backend/src/backtest.rs` 中 `history = &draws[..t]`，
   不得为了让回测「效果更好」提前使用 `draws[t]`。
2. **随机性结论必须做多重比较校正**。`analysis::randomness` 用二项分布计算 `overall_p`，
   前端徽标看 `overall_verdict`。不得退回「有 1 项 p<0.05 就报异常」。
3. **奖级表集中在 `backend/src/config.rs`**。一、二等奖是估值，UI 必须显示 `prize_note`。
4. **大乐透 2014 年前的分布异常是历史数据/设备问题**，不是可利用规律，`note` 字段的说明不得删除。
5. **后端与前端 API 契约以 `README.md` 的表格为准**，修改字段时同步更新 Dart 解析。
6. **`bets` 与 `draws` 共享同一个 SQLite 连接**，不要为 `bets` 另开连接。
7. **移动端同步走 webpki 根证书**（`tls_backend_preconfigured` + `webpki-roots`），
   改回默认 TLS 会在 Android 上 panic。
8. **种子数据库只在缺失时复制**，不得改成每次启动覆盖，否则用户同步的新数据会丢失。
9. **自动同步是常驻增量任务**，只抓官方第一页，不得改回全量翻页。

## 本地开发

```bash
# 后端
cd backend && cargo test && cargo run

# 前端
cd frontend && flutter analyze && flutter test && flutter run -d windows
```

完整环境要求见根目录 `README.md` 的「快速开始」。

## 提交 PR 前必须通过

```bash
cd backend  && cargo test
cd frontend && flutter analyze && flutter test
```

另外请自查：

- 没有 `console.log`、`dbg!`、`println!`、`eprintln!`（`eprintln!` 仅限
  `backend/src/embedded.rs` 中 C ABI 的错误上报）等调试残留；
- 没有未完成的 TODO、临时脚本；
- 不提交构建产物（`target/`、`build/`、`dist/`、`jniLibs/` 均已被 `.gitignore` 覆盖）。

新增或修改功能时，请同时补充对应的单元测试。后端测试放 `backend/src/*.rs` 的
`mod tests`，前端测试放 `frontend/test/`。

## Commit Message

首行是中文摘要，不超过 50 字，动词开头；空一行后用 `-` 列出关键改动点，按模块归类。

```text
新增购彩记录的自动对奖

- backend/src/bets.rs：同步写入新开奖后结算该期 pending 注
- backend/src/routes.rs：新增 POST /api/bets/check
- frontend/lib/api.dart：新增 checkBets 客户端方法
```

一个 commit 只做一个主题。不相关的改动请拆成多个 commit。

## 报告安全问题

请**不要**开公开 issue，按 `SECURITY.md` 的流程私下报告。

## 行为准则

参与本项目即视为同意遵守 `CODE_OF_CONDUCT.md`。
