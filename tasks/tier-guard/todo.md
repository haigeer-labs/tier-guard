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
- [ ] Checkpoint · v2 review（阻塞：Task 7 仍等待上游提供任务明文或可信结构化信号。）

## 待补宿主验收（不改变生产配置）

- [x] Codex CLI 主代理明文预路由：在真实交互式 Terminal/TUI 中复现 Desktop 的三档 child 回执。
  2026-09-13 00:54–00:55 +0800，CLI `0.154.0` 的真实 TUI 父线程保持 `terra/high`，三个
  child 的 SQLite 回执依次为 `luna/medium`、`terra/high`、`terra/xhigh`；三条原生 hook 审计均为
  `opaque_token`、显式 pin、`applied=false`。详见
  [`Task 7 CLI v2 smoke`](../../docs/research/2026-09-12-task7-codex-cli-v2-smoke.md)。

- [x] Claude Code CLI v2：真实 `PreToolUse` audit 与受控 auto 都已验证；明确只读的未 pin child
  实际回执为 `claude-haiku-4-5-20251001`。生产仍默认 audit，Cloud 未外推。详见
  [`Claude CLI v2 smoke`](../../docs/research/2026-09-13-claude-cli-v2-smoke.md)。

## 上游前置条件（不在本插件内绕过）

- [ ] Codex Multi-Agent V2：在 `PreToolUse` 派发前提供可验证的任务明文，或与实际 child payload
  绑定的可信结构化能力标签；满足后重跑 Task 7。参见 OpenAI Codex
  [#33284](https://github.com/openai/codex/issues/33284)。
