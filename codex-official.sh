#!/usr/bin/env bash
# Codex 官方安装（HumansLive 包装）：先运行官方安装命令，成功后在 humanslive.ai/tools 点亮这一站。
#   用法：curl -fsSL https://humanslive.ai/codex-official.sh | HL_TOKEN=<安装页给的 token> bash
# 官方命令：curl -fsSL https://chatgpt.com/codex/install.sh | sh

# 以前用国产模型版装过：它写的智谱配置会让 Codex 继续走智谱、不认 ChatGPT 登录。
# 只删国产模型版写的那几行（model_provider = "zhipu"、model = "glm-…"、[model_providers.zhipu]）
# 和只装着智谱 Key 的 auth.json，其余原样保留；改之前先备份。
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
  printf '  已去掉国产模型版的智谱配置（原文件备份为 %s）\n' "$CONFIG$BACKUP_SUFFIX" >&2
fi
if [ -f "$AUTH" ] && grep -Eqx '[{]"OPENAI_API_KEY":"[0-9a-f]{32}[.][A-Za-z0-9]{16}"[}]' "$AUTH"; then
  mv "$AUTH" "$AUTH$BACKUP_SUFFIX"
  printf '  已移走国产模型版的智谱 Key（备份为 %s）\n' "$AUTH$BACKUP_SUFFIX" >&2
fi
# 源码：私有仓库 codex-install-made-easy（网站 public/ 下是副本，改动两边同步）。
set -euo pipefail

curl -fsSL https://chatgpt.com/codex/install.sh | sh

# 以前用国产模型版装过：它写的智谱配置会让 Codex 继续走智谱、不认 ChatGPT 登录。
# 只删国产模型版写的那几行（model_provider = "zhipu"、model = "glm-…"、[model_providers.zhipu]）
# 和只装着智谱 Key 的 auth.json，其余原样保留；改之前先备份。
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
  printf '  已去掉国产模型版的智谱配置（原文件备份为 %s）\n' "$CONFIG$BACKUP_SUFFIX" >&2
fi
if [ -f "$AUTH" ] && grep -Eqx '[{]"OPENAI_API_KEY":"[0-9a-f]{32}[.][A-Za-z0-9]{16}"[}]' "$AUTH"; then
  mv "$AUTH" "$AUTH$BACKUP_SUFFIX"
  printf '  已移走国产模型版的智谱 Key（备份为 %s）\n' "$AUTH$BACKUP_SUFFIX" >&2
fi

# HL_TOKEN 来自安装页上复制的命令（网站签名，7 天有效）；没有就跳过，请求失败也不影响安装结果。
if [ -n "${HL_TOKEN:-}" ]; then
  curl -fsS --max-time 6 -X POST -H 'Content-Type: application/json' -d "{\"token\":\"${HL_TOKEN}\"}" \
    https://humanslive.ai/api/tools/progress/claim >/dev/null 2>&1 || true
fi
printf '\n  装好了。%s\n\n' '打开一个新的终端窗口，进入项目文件夹，输入 codex 回车，选 Sign in with ChatGPT 登录。' >&2

# ---------- 结尾：HumansLive 的其他免费工具和商城 ----------
# 内容和排版来自网站（每行 kind<TAB>a<TAB>b），这里只按 kind 上色；拿不到就只打一行网址，不影响安装结果。
show_banner() {
  local banner kind a b reset="" dim="" bold="" blue="" link=""
  banner=$(curl -fsS --max-time 6 "https://humanslive.ai/api/install-banner?f=$1" 2>/dev/null | tr -d '\033\r') || banner=""
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
