#!/bin/bash
# ─────────────────────────────────────────────────────────────
# 装 pre-push 钩子。
#
# 为什么需要：本仓没有 CI。所有断言都依赖「一个人记得在自己机器上敲那几条
# 命令」，而 spec-guard 的经验是这个人会忘。钩子是止血带，不是解药。
#
# 只跑不花钱的那几层；变异测试不在里面。
# 急着推可以 `git push --no-verify` 绕过，但那就回到了「靠自觉」。
#
# 用法: /bin/bash scripts/install-git-hooks.sh [--uninstall]
# ─────────────────────────────────────────────────────────────
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARK="tier-guard-pre-push"
DIR="$(git -C "${ROOT}" rev-parse --git-path hooks 2>/dev/null)" || {
  echo "❌ ${ROOT} 不是 git 仓库"; exit 1; }
case "${DIR}" in /*) ;; *) DIR="${ROOT}/${DIR}" ;; esac
HOOK="${DIR}/pre-push"

ours() { grep -q "${MARK}" "${HOOK}" 2>/dev/null; }

if [ "${1:-}" = "--uninstall" ]; then
  if [ ! -f "${HOOK}" ]; then echo "⏭  没装过"; exit 0; fi
  if ! ours; then echo "❌ ${HOOK} 不是本脚本装的 —— 不删别人的钩子"; exit 1; fi
  rm -f "${HOOK}" && echo "✅ 已移除 ${HOOK}"
  exit 0
fi

if [ -f "${HOOK}" ] && ! ours; then
  echo "❌ ${HOOK} 已存在且不是本脚本装的 —— 不覆盖别人的钩子，请人工合并"
  exit 1
fi

mkdir -p "${DIR}"
cat > "${HOOK}" <<'PRE'
#!/bin/bash
# tier-guard-pre-push —— 由 scripts/install-git-hooks.sh 生成
# 绕过: git push --no-verify
set -uo pipefail
R="$(git rev-parse --show-toplevel)" || exit 1
# git 会给钩子导出 GIT_DIR 等仓库局部变量；测试里若自建临时仓库，
# 这些变量会让那边的 git 命令打到本仓上。先清掉。
GIT_LOCAL_VARS="$(git rev-parse --local-env-vars)" || exit 1
while IFS= read -r git_var; do
  [ -z "${git_var}" ] || unset "${git_var}" || exit 1
done <<< "${GIT_LOCAL_VARS}"
echo "── pre-push: 跑不花钱的那几层 ──"
F=0
# 每样只跑**一遍**，输出存变量。跑两遍（一遍取输出一遍取退出码）会让
# pre-push 慢一倍，而慢到让人条件反射加 --no-verify 就等于没装。
chk() {  # $1=说明 其余=命令
  local name="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "${rc}" -eq 0 ]; then
    printf '  ✅ %s —— %s\n' "${name}" "$(printf '%s' "${out}" | tail -1 | sed 's/^ *//')"
  else
    printf '  ❌ %s\n' "${name}"
    printf '%s\n' "${out}" | grep -E "^ *❌|[1-9][0-9]* 失败" | head -8 | sed 's/^/     /'
    F=1
  fi
}
# 显式 /bin/bash：macOS 自带的 3.2 才是要防的那个版本
chk "validate" /bin/bash "${R}/scripts/validate.sh"
if [ "${F}" -ne 0 ]; then
  echo "❌ 有检查没过 —— push 中止。细节见上面，或单独跑 /bin/bash scripts/validate.sh"
  echo "   确实要推: git push --no-verify"
  exit 1
fi
echo "✅ 全绿，继续 push"
PRE
chmod +x "${HOOK}"
echo "✅ 已装 ${HOOK}"
echo "   它会跑 scripts/validate.sh。绕过: git push --no-verify"
