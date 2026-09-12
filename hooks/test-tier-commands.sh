#!/bin/bash
# ─────────────────────────────────────────────────────────────
# /tier-mode（tier_state.py）与 /tier-report（tier_report.py）的回归断言。
#
# 报表的输入不手写：先让真的 hook（tier-guard.sh）判一轮，再汇总它写下的日志 ——
# 手写的日志夹具只能证明报表认得「我以为 hook 会写的格式」。
# ─────────────────────────────────────────────────────────────
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
PASS=0; FAIL=0
check() { if [ "$2" = yes ]; then printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); else printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); fi; }
# yn 只包一条命令。复合条件写成具名函数再交给 yn —— `$(yn A && B)` 里 yn 先打印了 yes，
# B 失败也改不了结果，是一条永远为真的空断言。
yn() { if "$@"; then echo yes; else echo no; fi; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }   # 纯 bash 子串判断，不走管道

DATA="${TMP}/data"; FAKEHOME="${TMP}/home"; mkdir -p "${FAKEHOME}"
state()  { env -u TIER_GUARD_MODE HOME="${FAKEHOME}" python3 "${ROOT}/hooks/tier_state.py" "$@" --data "${DATA}" --config "${ROOT}/config/routing.default.json"; }
statev2() { env -u TIER_GUARD_MODE HOME="${FAKEHOME}" python3 "${ROOT}/hooks/tier_state.py" "$@" --data "${V2STATE}" --config "${ROOT}/config/routing.catalog.v2.json"; }
statecurrent() { env -u TIER_GUARD_MODE HOME="${FAKEHOME}" python3 "${ROOT}/hooks/tier_state.py" "$@" --data "${V2STATE}"; }
report() { env -u TIER_GUARD_MODE HOME="${FAKEHOME}" python3 "${ROOT}/hooks/tier_report.py" --data "${DATA}"; }
hook() {  # $1=事件 $2=payload [$3=TIER_GUARD_MODE，空 = 不设]
  if [ -n "${3:-}" ]; then
    printf '%s' "$2" | env HOME="${FAKEHOME}" TIER_GUARD_LOG_DIR="${DATA}" TIER_GUARD_MODE="$3" TIER_GUARD_CONFIG="${ROOT}/config/routing.default.json" /bin/bash "${ROOT}/hooks/tier-guard.sh" "$1"
  else
    printf '%s' "$2" | env -u TIER_GUARD_MODE HOME="${FAKEHOME}" TIER_GUARD_LOG_DIR="${DATA}" TIER_GUARD_CONFIG="${ROOT}/config/routing.default.json" /bin/bash "${ROOT}/hooks/tier-guard.sh" "$1"
  fi
}
hookv2() {  # $1=数据目录 $2=profile $3=事件 $4=payload
  printf '%s' "$4" | env HOME="${FAKEHOME}" TIER_GUARD_LOG_DIR="$1" TIER_GUARD_MODE="$2" \
    TIER_GUARD_CONFIG="${ROOT}/config/routing.catalog.v2.json" /bin/bash "${ROOT}/hooks/tier-guard.sh" "$3"
}
hookv2state() {  # $1=数据目录 $2=事件 $3=payload
  printf '%s' "$3" | env -u TIER_GUARD_MODE HOME="${FAKEHOME}" TIER_GUARD_LOG_DIR="$1" \
    TIER_GUARD_CONFIG="${ROOT}/config/routing.catalog.v2.json" /bin/bash "${ROOT}/hooks/tier-guard.sh" "$2"
}
hookcurrent() {  # $1=数据目录 $2=事件 $3=payload
  printf '%s' "$3" | env -u TIER_GUARD_MODE HOME="${FAKEHOME}" TIER_GUARD_LOG_DIR="$1" \
    /bin/bash "${ROOT}/hooks/tier-guard.sh" "$2"
}
v2_state_audit() {
  python3 - "${V2STATE}/decisions.jsonl" <<'PY'
import json, sys
try:
    record = json.loads(open(sys.argv[1], encoding="utf-8").read().splitlines()[-1])
    raise SystemExit(0 if record["decision"]["profile"] == "audit" else 1)
except Exception:
    raise SystemExit(1)
PY
}
mk() {  # $1=prompt $2=model(- 不传)
  python3 -c 'import json,sys
ti={"description":"t","prompt":sys.argv[1],"subagent_type":"general-purpose"}
if sys.argv[2]!="-": ti["model"]=sys.argv[2]
print(json.dumps({"session_id":"s","tool_use_id":"u","tool_name":"Agent","tool_input":ti},ensure_ascii=False))' "$1" "$2"
}
bashp() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1"; }
# PAD 要让 prompt 真的越过收益门槛（150 字），否则「放行」那条会被判成 local —— 第一版就栽在这
PAD="背景：这是一段中性的背景说明，只用来让 prompt 越过收益门槛，不含任何判据词。背景：这是一段中性的背景说明，只用来让 prompt 越过收益门槛。背景：再补一句中性的说明文字，凑够长度。背景：再补一句中性的说明文字。"
PAD="${PAD}${PAD}"
AC=$'\n验收：pytest 全绿\n'

echo "═══ /tier-mode ═══"
OUT="$(state show)"
check "legacy show：显式旧配置默认 dry-run" "$(yn has "${OUT}" "当前 mode：dry-run（来源：当前路由配置默认值）")"
state set off >/dev/null; RC=$?
check "set off → 退出 0，写入状态文件" "$(yn [ "${RC}" -eq 0 -a "$(cat "${DATA}/mode" 2>/dev/null)" = off ])"
check "show：状态文件生效" "$(yn has "$(state show)" "当前 mode：off")"
OUT="$(hook agent "$(mk "改完后 git push。${AC}${PAD}" sonnet)")"
check "状态文件 off → hook stdout 空、不留日志" "$(yn [ -z "${OUT}" -a ! -e "${DATA}/decisions.jsonl" ])"
OUT="$(hook agent "$(mk "改完后 git push。${AC}${PAD}" sonnet)" auto)"
check "环境变量优先于状态文件（env=auto 压过 off）" "$(yn has "${OUT}" '"updatedInput"')"
rm -f "${DATA}/decisions.jsonl"
OUT="$(state set auto)"; RC=$?
c_auto_rejected() { [ "${RC}" -ne 0 ] && has "${OUT}" "数据门槛没过"; }
check "set auto → 拒绝（退出非零、说明数据门槛没过）" "$(yn c_auto_rejected)"
check "set auto → 状态文件没被改" "$(yn [ "$(cat "${DATA}/mode")" = off ])"
state set deny >/dev/null; RC=$?
check "set 未知值 → 拒绝" "$(yn [ "${RC}" -ne 0 ])"
state set dry-run >/dev/null

echo ""
echo "═══ /tier-report ═══"
rm -rf "${TMP}/empty"
OUT="$(env -u TIER_GUARD_MODE HOME="${FAKEHOME}" python3 "${ROOT}/hooks/tier_report.py" --data "${TMP}/empty")"; RC=$?
c_empty() { [ "${RC}" -eq 0 ] && has "${OUT}" "还没有任何记录"; }
check "没有日志 → 退出 0，明说还没有记录" "$(yn c_empty)"

# 让真 hook 判一轮（状态文件是 dry-run）
hook agent "$(mk "改完后 git push 到 origin。${AC}${PAD}" sonnet)"        >/dev/null  # 欠配
hook agent "$(mk "检查有没有人写了 git push。${AC}${PAD}" sonnet)"        >/dev/null  # 欠配 + 疑似误报
hook agent "$(mk "改完后 git push 到 origin。${AC}${PAD}" -)"             >/dev/null  # 起点未知被钉 T2
hook agent "$(mk "按 spec 实现缓存层。${AC}${PAD}" sonnet)"               >/dev/null  # 放行
hook agent "$(mk "改个常量。${AC}" sonnet)"                               >/dev/null  # 建议 local
hook bash  "$(bashp "bash /x/codex-exec.sh --model gpt-5.6-terra --effort high \"按 spec 实现缓存层。${AC}${PAD}\"")" >/dev/null
hook bash  "$(bashp "bash /x/codex-exec.sh --model gpt-5.6-terra --effort high \"改完后 git push。${AC}${PAD}\"")"   >/dev/null
hook bash  "$(bashp 'ls -la')" >/dev/null                                                                          # 不记
REP="$(report)"
check "report：判定总数 5" "$(yn has "${REP}" "| 判定总数 | 5 |")"
check "report：欠配 2（只算起点已知的）" "$(yn has "${REP}" "被判 raise） | 2 |")"
check "report：其中疑似误报 1" "$(yn has "${REP}" "其中疑似误报（只是提到动作词） | 1 |")"
check "report：dry-run 下 hook 改写输出 0" "$(yn has "${REP}" "其中 auto 下 hook 已输出改写 | 0 |")"
check "report：起点未知被钉 T2 单列 1" "$(yn has "${REP}" "不计入欠配） | 1 |")"
check "report：建议 local 1" "$(yn has "${REP}" "| 建议 local / defer | 1 / 0 |")"
check "report：Codex 一致 1 / 不一致 1（普通 Bash 不计）" "$(yn has "${REP}" "共 2 次：一致 1 / 不一致 1")"
check "report：Codex 表格给出建议值（不一致那条建议 xhigh）" "$(yn has "${REP}" "| gpt-5.6-terra / high | gpt-5.6-terra / xhigh | ❌ |")"
check "report：当前 mode 来自状态文件" "$(yn has "${REP}" "当前 mode：**dry-run**")"
c_sections() { has "${REP}" "### 建议档 vs 实际执行档" && has "${REP}" "### 打回率" && has "${REP}" "### 误报率" && has "${REP}" "### 切 auto 的门槛"; }
check "report：建议 vs 实际 / 打回率 / 误报率 / auto 门槛 四节都在" "$(yn c_sections)"
printf 'not json\n' >> "${DATA}/decisions.jsonl"
OUT="$(report)"; RC=$?
c_broken() { [ "${RC}" -eq 0 ] && has "${OUT}" "有 1 行不是合法 JSON"; }
check "report：坏行跳过并提示，仍退出 0" "$(yn c_broken)"

echo ""
echo "═══ v2 路由审计 ═══"
V2DATA="${TMP}/v2-data"
V2STATE="${TMP}/v2-state"
V2SIMPLE=$'只读审查配置，禁止修改任何文件。\n验收：报告所有键名。'
check "运行时默认：mode 命令读取 v2 audit" "$(yn has "$(statecurrent show)" "当前 mode：audit")"
hookcurrent "${V2STATE}" agent "$(mk "${V2SIMPLE}" -)" >/dev/null
check "运行时默认：Claude hook 产生 v2 审计记录" "$(yn v2_state_audit)"
check "v2 mode：默认是 audit" "$(yn has "$(statev2 show)" "当前 mode：audit")"
statev2 set audit >/dev/null; RC=$?
check "v2 mode：set audit 写入状态文件" "$(yn [ "${RC}" -eq 0 -a "$(cat "${V2STATE}/mode")" = audit ])"
statev2 set dry-run >/dev/null; RC=$?
check "v2 mode：拒绝遗留 dry-run 名称" "$(yn [ "${RC}" -ne 0 ])"
OUT="$(statev2 set auto)"; RC=$?
check "v2 mode：无真实宿主质量证据时拒绝持久 auto" "$(yn [ "${RC}" -ne 0 -a "$(cat "${V2STATE}/mode")" = audit ])"
hookv2state "${V2STATE}" agent "$(mk "${V2SIMPLE}" -)" >/dev/null
check "v2 mode：hook 从状态文件读 audit" \
  "$(yn v2_state_audit)"
hookv2 "${V2DATA}" audit agent "$(mk "${V2SIMPLE}" -)" >/dev/null
hookv2 "${V2DATA}" auto agent "$(mk "${V2SIMPLE}" -)" >/dev/null
# 显式 model 是 pin：真实 hook 要记录建议，但绝不能偷偷覆盖用户指定值。
hookv2 "${V2DATA}" audit agent "$(mk "${V2SIMPLE}" sonnet)" >/dev/null
V2REP="$(env -u TIER_GUARD_MODE HOME="${FAKEHOME}" python3 "${ROOT}/hooks/tier_report.py" --data "${V2DATA}")"
check "v2 report：列出请求、选择、hook 改写输出与实际观测" \
  "$(yn has "${V2REP}" "### v2 路由审计")"
v2_host_capability() { has "${V2REP}" "宿主可改写" && has "${V2REP}" "是"; }
check "v2 report：列出宿主是否获准派发前改写" "$(yn v2_host_capability)"
v2_profiles() { has "${V2REP}" "audit：2 / auto：1" && has "${V2REP}" "haiku"; }
check "v2 report：audit / auto 分开且能看到 selected haiku" \
  "$(yn v2_profiles)"
v2_pin() { has "${V2REP}" "pin 1" && has "${V2REP}" "| lower |"; }
check "v2 report：audit 的 pin 保留方向建议、仍不写成实际执行" \
  "$(yn v2_pin)"
v2_no_token() { has "${V2REP}" "未观测" && ! has "${V2REP}" "token"; }
check "v2 report：未观测到实际执行时明确写未知，不推算 token" \
  "$(yn v2_no_token)"

echo ""
echo "  总计 ${PASS} 通过 / ${FAIL} 失败"
[ "${PASS}" -gt 0 ] && [ "${FAIL}" -eq 0 ]
