#!/usr/bin/env python3
"""校验 tier-routing skill 的候选能力表与 v2 catalog 一致。"""
import json
import os
import re
import sys

SKILL = os.path.join("skills", "tier-routing", "SKILL.md")
CATALOG = os.path.join("config", "routing.catalog.v2.json")


def block(text):
    match = re.search(r"<!-- candidate-table:begin -->\n(.*?)<!-- candidate-table:end -->", text, re.S)
    return match.group(1) if match else None


def pick(candidates, host, capabilities):
    matching = [c for c in candidates if c["host"] == host and c["auto_eligible"]
                and set(capabilities).issubset(c["capabilities"])]
    return min(matching, key=lambda c: (c["cost_rank"], c["id"]))


def main(argv):
    root = argv[0] if argv else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    try:
        skill = open(os.path.join(root, SKILL), encoding="utf-8").read()
        catalog = json.load(open(os.path.join(root, CATALOG), encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"  ❌ 读不到比对对象：{exc}")
        return 1
    table = block(skill)
    if table is None:
        print(f"  ❌ {SKILL} 缺 <!-- candidate-table:begin/end --> 标记")
        return 1
    rows = {}
    for line in table.splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) == 3 and cells[0] != "所需能力" and not cells[0].startswith("---"):
            rows[cells[0]] = (re.findall(r"`([^`]+)`", cells[1]), re.findall(r"`([^`]+)`", cells[2]))
    expected = {}
    for label, capabilities in (("mechanical + read_only", ["mechanical", "read_only"]),
                                ("implementation + bounded_change", ["implementation", "bounded_change"]),
                                ("tradeoff + cross_cutting", ["tradeoff", "cross_cutting"])):
        claude = pick(catalog["candidates"], "claude-code", capabilities)
        codex = pick(catalog["candidates"], "codex-cli", capabilities)
        expected[label] = ([claude["model"]], [codex["model"], codex["reasoning_effort"]])
    ok = True
    for label, want in expected.items():
        got = rows.get(label)
        if got != want:
            print(f"  ❌ 候选表 {label}: SKILL.md={got} 配置={want}")
            ok = False
    extra = set(rows) - set(expected)
    if extra:
        print(f"  ❌ 候选表多出目录里没有的能力行: {sorted(extra)}")
        ok = False
    if ok:
        print("  ✅ SKILL.md 的候选能力表与 v2 catalog 一致")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
