# Spec: tier-guard

> 状态：**待评审**（spec-driven-development Phase 1 产物）。
> 评审通过前不写实现代码。

## Objective

**按任务分级选择模型，并用机制保证不会在需要高级模型的地方用低级模型。**

- **目标**：把算力花在需要判断的地方，减少 token 消耗
- **硬约束**：绝不欠配。该用 opus 的地方用了 sonnet，比多花钱严重得多 ——
  欠配的表现不是报错，是**悄悄做出一个看起来对的错东西**
- **优先级**：硬约束 > 目标。任何取舍向"不欠配"倾斜

### 为什么需要它（实测依据，2026-08-28）

| 事实 | 数据 |
|---|---|
| 近 3 天主会话 Opus 输出 | 25.07M token |
| 同期缓存读 | 7,004M token（**平均每条消息 276.9k**） |
| subagent 占比 | **0.0%** —— `isSidechain` 字段出现 114,854 行，`true` 0 行 |

19 个配好模型的 subagent（7 sonnet / 2 haiku / 10 opus）**一次都没跑过**。
根因是全局 CLAUDE.md 里一条为省 token 写的规则（"subagent 会烧掉成倍
token，先说明再调"）—— 它的前提"subagent 更贵"只在 subagent 继承父模型时
成立，而这些 agent 各自钉了模型，还自带独立的短上下文。

**主要收益不是模型差价，是上下文隔离。** 输出 25M vs 缓存读 7,004M：
grep 出来的一屏、cat 出来的整个文件进了主上下文之后被之后每一轮重复计费。
subagent 跑完只交回结论。这决定了派活的优先级 ——
**输出体量大的活优先派，哪怕它本身不难**。

## 非目标

- 不做用量预算、配额、账单集成
- 不替代 Claude Code 的 `/model`、`--model`、agent frontmatter —— 建立在它们之上
- 不管主会话自己的工具调用，只管派出去的活
- 不依赖、不读取、不修改 agent-skills 的任何文件

## Tech Stack

| | |
|---|---|
| 形态 | 独立 Claude Code 插件（marketplace 分发） |
| 依赖 | `bash` / `git` / `python3`。**不引入 `jq` 硬依赖** |
| 目标平台 | macOS（bash 3.2）+ Linux |
| 与 agent-skills 的关系 | **零依赖**。卸载 agent-skills 不影响本插件 |

### 已实测的技术前提

**PreToolUse hook 能拦截，且拿得到完整 `tool_input`**（2026-08-28 实测）：

```
payload 字段: session_id / transcript_path / cwd / prompt_id /
             permission_mode / effort / hook_event_name /
             tool_name / tool_input / tool_use_id
拦截语法:    {"hookSpecificOutput":{"hookEventName":"PreToolUse",
             "permissionDecision":"deny","permissionDecisionReason":"..."}}
```

**`plugin.json` 支持 `agents` 字段**（agent-skills 的清单里就有），
所以插件能同时带 hooks / skills / commands / agents。

**Agent 工具的 `model` 参数优先级高于 agent 定义的 frontmatter** ——
这是本方案的支点：**agent 定角色，调用时传 model 定档位，两者正交**。

### 未验证的前提（实现前必须先验）

1. PreToolUse 的 `matcher` 对 **Agent** 工具是否按同样方式生效（只验过 `Bash`）
2. PostToolUse 的 payload 是否包含 subagent 的返回文本（用于统计"升级触发次数"）
3. 插件形态的 hook 能否注册 PreToolUse（spec-guard 只用过 UserPromptSubmit）

## 分级判据

**默认 T2。降级需要举证 —— 三条全部满足才能降。**

| 档 | 判据 | 模型 |
|---|---|---|
| **T0** | 只读 · 不产生任何持久影响 · 输出体量大 | haiku |
| **T1** | 验收标准已写死 **且** 无需取舍决策 **且** 后果 `git revert` 可撤 | sonnet |
| **T2** | 以上任一不满足（**默认值**） | opus |

**T2 触发条件（任一为真即不许降）：**

1. 要在多个都能 work 的方案里选一个
2. 不可逆：push / merge / deploy / 删除 / 数据迁移 / 改 auth 或密钥 /
   在外部系统建记录（GitHub issue、PR、release）
3. 验收标准不存在或有歧义

**关于第 3 条**：允许主会话（T2）**现场写一条 AC 再降级** ——
写 AC 花一次 opus，换整个实现走 sonnet。但 AC 必须写下来交给执行者，
不能只在脑子里。

**下界**：`/build` 一次加载 skill ≈ 26KB 固定开销，subagent 每派一次重付。
改一行、调常量这类，主会话直接做完更省。

## 三道防欠配的闸

| | 内容 | 落在哪 |
|---|---|---|
| **闸一** | 默认 T2，降级要能说出三条判据都满足 | skill（规约） |
| **闸二** | 升级触发器：派出去的活附固定合同文本，遇到就原样交回 | skill（合同文本） |
| **闸三** | T1 产出由主会话（T2）验收；执行者自证不算 | skill（规约） |

**闸二的合同文本**（每次派活附带，逐字）：

> 遇到以下任一情况，立即停止并把现状交回，不要自行决定：
> ① 测试改不红 / 构建坏了且没有显然修法
> ② 验收标准有歧义，或需要做规约没覆盖的决定
> ③ 需要做任何不可逆的事（push / 合并 / 删除 / 迁移 / 动密钥 / 建外部记录）
> ④ 你发现这活比派活时描述的复杂

## 守卫（hook）要做的判断

只做**机械可判**的事，不做语义判断。

| 规则 | 条件 | 处置 |
|---|---|---|
| **R1 欠配** | `tool_input.prompt` 命中不可逆动作词 **且** `model` ∈ {sonnet, haiku} | 记违规 |
| **R2 零节省** | `subagent_type` 指向的 agent 文件没有 `model:` **且** 调用未传 `model` | 记提示 |
| **R3 缺合同** | `model` ∈ {sonnet, haiku} **且** prompt 不含升级触发器标记 | 记提示 |

**不可逆动作词**（初版，靠日志校准）：
`git push` · `git commit --amend` · `gh pr merge` · `gh issue create` ·
`gh issue delete` · `gh release` · `rm -r` · `DROP TABLE` · `migrate` ·
`deploy` · `terraform apply` · `npm publish` · `--force` · `.env` ·
`SECRET` · `API_KEY`

### 已知的误报风险

R1 是**子串匹配**，`检查有没有人写了 git push` 会命中。

因此：**第一周只记日志，不拦截、不打扰**（`TIER_GUARD_MODE=log`，默认）。
攒够样本、量出误报率之后再决定是否切到 `deny`。
切换模式需要人工决定，不自动升级。

> 这条继承自 spec-guard 的第一条不可违反性质：**假警报比漏报危害大得多**。
> 一个会误拦的守卫，最终结果是被整个关掉。

## Project Structure

```
.claude-plugin/plugin.json      插件清单
hooks/
├── hooks.json                  hook 注册（PreToolUse → Agent）
├── tier-guard.sh               守卫本体（只读，<100ms）
└── test-tier-guard.sh          回归断言
skills/tier-routing/SKILL.md    分级判据 + 升级触发器合同文本
commands/tier-report.md         看 subagent 占比 / 违规计数
scripts/
├── validate.sh                 仓库完整性校验
├── check-*.py                  静态检查（bash32 / grep-pipe / manifests）
├── test-checkers.sh            校验器自身的回归
├── mutation-check.py           变异测试
└── install-git-hooks.sh        pre-push
docs/lenses.md                  透镜（改完对着照）
```

## Commands

```bash
/bin/bash scripts/validate.sh                  # 仓库校验
/bin/bash hooks/test-tier-guard.sh             # 守卫回归断言
/bin/bash scripts/test-checkers.sh             # 校验器自身回归
python3 scripts/mutation-check.py              # 变异测试（慢，不进 validate）
npx --yes shellcheck@4.1.0 -S warning hooks/*.sh scripts/*.sh
/bin/bash scripts/install-git-hooks.sh         # 装 pre-push
```

**显式写 `/bin/bash`** —— macOS 上 `bash` 可能是 Homebrew 的 5.x，
而 3.2 才是要防的那个版本。

## Testing Strategy

沿用 spec-guard 攒出来的那套方法（**复用模式，不复用代码**）：

1. **每条判据一正一反。** 反向用例和正向一样重要 —— 这类项目修过的假警报比真 bug 多
2. **判据写完当场用真实数据跑一遍。** spec-guard 在这条上翻过五次车
3. **变异测试。** 把判据改坏，断言必须红。活下来的变异体 = 那条路径上没有断言
4. **守卫自己不能崩。** 任何异常 → 放行 + 记日志，绝不因为守卫坏了挡住干活

### 关键的反向用例（实现时必须有）

- 不可逆动作词 + `model=opus` → **不记违规**
- prompt 里只是**提到**不可逆动作词（"检查有没有人写了 git push"）→ 记录时标为疑似误报
- `subagent_type` 指向有 `model:` 的 agent → R2 不触发
- hook 自身异常（读不到 agent 文件、payload 缺字段）→ **放行**，不拦
- `TIER_GUARD_MODE=log` 下**永不返回 deny**

## Boundaries

**Always（总是）**
- 异常时放行。守卫失效不能变成干活失效
- 只读 `tool_input`，不写任何用户文件（日志除外）
- 单次执行 < 100ms
- 默认 `TIER_GUARD_MODE=log`

**Ask first（先问）**
- 从 `log` 切到 `deny`
- 往不可逆动作词表里加词（每加一个都放大误报面）
- 任何会让守卫返回 deny 的改动

**Never（绝不）**
- 不 fork / vendored agent-skills 或 spec-guard 的任何文件
- 不在守卫里做写操作
- 不用 `jq` 作硬依赖
- 不写 `$VAR` 紧跟多字节字符（bash 3.2 会致命退出，且 hook 失败是静默的）
- 不写 `cmd | grep -q`（SIGPIPE + pipefail → 判断永远为假）
- 不为了省钱降级不可逆操作

## Success Criteria

**功能（可测）**

1. 不可逆动作词 + 低档 model → 记一条 R1 违规；同样调用改成 opus → 不记
2. `subagent_type` 指向无 `model:` 的 agent 且未传 model → 记一条 R2
3. hook 任何异常路径下都返回放行，且日志里能看出是哪条路径失败的
4. `TIER_GUARD_MODE=log` 下不存在任何返回 deny 的代码路径（断言覆盖）
5. 单次执行 < 100ms（实测，不是估计）

**效果（一周后量）**

6. `subagent 占比` 从 **0.0%** 上升 —— 基线已记录
7. **误报率可量**：R1 命中里，人工判定为误报的比例。切 `deny` 前必须 < 10%
8. **打回率可量**：T1 产出被主会话验收打回的比例。持续高说明降级是负收益

**第 6 条是目标，第 7 条是约束。** 7 不达标就不许切 deny，哪怕 6 很好看。

## Open Questions

1. **"升级触发次数"怎么统计？** 依赖 PostToolUse 能否拿到 subagent 返回文本 ——
   未验证。拿不到的话这个指标要换实现（或从 transcript 事后扫）
2. **插件形态能否注册 PreToolUse？** spec-guard 只用过 UserPromptSubmit。
   若不行，退路是让插件提供脚本 + 由 `/setup` 写进用户 settings（多一步手工）
3. **R3（缺合同）值不值得做？** 它靠标记字符串匹配，脆。可能第一版只留 R1 + R2
4. **主会话模型定档**：当前 `settings.json` 已从 `opus[1m]` 改为 `opus`。
   本方案生效后主上下文应显著变短，届时再看是否需要进一步调整
