---
description: 人工标注 tier-guard 的判定：R-IRREVERSIBLE 命中是否误报（fp/tp）、T1 产出是否被打回（reject/accept）
argument-hint: "<tool_use_id> <fp|tp|reject|accept>"
allowed-tools: Bash
---

参数：`$ARGUMENTS`

**只接受用户在本轮亲口给出的判定。** 参数不全、或判定是你推断出来的，就停下来问用户，
不要自己补 —— 误报率和打回率决定能不能切 auto，模型替人标注等于自己给自己的守卫放行。

参数齐全时，把 `<tool_use_id>` 和 `<判定>` 原样代入：

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/tier_label.py" "<tool_use_id>" "<判定>" --data "${CLAUDE_PLUGIN_DATA}"
```

把输出原样转告用户。报错（id 不存在、类型对不上）就照实说，不要换个 id 重试。
