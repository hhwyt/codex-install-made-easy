# Codex 官方安装（HumansLive 包装）：先运行官方安装命令，成功后在 humanslive.ai/tools 点亮这一站。
#   用法：$env:HL_TOKEN='<安装页给的 token>'; irm https://humanslive.ai/codex-official.ps1 | iex
# 官方命令：irm https://chatgpt.com/codex/install.ps1 | iex
# 源码：私有仓库 codex-install-made-easy（网站 public/ 下是副本，改动两边同步）。
$installed = $true
try { irm https://chatgpt.com/codex/install.ps1 | iex } catch { $installed = $false; Write-Host $_ -ForegroundColor Red }

# HL_TOKEN 来自安装页上复制的命令（网站签名，7 天有效）；没有就跳过，请求失败也不影响安装结果。
if ($installed) {
  if ($env:HL_TOKEN) {
    try { Invoke-RestMethod -TimeoutSec 6 -Method Post -ContentType 'application/json' -Body (@{ token = $env:HL_TOKEN } | ConvertTo-Json) 'https://humanslive.ai/api/tools/progress/claim' | Out-Null } catch { }
  }
  Write-Host ''
  Write-Host '  装好了。打开一个新的终端窗口，进入项目文件夹，输入 codex 回车，选 Sign in with ChatGPT 登录。'
  Write-Host ''
}
