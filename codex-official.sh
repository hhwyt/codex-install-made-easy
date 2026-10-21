#!/usr/bin/env bash
# Codex 官方安装（HumansLive 包装）：先运行官方安装命令，成功后在 humanslive.ai/tools 点亮这一站。
#   用法：curl -fsSL https://humanslive.ai/codex-official.sh | HL_TOKEN=<安装页给的 token> bash
# 官方命令：curl -fsSL https://chatgpt.com/codex/install.sh | sh
# 源码：私有仓库 codex-install-made-easy（网站 public/ 下是副本，改动两边同步）。
set -euo pipefail

curl -fsSL https://chatgpt.com/codex/install.sh | sh

# HL_TOKEN 来自安装页上复制的命令（网站签名，7 天有效）；没有就跳过，请求失败也不影响安装结果。
if [ -n "${HL_TOKEN:-}" ]; then
  curl -fsS --max-time 6 -X POST -H 'Content-Type: application/json' -d "{\"token\":\"${HL_TOKEN}\"}" \
    https://humanslive.ai/api/tools/progress/claim >/dev/null 2>&1 || true
fi
printf '\n  装好了。%s\n\n' '打开一个新的终端窗口，进入项目文件夹，输入 codex 回车，选 Sign in with ChatGPT 登录。' >&2
