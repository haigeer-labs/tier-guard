#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Claude 薄壳（tier-guard.sh + claude_hook.py）的回归断言。
#
# 判据本身的正反用例在 route_decide.py --selftest；这里只测薄壳自己的职责：
#   - 放行：异常 / 缺字段 / fork / python 不在 → 一律退出 0、stdout 空
#   - dry-run 下**没有任何**返回 updatedInput 的路径（扫一遍，不是口头保证）
#   - off 下与未装插件一致：stdout 空、退出 0、不留日志
#   - auto 下 updatedInput 只改 model、其余字段原样，且永不出现 deny / ask
#   - agent 定义解析（项目优先于用户目录）、Codex 派活「建议 vs 实际」
#   - 单次执行 < 100ms（实测中位数）
# ─────────────────────────────────────────────────────────────
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT}/hooks/tier-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
PASS=0; FAIL=0
ok()  { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = yes ]; then ok "$1"; else bad "$1"; fi; }  # $1=说明 $2=yes|no

FAKEHOME="${TMP}/home"; PROJ="${TMP}/proj"; LOGD="${TMP}/log"
mkdir -p "${FAKEHOME}/.claude/agents" "${PROJ}/.claude/agents"
agent() {  # $1=目录 $2=name $3=model（- 表示不写 model 行）
  { echo "---"; echo "name: $2"; [ "$3" = - ] || echo "model: $3"; echo "description: x"; echo "---"; echo "body"; } \
    > "$1/.claude/agents/$2.md"
}
agent "${FAKEHOME}" executor sonnet
agent "${FAKEHOME}" shadowed sonnet
agent "${PROJ}"     shadowed haiku
agent "${FAKEHOME}" nomodel -

# $1=mode $2=payload [$3=事件] → 设置 OUT / RC
run() {
  local mode="$1" payload="$2" ev="${3:-agent}"
  OUT="$(printf '%s' "${payload}" | env HOME="${FAKEHOME}" CLAUDE_PROJECT_DIR="${PROJ}" \
          TIER_GUARD_LOG_DIR="${LOGD}" TIER_GUARD_MODE="${mode}" \
          TIER_GUARD_CONFIG="${ROOT}/config/routing.default.json" /bin/bash "${HOOK}" "${ev}")"
  RC=$?
}
# v2 使用独立目录，避免迁移期旧配置的断言与新路由混在一起。
runv2with() {  # $1=profile $2=payload $3=config [$4=事件]
  local profile="$1" payload="$2" config="$3" ev="${4:-agent}"
  OUT="$(printf '%s' "${payload}" | env HOME="${FAKEHOME}" CLAUDE_PROJECT_DIR="${PROJ}" \
          TIER_GUARD_LOG_DIR="${LOGD}" TIER_GUARD_MODE="${profile}" \
          TIER_GUARD_CONFIG="${config}" /bin/bash "${HOOK}" "${ev}")"
  RC=$?
}
runv2() { runv2with "$1" "$2" "${ROOT}/config/routing.catalog.v2.json" "${3:-agent}"; }
runv2verified() { runv2with "$1" "$2" "${V2_VERIFIED_CONFIG}" "${3:-agent}"; }
V2_CATALOG_SHA="$(shasum -a 256 "${ROOT}/config/routing.catalog.v2.json" | awk '{print $1}')"
# 用 python 拼 payload / 断言 JSON，避免 jq 依赖
mk() {  # $1=prompt $2=model(- 不传) $3=subagent_type
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
prompt, model, st = sys.argv[1:4]
ti = {"description": "t", "prompt": prompt, "subagent_type": st, "run_in_background": False}
if model != "-":
    ti["model"] = model
print(json.dumps({"session_id": "s", "tool_use_id": "u", "hook_event_name": "PreToolUse",
                  "tool_name": "Agent", "tool_input": ti}, ensure_ascii=False))
PY
}
lastlog() {  # $1=python 表达式（变量 r = 最后一条日志）→ 打印结果
  python3 - "$1" "${LOGD}/decisions.jsonl" <<'PY'
import json, sys
expr, path = sys.argv[1], sys.argv[2]
try:
    r = json.loads(open(path, encoding="utf-8").read().splitlines()[-1])
    print("yes" if eval(expr) else "no")
except Exception as e:
    print("no")
PY
}
jsonq() {  # $1=python 表达式（变量 o = stdout 解析出的 JSON）
  python3 - "$1" "${OUT}" <<'PY'
import json, sys
try:
    o = json.loads(sys.argv[2])
    print("yes" if eval(sys.argv[1]) else "no")
except Exception:
    print("no")
PY
}
yn() { if "$@"; then echo yes; else echo no; fi; }

# 这份目录只用于验证已获得宿主拦截证据时的编码；生产目录必须保持未验证状态。
V2_VERIFIED_CONFIG="${TMP}/routing.catalog.v2.verified.json"
python3 - "${ROOT}/config/routing.catalog.v2.json" "${V2_VERIFIED_CONFIG}" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
cfg.setdefault("host_capabilities", {}).setdefault("claude-code", {})["pre_dispatch_apply"] = True
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, ensure_ascii=False)
PY

PAD="背景：这是一段中性的背景说明，只用来让 prompt 越过收益门槛，不含任何判据词。背景：这是一段中性的背景说明，只用来让 prompt 越过收益门槛。背景：再补一句中性的说明文字，凑够长度。"
AC=$'\n验收：python3 -m pytest 全绿\n'
IRR="$(mk "改完后 git push 到 origin。${AC}${PAD}" sonnet executor)"
SAFE="$(mk "按 spec 第 3 节实现缓存层。${AC}${PAD}" sonnet executor)"

echo "═══ tier-guard.sh 回归 ═══"

# ── off：与未装插件一致 ──
rm -rf "${LOGD}"
run off "${IRR}"
check "off：退出 0、stdout 空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "off：不留日志" "$(yn [ ! -e "${LOGD}/decisions.jsonl" ])"

# ── dry-run：只记不改 ──
run dry-run "${IRR}"
check "dry-run：欠配调用 stdout 仍为空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "dry-run：日志记下 raise，applied=false" \
  "$(lastlog 'r["decision"]["action"] == "raise" and r["applied"] is False')"
check "dry-run：日志不含 prompt 原文（只有长度和 sha256）" \
  "$(lastlog '"改完后" not in json.dumps(r, ensure_ascii=False) and len(r["prompt_sha256"]) == 64')"
LEAK=0
for p in "改完后 git push。${AC}${PAD}" "把 foo 改名为 bar。${PAD}" "两种做法权衡后选一个。${AC}${PAD}" "改个常量。${AC}"; do
  for m in haiku sonnet opus -; do
    for st in executor fork nomodel general-purpose; do
      run dry-run "$(mk "${p}" "${m}" "${st}")"
      [ "${RC}" -eq 0 ] && [ -z "${OUT}" ] || LEAK=$((LEAK+1))
    done
  done
done
check "dry-run：64 种组合里没有一条产出 stdout（updatedInput 路径不存在）" "$(yn [ "${LEAK}" -eq 0 ])"

# ── auto：只改 model ──
run auto "${IRR}"
check "auto：欠配调用 → updatedInput.model = opus" \
  "$(jsonq 'o["hookSpecificOutput"]["hookEventName"] == "PreToolUse" and o["hookSpecificOutput"]["updatedInput"]["model"] == "opus"')"
check "auto：updatedInput 其余字段原样" \
  "$(jsonq 'o["hookSpecificOutput"]["updatedInput"]["prompt"].startswith("改完后 git push") and o["hookSpecificOutput"]["updatedInput"]["subagent_type"] == "executor" and o["hookSpecificOutput"]["updatedInput"]["run_in_background"] is False')"
check "auto：不带 permissionDecision（不绕过权限流程）" \
  "$(jsonq '"permissionDecision" not in o["hookSpecificOutput"]')"
check "auto：日志标记已输出 updatedInput" "$(lastlog 'r["applied"] is True')"
run auto "${SAFE}"
check "auto：无 floor 的 sonnet 调用 → stdout 空" "$(yn [ -z "${OUT}" ])"
run auto "$(mk "改完后 git push 到 origin。${AC}${PAD}" opus executor)"
check "auto：动作词 + opus → stdout 空（不算欠配）" "$(yn [ -z "${OUT}" ])"
run auto "$(mk "git push。${PAD}" sonnet fork)"
check "auto：fork → 原样放行" "$(yn [ -z "${OUT}" ])"
DENY=0
for p in "改完后 git push。${AC}${PAD}" "把 foo 改名为 bar。${PAD}" "改个常量。${AC}"; do
  for m in haiku sonnet opus -; do
    run auto "$(mk "${p}" "${m}" executor)"
    case "${OUT}" in *deny*|*'"ask"'*) DENY=$((DENY+1)) ;; esac
  done
done
check "auto：任何组合都不出现 deny / ask" "$(yn [ "${DENY}" -eq 0 ])"
run deny "${IRR}"
check "未知 mode（deny）→ 放行" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"

# ── 异常一律放行，且日志能看出是哪条路径 ──
run auto 'not json'
check "payload 不是 JSON → 退出 0、stdout 空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "payload 不是 JSON → 日志写明 fallback（claude_hook 自己接住，不是薄壳兜底）" \
  "$(lastlog 'r["fallback"].startswith("claude_hook:")')"
run auto '{"tool_name":"Agent","tool_input":{"subagent_type":"x"}}'
check "缺 prompt → 退出 0、stdout 空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "缺 prompt → 日志写明缺什么" "$(lastlog '"prompt" in r["decision"]["fallback"]')"
OUT="$(printf '%s' "${IRR}" | env HOME="${FAKEHOME}" TIER_GUARD_LOG_DIR="${LOGD}" TIER_GUARD_MODE=auto \
        TIER_GUARD_CONFIG=/nonexistent/routing.json /bin/bash "${HOOK}" agent)"; RC=$?
check "配置读不到 → 退出 0、stdout 空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
mkdir -p "${TMP}/bin"; ln -s /bin/cat "${TMP}/bin/cat"; ln -s /usr/bin/dirname "${TMP}/bin/dirname"
OUT="$(printf '%s' "${IRR}" | env PATH="${TMP}/bin" TIER_GUARD_LOG_DIR="${LOGD}" TIER_GUARD_MODE=auto \
        /bin/bash "${HOOK}" agent)"; RC=$?
check "python3 不在 PATH → 退出 0、stdout 空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "python3 不在 PATH → 薄壳自己补一条 fallback 记录" "$(lastlog '"没跑起来" in r["fallback"]')"

# ── agent 定义解析 ──
run auto "$(mk "改完后 git push。${AC}${PAD}" - executor)"
check "agent：未传 model 时读 ~/.claude/agents 的 frontmatter（sonnet → T1）" \
  "$(lastlog 'r["decision"]["start_tier"] == "T1" and r["agent_model"] == "sonnet"')"
run dry-run "$(mk "跑测试。${AC}${PAD}" - shadowed)"
check "agent：项目 .claude/agents 优先于用户目录（haiku → T0）" "$(lastlog 'r["decision"]["start_tier"] == "T0"')"
run dry-run "$(mk "跑测试。${AC}${PAD}" - nomodel)"
check "agent：没钉 model → 日志有 R2 提示" "$(lastlog 'any(w["rule"] == "R2" for w in r["decision"]["why"])')"
run dry-run "$(mk "跑测试。${AC}${PAD}" - some-plugin:executor)"
check "agent：插件 agent（带冒号）不解析，也不判 R2" \
  "$(lastlog 'r["agent_model"] == "(未解析)" and not any(w["rule"] == "R2" for w in r["decision"]["why"])')"

# ── Bash：Codex 派活的「建议 vs 实际」（Task 4a）──
bashp() {  # $1=命令
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s","tool_use_id":"b","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}, ensure_ascii=False))' "$1"
}
N0="$(wc -l < "${LOGD}/decisions.jsonl" | tr -d ' ')"
run auto "$(bashp 'ls -la && echo hi')" bash
N1="$(wc -l < "${LOGD}/decisions.jsonl" | tr -d ' ')"
check "Bash：普通命令 → stdout 空、不留日志" "$(yn [ -z "${OUT}" -a "${N0}" = "${N1}" ])"
T1TASK="按 spec 第 3 节实现缓存层。${AC}${PAD}"
run auto "$(bashp "bash \"/x/delegate/scripts/codex-exec.sh\" --write --model gpt-5.6-terra --effort high \"${T1TASK}\"")" bash
check "Bash：T1 任务按 terra/high 派出 → 建议与实际一致" \
  "$(lastlog 'r["event"] == "codex-dispatch" and r["consistent"] is True and r["suggested"] == {"model": "gpt-5.6-terra", "effort": "high"}')"
run auto "$(bashp "bash /x/codex-exec.sh --model gpt-5.6-terra --effort high -- \"改完后 git push。${AC}${PAD}\" && echo done")" bash
check "Bash：不可逆任务按 T1 派出 → 记为不一致，建议 xhigh" \
  "$(lastlog 'r["consistent"] is False and r["suggested"]["effort"] == "xhigh"')"
check "Bash：任务文本在 && 处截断（取到的是任务，不是后面的 echo done）" \
  "$(lastlog 'r["prompt_chars"] > 50')"
check "Bash：即使 auto 也不改派活命令（stdout 空）" "$(yn [ -z "${OUT}" ])"

# ── v2 Claude pre-dispatch：目录/纯路由在前，此处只验证宿主编码 ──
V2SIMPLE="$(mk $'只读审查配置，禁止修改任何文件。\n验收：报告所有键名。' - nomodel)"
runv2 audit "${V2SIMPLE}"
check "v2 audit：未 pin 的简单任务只记 select，stdout 空" \
  "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "v2 audit：记录 v2 决策且 applied=false" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "select" and r["decision"]["target"]["model"] == "haiku" and r["applied"] is False')"
check "v2 audit：记录实际读取目录的来源与内容指纹，不记录路径" \
  "$(lastlog 'r["catalog_identity"] == {"origin": "environment", "sha256": "'"${V2_CATALOG_SHA}"'"}')"
runv2 auto "${V2SIMPLE}"
check "v2 auto：未验证宿主不得改写参数，仍只审计" \
  "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "v2 auto：未验证宿主记录 applied=false" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "select" and r["applied"] is False and r["host_pre_dispatch_apply"] is False')"
runv2verified auto "${V2SIMPLE}"
check "v2 auto：已验证宿主才选择低成本 haiku" \
  "$(jsonq 'o["hookSpecificOutput"]["hookEventName"] == "PreToolUse" and o["hookSpecificOutput"]["updatedInput"]["model"] == "haiku"')"
check "v2 auto：已验证 Claude 编码不附带 permissionDecision" \
  "$(jsonq '"permissionDecision" not in o["hookSpecificOutput"]')"
check "v2 auto：已验证宿主只改 model，保留所有非路由字段" \
  "$(jsonq 'o["hookSpecificOutput"]["updatedInput"]["description"] == "t" and o["hookSpecificOutput"]["updatedInput"]["prompt"].startswith("只读审查") and o["hookSpecificOutput"]["updatedInput"]["subagent_type"] == "nomodel" and o["hookSpecificOutput"]["updatedInput"]["run_in_background"] is False')"
check "v2 auto：已验证宿主的 updatedInput 输出可审计" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "select" and r["host_pre_dispatch_apply"] is True and r["applied"] is True')"
runv2 auto "$(mk $'只读审查配置，禁止修改任何文件。\n验收：报告所有键名。' opus nomodel)"
check "v2 auto：调用显式 model 是 pin，不改写" "$(yn [ -z "${OUT}" ])"
check "v2 auto：pin 留下建议但 target 为空" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "pinned" and r["decision"]["target"] is None and r["decision"]["recommended"]["model"] == "haiku" and r["applied"] is False')"
runv2 auto "$(mk $'只读审查配置，禁止修改任何文件。\n验收：报告所有键名。' - executor)"
check "v2 auto：agent frontmatter 的显式 model 也是 pin" "$(yn [ -z "${OUT}" ])"
check "v2 auto：frontmatter pin 不改写" \
  "$(lastlog 'r["routing_version"] == 2 and r["agent_model"] == "sonnet" and r["decision"]["action"] == "pinned" and r["applied"] is False')"
runv2 auto '{"tool_name":"Agent","tool_input":{"subagent_type":"nomodel"}}'
check "v2：缺 prompt → 退出 0、stdout 空且不应用" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "v2：缺 prompt → fallback 可审计" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "pass" and bool(r["decision"]["fallback"]) and r["applied"] is False')"

# ── 性能：单次 < 100ms（实测中位数）──
MS="$(python3 - "${HOOK}" "${IRR}" "${FAKEHOME}" "${LOGD}" <<'PY'
import os, subprocess, sys, time
hook, payload, home, logd = sys.argv[1:5]
env = dict(os.environ, HOME=home, TIER_GUARD_LOG_DIR=logd, TIER_GUARD_MODE="auto",
           TIER_GUARD_CONFIG=os.path.join(os.path.dirname(os.path.dirname(hook)), "config", "routing.default.json"))
ts = []
for _ in range(15):
    t = time.perf_counter()
    subprocess.run(["/bin/bash", hook, "agent"], input=payload, capture_output=True, text=True, env=env)
    ts.append((time.perf_counter() - t) * 1000)
print(int(sorted(ts)[len(ts) // 2]))
PY
)"
check "性能：单次执行中位 ${MS}ms < 100ms" "$(yn [ "${MS}" -lt 100 ])"

echo ""
echo "  总计 ${PASS} 通过 / ${FAIL} 失败"
[ "${PASS}" -gt 0 ] && [ "${FAIL}" -eq 0 ]
