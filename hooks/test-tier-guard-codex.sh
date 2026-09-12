#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Codex 薄壳（tier-guard-codex.sh + codex_hook.py）的回归断言。Task 4b 的离线部分。
#
# payload 形状照本机 codex-cli 0.153.4 内嵌的 pre-tool-use.command.input schema 造
# （必填：cwd / hook_event_name / model / permission_mode / session_id / tool_input /
#   tool_name / tool_use_id / transcript_path / turn_id）。
# 与 Claude 侧的关键差别：updatedInput 必须配 permissionDecision:"allow"。
# ─────────────────────────────────────────────────────────────
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT}/hooks/tier-guard-codex.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
PASS=0; FAIL=0
check() { if [ "$2" = yes ]; then printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); else printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); fi; }
# yn 只包一条命令；复合条件写成具名函数（`$(yn A && B)` 是永远为真的空断言）
yn() { if "$@"; then echo yes; else echo no; fi; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
LOGD="${TMP}/log"; FAKEHOME="${TMP}/home"; mkdir -p "${FAKEHOME}"

run() {  # $1=mode $2=payload → OUT / RC
  OUT="$(printf '%s' "$2" | env HOME="${FAKEHOME}" TIER_GUARD_LOG_DIR="${LOGD}" TIER_GUARD_MODE="$1" \
        TIER_GUARD_CONFIG="${ROOT}/config/routing.default.json" /bin/bash "${HOOK}")"
  RC=$?
}
runv2with() {  # $1=profile $2=payload $3=config → OUT / RC
  OUT="$(printf '%s' "$2" | env HOME="${FAKEHOME}" TIER_GUARD_LOG_DIR="${LOGD}" TIER_GUARD_MODE="$1" \
        TIER_GUARD_CONFIG="$3" /bin/bash "${HOOK}")"
  RC=$?
}
runv2() { runv2with "$1" "$2" "${ROOT}/config/routing.catalog.v2.json"; }
runv2verified() { runv2with "$1" "$2" "${V2_VERIFIED_CONFIG}"; }
V2_CATALOG_SHA="$(shasum -a 256 "${ROOT}/config/routing.catalog.v2.json" | awk '{print $1}')"
# $1=message $2=显式 model(- 不传) $3=显式 reasoning_effort(- 不传) [$4=会话 model] [$5=tool_name]
sp() {
  python3 - "$1" "$2" "$3" "${4:-gpt-5.6-terra}" "${5:-spawn_agent}" <<'PY'
import json, sys
msg, model, effort, session_model, tool = sys.argv[1:6]
ti = {"message": msg, "task_name": "t1", "agent_type": "worker", "fork_turns": "none"}
if model != "-":
    ti["model"] = model
if effort != "-":
    ti["reasoning_effort"] = effort
print(json.dumps({"session_id": "s", "turn_id": "t", "cwd": "/x", "hook_event_name": "PreToolUse",
                  "model": session_model, "permission_mode": "default", "transcript_path": None,
                  "tool_name": tool, "tool_use_id": "c1", "tool_input": ti}, ensure_ascii=False))
PY
}
jsonq() {  # $1=python 表达式（o = stdout 的 JSON）
  python3 - "$1" "${OUT}" <<'PY'
import json, sys
try:
    o = json.loads(sys.argv[2])
    print("yes" if eval(sys.argv[1]) else "no")
except Exception:
    print("no")
PY
}
lastlog() {
  python3 - "$1" "${LOGD}/decisions.jsonl" <<'PY'
import json, sys
try:
    r = json.loads(open(sys.argv[2], encoding="utf-8").read().splitlines()[-1])
    print("yes" if eval(sys.argv[1]) else "no")
except Exception:
    print("no")
PY
}
PAD="背景：这是一段中性的背景说明，只用来让 prompt 越过收益门槛，不含任何判据词。背景：这是一段中性的背景说明，只用来让 prompt 越过收益门槛。背景：再补一句中性的说明文字，凑够长度。"
AC=$'\n验收：pytest 全绿\n'
IRR="改完后 git push 到 origin。${AC}${PAD}"
SAFE="按 spec 第 3 节实现缓存层。${AC}${PAD}"
V2_VERIFIED_CONFIG="${TMP}/routing.catalog.v2.verified.json"
python3 - "${ROOT}/config/routing.catalog.v2.json" "${V2_VERIFIED_CONFIG}" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
cfg.setdefault("host_capabilities", {}).setdefault("codex-cli", {})["pre_dispatch_apply"] = True
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, ensure_ascii=False)
PY

echo "═══ tier-guard-codex.sh 回归 ═══"

CODEX_MATCHERS="$(python3 - "${ROOT}/hooks/codex-hooks.json" <<'PY'
import json, sys
try:
    entries = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["PreToolUse"]
    expected = "^(?:Agent|spawn_agent|collaborationspawn_agent|collaboration[.:_]+spawn_agent)$"
    print("yes" if {e.get("matcher") for e in entries} == {expected} else "no")
except Exception:
    print("no")
PY
)"
check "插件以单一严格 matcher 覆盖规范名、扁平 V2 名与分隔符兼容名" "${CODEX_MATCHERS}"

rm -rf "${LOGD}"
run off "$(sp "${IRR}" gpt-5.6-terra high)"
c_off() { [ "${RC}" -eq 0 ] && [ -z "${OUT}" ] && [ ! -e "${LOGD}/decisions.jsonl" ]; }
check "off：退出 0、stdout 空、不留日志" "$(yn c_off)"

run dry-run "$(sp "${IRR}" gpt-5.6-terra high)"
check "dry-run：欠配调用 stdout 仍为空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "dry-run：日志记下 raise（起点 T1 → T2），applied=false" \
  "$(lastlog 'r["event"] == "codex-spawn" and r["decision"]["start_tier"] == "T1" and r["decision"]["action"] == "raise" and r["applied"] is False')"
check "dry-run：任务文本取自 message，日志不含原文" \
  "$(lastlog 'r["text_source"] == "message" and "改完后" not in json.dumps(r, ensure_ascii=False)')"

run auto "$(sp "${IRR}" gpt-5.6-terra high)"
check "auto：带 permissionDecision=allow（Codex 要求，Claude 侧没有）" \
  "$(jsonq 'o["hookSpecificOutput"]["permissionDecision"] == "allow" and o["hookSpecificOutput"]["hookEventName"] == "PreToolUse"')"
check "auto：只抬 effort 到 xhigh，slug 不换" \
  "$(jsonq 'o["hookSpecificOutput"]["updatedInput"]["reasoning_effort"] == "xhigh" and o["hookSpecificOutput"]["updatedInput"]["model"] == "gpt-5.6-terra"')"
check "auto：updatedInput 是完整参数（message / task_name / agent_type / fork_turns 原样）" \
  "$(jsonq 'o["hookSpecificOutput"]["updatedInput"]["message"].startswith("改完后") and o["hookSpecificOutput"]["updatedInput"]["task_name"] == "t1" and o["hookSpecificOutput"]["updatedInput"]["agent_type"] == "worker" and o["hookSpecificOutput"]["updatedInput"]["fork_turns"] == "none"')"
check "auto：日志标记已输出 updatedInput" "$(lastlog 'r["applied"] is True')"

run auto "$(sp "${IRR}" - high)"
check "auto：显式 effort + 继承会话 model（terra）也认得出 T1 → 抬到 xhigh" \
  "$(jsonq 'o["hookSpecificOutput"]["updatedInput"]["reasoning_effort"] == "xhigh"')"
run auto "$(sp "${IRR}" - -)"
check "auto：effort 继承（看不到父会话的 effort）→ 不动（父会话若是 max，设 xhigh 反而降档）" "$(yn [ -z "${OUT}" ])"
run auto "$(sp "${IRR}" gpt-5.6-sol high)"
check "auto：表外组合（sol）→ 不动" "$(yn [ -z "${OUT}" ])"
run auto "$(sp "${IRR}" gpt-5.6-terra xhigh)"
check "auto：已经是 T2（terra/xhigh）→ 不动" "$(yn [ -z "${OUT}" ])"
run auto "$(sp "${IRR}" gpt-5.6-terra max)"
check "auto：比 T2 还高（max）→ 不动（只升不降）" "$(yn [ -z "${OUT}" ])"
run auto "$(sp "${SAFE}" gpt-5.6-terra high)"
check "auto：无 floor 的 T1 调用 → 不动" "$(yn [ -z "${OUT}" ])"
run auto "$(sp "${IRR}" gpt-5.6-terra high gpt-5.6-terra exec_command)"
check "auto：不是 spawn_agent → 不动、不记" "$(yn [ -z "${OUT}" ])"

BAD=0
for msg in "${IRR}" "${SAFE}" "两种做法权衡后选一个。${AC}${PAD}" "把 foo 改名。${PAD}"; do
  for pair in "gpt-5.6-luna medium" "gpt-5.6-terra high" "gpt-5.6-terra xhigh" "- -" "gpt-6-astra high"; do
    set -- ${pair}
    run auto "$(sp "${msg}" "$1" "$2")"
    case "${OUT}" in *'"deny"'*|*'"ask"'*|*'"max"'*|*'"ultra"'*|*gpt-6-astra*|*gpt-5.6-sol*) BAD=$((BAD+1)) ;; esac
  done
done
check "auto：20 种组合里从不出现 deny / ask，也从不自动选 astra / sol / max / ultra" "$(yn [ "${BAD}" -eq 0 ])"
LEAK=0
for msg in "${IRR}" "${SAFE}" "两种做法权衡后选一个。${AC}${PAD}"; do
  for pair in "gpt-5.6-luna medium" "gpt-5.6-terra high" "- -"; do
    set -- ${pair}
    run dry-run "$(sp "${msg}" "$1" "$2")"
    [ -z "${OUT}" ] || LEAK=$((LEAK+1))
  done
done
check "dry-run：9 种组合里没有一条产出 stdout" "$(yn [ "${LEAK}" -eq 0 ])"

run auto 'not json'
check "payload 不是 JSON → 退出 0、stdout 空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "payload 不是 JSON → 日志写明 fallback（codex_hook 自己接住）" "$(lastlog 'r["fallback"].startswith("codex_hook:")')"
mkdir -p "${TMP}/bin"; ln -s /bin/cat "${TMP}/bin/cat"; ln -s /usr/bin/dirname "${TMP}/bin/dirname"
OUT="$(printf '%s' "$(sp "${IRR}" gpt-5.6-terra high)" | env PATH="${TMP}/bin" TIER_GUARD_LOG_DIR="${LOGD}" TIER_GUARD_MODE=auto /bin/bash "${HOOK}")"; RC=$?
check "python3 不在 PATH → 退出 0、stdout 空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"

# ── v2 Codex CLI pre-dispatch：只验证宿主编码，判据由 route contract 覆盖 ──
V2SIMPLE="$(sp $'只读审查配置，禁止修改任何文件。\n验收：报告所有键名。' - -)"
runv2 audit "${V2SIMPLE}"
check "v2 audit：未 pin 的简单任务只记 select，stdout 空" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "v2 audit：记录 v2 决策且 applied=false" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "select" and r["decision"]["target"] == {"id": "codex-luna-medium", "model": "gpt-5.6-luna", "reasoning_effort": "medium"} and r["applied"] is False')"
check "v2 audit：记录实际读取目录的来源与内容指纹，不记录路径" \
  "$(lastlog 'r["catalog_identity"] == {"origin": "environment", "sha256": "'"${V2_CATALOG_SHA}"'"}')"
check "v2 audit：派发前输入只记为 requested，不冒充实际执行" \
  "$(lastlog 'r["routing_version"] == 2 and "actual" not in r and r["decision"]["requested"]["model"] == "gpt-5.6-terra" and r["decision"]["requested"]["reasoning_effort"] is None')"
OPAQUE_TASK_TOKEN='gAAAAABqpV6vt1_VldXEBZKJFvQMBgplGnbDAsDfxP_Yk4J18GutDTltnSfReyHQokOmEoLYexQltP_gH8Dbbi8_fDfzmTT3f7YW0fSkHJDKu_ltyNhCSuj_uuO95A3l-T_uxvrekZ-TsnHEtBiGhf0Q66CtHM0kvnhOqAaXZCbfVIwuIUCA-9BdxAm9Us7zfcTWUO46R6Ka'
runv2 audit "$(sp "${OPAQUE_TASK_TOKEN}" - -)"
check "v2 audit：宿主不透明任务令牌明确标记，保守选高能力候选" \
  "$(lastlog 'r["task_visibility"] == "opaque_token" and r["decision"]["confidence"] == "low" and r["decision"]["target"]["id"] == "codex-terra-xhigh"')"
runv2verified auto "$(sp "${OPAQUE_TASK_TOKEN}" - -)"
check "v2 auto：不透明任务令牌不自动改写，避免无语义依据的升档" \
  "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "v2 auto：不透明任务令牌保留审计但 applied=false" \
  "$(lastlog 'r["task_visibility"] == "opaque_token" and r["host_pre_dispatch_apply"] is True and r["applied"] is False')"
runv2 audit "$(sp $'完成后 git push 到 origin。\n验收：远端分支可见。' gpt-5.6-terra high)"
check "v2 audit：显式 pin 仍报告 terra/high → terra/xhigh 的 raise，但不产出 target" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "raise" and r["decision"]["target"] is None and r["decision"]["recommended"]["id"] == "codex-terra-xhigh" and r["applied"] is False')"
rm -rf "${LOGD}"
runv2 audit "$(sp $'只读审查配置，禁止修改任何文件。\n验收：报告所有键名。' - - gpt-5.6-terra collaboration.spawn_agent)"
check "v2 audit：MultiAgentV2 原始工具名归一后也记录 select" \
  "$(lastlog 'r["routing_version"] == 2 and r["event"] == "codex-spawn" and r["decision"]["action"] == "select" and r["applied"] is False')"
rm -rf "${LOGD}"
runv2 audit "$(sp $'只读审查配置，禁止修改任何文件。\n验收：报告所有键名。' - - gpt-5.6-terra collaborationspawn_agent)"
check "v2 audit：MultiAgentV2 扁平工具名也记录 select" \
  "$(lastlog 'r["routing_version"] == 2 and r["event"] == "codex-spawn" and r["decision"]["action"] == "select" and r["applied"] is False')"
runv2 auto "${V2SIMPLE}"
check "v2 auto：未验证 Codex 宿主不得改写参数，仍只审计" \
  "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "v2 auto：未验证 Codex 宿主记录 applied=false" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "select" and r["applied"] is False and r["host_pre_dispatch_apply"] is False')"
runv2verified auto "${V2SIMPLE}"
check "v2 auto：已验证 Codex 宿主选择 luna/medium 并带 allow" \
  "$(jsonq 'o["hookSpecificOutput"]["permissionDecision"] == "allow" and o["hookSpecificOutput"]["updatedInput"]["model"] == "gpt-5.6-luna" and o["hookSpecificOutput"]["updatedInput"]["reasoning_effort"] == "medium"')"
check "v2 auto：已验证宿主只改 model / effort，保留完整 spawn 参数" \
  "$(jsonq 'o["hookSpecificOutput"]["updatedInput"]["message"].startswith("只读审查") and o["hookSpecificOutput"]["updatedInput"]["task_name"] == "t1" and o["hookSpecificOutput"]["updatedInput"]["agent_type"] == "worker" and o["hookSpecificOutput"]["updatedInput"]["fork_turns"] == "none"')"
check "v2 auto：已验证宿主的 updatedInput 输出可审计" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "select" and r["host_pre_dispatch_apply"] is True and r["applied"] is True')"
runv2 auto "$(sp $'只读审查配置，禁止修改任何文件。\n验收：报告所有键名。' gpt-5.6-terra high)"
check "v2 auto：显式 model / effort 是 pin，不改写" "$(yn [ -z "${OUT}" ])"
check "v2 auto：pin 留下建议但 target 为空" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "pinned" and r["decision"]["target"] is None and r["decision"]["recommended"]["id"] == "codex-luna-medium" and r["applied"] is False')"
runv2 auto "$(sp $'只读审查配置，禁止修改任何文件。\n验收：报告所有键名。' - high)"
check "v2 auto：仅显式 effort 也视为 pin，不改写" "$(yn [ -z "${OUT}" ])"
runv2verified auto "$(sp $'比较两种缓存架构并权衡后选一个实现。\n验收：给出取舍理由。' - -)"
check "v2 auto：复杂取舍任务选择 terra/xhigh" \
  "$(jsonq 'o["hookSpecificOutput"]["updatedInput"]["model"] == "gpt-5.6-terra" and o["hookSpecificOutput"]["updatedInput"]["reasoning_effort"] == "xhigh"')"
runv2verified auto "$(sp '处理这个问题。' - -)"
check "v2 auto：未知任务保守选择高能力候选" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["confidence"] == "low" and r["decision"]["target"]["id"] == "codex-terra-xhigh" and r["applied"] is True')"
rm -rf "${LOGD}"
runv2 auto "$(sp "${V2SIMPLE}" - - gpt-5.6-terra exec_command)"
check "v2：不是 spawn_agent → stdout 空、不留日志" \
  "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" -a ! -e "${LOGD}/decisions.jsonl" ])"
runv2 auto '{"tool_name":"spawn_agent","tool_input":{"task_name":"t"}}'
check "v2：没有任务文本 → 退出 0、stdout 空且不应用" "$(yn [ "${RC}" -eq 0 -a -z "${OUT}" ])"
check "v2：没有任务文本 → fallback 可审计" \
  "$(lastlog 'r["routing_version"] == 2 and r["decision"]["action"] == "pass" and bool(r["decision"]["fallback"]) and r["applied"] is False')"

MS="$(python3 - "${HOOK}" "$(sp "${IRR}" gpt-5.6-terra high)" "${FAKEHOME}" "${LOGD}" <<'PY'
import os, subprocess, sys, time
hook, payload, home, logd = sys.argv[1:5]
env = dict(os.environ, HOME=home, TIER_GUARD_LOG_DIR=logd, TIER_GUARD_MODE="auto",
           TIER_GUARD_CONFIG=os.path.join(os.path.dirname(os.path.dirname(hook)), "config", "routing.default.json"))
ts = []
for _ in range(15):
    t = time.perf_counter()
    subprocess.run(["/bin/bash", hook], input=payload, capture_output=True, text=True, env=env)
    ts.append((time.perf_counter() - t) * 1000)
print(int(sorted(ts)[len(ts) // 2]))
PY
)"
check "性能：单次执行中位 ${MS}ms < 100ms" "$(yn [ "${MS}" -lt 100 ])"

echo ""
echo "  总计 ${PASS} 通过 / ${FAIL} 失败"
[ "${PASS}" -gt 0 ] && [ "${FAIL}" -eq 0 ]
