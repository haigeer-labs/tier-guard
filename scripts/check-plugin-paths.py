#!/usr/bin/env python3
"""命令 / skill / hooks.json 里引用的 `${CLAUDE_PLUGIN_ROOT}/<路径>` 必须真实存在。

脚本改名或挪位置后，引用它的命令不会报错 —— 模型照着跑一条找不到文件的命令，
然后把「No such file」当成结果转述给用户，或者自己想办法绕过去。静态查一遍是免费的。

用法: python3 scripts/check-plugin-paths.py [仓库根目录]
"""
import glob
import os
import re
import sys

# Claude 用 ${CLAUDE_PLUGIN_ROOT}，Codex 用 ${PLUGIN_ROOT}（两者都会在 hook command 里被替换）
REF = re.compile(r"\$\{(?:CLAUDE_)?PLUGIN_ROOT\}/([A-Za-z0-9_./-]+)")


def main(argv):
    root = argv[0] if argv else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = sorted(glob.glob(os.path.join(root, "commands", "*.md"))
                   + glob.glob(os.path.join(root, "skills", "*", "SKILL.md"))
                   + glob.glob(os.path.join(root, "hooks", "*.json")))
    if not files:
        print("  ❌ 没找到任何命令 / skill / hooks.json —— 「什么都没查」不等于「没问题」")
        return 1
    refs, bad = 0, 0
    for f in files:
        for m in REF.finditer(open(f, encoding="utf-8").read()):
            refs += 1
            if not os.path.exists(os.path.join(root, m.group(1))):
                print(f"  ❌ {os.path.relpath(f, root)} 引用了不存在的 {m.group(0)}")
                bad += 1
    if bad == 0:
        print(f"  ✅ {len(files)} 个文件、{refs} 处 ${{(CLAUDE_)PLUGIN_ROOT}} 引用都指向真实文件")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
