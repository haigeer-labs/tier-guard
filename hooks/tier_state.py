#!/usr/bin/env python3
"""tier-guard 的运行时状态：数据目录在哪、当前 mode 是什么。

hook（claude_hook.py）、/tier-report、/tier-mode 共用这一份 —— 数据目录的解析顺序
只许写在这里（tier-guard.sh 在 python 起不来时的兜底记录照抄同一顺序）：

  数据目录  --data 参数 → TIER_GUARD_LOG_DIR → CLAUDE_PLUGIN_DATA → ~/.local/state/tier-guard
  mode      TIER_GUARD_MODE → <数据目录>/mode（/tier-mode 写的）→ 配置默认值

/tier-mode 的 v2 默认是 audit；持久 auto 要等真实宿主质量校准。旧 v1 配置仍可显式读取，
其 mode 集合是 off / dry-run / auto，供历史日志和迁移测试兼容。

用法:
  python3 hooks/tier_state.py show [--data DIR]
  python3 hooks/tier_state.py set <off|audit|auto> [--data DIR]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import route_decide as rd  # noqa: E402

LEGACY_SETTABLE = ("off", "dry-run", "auto")
V2_SETTABLE = ("off", "audit", "auto")


def data_dir(explicit=None):
    return (explicit or os.environ.get("TIER_GUARD_LOG_DIR") or os.environ.get("CLAUDE_PLUGIN_DATA")
            or os.path.join(os.path.expanduser("~"), ".local", "state", "tier-guard"))


def read_mode(ddir, default, allowed=None):
    """→ (mode, 来源说明)。不校验取值 —— 非法值交给 route_decide 判成放行 + fallback。"""
    env = os.environ.get("TIER_GUARD_MODE")
    if env:
        return env, "环境变量 TIER_GUARD_MODE"
    path = os.path.join(ddir, "mode")
    try:
        with open(path, encoding="utf-8") as fh:
            m = fh.read().strip()
    except OSError:
        m = ""
    if m and (allowed is None or m in allowed):
        return m, f"{path}（/tier-mode 设置）"
    if m:
        return default, f"{path} 的旧模式 {m!r} 不适用于当前配置，已回退默认值"
    return default, "当前路由配置默认值"


def _config(path=None):
    try:
        return rd.load_config(path or rd.DEFAULT_CATALOG)
    except Exception:
        return None


def _config_mode():
    """保留给 doctor 等只读调用方的旧接口。"""
    cfg = _config()
    return (cfg or {}).get("mode")


def _profiles(cfg):
    return V2_SETTABLE if isinstance(cfg, dict) and cfg.get("schema_version") == 2 else LEGACY_SETTABLE


def cmd_show(ddir, cfg):
    mode, src = read_mode(ddir, (cfg or {}).get("mode"), _profiles(cfg))
    print(f"当前 mode：{mode}（来源：{src}）")
    print(f"数据目录：{ddir}")
    return 0


def cmd_set(ddir, mode, cfg):
    allowed = _profiles(cfg)
    if mode not in allowed:
        print(f"❌ 未知 mode {mode!r}，只能是 {' / '.join(allowed)}（auto 要先过数据门槛）")
        return 1
    if mode == "auto":
        if isinstance(cfg, dict) and cfg.get("schema_version") == 2:
            print("❌ v2 还没有真实宿主的质量校准证据，拒绝把持久 mode 切到 auto；保持 audit。")
            return 1
        import tier_report                     # 门槛的算法只在 tier_report 里
        recs, _ = tier_report.load(os.path.join(ddir, "decisions.jsonl"))
        ok, reasons = tier_report.gate(recs or [], tier_report.load_labels(ddir), cfg)
        if not ok:
            print("❌ 拒绝切到 auto —— 数据门槛没过：\n" + "\n".join(f"   - {r}" for r in reasons)
                  + "\n   只想临时试：在启动 claude 的 shell 里 export TIER_GUARD_MODE=auto（只对那个会话生效）。")
            return 1
    os.makedirs(ddir, mode=0o700, exist_ok=True)
    with open(os.path.join(ddir, "mode"), "w", encoding="utf-8") as fh:
        fh.write(mode + "\n")
    print(f"✅ mode 已设为 {mode}（写入 {os.path.join(ddir, 'mode')}）")
    if os.environ.get("TIER_GUARD_MODE"):
        print(f"⚠️  但环境变量 TIER_GUARD_MODE={os.environ['TIER_GUARD_MODE']} 优先级更高，本会话仍按它走")
    return 0


def main(argv):
    explicit = cfg_path = None
    if "--data" in argv:
        i = argv.index("--data")
        explicit = argv[i + 1] if i + 1 < len(argv) else None
        argv = argv[:i] + argv[i + 2:]
    if "--config" in argv:
        i = argv.index("--config")
        cfg_path = argv[i + 1] if i + 1 < len(argv) else None
        argv = argv[:i] + argv[i + 2:]
    ddir = data_dir(explicit or None)
    cfg = _config(cfg_path)
    if cfg is None:
        print("❌ 路由配置读不到，拒绝修改 mode")
        return 1
    if argv[:1] == ["set"] and len(argv) == 2:
        return cmd_set(ddir, argv[1], cfg)
    if argv[:1] in (["show"], []):
        return cmd_show(ddir, cfg)
    print("用法: tier_state.py show | set <mode> [--data DIR] [--config PATH]")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
