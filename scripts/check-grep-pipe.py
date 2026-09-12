#!/usr/bin/env python3
"""找出 `cmd | grep -q` —— 本仓禁止的写法。

`grep -q` 命中即退出、关掉管道读端，还在写的上游命令吃到 SIGPIPE(141)，
`set -o pipefail` 把 141 传出来，判断因此永远为假。hook 出错是静默的，
线上表现是「守卫突然不说话了」或「豁免莫名其妙失效」。

修法：herestring `grep -q pat <<<"$(cmd)"`，或纯 bash 的 `case`。

判据的三个边界（各有反向用例盯着，见 test-checkers.sh）：
  - `-q` 不一定是第一个选项：`| grep -E -q pat` 一样中招
  - `a || grep -q pat file` 是逻辑或，不是管道，不能报
  - 整行注释里解释这个坑是允许的

用法: python3 scripts/check-grep-pipe.py <文件>...
"""
import re
import sys

# 单个 `|`（排除 `||`）→ grep → 同一段命令里任意位置的 -q / -qE / --quiet
PAT = re.compile(r"(?<!\|)\|(?!\|)\s*grep\b[^|;&]*?\s(?:-[A-Za-z]*q[A-Za-z]*|--quiet)(?=\s|$)")


def main(paths):
    if not paths:
        print("  ❌ 没有传入任何文件 —— 「什么都没查」不等于「没问题」")
        return 1
    bad = 0
    for path in paths:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                if line.lstrip().startswith("#"):
                    continue
                if PAT.search(line):
                    print(f"  ❌ {path}:{lineno} `cmd | grep -q` 会因 SIGPIPE 永远判假，"
                          f"改用 herestring: grep -q pat <<<\"$(cmd)\"")
                    bad += 1
    if bad == 0:
        print(f"  ✅ {len(paths)} 个文件，无 `cmd | grep -q` SIGPIPE 陷阱")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
