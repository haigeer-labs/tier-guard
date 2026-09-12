#!/usr/bin/env python3
"""校验 Claude 与 Codex 两份插件清单互为镜像。

版本号是使用者收到更新的唯一信号。两份清单只升了一份，另一个宿主的使用者
就永远停在旧版，而且没有任何报错。所以：两份都必须存在，name 相同，
version 相同且是标准 `X.Y.Z`（可带 prerelease）或 Codex 本地更新所需的
`+codex.<cachebuster>`。两边都没写 version 也算不一致（None == None 不是通过）。

用法: python3 scripts/check-manifests.py [仓库根目录]   # 默认是本脚本所在的仓库
"""
import json
import os
import re
import sys

HOSTS = ("claude", "codex")
# 本地 marketplace 的更新快照用 `+codex.<token>` 区分。只放行这个 build metadata，
# 防止任意字符串伪装成版本号，也保证两个宿主的清单仍能精确镜像。
SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+codex\.[a-z0-9]+(?:-[a-z0-9]+)*)?$")


def load(root, host):
    rel = os.path.join(f".{host}-plugin", "plugin.json")
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        return None, f"{rel} 不存在"
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as e:
        return None, f"{rel} 解析失败：{e}"
    if not isinstance(data, dict):
        return None, f"{rel} 顶层不是 JSON 对象"
    return data, None


def main(argv):
    root = argv[0] if argv else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    manifests, ok = {}, True
    for host in HOSTS:
        data, err = load(root, host)
        if err:
            print(f"  ❌ {err}")
            ok = False
        else:
            manifests[host] = data
    if not ok:
        return 1

    for host, m in manifests.items():
        if not isinstance(m.get("name"), str) or not m.get("name"):
            print(f"  ❌ {host}: 缺 name")
            ok = False
        version = m.get("version")
        if not isinstance(version, str) or not SEMVER.match(version):
            print(f"  ❌ {host}: version 必须是 X.Y.Z 或 X.Y.Z+codex.<cachebuster>，实际 {version!r}")
            ok = False

    claude, codex = manifests["claude"], manifests["codex"]
    if claude.get("name") != codex.get("name"):
        print(f"  ❌ 名称不一致: Claude={claude.get('name')!r} Codex={codex.get('name')!r}")
        ok = False
    if claude.get("version") != codex.get("version"):
        print(f"  ❌ 版本不一致: Claude={claude.get('version')!r} Codex={codex.get('version')!r}"
              " —— 只升一份，另一个宿主的使用者收不到更新")
        ok = False

    # marketplace（Claude 与 Codex 都认 .claude-plugin/marketplace.json）：条目名 = 插件名，source 指向插件根
    mp = os.path.join(root, ".claude-plugin", "marketplace.json")
    if os.path.isfile(mp):
        try:
            with open(mp, encoding="utf-8") as fh:
                entries = json.load(fh).get("plugins") or []
        except (OSError, ValueError, AttributeError) as e:
            print(f"  ❌ marketplace.json 解析失败：{e}")
            entries, ok = [], False
        if not entries:
            print("  ❌ marketplace.json 里没有 plugins 条目")
            ok = False
        for entry in entries:
            src = os.path.join(root, str(entry.get("source", "")))
            if entry.get("name") != claude.get("name"):
                print(f"  ❌ marketplace 条目名 {entry.get('name')!r} ≠ 插件名 {claude.get('name')!r}")
                ok = False
            if not os.path.isfile(os.path.join(src, ".claude-plugin", "plugin.json")):
                print(f"  ❌ marketplace 条目 source={entry.get('source')!r} 下没有 .claude-plugin/plugin.json")
                ok = False

    # 清单里声明的路径必须真实存在 —— 指向不存在的 hooks 文件时，宿主静默不装 hook，守卫整个不在场
    for host, m in manifests.items():
        for field in ("hooks", "skills", "commands", "agents"):
            rel = m.get(field)
            if isinstance(rel, str) and not os.path.exists(os.path.join(root, rel)):
                print(f"  ❌ {host}: {field} 指向不存在的 {rel}")
                ok = False

    if ok:
        print(f"  ✅ {claude['name']} v{claude['version']}（Claude 与 Codex 清单一致）")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
