---
description: 查看或切换 tier-guard 的 mode（off / audit；auto 需真实宿主质量证据）
argument-hint: "[off|audit|auto]"
allowed-tools: Bash
---

参数：`$ARGUMENTS`

- 参数为空：查看当前 mode 和它的来源

  ```bash
  python3 "${CLAUDE_PLUGIN_ROOT}/hooks/tier_state.py" show --data "${CLAUDE_PLUGIN_DATA}"
  ```

- 参数非空：把参数原样作为 `<mode>` 切换

  ```bash
  python3 "${CLAUDE_PLUGIN_ROOT}/hooks/tier_state.py" set "<mode>" --data "${CLAUDE_PLUGIN_DATA}"
  ```

把输出原样转告用户。当前 `auto` 会被拒绝 —— 尚缺真实宿主端到端质量校准证据。
**不要替用户绕过**：不要改环境变量、不要直接编辑状态文件、不要换个说法再试。
