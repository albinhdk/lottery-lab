name: Pull Request

描述清楚这个 PR 做了什么、为什么这么做。

## 类型

- [ ] 缺陷修复
- [ ] 新功能
- [ ] 文档
- [ ] 重构（不改变外部行为）
- [ ] 构建 / 工具链

## 检查清单

提交前请逐项确认：

- [ ] 已在本地通过 `cd backend && cargo test`
- [ ] 已在本地通过 `cd frontend && flutter analyze && flutter test`
- [ ] 无调试残留（`console.log`、`dbg!`、`println!` 等）
- [ ] 若改动了 API，已同步更新 `README.md` 的 API 表格与 Dart 解析
- [ ] 若改动了奖级或估值，UI 仍显示 `prize_note`
- [ ] 未触碰 `AGENTS.md` 中列出的硬约束（回测不用未来数据、多重比较校正、
      `bets` 与 `draws` 共享连接、webpki 根证书、种子 DB 不覆盖等）
- [ ] 新增/修改功能已补充单元测试
- [ ] 一个 PR 只做一个主题

## 关联 Issue

Closes #（issue 编号，如有）
