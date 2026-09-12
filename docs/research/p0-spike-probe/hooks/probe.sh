#!/bin/bash
set -uo pipefail
LOG="${PROBE_LOG:?}"
EVENT="${1:-unknown}"
# 先把 stdin 吃进变量 —— 不能让 heredoc 抢走 stdin（第一版就是栽在这）
PROBE_RAW="$(cat)"
export PROBE_RAW PROBE_LOG PROBE_EVENT="$EVENT"
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/probe.py"
exit 0
