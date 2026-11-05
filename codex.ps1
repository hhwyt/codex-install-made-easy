# Codex one-command installer (Windows): installs the official Codex app, creates a Zhipu API key after a
# WeChat QR login, and wires Codex to Zhipu's free model.
# Usage (PowerShell): irm https://humanslive.ai/codex.ps1 | iex
# It only: downloads and verifies the official Codex package (China mirror, falling back to the Microsoft Store),
# opens a Zhipu login window, creates one API key,
# writes the config under %USERPROFILE%\.codex, and opens Codex. As on Mac, Codex downloads in the background while
# the user scans.
# Works with the built-in Windows PowerShell 5.1. Codex ships a system service (its command sandbox relies on it)
# and Windows requires administrator consent to install it:
# one UAC prompt at the start, used only to install Codex; every other step runs as the user.
# Every run writes a log to %LOCALAPPDATA%\HumansLive\logs for debugging. Keys are never logged.

$ErrorActionPreference = 'Continue'   # codex.exe writes warnings to stderr; 'Stop' would treat them as fatal
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$ProgressPreference = 'SilentlyContinue'

$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$CodexStoreId = '9PLM9XGG6VKS'
$CodexPackageName = 'OpenAI.Codex'
$CodexPublisher = 'CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B'   # Publisher of OpenAI.Codex in the Microsoft Store; used to verify mirror downloads
$ZhipuBaseUrl = 'https://open.bigmodel.cn/api/v1'
$ZhipuLoginUrl = 'https://bigmodel.cn/login?redirect=%2Fapikey%2Fplatform'
$ZhipuKeyPattern = '^[0-9a-f]{32}\.[A-Za-z0-9]{16}$'
$FreeModels = @('glm-4.7-flash', 'glm-4.5-flash')   # Zhipu now routes 4.5-flash to 4.7-flash; try the newer one first
$DebugPort = 9333
$CacheDir = if ($env:CODEX_SETUP_CACHE_DIR) { $env:CODEX_SETUP_CACHE_DIR } else { Join-Path $env:LOCALAPPDATA 'HumansLive' }
$WorkDir = Join-Path $env:TEMP ('codex-setup-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# ---------- Log: one line per step, so a user can send us the file when something fails ----------
$LogFile = Join-Path $CacheDir ('logs\codex-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
New-Item -ItemType Directory -Force (Split-Path $LogFile) | Out-Null
function Log($text) { try { Add-Content -LiteralPath $LogFile -Value ((Get-Date -Format 'HH:mm:ss.fff') + '  ' + $text) -Encoding UTF8 } catch { } }

# ---------- Terminal output ----------
# One accent color (blue), gray for secondary text, red only for errors. ANSI terminals get the same animations and
# glyphs as the Mac version;
# the legacy console (whose font lacks braille, katakana and heavy box lines) gets ASCII. Redirected output or
# NO_COLOR gets plain text.
$E = [char]27
$Live = $Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected -and -not $env:NO_COLOR
# Detect Windows Terminal: Windows 11 opens PowerShell in it by default, but WT_SESSION is empty in that case,
# so check the console window class (PseudoConsoleWindow for Windows Terminal, ConsoleWindowClass for the legacy console)
$ConsoleClass = ''
try {
  Add-Type -Namespace HL -Name Con -MemberDefinition '[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow(); [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);'
  $sb = New-Object Text.StringBuilder 64; [void][HL.Con]::GetClassName([HL.Con]::GetConsoleWindow(), $sb, 64); $ConsoleClass = "$sb"
} catch { }
$Fancy = [bool]$env:WT_SESSION -or $ConsoleClass -eq 'PseudoConsoleWindow'
$Check = if ($Fancy) { '✓' } else { '√' }
$Cross = if ($Fancy) { '✗' } else { '×' }
if ($Live) {
  $R = "$E[0m"; $Bold = "$E[1m"; $Dim = "$E[2m"; $Blue = "$E[38;5;33m"; $Head = "$E[38;5;153m"; $Deep = "$E[38;5;25m"; $Red = "$E[31m"; $Link = "$E[4;38;5;33m"
} else { $R = $Bold = $Dim = $Blue = $Head = $Deep = $Red = $Link = '' }
$Spinner = if ($Fancy) { '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'.ToCharArray() } else { '|/-\'.ToCharArray() }
$BarOn = if ($Fancy) { '━' } else { '=' }
$BarOff = if ($Fancy) { '─' } else { '-' }
$Script:Step = 0
$Script:Started = Get-Date

function W($text) { Write-Host $text -NoNewline }
function Get-ConsoleWidth { try { [int]$Host.UI.RawUI.WindowSize.Width } catch { 80 } }
# Display width in terminal columns: CJK wide characters take two
function Get-TextWidth([string]$text) {
  $w = 0
  foreach ($ch in $text.ToCharArray()) {
    $c = [int]$ch
    $w += if (($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0xA4CF) -or ($c -ge 0xAC00 -and $c -le 0xD7A3) -or
      ($c -ge 0xF900 -and $c -le 0xFAFF) -or ($c -ge 0xFE30 -and $c -le 0xFE4F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or ($c -ge 0xFFE0 -and $c -le 0xFFE6)) { 2 } else { 1 }
  }
  $w
}
function Pad([string]$text, [int]$width) { $text + (' ' * [Math]::Max(0, $width - (Get-TextWidth $text))) }
function MB([double]$bytes) { '{0:0.0}' -f ($bytes / 1MB) }

# Digital rain: a few rows of falling glyphs, erased when done
function Show-Rain([int]$cols, [int]$rows, [int]$ms) {
  $glyphs = if ($Fancy) { ('0123456789' + (-join ((0xFF66..0xFF9D) | ForEach-Object { [char]$_ }))).ToCharArray() } else { '0123456789ABCDEFXZ#$%&'.ToCharArray() }
  $rand = [Random]::new()
  $drop = @{}; $len = @{}
  for ($c = 0; $c -lt $cols; $c += 2) { $drop[$c] = - $rand.Next($rows * 2); $len[$c] = 3 + $rand.Next(5) }
  W ("`n" * $rows)
  for ($f = 0; $f -lt [int]($ms / 45); $f++) {
    $sb = [Text.StringBuilder]::new("$E[${rows}A")
    for ($row = 0; $row -lt $rows; $row++) {
      [void]$sb.Append("`r$E[K  ")
      for ($c = 0; $c -lt $cols; $c++) {
        if ($c % 2) { [void]$sb.Append(' '); continue }
        $d = $drop[$c] - $row
        if ($d -eq 0) { [void]$sb.Append($Head + $glyphs[$rand.Next($glyphs.Length)] + $R) }
        elseif ($d -gt 0 -and $d -lt $len[$c]) { [void]$sb.Append($(if ($d -lt 3) { $Blue } else { $Deep }) + $glyphs[$rand.Next($glyphs.Length)] + $R) }
        else { [void]$sb.Append(' ') }
      }
      [void]$sb.Append("`n")
    }
    W $sb.ToString()
    foreach ($c in @($drop.Keys)) { $drop[$c]++; if ($drop[$c] - $len[$c] -gt $rows) { $drop[$c] = - $rand.Next($rows); $len[$c] = 3 + $rand.Next(5) } }
    Start-Sleep -Milliseconds 45
  }
  W ("$E[${rows}A" + ("`r$E[K`n" * $rows) + "$E[${rows}A")
}
# Text decodes out of noise (only ASCII is scrambled; CJK stays as is)
function Show-Decode([string]$color, [string]$text) {
  $chars = $text.ToCharArray(); $rand = [Random]::new(); $pool = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
  for ($s = 0; $s -le 14; $s++) {
    $shown = [int]($chars.Length * $s / 14)
    $line = ''
    for ($i = 0; $i -lt $chars.Length; $i++) {
      if ($i -lt $shown -or $chars[$i] -notmatch '[!-~]') { $line += $chars[$i] } else { $line += $Dim + $pool[$rand.Next($pool.Length)] + $R + $color }
    }
    W "`r$E[K  $color$line$R"
    Start-Sleep -Milliseconds 25
  }
  Write-Host ''
}

function Header($title, $subtitle) {
  Write-Host ''
  if ($Live) {
    $cols = Get-ConsoleWidth
    Show-Rain $(if ($cols -gt 76) { 70 } else { $cols - 6 }) 6 900
    Show-Decode "$Blue$Bold" "HUMANSLIVE.AI ▸ $title"
  } else { Write-Host "  HUMANSLIVE.AI ▸ $title" }
  Write-Host "  $Dim$subtitle$R"
}
function Section($title, $note) { Log "== $title $note"; Write-Host ''; Write-Host "  $Blue$Bold▸$R $Bold$title$R  $Dim$note$R" }
function Say($text) { $Script:Step++; Log "[$($Script:Step)/$Steps] $text"; Write-Host ''; Write-Host "  $Blue$Bold[$($Script:Step)/$Steps]$R $Bold$text$R" }
function Info($text) { Log "   $text"; Write-Host "       $Dim$text$R" }
function Ok($text)   { Log "ok $text"; Write-Host "     $Blue$Check$R $text" }
function Todo($text) { Log "-> $text"; Write-Host "     $Blue→$R $Bold$text$R" }
function Finish($text) {
  $took = (Get-Date) - $Script:Started
  $tookText = if ($took.TotalSeconds -lt 60) { "$([int]$took.TotalSeconds) 秒" } else { "$([int][Math]::Floor($took.TotalMinutes)) 分 $($took.Seconds) 秒" }
  Log "done in $tookText"
  Write-Host ''
  if ($Live) { Show-Decode "$Blue$Bold" "$Check ALL SYSTEMS GO · 全部完成" } else { Write-Host "  $Check ALL SYSTEMS GO · 全部完成" }
  Write-Host "     ${Dim}用时 $tookText$R"
  Write-Host "     $text"
}
# On failure: say what to do, show the log path and select the file in Explorer so it is easy to send
function Show-Error($text) {
  if ($Live) { W "`r$E[K" }
  Write-Host ''
  Write-Host "  $Red$Bold$Cross 出错了$R"
  Write-Host "     $text"
  Write-Host "     ${Dim}日志：$LogFile$R"
  Write-Host "     ${Dim}需要帮助：把这个日志文件发到社群 https://humanslive.ai/community$R"
  Write-Host ''
  Start-Process explorer.exe "/select,`"$LogFile`"" -ErrorAction SilentlyContinue
}
# After the key is created, tell the user where it lives and who can see it
function Show-KeyNote {
  $lock = if ($Fancy) { '🔒 ' } else { '' }
  Write-Host "       $Blue$lock$R${Bold}安全说明$R"
  Info '这个 Key 是用你自己的智谱账号建的，只保存在你的电脑上，绝对安全'
  Info '随时可以在智谱控制台删掉（名字以 Codex- 开头）'
}
# After install: how to open Codex, free-model rate limits and top-ups, stronger models
function Show-NextSteps($configShown) {
  Section '以后怎么打开' ''
  if ($Edition -eq 'zh') { Write-Host "     用桌面或开始菜单里的「Codex 汉化版」打开  ${Dim}从「ChatGPT」打开是英文原版$R" }
  else { Write-Host "     开始菜单里的「ChatGPT」就是 Codex  ${Dim}OpenAI 把 Codex 并进了 ChatGPT 桌面版$R" }
  Section '关于免费模型' ''
  Write-Host '     不扣费，用得太频繁会被限速，等一会儿就恢复'
  Write-Host "     ${Dim}不想被限速：在智谱充值，再把$R $Bold$configShown$R ${Dim}里的 model 换成付费模型$R"
  Write-Host "     ${Link}https://bigmodel.cn/finance/pay$R"
  Section '想用更强的模型' '我们帮你开通'
  Write-Host "     ${Bold}OpenAI 官方 GPT 模型$R"
  Write-Host "     ${Bold}Claude 模型$R"
  Write-Host "     $Blue→$R 来社群找我们：${Link}https://humanslive.ai/community$R"
}
function Fail($text) {
  Log "FAIL $text"
  Show-Error $text
  throw 'HL_FAIL'   # The outer catch recognizes this and skips PowerShell's red error dump
}

# Spin for a moment (while advancing the background download), showing text, elapsed seconds and download progress
$Script:SpinTick = 0
function Wait-Tick([double]$seconds, [string]$text, [datetime]$since) {
  $until = (Get-Date).AddSeconds($seconds)
  do {
    Update-Download
    if ($Live) {
      $note = Get-DownloadNote
      W "`r$E[K     $Blue$($Spinner[$Script:SpinTick % $Spinner.Length])$R $text  $Dim$([int]((Get-Date) - $since).TotalSeconds)s$note$R"
      $Script:SpinTick++
    }
    Start-Sleep -Milliseconds 120
  } while ((Get-Date) -lt $until)
}
function Clear-Line { if ($Live) { W "`r$E[K" } }

# ---------- Background download: curl.exe (built in since Windows 10), auto-retry, cached and resumable on rerun ----------
$Script:Dl = $null   # @{ Url; Name; File; Total; Proc; Tries; Done; Failed }
function Start-DownloadProcess {
  $d = $Script:Dl
  $d.Proc = Start-Process curl.exe -PassThru -WindowStyle Hidden -ArgumentList @('-fsSL', '-C', '-', '--retry', '3', '--connect-timeout', '15', '-o', "`"$($d.File)`"", $d.Url)
  $null = $d.Proc.Handle   # Touch Handle now, or ExitCode is unavailable after the process exits
  $d.Tries++
  Log "download try $($d.Tries): $($d.Url)"
}
function Start-Download($url, $name, $file) {
  $headers = (& curl.exe -sIL --connect-timeout 15 --max-time 20 $url 2>$null) -join "`n"
  $total = 0; $etag = ''
  foreach ($line in ($headers -split "`n")) {
    if ($line -match '^(?i)content-length:\s*(\d+)') { $total = [long]$Matches[1] }
    if ($line -match '^(?i)etag:\s*(\S+)') { $etag = $Matches[1] }
  }
  # A partial file from an older release cannot be resumed; delete it and start over
  if ((Test-Path "$file.etag") -and ((Get-Content "$file.etag" -Raw) -ne $etag)) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
  Set-Content "$file.etag" $etag -NoNewline
  $size = if (Test-Path $file) { (Get-Item $file).Length } else { 0 }
  if ($total -gt 0 -and $size -gt $total) { Remove-Item $file -Force; $size = 0 }
  Log "download $name total=$total etag=$etag cached=$size"
  $Script:Dl = @{ Url = $url; Name = $name; File = $file; Total = $total; Proc = $null; Tries = 0; Done = $false; Failed = $false }
  if ($total -gt 0 -and $size -eq $total) { $Script:Dl.Done = $true } else { Start-DownloadProcess }
}
function Update-Download {
  $d = $Script:Dl
  if (-not $d -or $d.Done -or $d.Failed -or -not $d.Proc.HasExited) { return }
  Log "download try $($d.Tries) exit=$($d.Proc.ExitCode) size=$(Get-DownloadedBytes)"
  if ($d.Proc.ExitCode -eq 0) { $d.Done = $true }
  elseif ($d.Tries -lt 5) { Start-DownloadProcess }
  else { $d.Failed = $true }
}
function Get-DownloadedBytes { if ($Script:Dl -and (Test-Path $Script:Dl.File)) { (Get-Item $Script:Dl.File).Length } else { 0 } }
function Get-DownloadNote {
  $d = $Script:Dl
  if (-not $d) { return '' }
  if ($d.Done) { return '  · Codex 已在后台下载好' }
  if ($d.Total -gt 0) { return "  · 后台下载 Codex $([int]((Get-DownloadedBytes) * 100 / $d.Total))%" }
  '  · 后台下载 Codex 中'
}
function Stop-Download { if ($Script:Dl -and $Script:Dl.Proc -and -not $Script:Dl.Proc.HasExited) { Stop-Process -Id $Script:Dl.Proc.Id -Force -ErrorAction SilentlyContinue } }

# Draw the progress bar in the foreground until the background download ends
function Show-DownloadProgress {
  $d = $Script:Dl
  $windowStart = Get-Date; $windowBytes = Get-DownloadedBytes; $speed = 0
  while (-not $d.Done -and -not $d.Failed) {
    Update-Download
    $size = Get-DownloadedBytes
    $elapsed = ((Get-Date) - $windowStart).TotalSeconds
    if ($elapsed -ge 2) { $speed = ($size - $windowBytes) / $elapsed; $windowStart = Get-Date; $windowBytes = $size }
    if ($Live -and $d.Total -gt 0) {
      $pct = [Math]::Min(100, [int]($size * 100 / $d.Total))
      $stats = '{0,3}%  {1,6} / {2} MB  {3}' -f $pct, (MB $size), (MB $d.Total), $(if ($speed -gt 0) { '{0,5} MB/s' -f (MB $speed) } else { ' ' * 10 })
      $width = [Math]::Min(28, (Get-ConsoleWidth) - 9 - $stats.Length)
      if ($width -ge 8) {
        $fill = [int]($pct * $width / 100)
        W "`r$E[K     $Blue$($BarOn * $fill)$R$Dim$($BarOff * ($width - $fill))$R  $stats"
      } else { W "`r$E[K     $stats" }
    }
    Start-Sleep -Milliseconds 250
  }
  Clear-Line
}

# ---------- Source race: mirror vs Microsoft Store. The mirror is served from mainland China and gets 8 s; the Store cannot be probed, so it is the fallback ----------
function Select-Source {
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
  $mirrorUrl = "https://codexapp.agentsmirror.com/latest/$arch"
  Section '线路测速' '探测下载线路，选最快的'
  $probe = Join-Path $WorkDir 'probe.msix'
  $proc = Start-Process curl.exe -PassThru -WindowStyle Hidden -ArgumentList @('-sL', '-r', '0-33554431', '--connect-timeout', '8', '--max-time', '8', '-o', "`"$probe`"", $mirrorUrl)
  $start = Get-Date; $speed = 0; $tick = 0
  $names = @((Pad '国内镜像' 13), (Pad '微软商店' 13)); $tags = @((Pad '不用科学上网' 12), (Pad '官方渠道' 12))
  $barW = [Math]::Min(24, (Get-ConsoleWidth) - 5 - 2 - 13 - 2 - 12 - 2 - 2 - 10 - 6 - 2)
  if ($Live) { W "`n`n" }
  while (-not $proc.HasExited) {
    $el = ((Get-Date) - $start).TotalSeconds
    $size = if (Test-Path $probe) { (Get-Item $probe).Length } else { 0 }
    if ($el -gt 0.3) { $speed = $size / $el }
    if ($Live) {
      $fill = if ($barW -ge 6) { [Math]::Min($barW, [int]($barW * $speed / [Math]::Max($speed, 4MB))) } else { 0 }
      $bar = if ($barW -ge 6) { "$Blue$($BarOn * $fill)$R$Dim$($BarOff * ($barW - $fill))$R  " } else { '' }
      $num = if ($speed -gt 0) { '{0,5} MB/s' -f (MB $speed) } else { "$Dim   测速中 $R" }
      W ("$E[2A`r$E[K     $Blue$($Spinner[$tick % $Spinner.Length])$R $($names[0])  $Dim$($tags[0])$R  $bar$num`n" +
         "`r$E[K     $Dim·$R $($names[1])  $Dim$($tags[1])$R  ${Dim}备用：镜像连不上或太慢时改用$R`n")
      $tick++
    }
    Start-Sleep -Milliseconds 100
  }
  $size = if (Test-Path $probe) { (Get-Item $probe).Length } else { 0 }
  $el = ((Get-Date) - $start).TotalSeconds
  $speed = if ($el -gt 0) { $size / $el } else { 0 }
  $useMirror = $speed -gt 300KB
  Log "probe mirror: $size bytes in $([Math]::Round($el, 1))s, curl exit=$($proc.ExitCode), useMirror=$useMirror"
  $file = Join-Path $CacheDir "Codex-$arch.msix"
  if ($Live) {
    $bar = if ($barW -ge 6) { "$Blue$($BarOn * $barW)$R  " } else { '' }
    $num = if ($speed -gt 0) { '{0,5} MB/s' -f (MB $speed) } else { '   连不上 ' }
    if ($useMirror) {
      W ("$E[2A`r$E[K     $Blue$Bold$Check$R $($names[0])  $Dim$($tags[0])$R  $bar$num  $Blue${Bold}最快$R`n" +
         "`r$E[K     $Dim· $($names[1])  $($tags[1])  备用$R`n")
    } else {
      W ("$E[2A`r$E[K     $Dim· $($names[0])  $($tags[0])  $num$R`n" +
         "`r$E[K     $Blue$Bold$Check$R $($names[1])  $Dim$($tags[1])$R  ${Blue}${Bold}改用这条$R`n")
    }
  }
  if (-not $useMirror) { return $null }
  # The probe is the start of the file: keep it unless the cache already has more
  New-Item -ItemType Directory -Force $CacheDir | Out-Null
  $cached = if (Test-Path $file) { (Get-Item $file).Length } else { 0 }
  if ($size -gt $cached) { Move-Item $probe $file -Force; Remove-Item "$file.etag" -ErrorAction SilentlyContinue }
  Ok '下载线路：国内镜像'
  @{ Url = $mirrorUrl; Name = '国内镜像'; File = $file }
}

# ---------- Install Codex ----------
# The Codex package ships a system service (CodexSandboxService). Its command sandbox relies on it; once installed,
# commands need no elevation,
# and updates come from Codex itself or the Store. Windows requires administrator consent to install it (double-click,
# Store and Add-AppxPackage alike).
# There is no way around it: without a properly installed package, every sandboxed command asks for elevation and
# the app never updates (verified on a PC and in the Codex source).
# So we prompt once at the start and keep a small elevated helper waiting; it installs once the download is verified.
# The user clicks Yes, scans, and can walk away. Everything else (download, login, config) runs as the user.
function Get-CodexPackage { Get-AppxPackage -Name $CodexPackageName -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1 }
function Get-Codex {
  $pkg = Get-CodexPackage
  if ($pkg) { @{ Version = "$($pkg.Version)"; Package = $pkg; Cli = Join-Path $pkg.InstallLocation 'app\resources\codex.exe' } }
}
function Open-Codex($codex) {
  $appId = (Get-AppxPackageManifest $codex.Package).Package.Applications.Application.Id | Select-Object -First 1
  Start-Process "shell:AppsFolder\$($codex.Package.PackageFamilyName)!$appId"
}
# Codex's own Language setting does nothing where OpenAI is unreachable (the comment at the top of the launcher says
# why). The launcher opens Codex with Chinese turned on locally; "Codex 汉化版" shortcuts on the desktop and in the
# Start menu point at it. Written to disk as is, so it stays readable for anyone who wants to check what it does
$CodexZhLauncher = {
# Opens Codex with a Chinese interface (written by the HumansLive Codex installer).
# Codex shows translations only when OpenAI's feature switch enable_i18n (Statsig layer 72216192) is on, and the
# switch is fetched from OpenAI on every launch; where OpenAI is unreachable it stays off and the UI is English
# whatever the Language setting says. So start Codex with a local DevTools port, patch that one switch in every
# Codex page, and stay alive while Codex runs (the patch only holds while the DevTools connection is open).
# Nothing runs in the background: no service, no startup entry; after a restart it does nothing until opened again.
# Whatever goes wrong, Codex still opens, at worst in English: the shortcut opens Codex directly when this script
# cannot run, every failure here falls back to a plain launch, and if Codex does not render with the patch, it is
# reopened without it and the patch stays off for that Codex version (disabled-<version>.txt).
# Codex is never closed for this: if it is already open (from the Start menu, say), it is just brought to the front.
# -InstallShortcuts: create the shortcuts ("Codex" plus the Chinese for "Chinese edition") on the desktop and in the
# Start menu, then return.
param([switch]$InstallShortcuts)
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $Dir 'codex-zh.log'
function Log($text) { try { Add-Content -LiteralPath $LogFile -Value ((Get-Date -Format 'HH:mm:ss.fff') + '  ' + $text) -Encoding UTF8 } catch { } }

$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { Log 'codex not installed'; exit 1 }
$appUserModelId = "$($package.PackageFamilyName)!App"
$appDir = Join-Path $package.InstallLocation 'app\'

# The shortcut icon is Codex's own, inside its versioned folder, so rewrite the shortcuts after a Codex update.
# WScript.Shell cannot save a shortcut whose name is outside the system code page (Chinese on an English Windows),
# so save it under an ASCII name and rename it
$icon = Join-Path $appDir 'ChatGPT.exe'
$shortcutName = 'Codex ' + [char]0x6C49 + [char]0x5316 + [char]0x7248 + '.lnk'
$shortcuts = [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs') | ForEach-Object { Join-Path $_ $shortcutName }
$iconStamp = Join-Path $Dir 'shortcut-icon.txt'
function Save-Shortcut($path) {
  $temporary = Join-Path $env:TEMP 'humanslive-codex-zh.lnk'
  $link = (New-Object -ComObject WScript.Shell).CreateShortcut($temporary)
  $link.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  # If this script cannot run at all (deleted, or blocked by a policy), open Codex directly
  $quotedScript = $PSCommandPath -replace "'", "''"
  $link.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"try { & '$quotedScript' } catch { Start-Process 'shell:AppsFolder\$appUserModelId' }`""
  $link.WindowStyle = 7   # Minimized, so no PowerShell window shows up
  $link.IconLocation = "$icon,0"
  $link.Description = 'Codex'
  $link.Save()
  Move-Item -LiteralPath $temporary -Destination $path -Force
}
if ($InstallShortcuts) { $shortcuts | ForEach-Object { Save-Shortcut $_ }; Set-Content -LiteralPath $iconStamp -Value $icon; Log 'shortcuts installed'; return }
try {
  if ((Get-Content -LiteralPath $iconStamp -ErrorAction SilentlyContinue) -ne $icon) {
    $shortcuts | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Save-Shortcut $_ }
    Set-Content -LiteralPath $iconStamp -Value $icon; Log 'shortcut icons updated'
  }
} catch { Log "shortcut update failed: $($_.Exception.Message)" }

function Open-CodexPlain { Start-Process "shell:AppsFolder\$appUserModelId" }
$disabledFile = Join-Path $Dir "disabled-$($package.Version).txt"
if (Test-Path -LiteralPath $disabledFile) { Log "patch disabled for codex $($package.Version): opening it plainly"; Open-CodexPlain; exit }

try {
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CodexActivator {
  [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IApplicationActivationManager {
    int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, [MarshalAs(UnmanagedType.LPWStr)] string arguments, int options, out uint processId);
  }
  [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")] class ApplicationActivationManager { }
  public static uint Activate(string appUserModelId, string arguments) {
    uint processId;
    Marshal.ThrowExceptionForHR(((IApplicationActivationManager)new ApplicationActivationManager()).ActivateApplication(appUserModelId, arguments, 0, out processId));
    return processId;
  }
}
'@
} catch { Log "activator failed: $($_.Exception.Message)"; Open-CodexPlain; exit 1 }

# Runs at document start in every Codex page, before Codex's own scripts. The Statsig SDK stores its clients on
# window.__STATSIG__ (it reuses an existing object, reassigns the property whenever a client registers, and sets
# instances/firstInstance on it), so trap those assignments and wrap each client's getLayer/getDynamicConfig: for
# layer 72216192, get('enable_i18n') answers true. Everything else Statsig returns is left as it is.
$Patch = @'
(() => {
  if (window.__humansliveZh) return;
  window.__humansliveZh = true;
  const LAYER = '72216192';
  // Every hook hands Codex exactly what it would have got and only then tries the patch, inside try/catch: if
  // anything here breaks on a future Codex, the switch simply stays off
  const fixValue = (value) => {
    try {
      if (!value || typeof value.get !== 'function' || value.__humansliveZh) return;
      const get = value.get;
      value.get = function (key, fallback) { return key === 'enable_i18n' ? true : get.call(this, key, fallback); };
      value.__humansliveZh = true;
    } catch (e) { }
  };
  const wrap = (original) => {
    if (typeof original !== 'function' || original.__humansliveZh) return original;
    const wrapped = function (layerName, options) {
      const value = original.apply(this, arguments);
      if (layerName === LAYER) fixValue(value);
      return value;
    };
    wrapped.__humansliveZh = true;
    return wrapped;
  };
  // The client registers itself before its constructor finishes and assigns its own getLayer/getDynamicConfig
  // afterwards, so wrap whatever gets assigned, not just what is there now
  const fixClient = (client) => {
    if (!client || typeof client !== 'object' || client.__humansliveZh) return;
    client.__humansliveZh = true;
    for (const name of ['getLayer', 'getDynamicConfig']) {
      let current = wrap(client[name]);
      Object.defineProperty(client, name, { configurable: true, get: () => current, set: (next) => { current = next; try { current = wrap(next); } catch (e) { } } });
    }
  };
  const fixAll = (root) => {
    try {
      fixClient(root.firstInstance);
      if (root.instances) Object.values(root.instances).forEach(fixClient);
    } catch (e) { }
  };
  const fixRoot = (root) => {
    try {
      if (!root || typeof root !== 'object' || root.__humansliveZh) return;
      root.__humansliveZh = true;
      for (const key of ['firstInstance', 'instances']) {
        let current = root[key];
        Object.defineProperty(root, key, { configurable: true, enumerable: true, get: () => current, set: (next) => { current = next; fixAll(root); } });
      }
      fixAll(root);
    } catch (e) { }
  };
  let root = window.__STATSIG__;
  fixRoot(root);
  try { Object.defineProperty(window, '__STATSIG__', { configurable: true, get: () => root, set: (next) => { root = next; fixRoot(next); } }); } catch (e) { }
})();
'@

function Send-Cdp($socket, $sessionId, $method, $params) {
  $Script:CdpId++
  $id = $Script:CdpId
  $message = @{ id = $Script:CdpId; method = $method; params = $params }
  if ($sessionId) { $message.sessionId = $sessionId }
  $message = $message | ConvertTo-Json -Depth 5 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($message)
  $socket.SendAsync([ArraySegment[byte]]::new($bytes), 'Text', $true, [Threading.CancellationToken]::None).Wait()
  $id
}
# Returns the next message, 'TICK' after 2 s without one, or $null once Codex has quit (a killed Codex does not always
# close the connection, so also watch its process). A receive that times out stays pending for the next call
$Script:Buffer = New-Object byte[] 65536
$Script:Received = [IO.MemoryStream]::new()
$Script:Pending = $null
function Receive-Cdp($socket) {
  while ($true) {
    if (-not $Script:Pending) { $Script:Pending = $socket.ReceiveAsync([ArraySegment[byte]]::new($Script:Buffer), [Threading.CancellationToken]::None) }
    if (-not $Script:Pending.Wait(2000)) {
      if (-not (Get-Process -Id $codexProcessId -ErrorAction SilentlyContinue)) { return $null }
      return 'TICK'
    }
    $received = $Script:Pending.Result; $Script:Pending = $null
    if ($received.MessageType -eq 'Close') { return $null }
    $Script:Received.Write($Script:Buffer, 0, $received.Count)
    if ($received.EndOfMessage) {
      $text = [Text.Encoding]::UTF8.GetString($Script:Received.ToArray()); $Script:Received.SetLength(0)
      return ($text | ConvertFrom-Json)
    }
  }
}
function Get-CodexProcesses($appDir) {
  @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($appDir, [StringComparison]::OrdinalIgnoreCase) -and $_.Name -notlike 'codex-windows-sandbox-service*' })
}


# Already running from this launcher: just bring Codex to the front
$mutex = [Threading.Mutex]::new($false, 'Local\HumansLiveCodexZh')
if (-not $mutex.WaitOne(0)) { Log 'launcher already running: activating codex'; Open-CodexPlain; exit }
Set-Content -LiteralPath $LogFile -Value "$(Get-Date -Format s) start" -Encoding UTF8

try {
  # Codex runs as a single instance and ignores the arguments of a second launch. A Codex opened some other way may be
  # in the middle of a task, so leave it alone and just bring it to the front; it is Chinese the next time it is
  # opened from our shortcut
  if (Get-CodexProcesses $appDir | Where-Object { $_.Name -eq 'ChatGPT.exe' }) {
    Log 'codex already open without the patch: bringing it to the front'
    Open-CodexPlain; exit
  }
  # A free port picked by the system; Chromium binds DevTools to 127.0.0.1 only
  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop()
  $codexProcessId = [CodexActivator]::Activate($appUserModelId, "--remote-debugging-port=$port")
  Log "codex $($package.Version) started: pid=$codexProcessId port=$port"
  $browserUrl = $null
  for ($i = 0; $i -lt 300 -and -not $browserUrl; $i++) {
    try { $browserUrl = (Invoke-RestMethod "http://127.0.0.1:$port/json/version" -TimeoutSec 1).webSocketDebuggerUrl } catch { Start-Sleep -Milliseconds 100 }
  }
  if (-not $browserUrl) { throw 'DevTools port never opened' }
  $socket = [Net.WebSockets.ClientWebSocket]::new()
  $socket.ConnectAsync([Uri]$browserUrl, [Threading.CancellationToken]::None).Wait()
} catch {
  Log "launch failed: $($_.Exception.Message)"
  # Never leave the user without Codex: if it is not running, open it the normal way (English where OpenAI is unreachable)
  if (-not (Get-CodexProcesses $appDir)) { Open-CodexPlain; Log 'opened codex without the patch' }
  exit 1
}

# One browser-wide connection: every new page pauses until the patch is registered, then runs (if this script dies
# first, Chromium resumes the page by itself). A reload during Codex's startup makes it fail to start, so a page that
# was already running is patched in place instead. The patch holds while this connection is open; it closes when
# Codex quits, and so does this launcher.
# Health check: a Codex window must show its UI within 60 s. If it does not, assume the patch broke this Codex
# version: turn the patch off for this version and reopen Codex without it
function Disable-Patch($reason) {
  Log "patch disabled: $reason"
  try { Set-Content -LiteralPath $disabledFile -Value $reason } catch { }
  foreach ($p in Get-CodexProcesses $appDir) { taskkill.exe /F /T /PID $p.ProcessId 2>&1 | Out-Null }
  for ($i = 0; $i -lt 20 -and (Get-CodexProcesses $appDir); $i++) { Start-Sleep -Milliseconds 500 }
  Open-CodexPlain
}
$HealthScript = "document.readyState === 'complete' && document.body !== null && document.body.innerText.trim().length > 0"
try {
  $Script:CdpId = 0
  $pages = @(); $attachedAt = $null; $healthy = $false; $probeIds = @{}; $probedAt = [datetime]::MinValue
  Send-Cdp $socket $null 'Target.setAutoAttach' @{ autoAttach = $true; waitForDebuggerOnStart = $true; flatten = $true } | Out-Null
  while ($null -ne ($message = Receive-Cdp $socket)) {
    if (-not $healthy -and $pages) {
      if ($message -isnot [string] -and $message.id -and $probeIds.ContainsKey([int]$message.id) -and $message.result.result.value -eq $true) {
        $healthy = $true; Log "codex ui is up after $([int]((Get-Date) - $attachedAt).TotalSeconds) s"
      } elseif (((Get-Date) - $attachedAt).TotalSeconds -gt 60) {
        Disable-Patch "codex $($package.Version) showed no UI within 60 s"; exit 1
      } elseif (((Get-Date) - $probedAt).TotalSeconds -ge 2) {
        foreach ($page in $pages) { $probeIds[(Send-Cdp $socket $page 'Runtime.evaluate' @{ expression = $HealthScript; returnByValue = $true })] = $true }
        $probedAt = Get-Date
      }
    }
    if ($message -is [string]) { continue }
    if ($message.error) { Log "cdp error: $($message.error.message)" }
    if ($message.method -ne 'Target.attachedToTarget') { continue }
    $sessionId = $message.params.sessionId; $target = $message.params.targetInfo; $paused = $message.params.waitingForDebugger
    if ($target.type -eq 'page') {
      Send-Cdp $socket $sessionId 'Page.enable' @{ } | Out-Null
      Send-Cdp $socket $sessionId 'Page.addScriptToEvaluateOnNewDocument' @{ source = $Patch } | Out-Null
      if (-not $paused) { Send-Cdp $socket $sessionId 'Runtime.evaluate' @{ expression = $Patch } | Out-Null }
      if (-not $pages) { $attachedAt = Get-Date }
      $pages += $sessionId
      Log "patched page $($target.url) paused=$paused"
    }
    if ($paused) { Send-Cdp $socket $sessionId 'Runtime.runIfWaitingForDebugger' @{ } | Out-Null }
  }
} catch { Log "connection ended: $($_.Exception.Message)" }
Log 'codex closed'
}
function Install-CodexZh {
  $dir = Join-Path $env:LOCALAPPDATA 'HumansLive'
  New-Item -ItemType Directory -Force $dir | Out-Null
  $launcher = Join-Path $dir 'codex-zh.ps1'
  [IO.File]::WriteAllText($launcher, $CodexZhLauncher.ToString().Trim() + "`r`n", $utf8NoBom)
  & $launcher -InstallShortcuts
  Log "chinese launcher installed: $launcher"
  $launcher
}
# English edition chosen: remove what the Chinese edition added, so Codex is only opened the original way
function Remove-CodexZh {
  $dir = Join-Path $env:LOCALAPPDATA 'HumansLive'
  $links = [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs') | ForEach-Object { Join-Path $_ 'Codex 汉化版.lnk' }
  Remove-Item -LiteralPath $links -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $dir 'codex-zh.*'), (Join-Path $dir 'shortcut-icon.txt'), (Join-Path $dir 'disabled-*.txt') -ErrorAction SilentlyContinue
}
# Two big buttons in a window on top, for users who would not think of typing into the console. Styled like the
# humanslive.ai dialogs: white card, ink text, one blue primary button. Closing the window or Enter picks Chinese;
# returns $null when no window can be shown
function Show-EditionDialog {
  try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    try { Add-Type -Namespace HumansLive -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction Stop } catch {}
    try { [void][HumansLive.Dpi]::SetProcessDPIAware() } catch {}
    $color = { param($hex) [Drawing.ColorTranslator]::FromHtml($hex) }
    $white = [Drawing.Color]::White
    $form = New-Object Windows.Forms.Form
    $form.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96)
    $form.AutoScaleMode = 'Dpi'
    $form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    $form.ClientSize = New-Object Drawing.Size(480, 318)
    $form.Text = 'Codex 安装'; $form.BackColor = $white; $form.StartPosition = 'CenterScreen'; $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false; $form.KeyPreview = $true
    $addLabel = {
      param($text, $font, $hex, $y, $height)
      $form.Controls.Add((New-Object Windows.Forms.Label -Property @{
        Text = $text; Font = $font; ForeColor = (& $color $hex); Location = New-Object Drawing.Point(28, $y); Size = New-Object Drawing.Size(424, $height)
      }))
    }
    & $addLabel 'HUMANSLIVE.AI ▸ CODEX' (New-Object Drawing.Font('Consolas', 9, [Drawing.FontStyle]::Bold)) '#0c8df6' 26 20
    & $addLabel '选择 Codex 版本' (New-Object Drawing.Font('Microsoft YaHei UI', 15)) '#2e343b' 50 36
    & $addLabel 'Codex 在国内打开只有英文界面，我们可以帮你汉化。' (New-Object Drawing.Font('Microsoft YaHei UI Light', 10)) '#737b85' 90 24
    $choice = @{ value = 'zh' }
    $titleFont = New-Object Drawing.Font('Microsoft YaHei UI', 11)
    $noteFont = New-Object Drawing.Font('Microsoft YaHei UI Light', 9.5)
    $y = 128
    foreach ($option in @(
        @{ value = 'zh'; title = '汉化版（推荐）'; note = '界面中文 · 从桌面「Codex 汉化版」打开'; primary = $true },
        @{ value = 'en'; title = '英文原版'; note = '界面英文 · 和官方一模一样'; primary = $false })) {
      $option.hover = $false
      $card = New-Object Windows.Forms.Panel -Property @{
        Tag = $option; BackColor = $white; Cursor = [Windows.Forms.Cursors]::Hand
        Location = New-Object Drawing.Point(28, $y); Size = New-Object Drawing.Size(424, 70)
      }
      $card.Add_Paint({
        $o = $this.Tag; $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'
        $k = $g.DpiX / 96; $r = 10 * $k; $w = $this.Width - 1; $h = $this.Height - 1
        $path = New-Object Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, 2 * $r, 2 * $r, 180, 90); $path.AddArc($w - 2 * $r, 0, 2 * $r, 2 * $r, 270, 90)
        $path.AddArc($w - 2 * $r, $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $path.AddArc(0, $h - 2 * $r, 2 * $r, 2 * $r, 90, 90); $path.CloseFigure()
        if ($o.primary) {
          $g.FillPath((New-Object Drawing.SolidBrush (& $color $(if ($o.hover) { '#0a77d1' } else { '#0c8df6' }))), $path)
          $titleColor = $white; $noteColor = & $color '#e3f0fd'
        } else {
          $g.DrawPath((New-Object Drawing.Pen (& $color $(if ($o.hover) { '#2e343b' } else { '#cdd2d8' }))), $path)
          $titleColor = & $color '#2e343b'; $noteColor = & $color '#737b85'
        }
        $left = [int](20 * $k)
        [Windows.Forms.TextRenderer]::DrawText($g, $o.title, $titleFont, (New-Object Drawing.Point($left, [int](12 * $k))), $titleColor)
        [Windows.Forms.TextRenderer]::DrawText($g, $o.note, $noteFont, (New-Object Drawing.Point($left, [int](38 * $k))), $noteColor)
      })
      $card.Add_MouseEnter({ $this.Tag.hover = $true; $this.Invalidate() })
      $card.Add_MouseLeave({ $this.Tag.hover = $false; $this.Invalidate() })
      $card.Add_Click({ $choice.value = $this.Tag.value; $form.Close() })
      $form.Controls.Add($card)
      $y += 84
    }
    $form.Add_KeyDown({ if ($_.KeyCode -in 'Enter', 'Escape') { $form.Close() } })
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    $form.Dispose()
    $choice.value
  } catch { Log "edition dialog failed: $($_.Exception.Message)"; $null }
}
# Ask once, before anything is installed. Chinese is the default: Enter, a redirected input, or CODEX_SETUP_EDITION=zh;
# CODEX_SETUP_EDITION=en picks English without asking
function Select-Edition {
  if ($env:CODEX_SETUP_EDITION -in 'zh', 'en') { return $env:CODEX_SETUP_EDITION }
  if ([Console]::IsInputRedirected) { return 'zh' }
  Section '选择版本' '在弹出的窗口里点一下'
  $picked = Show-EditionDialog
  if ($picked) { return $picked }
  $H = "$Blue$Bold"
  Write-Host "     ${Dim}Codex 是 OpenAI 做的，在国内打开$R${H}只有英文界面$R${Dim}。我们可以帮你汉化：$R"
  Write-Host "     $(Pad '1. 汉化版（推荐）' 20)界面${H}中文$R · 从桌面「${H}Codex 汉化版$R」打开"
  Write-Host "     $(Pad '2. 英文原版' 20)界面${H}英文$R · 和官方${H}一模一样$R"
  while ($true) {
    $answer = "$(Read-Host '     输入 1 或 2，直接按回车选 1')".Trim()
    if ($answer -in '', '1') { return 'zh' }
    if ($answer -eq '2') { return 'en' }
  }
}
function Test-Elevated { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
# Is the current account in Administrators? In a non-elevated window the group is deny-only but the SID is still
# listed, so check the SID.
# If not, UAC asks for another admin's password and the package installs for that admin, not for this user
function Test-AdminMember { [bool]((whoami /groups) -match 'S-1-5-32-544') }

# Prompt once at the start and launch an elevated helper. It waits for install.go (the path of the verified package),
# installs it and writes install.result; it exits if the main process goes away. If the user clicks No, Start-Process
# throws "The operation was canceled by the user", so we know right away
$Script:Helper = $null
function Start-InstallHelper {
  if (Test-Elevated) { Log 'already elevated, no helper needed'; return }
  $go = Join-Path $WorkDir 'install.go'; $res = Join-Path $WorkDir 'install.result'
  $code = @"
`$go = '$go'; `$res = '$res'
while (-not (Test-Path `$go)) { if (-not (Get-Process -Id $PID -ErrorAction SilentlyContinue)) { exit }; Start-Sleep -Milliseconds 500 }
`$r = try { Add-AppxPackage -Path ([IO.File]::ReadAllText(`$go).Trim()) -ErrorAction Stop; 'OK' } catch { 'ERROR:' + `$_.Exception.Message }
[IO.File]::WriteAllText(`$res, `$r)
"@
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  Section '安装授权' '只用来装 Codex'
  Todo '马上会弹出「你要允许此应用对你的设备进行更改吗？」，点「是」'
  Info 'Codex 带一个安全沙盒组件，Windows 规定装它要你确认一次'
  try {
    $Script:Helper = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $null = $Script:Helper.Handle
    Log "install helper started pid=$($Script:Helper.Id)"
    Ok '已确认，Codex 下载完会自动安装'
  } catch {
    Log "install helper declined: $($_.Exception.Message)"
    Fail '没有点「是」，Codex 装不上。重新运行这行命令，弹出确认框时点「是」就行（已经下载的部分会接着下）。'
  }
}

# Mirror download: verify it is OpenAI's Codex from the Microsoft Store (name, publisher, signature), then hand it to
# the elevated helper
function Install-FromMsix($file) {
  $job = Start-Job -ArgumentList $file -ScriptBlock {
    param($f)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($f)
    try {
      $entry = $zip.GetEntry('AppxManifest.xml')
      $reader = [IO.StreamReader]::new($entry.Open())
      [xml]$manifest = $reader.ReadToEnd(); $reader.Close()
    } finally { $zip.Dispose() }
    $sig = Get-AuthenticodeSignature $f
    "$($manifest.Package.Identity.Name)|$($manifest.Package.Identity.Publisher)|$($sig.Status)|$($manifest.Package.Identity.Version)"
  }
  while ($job.State -eq 'Running') { Wait-Tick 0.3 '核对安装包的签名和发布者' $Script:Started }
  Clear-Line
  $check = Receive-Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  Log "package check: $check"
  $name, $publisher, $status, $version = "$check" -split '\|'
  if ($name -ne $CodexPackageName -or $publisher -ne $CodexPublisher -or $status -ne 'Valid') {
    Remove-Item $file -Force -ErrorAction SilentlyContinue
    Info "安装包核对没通过（$check），已删掉，改用微软商店"
    return $false
  }
  Ok "已确认是 OpenAI 官方原版 $version（微软商店签名）"
  $since = Get-Date
  if (Test-Elevated) {
    $job = Start-Job -ArgumentList $file -ScriptBlock { param($f) try { Add-AppxPackage -Path $f -ErrorAction Stop; 'OK' } catch { "ERROR:$($_.Exception.Message)" } }
    while ($job.State -eq 'Running') { Wait-Tick 0.3 '安装 Codex' $since }
    $result = Receive-Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
    Remove-Job $job -Force -ErrorAction SilentlyContinue
  } elseif ($Script:Helper -and -not $Script:Helper.HasExited) {
    $res = Join-Path $WorkDir 'install.result'
    [IO.File]::WriteAllText((Join-Path $WorkDir 'install.go'), $file)
    while (-not (Test-Path $res) -and -not $Script:Helper.HasExited) { Wait-Tick 0.3 '安装 Codex' $since }
    Start-Sleep -Milliseconds 300
    $result = if (Test-Path $res) { [IO.File]::ReadAllText($res).Trim() } else { 'ERROR:安装进程意外退出' }
  } else { $result = 'ERROR:没有管理员权限' }
  Clear-Line
  Log "install msix: $result"
  if ("$result" -match '0x80073CFE') { $Script:RepositoryBroken = $true }
  if ("$result" -ne 'OK') { Info "直接安装没成功（$($result -replace '^ERROR:', '')），改用微软商店"; return $false }
  Remove-Item $file, "$file.etag" -Force -ErrorAction SilentlyContinue
  $true
}

function Install-FromStore {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Start-Process "ms-windows-store://pdp/?ProductId=$CodexStoreId" -ErrorAction SilentlyContinue
    Fail '没能自动安装 Codex。已为你打开微软商店的 Codex 页面：点「获取」装好后，重新运行这行命令。'
  }
  Info '从微软商店安装（会自动同意商店条款）'
  Todo '会再弹一次「你要允许此应用对你的设备进行更改吗？」，点「是」'
  $winget = Start-Process winget -PassThru -WindowStyle Hidden -ArgumentList "install --id $CodexStoreId --source msstore --accept-package-agreements --accept-source-agreements --disable-interactivity"
  $since = Get-Date
  while (-not $winget.HasExited) { Wait-Tick 0.3 '从微软商店安装 Codex' $since }
  Clear-Line
  Log "winget exit=$($winget.ExitCode)"   # winget reports success even when UAC was declined, so the caller checks again
  if ($winget.ExitCode -eq -2147009282) { $Script:RepositoryBroken = $true }   # 0x80073CFE
}

# ---------- Zhipu API key ----------
# The login window needs a Chromium browser with a DevTools port: Edge first, then Chrome. Stripped-down Windows
# images often remove Edge, and either may live outside the default folder, so also ask the registry (App Paths).
# Returns every browser found, so a blocked or crashing Edge can fall back to Chrome
function Find-LoginBrowsers {
  foreach ($exe in 'msedge.exe', 'chrome.exe') {
    $paths = @(@('HKLM:', 'HKCU:') | ForEach-Object { (Get-ItemProperty "$_\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe" -ErrorAction SilentlyContinue).'(default)' })
    $vendor = if ($exe -eq 'msedge.exe') { 'Microsoft\Edge' } else { 'Google\Chrome' }
    $paths += @("${env:ProgramFiles(x86)}", $env:ProgramFiles, $env:LOCALAPPDATA) | ForEach-Object { "$_\$vendor\Application\$exe" }
    $found = $paths | Where-Object { $_ -and (Test-Path $_.Trim('"')) } | Select-Object -First 1
    if ($found) { $found.Trim('"') }
  }
}

# No Edge or Chrome: install Edge with Microsoft's own online installer (about 2 MB, reachable from China), after
# checking it is signed by Microsoft. It installs silently; Windows may ask once for permission
function Install-Edge {
  $setup = Join-Path $WorkDir 'MicrosoftEdgeSetup.exe'
  Info '这台电脑没有 Edge 浏览器（精简版 Windows 常见），先从微软官网装一个，扫码登录要用'
  $job = Start-Job -ArgumentList $setup -ScriptBlock {
    param($f)
    try {
      Invoke-WebRequest 'https://go.microsoft.com/fwlink/?linkid=2108834&Channel=Stable&language=zh-cn' -OutFile $f -UseBasicParsing -TimeoutSec 120
      $sig = Get-AuthenticodeSignature $f
      "$($sig.Status)|$($sig.SignerCertificate.Subject)"
    } catch { "ERROR|$($_.Exception.Message)" }
  }
  while ($job.State -eq 'Running') { Wait-Tick 0.3 '下载 Edge 安装器' $Script:Started }
  Clear-Line
  $check = Receive-Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  Log "edge setup check: $check"
  $status, $subject = "$check" -split '\|', 2
  if ($status -ne 'Valid' -or $subject -notmatch 'O=Microsoft Corporation') { Remove-Item $setup -Force -ErrorAction SilentlyContinue; return }
  Todo '如果弹出「你要允许此应用对你的设备进行更改吗？」，点「是」'
  try { $process = Start-Process $setup -PassThru -ArgumentList '/silent /install' } catch { Log "edge setup declined: $($_.Exception.Message)"; return }
  $since = Get-Date
  while (-not $process.HasExited) { Wait-Tick 0.3 '安装 Edge' $since }
  Clear-Line
  # The online installer exits before the browser files are all in place, so wait for msedge.exe to show up
  for ($i = 0; $i -lt 120 -and -not (Find-LoginBrowsers); $i++) { Wait-Tick 0.5 '安装 Edge' $since }
  Clear-Line
  Log "edge setup exit=$($process.ExitCode) browsers=$(Find-LoginBrowsers)"
  Remove-Item $setup -Force -ErrorAction SilentlyContinue
}

function Invoke-PageScript($socket, [ref]$nextId, $expression) {
  $id = $nextId.Value; $nextId.Value++
  $message = @{ id = $id; method = 'Runtime.evaluate'; params = @{ expression = $expression; awaitPromise = $true; returnByValue = $true } } | ConvertTo-Json -Depth 5 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($message)
  $socket.SendAsync([ArraySegment[byte]]::new($bytes), 'Text', $true, [Threading.CancellationToken]::None).Wait()
  $buffer = New-Object byte[] 65536
  while ($true) {
    $text = ''
    do {
      $received = $socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), [Threading.CancellationToken]::None).Result
      $text += [Text.Encoding]::UTF8.GetString($buffer, 0, $received.Count)
    } while (-not $received.EndOfMessage)
    $reply = $text | ConvertFrom-Json
    if ($reply.id -eq $id) { return $reply.result.result.value }
  }
}

$ReadStateScript = @'
(() => {
  const token = (document.cookie.split('; ').find(c => c.startsWith('bigmodel_token_production=')) || '').split('=').slice(1).join('=');
  const ready = Boolean(token && localStorage.getItem('Bigmodel-Organization') && localStorage.getItem('Bigmodel-Project'));
  if (ready && !location.pathname.startsWith('/apikey') && !location.pathname.startsWith('/usercenter')) location.href = '/apikey/platform';
  return ready ? 'ready' : 'waiting';
})()
'@
$CreateKeyScript = @'
(async () => {
  try {
    const token = (document.cookie.split('; ').find(c => c.startsWith('bigmodel_token_production=')) || '').split('=').slice(1).join('=');
    const organization = localStorage.getItem('Bigmodel-Organization');
    const project = localStorage.getItem('Bigmodel-Project');
    const response = await fetch('/api/biz/v1/organization/' + organization + '/projects/' + project + '/api_keys', {
      method: 'POST', credentials: 'include',
      headers: { 'Content-Type': 'application/json', Authorization: token, 'Bigmodel-Organization': organization, 'Bigmodel-Project': project },
      body: JSON.stringify({ name: (() => { const d = new Date(), p = n => String(n).padStart(2, '0'); return 'Codex-' + String(d.getFullYear()).slice(2) + p(d.getMonth() + 1) + p(d.getDate()) + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds()); })(), keyType: 1, usageScene: 2 }),
    }).then(r => r.json());
    return response.code === 200 && response.data ? 'KEY:' + response.data.apiKey + '.' + response.data.secretKey : 'ERROR:' + (response.msg || response.code);
  } catch (e) { return 'ERROR:' + e.message; }
})()
'@

function Get-ZhipuKeyAutomatically {
  $browsers = @(Find-LoginBrowsers)
  if (-not $browsers) { Install-Edge; $browsers = @(Find-LoginBrowsers) }
  if (-not $browsers) { return 'ERROR:没有找到 Edge 浏览器，自动安装也没成功' }
  foreach ($browser in $browsers) {
    $outcome = Get-ZhipuKeyWithBrowser $browser
    if ($outcome -notlike 'WINDOW:*') { return $outcome }
  }
  return $outcome
}

# The login window never connected: find out why from the browser process, its DevTools port, the pages it shows and
# the browser's admin policy (company and school PCs can switch remote debugging off), and log it all
function Get-LoginWindowProblem($browser, $process, $lastError) {
  $vendor = if ($browser -like '*chrome.exe') { 'Google\Chrome' } else { 'Microsoft\Edge' }
  $policy = @('HKLM:', 'HKCU:') | ForEach-Object { (Get-ItemProperty "$_\SOFTWARE\Policies\$vendor" -ErrorAction SilentlyContinue).RemoteDebuggingAllowed } | Where-Object { $null -ne $_ } | Select-Object -First 1
  $pages = try { (@(Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/list" -TimeoutSec 2) | ForEach-Object { $_.url }) -join ' ' } catch { "no port ($($_.Exception.Message))" }
  $exited = $process.HasExited
  Log "login window failed: browser=$browser exited=$exited exit=$(if ($exited) { $process.ExitCode }) policy=$policy pages=$pages last=$lastError"
  if ("$policy" -eq '0') { return 'WINDOW:POLICY' }
  if ($pages -match 'chrome-error://') { return 'WINDOW:NETWORK' }
  if ($exited -and $pages -like 'no port*') { return 'WINDOW:EXITED' }
  return 'WINDOW:NO_CONNECTION'
}

function Get-ZhipuKeyWithBrowser($browser) {
  $profileDir = Join-Path $WorkDir $(if ($browser -like '*chrome.exe') { 'chrome-profile' } else { 'edge-profile' })
  $edgeProcess = Start-Process -FilePath $browser -PassThru -ArgumentList @(
    "--remote-debugging-port=$DebugPort", "--user-data-dir=`"$profileDir`"", '--no-first-run', '--no-default-browser-check', '--lang=zh-CN', '--disable-features=Translate',
    "--app=$ZhipuLoginUrl", '--window-size=1100,800')
  try {
    # Reloads and navigations drop the DevTools connection, so reconnect on every error; give up only when the window is closed
    $connectToPage = {
      for ($i = 0; $i -lt 20; $i++) {
        try {
          $targets = Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/list" -TimeoutSec 2
          $url = ($targets | Where-Object { $_.type -eq 'page' -and $_.url -like '*bigmodel.cn*' } | Select-Object -First 1).webSocketDebuggerUrl
          if ($url) {
            $newSocket = [Net.WebSockets.ClientWebSocket]::new()
            $newSocket.ConnectAsync([Uri]$url, [Threading.CancellationToken]::None).Wait()
            return $newSocket
          }
        } catch { $Script:LastConnectError = $_.Exception.Message }
        Start-Sleep -Milliseconds 500
      }
      return $null
    }
    $Script:LastConnectError = $null
    $socket = & $connectToPage
    if (-not $socket) { return Get-LoginWindowProblem $browser $edgeProcess $Script:LastConnectError }
    $nextId = 1
    $loginSince = Get-Date
    $deadline = (Get-Date).AddMinutes(60)
    $lastRefresh = Get-Date
    while ((Get-Date) -lt $deadline) {
      Wait-Tick 1.5 '等待扫码登录' $loginSince
      # The debugging port is gone: the user closed the login window
      try { Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/version" -TimeoutSec 2 | Out-Null } catch { return 'CANCELLED' }
      try { $state = Invoke-PageScript $socket ([ref]$nextId) $ReadStateScript }
      catch {
        $socket = & $connectToPage
        if (-not $socket) { return 'CANCELLED' }
        continue
      }
      if ($state -ne 'ready') {
        # WeChat QR codes expire within minutes: reload every 4 minutes until the user logs in
        if (((Get-Date) - $lastRefresh).TotalMinutes -ge 4) {
          try { Invoke-PageScript $socket ([ref]$nextId) 'location.reload()' | Out-Null } catch { }
          $lastRefresh = Get-Date
        }
        continue
      }
      Start-Sleep -Seconds 2   # Let the redirect to the console settle
      $result = Invoke-PageScript $socket ([ref]$nextId) $CreateKeyScript
      if ($result -like 'KEY:*') { return $result.Substring(4) }
      return $result
    }
    return 'TIMEOUT'
  } finally {
    if ($edgeProcess -and -not $edgeProcess.HasExited) { Stop-Process -Id $edgeProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}


# Try each free Zhipu model with this key and return the first that works; the last HTTP status is left in $Script:LastStatus
function Find-FreeModel($key) {
  foreach ($candidate in $FreeModels) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
      $job = Start-Job -ArgumentList $ZhipuBaseUrl, $key, $candidate -ScriptBlock {
        param($base, $k, $m)
        $body = @{ model = $m; input = 'Reply with exactly one word: pong'; max_output_tokens = 16 } | ConvertTo-Json -Compress
        # Zhipu answers HTTP 200 even for an invalid key, with a body like {"code":1000,...,"success":false}
        try { $resp = Invoke-RestMethod -Method Post -Uri "$base/responses" -Headers @{ Authorization = "Bearer $k" } -ContentType 'application/json' -Body $body -TimeoutSec 60; if ($resp.success -eq $false) { 401 } else { 200 } }
        catch { [int]$_.Exception.Response.StatusCode }
      }
      $since = Get-Date
      while ($job.State -eq 'Running') { Wait-Tick 0.3 "测试智谱免费模型 $candidate" $since }
      Clear-Line
      $Script:LastStatus = Receive-Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
      Remove-Job $job -Force -ErrorAction SilentlyContinue
      Log "model test $candidate try $($attempt + 1): HTTP $Script:LastStatus"
      if ($Script:LastStatus -eq 200) { return $candidate }
      if ($Script:LastStatus -ne 429) { break }
      Start-Sleep -Seconds 3
    }
  }
  return $null
}

# ================= Main =================
$Steps = 3
try {
  Header 'CODEX INSTALLER' 'Codex 一键安装 · 国产模型版 · 不用科学上网 · 不花一分钱'
  Write-Host "  $Blue→$R 遇到问题来社群找我们：${Link}https://humanslive.ai/community$R"
  $Edition = Select-Edition
  Log "edition: $Edition"
  Ok $(if ($Edition -eq 'zh') { '汉化版' } else { '英文原版' })

  # ---------- Preparation: system check, source race, then start the background download ----------
  Section '系统检测' ''
  $os = Get-CimInstance Win32_OperatingSystem
  Log "os=$($os.Caption) build=$($os.BuildNumber) arch=$env:PROCESSOR_ARCHITECTURE ps=$($PSVersionTable.PSVersion) console=$ConsoleClass fancy=$Fancy live=$Live"
  Log "user=$env:USERNAME locale=$((Get-Culture).Name) proxy=$([bool]($env:HTTPS_PROXY -or $env:HTTP_PROXY)) browsers=$(Find-LoginBrowsers)"
  Ok "$($os.Caption -replace 'Microsoft ', '') · $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM' } else { 'x64' })"
  $codex = Get-Codex
  $source = $null
  if ($codex) {
    Log "codex already installed: $($codex.Version)"
    Ok '已经装过 Codex，这次不用下载'
  } else {
    $freeGb = [int]((Get-PSDrive ($env:LOCALAPPDATA.Substring(0, 1))).Free / 1GB)
    if ($freeGb -lt 4) { Fail "硬盘空间不够：装 Codex 需要约 4GB，现在只剩 ${freeGb}GB。清理一些文件后，重新运行这行命令。" }
    Ok "硬盘可用 $freeGb GB，够装 Codex"
    if (-not (Test-AdminMember)) {
      Log 'not an administrator account'
      Fail '这台电脑现在登录的账号不是管理员。Codex 带一个系统组件，Windows 规定要管理员账号才能装。换管理员账号登录后，重新运行这行命令。'
    }
    $source = Select-Source
    if ($source) { Start-Download $source.Url $source.Name $source.File; Start-InstallHelper }
  }

  # ---------- [1/3] Zhipu account (the only step that needs the user) ----------
  Say '登录智谱'
  $configPath = Join-Path $CodexHome 'config.toml'
  $authPath = Join-Path $CodexHome 'auth.json'
  $utf8NoBom = [Text.UTF8Encoding]::new($false)
  # Already set up by this script and the key still works: no new scan, no new key
  $oldKey = $null
  if ((Test-Path $authPath) -and (Test-Path $configPath) -and (Select-String -Quiet -Path $configPath -Pattern '^model_provider = "zhipu"')) {
    if ([IO.File]::ReadAllText($authPath, $utf8NoBom).Trim() -match '^\{"OPENAI_API_KEY":"(.+)"\}$') { $oldKey = $Matches[1] }
  }
  $Model = $null
  if (-not $env:CODEX_SETUP_ZHIPU_KEY -and $oldKey -match $ZhipuKeyPattern -and ($Model = Find-FreeModel $oldKey)) {
    $ZhipuApiKey = $oldKey
    Ok '之前已经登录过智谱，Key 还能用，这次不用扫码'
  } else {
    if ($env:CODEX_SETUP_ZHIPU_KEY) {
      $ZhipuApiKey = $env:CODEX_SETUP_ZHIPU_KEY
      Ok '使用环境变量里提供的 Key'
    } else {
      Todo '在弹出的智谱窗口里，用手机微信扫码登录'
      Info '第一次用智谱的话，扫码后还要填手机号、收一次验证码'
      if ($Script:Dl) { Info 'Codex 同时在后台下载，不用等' }
      $outcome = Get-ZhipuKeyAutomatically
      Clear-Line
      if ($outcome -match $ZhipuKeyPattern) {
        Log 'login outcome: key created'
        $ZhipuApiKey = $outcome
        Ok '已登录，自动创建好 API Key'
        Show-KeyNote
      } else {
        # No manual copy-the-key fallback: reading the clipboard gets the script flagged by Windows Defender as a
        # credential stealer (VirTool:PowerShell/MaleficAms),
        # and the user should not need an extra step. A closed window, no scan or a Zhipu API error all ask the
        # user to rerun, with the reason in the log
        Log "login outcome: $outcome"
        switch -Wildcard ($outcome) {
          'CANCELLED' { Fail '智谱登录窗口被关掉了。重新运行这行命令，扫码登录就行。' }
          'TIMEOUT'   { Fail '一个小时内没有扫码登录。重新运行这行命令，扫码登录就行。' }
          'WINDOW:POLICY'  { Fail '这台电脑的管理策略不允许程序打开浏览器登录窗口（公司、学校的电脑常见），没法自动登录智谱。换一台自己的电脑，或者请电脑管理员放开 Edge / Chrome 的 RemoteDebuggingAllowed 策略。' }
          'WINDOW:EXITED'  { Fail '智谱登录窗口刚打开就关掉了，多半是被安全软件（360、火绒、电脑管家等）拦住了。先暂时退出安全软件，再重新运行这行命令。' }
          'WINDOW:NETWORK' { Fail '登录窗口打不开智谱网站（open.bigmodel.cn）。先在浏览器里试试能不能打开这个网址，网络正常后再重新运行这行命令。' }
          'WINDOW:*'       { Fail '智谱登录窗口没能连上，多半是被安全软件（360、火绒、电脑管家等）拦住了。先暂时退出安全软件，再重新运行这行命令；还不行的话，把下面的日志发给我们，我们来修。' }
          default     { Fail ('自动创建 API Key 没成功（' + ($outcome -replace '^ERROR:', '') + '），可能是智谱的网站改版了。重新运行这行命令再试一次；还不行的话，把下面的日志发给我们，我们来修。') }
        }
      }
    }
    if ($ZhipuApiKey -notmatch $ZhipuKeyPattern) { Fail 'API Key 格式不对。' }
    $Model = Find-FreeModel $ZhipuApiKey
    if (-not $Model) { Fail "智谱免费模型暂时不可用（HTTP $Script:LastStatus），请稍后重新运行这行命令。" }
  }
  Ok "智谱免费模型可以用：$Model"
  # A running Codex reads its config, key and language only at startup, so close it before writing; Open-Codex starts
  # it again at the end. The sandbox service lives in the same package but runs as SYSTEM and stays
  if ($codex) {
    $appDir = Join-Path $codex.Package.InstallLocation 'app\'
    $running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      $_.ExecutablePath -and $_.ExecutablePath.StartsWith($appDir, [StringComparison]::OrdinalIgnoreCase) -and $_.Name -notlike 'codex-windows-sandbox-service*' })
    if ($running) {
      Log "codex app running ($($running.Count) processes): closing before writing the config"
      Info 'Codex 正开着，先关掉，配置写好后会重新打开'
      foreach ($p in $running) { taskkill.exe /F /T /PID $p.ProcessId 2>&1 | Out-Null }
      for ($i = 0; $i -lt 20 -and ($running | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }); $i++) { Start-Sleep -Milliseconds 500 }
    }
  }
  # ---------- Write the config as soon as the key exists, so a rerun after a later failure needs no new scan ----------
  # Only touch model, model_provider and [model_providers.zhipu]; keep everything else. Back up only if content
  # changes. UTF-8 without BOM.
  New-Item -ItemType Directory -Force $CodexHome | Out-Null
  $backupSuffix = '.bak-' + (Get-Date -Format 'yyyyMMddHHmmss')
  $keptLines = @()
  if (Test-Path $configPath) {
    $inTable = $false; $skipTable = $false
    foreach ($line in [IO.File]::ReadAllLines($configPath, $utf8NoBom)) {
      if ($line -match '^\[') { $inTable = $true; $skipTable = ($line.Trim() -eq '[model_providers.zhipu]') }
      if (-not $inTable -and $line -match '^\s*(model|model_provider)\s*=') { continue }
      if (-not $skipTable) { $keptLines += $line }
    }
  }
  $configLines = @("model_provider = `"zhipu`"", "model = `"$Model`"", '') + $keptLines + @(
    '', '[model_providers.zhipu]', 'name = "智谱 GLM"', "base_url = `"$ZhipuBaseUrl`"", 'wire_api = "responses"', 'requires_openai_auth = true')
  # Codex follows the system language by default; set the Language setting (stored under [desktop]) to the chosen
  # edition on every run: replace any other value in place, so an unchanged config stays byte-identical. Windows' own
  # dialogs follow the Windows display language; there is no per-app switch for those
  $localeLine = if ($Edition -eq 'zh') { 'localeOverride = "zh-CN"' } else { 'localeOverride = "en-US"' }
  $desktopAt = [array]::IndexOf($configLines, '[desktop]')
  if ($desktopAt -ge 0) {
    $found = $false
    for ($i = $desktopAt + 1; $i -lt $configLines.Count -and $configLines[$i] -notmatch '^\['; $i++) {
      if ($configLines[$i] -match '^\s*localeOverride\s*=') { $configLines[$i] = $localeLine; $found = $true }
    }
    if (-not $found) {
      $after = if ($desktopAt -lt $configLines.Count - 1) { $configLines[($desktopAt + 1)..($configLines.Count - 1)] } else { @() }
      $configLines = $configLines[0..$desktopAt] + @($localeLine) + $after
    }
  }
  else { $configLines += @('', '[desktop]', $localeLine) }
  $newConfig = ($configLines -join "`n") + "`n"
  $newAuth = "{`"OPENAI_API_KEY`":`"$ZhipuApiKey`"}`n"
  $backedUp = $false
  foreach ($pair in @(@($configPath, $newConfig), @($authPath, $newAuth))) {
    $path, $content = $pair
    if ((Test-Path $path) -and [IO.File]::ReadAllText($path, $utf8NoBom) -eq $content) { continue }
    if (Test-Path $path) { Copy-Item $path ($path + $backupSuffix); $backedUp = $true }
    [IO.File]::WriteAllText($path, $content, $utf8NoBom)
  }
  Log "config written: $configPath"
  Ok '已把 Key 和模型写进 Codex 的配置'
  if ($backedUp) { Info "原来的配置已备份为 *$backupSuffix" }


  # ---------- [2/3] Install Codex ----------
  Say '安装 Codex'
  if ($codex) {
    Ok "已经装过 Codex $($codex.Version)，跳过"
  } else {
    $installed = $false
    if ($Script:Dl) {
      if (-not $Script:Dl.Done) {
        Info "下载 Codex（$($Script:Dl.Name)$(if ($Script:Dl.Total -gt 0) { "，约 $([int]($Script:Dl.Total / 1MB)) MB" })；中断后重新运行会接着下）"
        Show-DownloadProgress
      }
      if ($Script:Dl.Done) {
        Ok "下载完成（$(MB (Get-DownloadedBytes)) MB）"
        $installed = Install-FromMsix $Script:Dl.File
      } else { Info '镜像下载失败，改用微软商店' }
    }
    # 0x80073CFE: Windows' app database (AppRepository) is damaged, so the Store fails the same way and only a
    # Windows repair helps; common on trimmed or modified Windows images
    if (-not $installed -and -not $Script:RepositoryBroken) { Install-FromStore }
    $codex = Get-Codex
    if (-not $codex -and $Script:RepositoryBroken) {
      $repair = if ([int]$os.BuildNumber -ge 22000) { '打开「设置 → 系统 → 恢复」，在「使用 Windows 更新修复问题」那一行点「立即重新安装」（保留文件和软件，约 1 小时）' }
                else { '到微软官网下载「Windows 10 媒体创建工具」，选「立即升级这台电脑」并保留文件和应用（约 1 小时）' }
      Fail "这台电脑的 Windows 应用数据库坏了（错误 0x80073CFE），微软商店也装不上任何应用，不是 Codex 的问题，多见于精简版、修改版 Windows。修复办法：$repair。修好后重新运行这行命令。"
    }
    if (-not $codex) {
      Start-Process "ms-windows-store://pdp/?ProductId=$CodexStoreId" -ErrorAction SilentlyContinue
      Fail '没能自动安装 Codex。已为你打开微软商店的 Codex 页面：点「获取」装好后，重新运行这行命令。'
    }
    Log "codex installed: $($codex.Version) service=$((Get-Service "CodexSandboxService.$($codex.Package.PackageFamilyName -replace '_[^_]+$', '')" -ErrorAction SilentlyContinue).Status)"
    Ok "Codex $($codex.Version) 已装好"
  }

  # ---------- [3/3] Smoke test, then open ----------
  Say '打开 Codex'
  $codexCli = $codex.Cli
  if (Test-Path $codexCli) {
    # codex waits forever unless stdin is closed; run it as a job with a 120 s limit
    $job = Start-Job -ArgumentList $codexCli, $CodexHome, $WorkDir -ScriptBlock {
      param($cli, $codexHomeDir, $dir)
      $env:CODEX_HOME = $codexHomeDir
      [Console]::OutputEncoding = [Text.UTF8Encoding]::new()   # codex prints UTF-8; without this, Chinese replies are garbled
      Set-Location $dir
      cmd /c "`"$cli`" exec --ephemeral --skip-git-repo-check `"只回复两个字：好了`" < NUL 2>NUL"
    }
    $since = Get-Date
    while ($job.State -eq 'Running' -and ((Get-Date) - $since).TotalSeconds -lt 120) { Wait-Tick 0.3 '让 Codex 回一句话' $since }
    Clear-Line
    $reply = if ($job.State -ne 'Running') { Receive-Job $job | Select-Object -Last 1 } else { Stop-Job $job; $null }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    Log "verify reply: $reply"
    if ($reply) { Ok "Codex 回复：$reply" } else { Info 'Codex 没有回复，打开后可以直接试用' }
  }
  $launcher = $null
  if ($Edition -eq 'zh') { $launcher = try { Install-CodexZh } catch { Log "chinese launcher failed: $($_.Exception.Message)"; $null } }
  else { Remove-CodexZh }
  if (-not $env:CODEX_SETUP_NO_OPEN) {
    if ($launcher) { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`"" }
    else { Open-Codex $codex }
  }
  Finish "Codex 已经打开，用的是智谱免费模型 $Bold$Model$R"
  Show-NextSteps $configPath

  # ---------- Closing banner: other free HumansLive tools ----------
  # Content and layout come from the website (one kind<TAB>a<TAB>b per line); this only colors by kind.
  # If it cannot be fetched, print one URL instead; the install result is unaffected.
  $text = $null
  try { $text = Invoke-RestMethod -TimeoutSec 6 "https://humanslive.ai/api/install-banner?f=codex&w=$(Get-ConsoleWidth)" } catch { }
  if (-not $text) { Write-Host ''; Write-Host '  更多免费工具和服务：https://humanslive.ai'; Write-Host '' }
  else {
    foreach ($line in (($text -replace "`r", '' -replace [char]27, '') -split "`n")) {
      $p = $line -split "`t"
      switch ($p[0]) {
        'rule'  { Write-Host "  $Dim$($p[1])$R" }
        'brand' { Write-Host "  $Bold$($p[1])$R$($p[2])" }
        'head'  { Write-Host "  $Blue$Bold$($p[1])$R  $Dim$($p[2])$R" }
        'row'   { Write-Host "    $($p[1])$Dim$($p[2])$R" }
        'link'  { Write-Host "    $Blue$($p[1])$R" }
        default { Write-Host '' }
      }
    }
  }
  Write-Host ''
  Write-Host "  ${Bold}装好了，可以关掉这个窗口。$R"
  Write-Host ''
} catch {
  # Unexpected error: log the details and show the user one sentence and the log path, not a red stack dump
  if ("$_" -ne 'HL_FAIL') {
    Log "EXCEPTION $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    Log "AT $($_.InvocationInfo.PositionMessage -replace "`r?`n", ' | ')"
    Show-Error "安装中途出了意外：$($_.Exception.Message)"
  }
} finally {
  # On Ctrl+C or error, stop the background download too; the partial file stays in the cache and a rerun resumes it
  Stop-Download
  Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}
