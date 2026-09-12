# Implementation Plan: tier-guard v2 — 动态子代理模型路由

> 基于 [`spec/tier-guard.md`](../../spec/tier-guard.md) 的需求草案。
> 本计划由用户在 2026-09-12 确认进入计划阶段后建立；本仓处于 spec-guard local 模式，
> 不进入远端 tracker。

## Prior implementation status

工作区已有 v1 实现与测试，验证的是“默认 T2、只升不降”的下限守卫。它们保留作宿主事件和
hook 编码的证据，但**不构成 v2 的完成项**。本计划完成前，不将现有 `Task 4b` 或任何既有
冒烟结果表述为动态路由已经交付。

## Architecture decisions

- 主代理不换 model 或 effort；路由只发生在子代理创建前。
- core 接受标准化 `RouteRequest`，独立选择目标候选，不以请求模型作为路由起点。
- 显式 pin 默认不改写；未 pin 的目标可能高于、低于或等于请求参数。
- 模型目录只存能力、可用性与成本事实；策略根据本次任务动态选择最低合格候选。
- agent-skills 是可选、显式的上下文 provider；spec-guard 仅是本仓开发流程，不是运行时依赖。
- semantic provider 先只定义受约束接口和“未配置”行为；不在本计划中联网、取凭据或发送任务原文。
- hook adapter 必须在真实派发前改写参数才能启用 auto；Codex Desktop 已验证主代理明文预路由的三档实际派发，但 hook 因接收不透明令牌仍保持 advisory。

## Dependency graph

```text
RouteRequest + model catalog
          ↓
pure route decision + contract tests
          ├─────────────┬─────────────┐
          ↓             ↓             ↓
  Claude adapter   Codex CLI adapter   optional context/provider interface
          └─────────────┴─────────────┘
                        ↓
              audit/report migration
                        ↓
         real-host verification and documentation
```

## Task list

### Phase 1: Contract and pure routing core

#### Task 1: Define route request, decision, catalog, and pin contracts

**Description:** Replace v1 tier/start/floor configuration with a versioned model catalog and a normalized route contract. Keep all task text in memory unless a host explicitly chooses audit hashing.

**Acceptance criteria:**

- [x] Config represents eligible candidates, capability facts, costs and host availability independently from task classification.
- [x] `RouteRequest` and `RouteDecision` schemas cover pin, evidence source, confidence, fallback and host capability.
- [x] No configuration invariant encodes “only raise”, “T1/T2 same slug”, or a blanket ban that is not user policy.

**Verification:**

- [x] Focused config/schema tests reject invalid catalog entries and accept an eligible low-cost candidate.
- [x] Existing v1 config is either migrated explicitly or rejected with an actionable migration error.

**Dependencies:** None.
**Files likely touched:** `config/routing.default.json`, `hooks/route_decide.py`, `spec/tier-guard.md`.
**Estimated scope:** M.

#### Task 2: Implement deterministic dynamic classification and selection

**Description:** Make the pure core classify task signals independently, filter candidates by hard constraints, then select the least-cost qualifying candidate. Add conservative behavior for absent task text, unknown signals, and low confidence.

**Acceptance criteria:**

- [x] Equivalent task input and catalog version produce the same decision and explanation.
- [x] A clear low-risk task can choose a lower-cost candidate even when request parameters were higher.
- [x] A complex, ambiguous, external or irreversible task cannot choose a candidate below its computed requirement.
- [x] Pin returns an advisory decision without a parameter rewrite target.

**Verification:**

- [x] New positive, negative and unknown-input cases run through the pure core self-test or dedicated test file.
- [x] Mutation checks cover accidental reintroduction of start-tier or only-raise behavior.

**Dependencies:** Task 1.
**Files likely touched:** `hooks/route_decide.py`, `hooks/test-tier-guard.sh`, `scripts/mutation-check.py`.
**Estimated scope:** M.

### Checkpoint: Core policy review

- [x] Contract and all deterministic route cases pass locally.
- [x] Human review confirms low-cost selection, pin semantics and conservative unknown handling before adapters change.

### Phase 2: Host adapters

#### Task 3: Adapt Claude pre-dispatch behavior

**Description:** Translate a v2 decision into Claude’s hook payload without changing non-routing parameters. Preserve explicit pin, audit mode and fail-open behavior.

**Acceptance criteria:**

- [x] `audit` writes the decision but never rewrites `model`.
- [x] `auto` rewrites an unpinned Agent call to the selected target, including a lower-cost target when eligible.
- [x] A pinned request, malformed payload or unavailable catalog never changes the call.

**Verification:**

- [x] `hooks/test-tier-guard.sh` covers lower, equal, higher, pinned and fallback decisions.
- [x] Full validation remains green after this task.

**Dependencies:** Task 2.
**Files likely touched:** `hooks/claude_hook.py`, `hooks/test-tier-guard.sh`, `hooks/tier-guard.sh`.
**Estimated scope:** M.

#### Task 4: Adapt Codex CLI pre-dispatch behavior

**Description:** Apply a v2 decision to native Codex CLI `spawn_agent` parameters while preserving Codex’s `permissionDecision: allow` encoding and its host capability limits.

**Acceptance criteria:**

- [x] An eligible unpinned simple task can change both slug and effort to the selected low-cost candidate.
- [x] A complex task can select a higher candidate when the catalog permits it.
- [x] Pin, malformed input and unsupported host capability remain non-mutating with an explicit audit state; inherited child settings are unpinned and can be selected dynamically.

**Verification:**

- [x] Pure-route contract covers lower/equal/higher decisions; `hooks/test-tier-guard-codex.sh` covers host selection, pin and unknown input.
- [x] A fixture proves `updatedInput` retains every non-routing spawn argument.

**Dependencies:** Task 2.
**Files likely touched:** `hooks/codex_hook.py`, `hooks/test-tier-guard-codex.sh`, `hooks/codex-hooks.json`.
**Estimated scope:** M.

### Checkpoint: Adapter review

- [x] Claude and Codex thin-shell suites pass.
- [x] Both adapters consume the same pure decision and differ only in host encoding.
- [x] Desktop remains explicitly marked advisory; no desktop auto claim is added.

### Phase 3: Optional context and observability

#### Task 5: Add versioned optional-context and semantic-provider interfaces

**Description:** Define a strict agent-skills context envelope and a semantic-provider abstraction. Implement only the no-provider path; do not send task text externally or add credentials.

**Acceptance criteria:**

- [x] Context from an unknown source/version is ignored safely and recorded as unavailable.
- [x] Valid agent-skills metadata can improve a decision without being required for core routing.
- [x] No source code reads `.agent/state.json` or invokes spec-guard.
- [x] Provider absence produces a deterministic conservative outcome.

**Verification:**

- [x] Tests cover absent, malformed and valid optional context.
- [x] Repository search demonstrates no runtime references to spec-guard state or commands.

**Dependencies:** Task 2.
**Files likely touched:** `hooks/route_decide.py`, `config/routing.default.json`, `skills/tier-routing/SKILL.md`.
**Estimated scope:** M.

#### Task 6: Migrate audit, reporting and mode controls

**Description:** Replace v1 “raise/floor violation” reporting with v2 decision/actual/quality fields. Keep privacy-safe task fingerprints and distinguish advisory from applied decisions.

**Acceptance criteria:**

- [x] Reports separate selected, requested and actual model/effort.
- [x] Reports never infer token cost when a host did not provide it.
- [x] `off`, `audit`, `auto`, pin and unsupported-host behavior are visible in output.

**Verification:**

- [x] Command and observability suites cover migrated records plus a backward-compatible v1 record if retained.
- [x] Reports remain resilient to malformed or partial logs.

**Dependencies:** Tasks 3–5.
**Files likely touched:** `hooks/tier_report.py`, `hooks/tier_state.py`, `hooks/test-tier-commands.sh`, `hooks/test-tier-observe.sh`.
**Estimated scope:** M.

### Checkpoint: Local full validation

- [x] `/bin/bash scripts/validate.sh` passes.
- [x] `python3 scripts/mutation-check.py` passes.
- [x] Documentation and skill text do not retain “default T2” or “only raise” as product policy.

### Phase 4: Real-host evidence and release readiness

#### Task 7: Prove Codex CLI lower-cost child execution

**Description:** Run an isolated interactive Codex CLI case that asks for a simple unpinned child task, then compare decision log, hook output and child’s actual model/effort.

**Acceptance criteria:**

- [ ] The child actually starts with the selected lower-cost candidate, not merely a suggested value.
- [ ] Evidence records host version, working directory, start/end time, task fingerprint and actual parameters.
- [ ] Failure to observe pre-dispatch application leaves CLI auto status unverified rather than passing by assertion.

**Verification:**

- [ ] Reproducible smoke command or documented manual protocol passes.
- [ ] Result is recorded in a research document without raw sensitive task text.

**Dependencies:** Tasks 4 and 6.
**Files likely touched:** `docs/research/`, `evals/` or `hooks/test-tier-guard-codex.sh`.
**Estimated scope:** S.

**2026-09-12 evidence:** [`Task 7 CLI v2 smoke`](../../docs/research/2026-09-12-task7-codex-cli-v2-smoke.md)
now proves a real CLI 0.154.0 `updatedInput` receipt (`terra/high` parent → `terra/xhigh` child),
while the low-cost-candidate acceptance remains intentionally unchecked.

**2026-09-13 status:** 原生 CLI 的 hook 边界把子任务替换为 `opaque_token`，因此 hook 不可安全地按
任务语义选择 Luna；即使 CLI 已证实接受 `updatedInput`，本项“hook 独立低成本实际执行”仍被该宿主输入
边界阻断，不能以猜测升/降档来满足验收。与此分开的可用路径是主代理在明文阶段使用同一能力目录预路由；
Codex Desktop 与 CLI 都已实际回执 `luna/medium`、`terra/high`、`terra/xhigh` 三档，详见
[`v2 compatibility status`](../../docs/research/2026-09-12-v2-compatibility-status.md)。这不改变本项的
未完成状态，也不授权开启生产 `auto`。

#### Task 8: Publish compatibility status and desktop escalation evidence

**Description:** Align docs, diagnostics and release criteria with actual host evidence. Preserve the advisory boundary and define the evidence needed to upgrade a host from audit to automatic.

**Acceptance criteria:**

- [x] CLI, Desktop and Cloud are each labeled with independently supported capability status.
- [x] No document claims Desktop automatic routing while the V2 pre-dispatch gap remains.
- [x] Doctor output directs users to evidence, not self-reported plugin state.

**Verification:**

- [x] Documentation checks and focused doctor tests pass.
- [x] A reviewer can trace each host claim to a reproducible evidence file.

**2026-09-13 status:** the [v2 compatibility table](../../docs/research/2026-09-12-v2-compatibility-status.md)
labels every host independently. Claude Code CLI `2.1.269` now has a real low-cost Haiku receipt and may
open its host capability gate while staying default-audit; Codex Task 7's independent low-cost hook receipt
remains open because its V2 input is opaque. This task preserves that distinction rather than converting it
into a broad routing claim.

**Dependencies:** Tasks 6 and 7.
**Files likely touched:** `commands/tier_doctor.md`, `hooks/tier_doctor.py`, `docs/research/`, `skills/tier-routing/SKILL.md`.
**Estimated scope:** M.

### Final checkpoint: v2 review

- [ ] All plan acceptance criteria and repository validation pass.
- [x] A fresh reviewer verifies model selection can move down as well as up.
- [ ] Real-host evidence exists for every claimed automatic host.
- [ ] Semantic-provider network integration remains disabled unless separately approved.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Semantic classifier itself costs more than it saves | High | Run only in gray cases; no provider by default; require cost/quality evidence before enablement. |
| Model catalog claims outlive host availability | High | Version catalog, capability-detect at adapter boundary, fail closed to advisory. |
| Desktop V2 does not apply updatedInput | High | Preserve advisory status; require pre-dispatch parameter-application evidence; do not emulate enforcement post-spawn. |
| agent-skills/spec-guard coupling leaks into runtime | Medium | Explicit envelope only; automated repository scan forbids state/command references. |
| An incorrect low route silently lowers quality | High | Conservative unknown handling, pin, audit rollout, labels and sampled quality checks. |

## Sequencing

Tasks 1 → 2 are sequential. Tasks 3, 4 and 5 may proceed after Task 2 but all touch the route contract and should be reviewed serially in this single working tree. Task 6 follows their settled record shape. Tasks 7 and 8 come last because they must validate the code actually installed in each host, not just repository tests.
