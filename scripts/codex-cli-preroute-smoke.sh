#!/bin/bash
# 在真实交互式 Terminal 中验收 Codex CLI 的主代理明文预路由。
# 不使用 codex exec：该入口的 collaboration wait 不会创建可观察 child。
set -eu

if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "请在真实交互式 Terminal 中运行；CI、管道和伪终端不能替代 Codex TUI。" >&2
  exit 2
fi
if ! command -v codex >/dev/null 2>&1; then
  echo "找不到 codex 命令。" >&2
  exit 2
fi

SMOKE_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/tier-guard-cli-preroute.XXXXXX")"
SMOKE_LOG_DIR="${SMOKE_DIR}/tier-logs"
mkdir -p "${SMOKE_LOG_DIR}"
git -C "${SMOKE_DIR}" init -q
git -C "${SMOKE_DIR}" config user.email tier-guard@example.invalid
git -C "${SMOKE_DIR}" config user.name tier-guard-probe

PROMPT=$'Use the installed tier-routing skill. Create exactly three native child agents, one at a time, and wait for each. The parent may read the skill but must not modify the project. Do not tell me model choices before spawning.\n\nChild A is a mechanical read-only task; it must not use tools, read files, write files, or run commands, and must reply exactly CLI_PREROUTE_LUNA_OK.\n\nChild B is a bounded implementation task with explicit acceptance; it must not use tools, read files, write files, or run commands, and must reply exactly CLI_PREROUTE_TERRA_OK.\n\nChild C compares approaches involving risk, cost, and rollback tradeoffs; it must not use tools, read files, write files, or run commands, and must reply exactly CLI_PREROUTE_XHIGH_OK.\n\nFor each child, independently choose and explicitly pass the lowest-cost qualified model and reasoning effort according to tier-routing. After all three finish, report their replies only.'

echo "隔离工作目录：${SMOKE_DIR}"
echo "唯一审计目录：${SMOKE_LOG_DIR}"
echo "父代理：gpt-5.6-terra / high；生产 catalog 保持 audit。"
echo "在 TUI 显示三个 child 回复后，退出 Codex 回到此脚本以打印只读证据。"

TIER_GUARD_LOG_DIR="${SMOKE_LOG_DIR}" TIER_GUARD_MODE=audit \
  codex -C "${SMOKE_DIR}" -m gpt-5.6-terra -c 'model_reasoning_effort="high"' \
  --no-alt-screen -s read-only -a never "${PROMPT}"

echo ""
echo "=== tier-guard 审计记录 ==="
if [ -f "${SMOKE_LOG_DIR}/decisions.jsonl" ]; then
  tail -n 3 "${SMOKE_LOG_DIR}/decisions.jsonl"
else
  echo "没有审计记录；不要据此宣布测试通过。"
fi

echo ""
echo "=== Codex 本地线程（仅此隔离 cwd） ==="
python3 - "${SMOKE_DIR}" <<'PY'
import sqlite3
import sys

cwd = sys.argv[1]
con = sqlite3.connect('/Users/vilin/.codex/state_5.sqlite')
for row in con.execute(
    'select id, model, reasoning_effort, title from threads where cwd = ? order by created_at',
    (cwd,),
):
    print('\t'.join('' if value is None else str(value) for value in row))
PY

echo ""
echo "通过条件：三个 child 回复、三条对应审计记录，且线程实际为 luna/medium、terra/high、terra/xhigh。"
echo "保留上述目录作证据；本脚本不会删除它。"
