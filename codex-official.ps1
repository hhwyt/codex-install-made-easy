# Codex official install (HumansLive wrapper): runs OpenAI's official install command, then removes the Zhipu
# config left by the Chinese-model edition.
#   Usage: irm https://humanslive.ai/codex-official.ps1 | iex
# Official command: irm https://chatgpt.com/codex/install.ps1 | iex
# Source: https://github.com/hhwyt/codex-install-made-easy
# ---------- Terminal output ----------
# One accent color (cyan), gray for secondary text, red only for errors. √ → × exist in the default fonts of both
# Chinese and English Windows.
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

if ($installed) {
  Say '检查旧配置'
  $cleaned = $false
  # A previous Chinese-model install leaves a Zhipu config that keeps Codex on Zhipu and ignores ChatGPT sign-in.
  # Remove only the lines that edition wrote (model_provider = "zhipu", model = "glm-…", its model catalog,
  # [model_providers.zhipu])
  # and an auth.json that holds only a Zhipu key; keep everything else and back up first. UTF-8 without BOM.
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
      if (-not $inTable -and $line -match '^\s*(model_provider\s*=\s*"zhipu"|model\s*=\s*"glm-|model_catalog_json\s*=.*humanslive-models\.json)') { continue }
      if (-not $skipTable) { $keptLines += $line }
    }
    [IO.File]::WriteAllText($configPath, (($keptLines -join "`n") + "`n"), $utf8NoBom)
    Remove-Item (Join-Path $codexHomeDir 'humanslive-models.json') -ErrorAction SilentlyContinue
    $cleaned = $true; Ok '已去掉国产模型版的智谱配置'; Info "原文件备份为 $configPath$backupSuffix"
  }
  if ((Test-Path $authPath) -and ([IO.File]::ReadAllText($authPath, $utf8NoBom).Trim() -cmatch '^\{"OPENAI_API_KEY":"[0-9a-f]{32}\.[A-Za-z0-9]{16}"\}$')) {
    Move-Item $authPath ($authPath + $backupSuffix)
    $cleaned = $true; Ok '已移走国产模型版的智谱 Key'; Info "备份为 $authPath$backupSuffix"
  }

  if (-not $cleaned) { Ok '没有要处理的旧配置' }
  Finish 'Codex 已装好，接下来：'
  Todo '打开一个新的终端窗口，进入项目文件夹，输入 codex 回车'
  Todo '选 Sign in with ChatGPT，用你的 ChatGPT 账号登录'

  # ---------- Closing banner: other free HumansLive tools ----------
  # Content and layout come from the website (one kind<TAB>a<TAB>b per line); this only colors by kind.
  # If it cannot be fetched, print one URL instead; the install result is unaffected.
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
