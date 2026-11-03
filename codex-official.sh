#!/usr/bin/env bash
# Codex official install (HumansLive wrapper): removes the Zhipu config left by the Chinese-model edition,
# then runs OpenAI's official install command.
#   Usage: curl -fsSL https://humanslive.ai/codex-official.sh | bash
# Official command: curl -fsSL https://chatgpt.com/codex/install.sh | sh
# Source: https://github.com/hhwyt/codex-install-made-easy
set -euo pipefail

# ---------- Terminal output ----------
# One accent color (blue), gray for secondary text, red only for errors. No color or animation when stderr is
# not a terminal or NO_COLOR is set.
# All messages go to stderr; stdout is reserved for $(...) captures.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_BLUE=$'\033[38;5;33m' C_RED=$'\033[31m'
  LIVE=1
else
  C_RESET="" C_BOLD="" C_DIM="" C_BLUE="" C_RED="" LIVE=""
fi
STEP=0
# Show the home directory as ~
short_path() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
term_cols() { local cols; cols=$( { stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2); [ "${cols:-0}" -gt 0 ] 2>/dev/null && echo "$cols" || echo 80; }
header() {
  printf '\n  %sHumansLive%s  %s%s%s\n  %s%s%s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" "$C_DIM" "$2" "$C_RESET" >&2
}
say()  { STEP=$((STEP + 1)); printf '\n  %s%d/%d%s  %s%s%s\n' "$C_BLUE$C_BOLD" "$STEP" "$STEPS" "$C_RESET" "$C_BOLD" "$*" "$C_RESET" >&2; }
info() { printf '       %s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }
ok()   { printf '     %s✓%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
todo() { printf '     %s→%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET" >&2; }
done_line() {
  local took="$((SECONDS % 60)) 秒"; [ "$SECONDS" -lt 60 ] || took="$((SECONDS / 60)) 分 $took"
  printf '\n  %s✓ 全部完成%s  %s用时 %s%s\n     %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$C_DIM" "$took" "$C_RESET" "$*" >&2
}
fail() {
  [ -z "$LIVE" ] || printf '\r\033[K' >&2
  printf '\n  %s✗ 出错了%s\n     %s\n     %s需要帮助：截图发到社群 https://humanslive.ai/community%s\n\n' "$C_RED$C_BOLD" "$C_RESET" "$*" "$C_DIM" "$C_RESET" >&2
  exit 1
}

STEPS=2
header "Codex 官方安装" "用 OpenAI 官方安装命令，登录你自己的 ChatGPT 账号"

say "检查旧配置"
CLEANED=""
# A previous Chinese-model install leaves a Zhipu config that keeps Codex on Zhipu and ignores ChatGPT sign-in.
# Remove only the lines that edition wrote (model_provider = "zhipu", model = "glm-…", [model_providers.zhipu])
# and an auth.json that holds only a Zhipu key; keep everything else and back up first.
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME/config.toml"
AUTH="$CODEX_HOME/auth.json"
BACKUP_SUFFIX=".bak-$(date +%Y%m%d%H%M%S)"
if [ -f "$CONFIG" ] && grep -Eq '^[[:space:]]*model_provider[[:space:]]*=[[:space:]]*"zhipu"' "$CONFIG"; then
  cp "$CONFIG" "$CONFIG$BACKUP_SUFFIX"
  awk '
    /^\[/ { in_table = 1; skip = ($0 == "[model_providers.zhipu]") }
    !in_table && /^[[:space:]]*model_provider[[:space:]]*=[[:space:]]*"zhipu"/ { next }
    !in_table && /^[[:space:]]*model[[:space:]]*=[[:space:]]*"glm-/ { next }
    !skip { print }
  ' "$CONFIG$BACKUP_SUFFIX" > "$CONFIG"
  CLEANED=1; ok "已去掉国产模型版的智谱配置"; info "原文件备份为 $(short_path "$CONFIG")$BACKUP_SUFFIX"
fi
if [ -f "$AUTH" ] && grep -Eqx '[{]"OPENAI_API_KEY":"[0-9a-f]{32}[.][A-Za-z0-9]{16}"[}]' "$AUTH"; then
  mv "$AUTH" "$AUTH$BACKUP_SUFFIX"
  CLEANED=1; ok "已移走国产模型版的智谱 Key"; info "备份为 $(short_path "$AUTH")$BACKUP_SUFFIX"
fi
[ -n "$CLEANED" ] || ok "没有要处理的旧配置"

say "运行 OpenAI 官方安装命令"
info "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
printf '\n' >&2
curl -fsSL https://chatgpt.com/codex/install.sh | sh || fail "官方安装命令没有成功，看上面的英文提示；网络问题的话，确认能打开 chatgpt.com 后重试。"

done_line "Codex 已装好，接下来："
todo "打开一个新的终端窗口，进入项目文件夹，输入 codex 回车"
todo "选 Sign in with ChatGPT，用你的 ChatGPT 账号登录"

# ---------- Closing banner: other free HumansLive tools ----------
# Content and layout come from the website (one kind<TAB>a<TAB>b per line); this only colors by kind.
# If it cannot be fetched, print one URL instead; the install result is unaffected.
show_banner() {
  local banner kind a b reset="" dim="" bold="" blue="" link=""
  banner=$(curl -fsS --max-time 6 "https://humanslive.ai/api/install-banner?f=$1&w=$(term_cols)" 2>/dev/null | tr -d '\033\r') || banner=""
  if [ -z "$banner" ]; then printf '\n  更多免费工具和服务：https://humanslive.ai\n\n' >&2; return 0; fi
  if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    reset=$'\033[0m' dim=$'\033[2m' bold=$'\033[1m' blue=$'\033[1;38;5;33m' link=$'\033[4;38;5;33m'
  fi
  while IFS=$'\t' read -r kind a b; do
    case "$kind" in
      rule)  printf '  %s%s%s\n' "$dim" "$a" "$reset" ;;
      brand) printf '  %s%s%s%s\n' "$bold" "$a" "$reset" "$b" ;;
      head)  printf '  %s%s%s  %s%s%s\n' "$blue" "$a" "$reset" "$dim" "$b" "$reset" ;;
      row)   printf '    %s%s%s%s\n' "$a" "$dim" "$b" "$reset" ;;
      link)  printf '    %s%s%s\n' "$link" "$a" "$reset" ;;
      *)     printf '\n' ;;
    esac
  done <<< "$banner" >&2
  return 0
}
show_banner codex
