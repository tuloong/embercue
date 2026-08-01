# MR Review - main 2026-08-01 20:45 Asia/Shanghai

- 风险等级: full（辅助功能权限、全局事件监听、持久化同意状态）
- 改动行数: 658（新增 624 / 删除 34，审查时点）
- 改动文件: 7 个生产/测试/文档文件，另含 discovery 与 plan 工件
- 涉及领域: Sources, Tests, README, permissions
- 调用的 reviewer: code-reviewer, security-reviewer, test-engineer
- 模式: 正常

## P1（必须修复）

无。测试 reviewer 首轮指出授权返回桥未被执行级测试覆盖；现已通过真实 `NSApplication.didBecomeActiveNotification` → production relay → coordinator refresh 的测试修复，并验证重复通知只启动一次监听器。

## P2（应该修复）

无未处理项。

- code reviewer 首轮指出全局监听回调在主 actor 外修改状态；现已把 modifier/timestamp 采样后的状态机与 action 一并切回 `MainActor`。
- code reviewer 复核建议监听器注册失败时保留 opt-in。协调结论为不采纳：注册失败即功能从未启用，清除 opt-in 并显示可重试错误更符合保守同意边界，避免后续启动在 UI 显示 disabled 后静默开始监听。该分支有失败与重试测试。

## P3（建议改进）

无未处理项。activation relay 测试已从固定 20ms 等待改为 callback 计数与明确 1 秒 deadline 的条件循环。

## 各 reviewer 摘要

### code-reviewer

- 命中: 3（actor 竞态已修、测试等待已修、opt-in 建议经安全边界裁决不采纳）
- 关键结论: 生产状态机与 activation relay 无阻断缺陷。

### security-reviewer

- 命中: 1（nullable monitor token 已修）
- 关键结论: 复核后无 P1/P2/P3；显式 opt-in、禁止 launch prompt、撤权停止、可取消等待状态均符合边界。

### test-engineer

- 命中: 首轮 1 P1 + 4 P2，全部补齐后复核为无 P1/P2/P3。
- 关键结论: 已覆盖真实 activation 通知、exactly-once、Disable/stop、撤权、错误恢复、注册失败、UserDefaults 重建与菜单状态。

## Coordinator 结论

- 是否建议保留改动: 是
- 阻塞项: 无
- 人工确认点（权限相关）: 当前 ad-hoc 构建必须由用户向精确 app bundle 授予 Accessibility；真实 TCC grant/return 与外部应用双击 Shift 捕获必须在该授权后手工确认。

## 后续动作

- [x] 修复 P1
- [x] 补充 P2 测试
- [x] 重新执行三路 review
- [ ] 在当前 packaged build 获得用户授权后完成真实 TCC/双击 Shift QA
