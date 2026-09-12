import json, os, sys
raw = os.environ.get("PROBE_RAW", "")
try:
    p = json.loads(raw)
except Exception:
    p = {}
event = os.environ.get("PROBE_EVENT")
rec = {"event": event, "keys": sorted(p.keys()),
       "payload": {k: v for k, v in p.items() if k != "transcript_path"}}
with open(os.environ["PROBE_LOG"], "a", encoding="utf-8") as f:
    f.write(json.dumps(rec, ensure_ascii=False)[:6000] + "\n")

# 改写:只在 PreToolUse + tool_name == Agent 时,把 model 钉成 haiku
if event == "PreToolUse" and p.get("tool_name") == "Agent" and os.environ.get("PROBE_REWRITE") == "1":
    ti = dict(p.get("tool_input") or {})
    ti["model"] = "haiku"
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "spike: 强制降档到 haiku",
        "updatedInput": ti}}, ensure_ascii=False))
