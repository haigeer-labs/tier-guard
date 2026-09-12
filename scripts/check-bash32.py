#!/usr/bin/env python3
"""找出 bash 3.2 会误解析的 `$VAR<多字节字符>`。

macOS 自带的 /bin/bash 是 3.2：它把紧跟在 `$VAR` 后面的多字节字符（如全角
括号「）」）的首字节吃进变量名，配合 `set -u` 直接致命退出。hook 出错是
静默的，所以线上表现是「守卫突然不说话了」。Linux 的 bash 5 多字节安全，
只在 Linux 上跑看不出来 —— 所以做成静态检查。修法：写成 `${VAR}`。

用法: python3 scripts/check-bash32.py <文件>...
"""
import re
import sys

PAT = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]")


def main(paths):
    if not paths:
        print("  ❌ 没有传入任何文件 —— 「什么都没查」不等于「没问题」")
        return 1
    bad = 0
    for path in paths:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                for m in PAT.finditer(line):
                    var = m.group(0)[1:-1]
                    print(f"  ❌ {path}:{lineno} ${var} 后紧跟多字节字符，写成 ${{{var}}}")
                    bad += 1
    if bad == 0:
        print(f"  ✅ {len(paths)} 个文件，无 bash 3.2 多字节解析陷阱")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
