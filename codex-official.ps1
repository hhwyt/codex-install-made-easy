# Codex 官方安装（HumansLive 包装）：先运行官方安装命令，成功后在 humanslive.ai/tools 点亮这一站。
#   用法：irm https://humanslive.ai/codex-official.ps1 | iex
# 官方命令：irm https://chatgpt.com/codex/install.ps1 | iex
# 源码：私有仓库 codex-install-made-easy（网站 public/ 下是副本，改动两边同步）。
# ---------- 终端输出 ----------
# 一个强调色（青蓝），次要信息用灰色，红色只用于出错。√ → × 在中文版和英文版 Windows 的默认字体里都有。
$Script:Step = 0
$Script:Started = Get-Date
function Get-ConsoleWidth { try { [int]$Host.UI.RawUI.WindowSize.Width } catch { 80 } }
function Header($title, $subtitle) {
  Write-Host ''
  Write-Host '  HumansLive  ' -NoNewline -ForegroundColor Cyan
  Write-Host $title -ForegroundColor White
  Write-Host "  $subtitle" -ForegroundColor DarkGray
}
function Say($text) {
  $Script:Step++
  Write-Host ''
  Write-Host "  $($Script:Step)/$Steps  " -NoNewline -ForegroundColor Cyan
  Write-Host $text -ForegroundColor White
}
function Info($text) { Write-Host "       $text" -ForegroundColor DarkGray }
function Ok($text)   { Write-Host '     √ ' -NoNewline -ForegroundColor Cyan; Write-Host $text }
function Todo($text) { Write-Host '     → ' -NoNewline -ForegroundColor Cyan; Write-Host $text -ForegroundColor White }
function Finish($text) {
  $took = (Get-Date) - $Script:Started
  $tookText = if ($took.TotalSeconds -lt 60) { "$([int]$took.TotalSeconds) 秒" } else { "$([int][Math]::Floor($took.TotalMinutes)) 分 $($took.Seconds) 秒" }
  Write-Host ''
  Write-Host '  √ 全部完成  ' -NoNewline -ForegroundColor Cyan
  Write-Host "用时 $tookText" -ForegroundColor DarkGray
  Write-Host "     $text"
}
$Steps = 2
Header 'Codex 官方安装' '用 OpenAI 官方安装命令，登录你自己的 ChatGPT 账号'

Say '运行 OpenAI 官方安装命令'
Info 'irm https://chatgpt.com/codex/install.ps1 | iex'
Write-Host ''
$installed = $true
try { irm https://chatgpt.com/codex/install.ps1 | iex } catch {
  $installed = $false
  Write-Host ''
  Write-Host '  × 出错了' -ForegroundColor Red
  Write-Host "     $_"
  Write-Host '     官方安装命令没有成功；网络问题的话，确认能打开 chatgpt.com 后重试。'
  Write-Host '     需要帮助：截图发到社群 https://humanslive.ai/community' -ForegroundColor DarkGray
}

# HL_TOKEN 来自安装页上复制的命令（网站签名，7 天有效）；没有就跳过，请求失败也不影响安装结果。
if ($installed) {
  Say '检查旧配置'
  $cleaned = $false
  # 以前用国产模型版装过：它写的智谱配置会让 Codex 继续走智谱、不认 ChatGPT 登录。
  # 只删国产模型版写的那几行（model_provider = "zhipu"、model = "glm-…"、[model_providers.zhipu]）
  # 和只装着智谱 Key 的 auth.json，其余原样保留；改之前先备份。UTF-8 不带 BOM。
  $codexHomeDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
  $configPath = Join-Path $codexHomeDir 'config.toml'
  $authPath = Join-Path $codexHomeDir 'auth.json'
  $backupSuffix = '.bak-' + (Get-Date -Format 'yyyyMMddHHmmss')
  $utf8NoBom = [Text.UTF8Encoding]::new($false)
  if ((Test-Path $configPath) -and (Select-String -Quiet -Path $configPath -Pattern '^\s*model_provider\s*=\s*"zhipu"')) {
    Copy-Item $configPath ($configPath + $backupSuffix)
    $keptLines = @(); $inTable = $false; $skipTable = $false
    foreach ($line in [IO.File]::ReadAllLines($configPath, $utf8NoBom)) {
      if ($line -match '^\[') { $inTable = $true; $skipTable = ($line.Trim() -eq '[model_providers.zhipu]') }
      if (-not $inTable -and $line -match '^\s*(model_provider\s*=\s*"zhipu"|model\s*=\s*"glm-)') { continue }
      if (-not $skipTable) { $keptLines += $line }
    }
    [IO.File]::WriteAllText($configPath, (($keptLines -join "`n") + "`n"), $utf8NoBom)
    $cleaned = $true; Ok '已去掉国产模型版的智谱配置'; Info "原文件备份为 $configPath$backupSuffix"
  }
  if ((Test-Path $authPath) -and ([IO.File]::ReadAllText($authPath, $utf8NoBom).Trim() -cmatch '^\{"OPENAI_API_KEY":"[0-9a-f]{32}\.[A-Za-z0-9]{16}"\}$')) {
    Move-Item $authPath ($authPath + $backupSuffix)
    $cleaned = $true; Ok '已移走国产模型版的智谱 Key'; Info "备份为 $authPath$backupSuffix"
  }

  if ($env:HL_TOKEN) {
    try { Invoke-RestMethod -TimeoutSec 6 -Method Post -ContentType 'application/json' -Body (@{ token = $env:HL_TOKEN } | ConvertTo-Json) 'https://humanslive.ai/api/tools/progress/claim' | Out-Null } catch { }
  }
  if (-not $cleaned) { Ok '没有要处理的旧配置' }
  Finish 'Codex 已装好，接下来：'
  Todo '打开一个新的终端窗口，进入项目文件夹，输入 codex 回车'
  Todo '选 Sign in with ChatGPT，用你的 ChatGPT 账号登录'

  # ---------- 结尾：HumansLive 的其他免费工具和商城 ----------
  # 内容和排版来自网站（每行 kind<TAB>a<TAB>b），这里只按 kind 上色；拿不到就只打一行网址，不影响安装结果。
  function Show-Banner($source) {
    $text = $null
    try { $text = Invoke-RestMethod -TimeoutSec 6 "https://humanslive.ai/api/install-banner?f=$source&w=$(Get-ConsoleWidth)" } catch { }
    if (-not $text) { Write-Host ''; Write-Host '  更多免费工具和服务：https://humanslive.ai'; Write-Host ''; return }
    foreach ($line in (($text -replace "`r", '' -replace [char]27, '') -split "`n")) {
      $p = $line -split "`t"
      switch ($p[0]) {
        'rule'  { Write-Host ('  ' + $p[1]) -ForegroundColor DarkGray }
        'brand' { Write-Host ('  ' + $p[1]) -NoNewline -ForegroundColor White; Write-Host $p[2] }
        'head'  { Write-Host ('  ' + $p[1]) -NoNewline -ForegroundColor Cyan; Write-Host ('  ' + $p[2]) -ForegroundColor DarkGray }
        'row'   { Write-Host ('    ' + $p[1]) -NoNewline; Write-Host $p[2] -ForegroundColor Gray }
        'link'  { Write-Host ('    ' + $p[1]) -ForegroundColor Cyan }
        default { Write-Host '' }
      }
    }
  }
  Show-Banner codex
}
