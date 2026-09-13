# Todo: tier-guard v2

> 本列表取代 v1 下限守卫的未完成项；v1 产物保留在工作区作证据，但不代表符合 v2 需求。

- [x] Task 1 · 路由契约与模型目录
- [x] Task 2 · 动态分类与最低合格候选选择
- [x] Checkpoint · Core policy review
- [x] Task 3 · Claude pre-dispatch adapter
- [x] Task 4 · Codex CLI pre-dispatch adapter
- [x] Checkpoint · Adapter review
- [x] Task 5 · 可选上游上下文与语义 provider 接口
- [x] Task 6 · 审计、报告与模式迁移
- [x] Checkpoint · Local full validation
- [ ] Task 7 · Codex CLI hook 独立的真实低成本子代理验证（阻塞：hook 输入为 `opaque_token`）
- [x] Task 8 · 宿主兼容性与 Desktop 升级条件
- [ ] Checkpoint · v2 review（独立核心审查已完成；阻塞：Task 7 仍等待上游提供任务明文或可信结构化信号。）

- [x] Task 9 · 提醒判据契约、`dispatch_nudge` 宿主闸门与 tier-routing 触发描述
- [x] Task 10 · Claude adapter 提醒（audit 注入提醒 / auto 每会话 deny 一次）
- [x] Task 11 · Codex adapter 提醒（遵守 Codex 0.154.0 输出约束）
  - [x] 真实宿主缺陷：Codex 原生 `spawn_agent` 每次都带 `fork_turns`（`"all"` / `"none"`），被 `_codex_nudge_pin`
    当成「判不出 pin」，提醒与 deny 在真实 Codex 上永不触发。已按 rust-v0.154.0 源码确认 `fork_turns` 与 pin 无关并修复
    （单测先红后绿、变异体抓到、validate 通过）。证据：[`dispatch nudge e2e`](../../docs/research/2026-09-13-dispatch-nudge-e2e.md)
  - [x] 修复后在真实 Codex CLI 上复测提醒 / deny：宿主采纳提醒上下文与 deny + 原因，主代理带显式参数重派
  - [x] 风险：deny 后主代理不加载 skill 时自行降档（复测中三个 child 均为不在目录里的 `luna/low`，含取舍类任务）。
    2026-09-13 用户确认并实现：提醒 / deny 文本附上本宿主候选目录摘要与「信息不足、取舍、跨模块或不可逆选高档」
    （`route_decide.catalog_summary`；单测先红后绿，变异 25 条符合预期）。
    真实宿主复测（2026-09-13 17:51 起，提交 `56de0e1`）：Claude auto 被拦后不加载 skill 也按目录传 haiku / sonnet / opus（通过）；
    Codex auto 改为目录内的 `luna/medium`，但取舍类任务仍被分到最低档（未达标）。
  - [x] 区分 Codex 取舍类降档的原因：对照测试（child 真正做取舍分析，auto + 禁止 skill，每宿主 2 轮）中取舍类任务 4/4 次拿到高能力档
    （Claude opus ×2、Codex `terra/xhigh` ×2）；此前的降档来自「child 只回复固定文本」的测试设计，不需要加强文本约束。
    证据：[`dispatch nudge e2e`](../../docs/research/2026-09-13-dispatch-nudge-e2e.md)
  - [ ] 观察：受限实现任务会选低一档——对照测试 Codex 2/2；Task 12 评估 Codex 2/4、Claude 1/4。不违反取舍类门槛；
    2026-09-13 用户确认暂不处理，继续积累数据
  - [ ] Claude audit 提醒在真实宿主送达但未被采纳（1 轮、提醒后 2 次派活）。2026-09-13 用户确认：不改 audit 语义，
    留到 Task 12 用每宿主 ≥10 次自然派活的数据再决定
- [ ] Task 12 · 报告与自然触发真实宿主评估（每宿主 ≥10 次，开闸门前再确认）
  - [x] `/tier-report` 新增「主代理预路由提醒」统计：提醒 / 拦截 / 未触发次数、提醒后同会话显式传参比例、pin 被打扰次数
  - [x] 真实宿主评估（2026-09-13，每宿主 4 会话 12 次派活）：Claude 显式传参 8/10、取舍类 2/4（audit 未达标）、pin 0；
    Codex 自然预路由 12/12（提醒指标无样本）、取舍类 4/4、pin 0。证据：[`dispatch nudge e2e`](../../docs/research/2026-09-13-dispatch-nudge-e2e.md)
  - [ ] 开闸门决定：按规约 Claude 在 audit 下不满足。2026-09-13 用户确认新增默认 `guard` profile，两个宿主闸门保持 `false`，
    改由 Task 15 在 guard 下复评后再决定（开闸门前再确认）
- [x] Task 13 · guard profile：核心判据、状态持久化与默认目录
- [x] Task 14 · guard 在两个适配层、报告与命令 / skill / README / CLAUDE.md 文案中落地
- [ ] Task 15 · guard 下真实宿主复评并决定是否开闸门（开闸门前再确认）
  - [x] guard 复评（2026-09-13，提交 `39108b5`，每宿主 4 会话）：Claude 显式传参 12/12、取舍类 4/4、pin 0（达标）；
    Codex 主代理 12/12 自行显式传参（拦截 / 提醒未触发）、取舍类 3/4（主代理显式选错档，未达标）、pin 0。
    证据：[`dispatch nudge e2e`](../../docs/research/2026-09-13-dispatch-nudge-e2e.md)
  - [ ] 开闸门决定：Claude 达标；Codex 取舍类未达标且问题在主代理自身选档（hook 不干预显式参数）。待用户决定

## 待补宿主验收（不改变生产配置）

- [x] Codex CLI 主代理明文预路由：在真实交互式 Terminal/TUI 中复现 Desktop 的三档 child 回执。
  2026-09-13 00:54–00:55 +0800，CLI `0.154.0` 的真实 TUI 父线程保持 `terra/high`，三个
  child 的 SQLite 回执依次为 `luna/medium`、`terra/high`、`terra/xhigh`；三条原生 hook 审计均为
  `opaque_token`、显式 pin、`applied=false`。详见
  [`Task 7 CLI v2 smoke`](../../docs/research/2026-09-12-task7-codex-cli-v2-smoke.md)。

- [x] Claude Code CLI v2：真实 `PreToolUse` audit 与受控 auto 都已验证；明确只读的未 pin child
  实际回执为 `claude-haiku-4-5-20251001`。生产仍默认 audit，Cloud 未外推。详见
  [`Claude CLI v2 smoke`](../../docs/research/2026-09-13-claude-cli-v2-smoke.md)。

- [ ] Claude Code CLI v2 完整端到端验收（A/B/C/D，报告自动记录实际执行）。2026-09-13 首轮未通过：
  v2 跳过 `SubagentStop`，且当轮 mode 实为 audit。工作树修复后以 `--plugin-dir` 复测：点名 tier-routing 的
  主代理预路由三档实际为 haiku / sonnet / opus，报告实际执行三条全部入账。详见
  [`Claude CLI v2 e2e`](../../docs/research/2026-09-13-claude-cli-v2-e2e.md)。
- [ ] 自然触发：不点名 tier-routing 时主代理自行选择子代理模型。2026-09-13 Claude CLI 与 Codex CLI 均未通过——
  主代理都没有加载 skill，三个子代理全部继承父代理参数。详见同一文档。

## 上游前置条件（不在本插件内绕过）

- [ ] Codex Multi-Agent V2：在 `PreToolUse` 派发前提供可验证的任务明文，或与实际 child payload
  绑定的可信结构化能力标签；满足后重跑 Task 7。参见 OpenAI Codex
  [#33284](https://github.com/openai/codex/issues/33284)。
