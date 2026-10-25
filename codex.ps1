# Codex 一键安装（Windows）：装好官方 Codex App，用微信扫码登录智谱后自动创建 API Key，接上智谱免费模型。
# 用法（PowerShell）：irm https://humanslive.ai/codex.ps1 | iex
# 只做这几件事：下载并核对官方 Codex 安装包（国内镜像，不行就用微软商店）、打开智谱登录窗口、新建一个 API Key、
# 写 %USERPROFILE%\.codex 下的配置、打开 Codex。和 Mac 版一样：先扫码，Codex 同时在后台下载。
# 兼容 Windows 自带的 PowerShell 5.1；不需要管理员权限。

$ErrorActionPreference = 'Continue'   # codex.exe 会往 stderr 写警告，Stop 会把它当成错误中断
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$ProgressPreference = 'SilentlyContinue'

$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$CodexStoreId = '9PLM9XGG6VKS'
$CodexPackageName = 'OpenAI.Codex'
$CodexPublisher = 'CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B'   # 微软商店里 OpenAI.Codex 的发布者，用来核对镜像下载的安装包
$ZhipuBaseUrl = 'https://open.bigmodel.cn/api/v1'
$ZhipuLoginUrl = 'https://bigmodel.cn/login?redirect=%2Fapikey%2Fplatform'
$ZhipuKeyPage = 'https://bigmodel.cn/usercenter/proj-mgmt/apikeys'
$ZhipuKeyPattern = '^[0-9a-f]{32}\.[A-Za-z0-9]{16}$'
$FreeModels = @('glm-4.5-flash', 'glm-4.7-flash')
$DebugPort = 9333
$CacheDir = if ($env:CODEX_SETUP_CACHE_DIR) { $env:CODEX_SETUP_CACHE_DIR } else { Join-Path $env:LOCALAPPDATA 'HumansLive' }
$WorkDir = Join-Path $env:TEMP ('codex-setup-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# ---------- 终端输出 ----------
# 只有一个强调色（蓝），次要信息用灰色，红色只用于出错。支持 ANSI 的终端里有动画（Windows Terminal 用更细的字符），
# 输出被重定向或设了 NO_COLOR 时只打纯文字。
$E = [char]27
$Live = $Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected -and -not $env:NO_COLOR
$Fancy = [bool]$env:WT_SESSION   # Windows Terminal 的字体有盲文转圈、片假名和粗横线；老的控制台窗口用 ASCII
if ($Live) {
  $R = "$E[0m"; $Bold = "$E[1m"; $Dim = "$E[2m"; $Blue = "$E[38;5;33m"; $Head = "$E[38;5;153m"; $Deep = "$E[38;5;25m"; $Red = "$E[31m"
} else { $R = $Bold = $Dim = $Blue = $Head = $Deep = $Red = '' }
$Spinner = if ($Fancy) { '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'.ToCharArray() } else { '|/-\'.ToCharArray() }
$BarOn = if ($Fancy) { '━' } else { '=' }
$BarOff = if ($Fancy) { '─' } else { '-' }
$Script:Step = 0
$Script:Started = Get-Date

function W($text) { Write-Host $text -NoNewline }
function Get-ConsoleWidth { try { [int]$Host.UI.RawUI.WindowSize.Width } catch { 80 } }
# 终端里占几列：中文等宽字符占两列
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

# 数字雨：几行字符往下落，结束后擦掉
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
# 乱码逐字解码成文字（只打乱英文和数字，中文原样）
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
function Section($title, $note) { Write-Host ''; Write-Host "  $Blue$Bold▸$R $Bold$title$R  $Dim$note$R" }
function Say($text) { $Script:Step++; Write-Host ''; Write-Host "  $Blue$Bold[$($Script:Step)/$Steps]$R $Bold$text$R" }
function Info($text) { Write-Host "       $Dim$text$R" }
function Ok($text)   { Write-Host "     $Blue√$R $text" }
function Todo($text) { Write-Host "     $Blue→$R $Bold$text$R" }
function Finish($text) {
  $took = (Get-Date) - $Script:Started
  $tookText = if ($took.TotalSeconds -lt 60) { "$([int]$took.TotalSeconds) 秒" } else { "$([int][Math]::Floor($took.TotalMinutes)) 分 $($took.Seconds) 秒" }
  Write-Host ''
  if ($Live) { Show-Decode "$Blue$Bold" '√ ALL SYSTEMS GO · 全部完成' } else { Write-Host '  √ ALL SYSTEMS GO · 全部完成' }
  Write-Host "     ${Dim}用时 $tookText$R"
  Write-Host "     $text"
}
function Fail($text) {
  if ($Live) { W "`r$E[K" }
  Write-Host ''
  Write-Host "  $Red$Bold× 出错了$R"
  Write-Host "     $text"
  Write-Host "     ${Dim}需要帮助：截图发到社群 https://humanslive.ai/community$R"
  Write-Host ''
  throw 'HL_FAIL'   # 外面的 catch 认这个，不再让 PowerShell 打一大段红色错误
}

# 转圈一小段时间（同时推进后台下载），显示文字、已等的秒数和后台下载进度
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

# ---------- 后台下载：curl.exe（Windows 10 起自带），断了自动重试，下到缓存目录，中断后重新运行会接着下 ----------
$Script:Dl = $null   # @{ Url; Name; File; Total; Proc; Tries; Done; Failed }
function Start-DownloadProcess {
  $d = $Script:Dl
  $d.Proc = Start-Process curl.exe -PassThru -WindowStyle Hidden -ArgumentList @('-fsSL', '-C', '-', '--retry', '3', '--connect-timeout', '15', '-o', "`"$($d.File)`"", $d.Url)
  $null = $d.Proc.Handle   # 不先取一次 Handle，进程结束后拿不到退出码
  $d.Tries++
}
function Start-Download($url, $name, $file) {
  $headers = (& curl.exe -sIL --connect-timeout 15 --max-time 20 $url 2>$null) -join "`n"
  $total = 0; $etag = ''
  foreach ($line in ($headers -split "`n")) {
    if ($line -match '^(?i)content-length:\s*(\d+)') { $total = [long]$Matches[1] }
    if ($line -match '^(?i)etag:\s*(\S+)') { $etag = $Matches[1] }
  }
  # 上次没下完、而源上已经换了新版本：旧的半截文件不能续，删掉重下
  if ((Test-Path "$file.etag") -and ((Get-Content "$file.etag" -Raw) -ne $etag)) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
  Set-Content "$file.etag" $etag -NoNewline
  $size = if (Test-Path $file) { (Get-Item $file).Length } else { 0 }
  if ($total -gt 0 -and $size -gt $total) { Remove-Item $file -Force; $size = 0 }
  $Script:Dl = @{ Url = $url; Name = $name; File = $file; Total = $total; Proc = $null; Tries = 0; Done = $false; Failed = $false }
  if ($total -gt 0 -and $size -eq $total) { $Script:Dl.Done = $true } else { Start-DownloadProcess }
}
function Update-Download {
  $d = $Script:Dl
  if (-not $d -or $d.Done -or $d.Failed -or -not $d.Proc.HasExited) { return }
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

# 前台画进度条，直到后台下载结束
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

# ---------- 线路测速：镜像和微软商店。镜像在中国大陆走国内节点，测 8 秒；商店没法单独测速，作为备用 ----------
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
  $file = Join-Path $CacheDir "Codex-$arch.msix"
  if ($Live) {
    $bar = if ($barW -ge 6) { "$Blue$($BarOn * $barW)$R  " } else { '' }
    $num = if ($speed -gt 0) { '{0,5} MB/s' -f (MB $speed) } else { '   连不上 ' }
    if ($useMirror) {
      W ("$E[2A`r$E[K     $Blue$Bold√$R $($names[0])  $Dim$($tags[0])$R  $bar$num  $Blue${Bold}最快$R`n" +
         "`r$E[K     $Dim· $($names[1])  $($tags[1])  备用$R`n")
    } else {
      W ("$E[2A`r$E[K     $Dim· $($names[0])  $($tags[0])  $num$R`n" +
         "`r$E[K     $Blue$Bold√$R $($names[1])  $Dim$($tags[1])$R  ${Blue}${Bold}改用这条$R`n")
    }
  }
  if (-not $useMirror) { return $null }
  # 测速下的这一段就是文件开头：缓存里没有更长的，就直接接着用
  New-Item -ItemType Directory -Force $CacheDir | Out-Null
  $cached = if (Test-Path $file) { (Get-Item $file).Length } else { 0 }
  if ($size -gt $cached) { Move-Item $probe $file -Force; Remove-Item "$file.etag" -ErrorAction SilentlyContinue }
  Ok '下载线路：国内镜像'
  @{ Url = $mirrorUrl; Name = '国内镜像'; File = $file }
}

# ---------- 安装 Codex ----------
function Get-CodexPackage { Get-AppxPackage -Name $CodexPackageName -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1 }

# 镜像下载的安装包：核对是不是微软商店里那份 OpenAI 官方的 Codex（包名、发布者、签名），再安装
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
    "$($manifest.Package.Identity.Name)|$($manifest.Package.Identity.Publisher)|$($sig.Status)"
  }
  while ($job.State -eq 'Running') { Wait-Tick 0.3 '核对安装包的签名和发布者' $Script:Started }
  Clear-Line
  $check = Receive-Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  $name, $publisher, $status = "$check" -split '\|'
  if ($name -ne $CodexPackageName -or $publisher -ne $CodexPublisher -or $status -ne 'Valid') {
    Remove-Item $file -Force -ErrorAction SilentlyContinue
    Info "安装包核对没通过（$check），已删掉，改用微软商店"
    return $false
  }
  Ok '已确认是 OpenAI 官方原版（微软商店签名）'
  $job = Start-Job -ArgumentList $file -ScriptBlock { param($f) try { Add-AppxPackage -Path $f -ErrorAction Stop; 'OK' } catch { "ERROR:$($_.Exception.Message)" } }
  $since = Get-Date
  while ($job.State -eq 'Running') { Wait-Tick 0.3 '安装 Codex' $since }
  Clear-Line
  $result = Receive-Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
  Remove-Job $job -Force -ErrorAction SilentlyContinue
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
  $winget = Start-Process winget -PassThru -WindowStyle Hidden -ArgumentList "install --id $CodexStoreId --source msstore --accept-package-agreements --accept-source-agreements --disable-interactivity"
  $since = Get-Date
  while (-not $winget.HasExited) { Wait-Tick 0.3 '从微软商店安装 Codex' $since }
  Clear-Line
}

# ---------- 智谱 API Key ----------
function Find-Edge {
  foreach ($path in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe")) {
    if (Test-Path $path) { return $path }
  }
  return $null
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
  $edge = Find-Edge
  if (-not $edge) { return 'ERROR:没有找到 Edge' }
  $profileDir = Join-Path $WorkDir 'edge-profile'
  $edgeProcess = Start-Process -FilePath $edge -PassThru -ArgumentList @(
    "--remote-debugging-port=$DebugPort", "--user-data-dir=`"$profileDir`"", '--no-first-run', '--no-default-browser-check', '--lang=zh-CN', '--disable-features=Translate',
    "--app=$ZhipuLoginUrl", '--window-size=1100,800')
  try {
    # 页面刷新或跳转后调试连接会断，所以每次出错都重新找页面、重新连；只有窗口真的关了才算放弃
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
        } catch { }
        Start-Sleep -Milliseconds 500
      }
      return $null
    }
    $socket = & $connectToPage
    if (-not $socket) { return 'ERROR:登录窗口没有打开' }
    $nextId = 1
    $loginSince = Get-Date
    $deadline = (Get-Date).AddMinutes(15)
    $lastRefresh = Get-Date
    while ((Get-Date) -lt $deadline) {
      Wait-Tick 1.5 '等待扫码登录' $loginSince
      # 调试端口没了，说明用户把登录窗口关了
      try { Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/version" -TimeoutSec 2 | Out-Null } catch { return 'CANCELLED' }
      try { $state = Invoke-PageScript $socket ([ref]$nextId) $ReadStateScript }
      catch {
        $socket = & $connectToPage
        if (-not $socket) { return 'CANCELLED' }
        continue
      }
      if ($state -ne 'ready') {
        # 微信二维码几分钟就过期：没登录的话每 4 分钟自动刷新一次，用户不用自己点
        if (((Get-Date) - $lastRefresh).TotalMinutes -ge 4) {
          try { Invoke-PageScript $socket ([ref]$nextId) 'location.reload()' | Out-Null } catch { }
          $lastRefresh = Get-Date
        }
        continue
      }
      Start-Sleep -Seconds 2   # 等跳转到控制台页面稳定下来
      $result = Invoke-PageScript $socket ([ref]$nextId) $CreateKeyScript
      if ($result -like 'KEY:*') { return $result.Substring(4) }
      return $result
    }
    return 'TIMEOUT'
  } finally {
    if ($edgeProcess -and -not $edgeProcess.HasExited) { Stop-Process -Id $edgeProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}

# 自动创建失败时的退路：在用户默认浏览器里打开 Key 页面，用户点「新建」「复制」，脚本从剪贴板读
function Get-ZhipuKeyFromClipboard {
  Start-Process $ZhipuKeyPage
  Todo '已在浏览器打开智谱的 API Key 页面：'
  Todo '① 点「新建 API Key」，名字随便填，点「确定」'
  Todo '② 点「复制」，复制后这里会自动继续'
  Info '（会先清空剪贴板，用来识别你复制的 Key）'
  Set-Clipboard -Value ' '
  $since = Get-Date
  while (((Get-Date) - $since).TotalMinutes -lt 15) {
    $clip = ((Get-Clipboard -Raw) -replace '\s', '')
    if ($clip -match $ZhipuKeyPattern) { Set-Clipboard -Value ' '; Clear-Line; return $clip }
    Wait-Tick 1 '等待复制 API Key' $since
  }
  Clear-Line
  return $null
}

# 用这个 Key 依次试智谱免费模型，能用就返回模型名；不能用时最后的 HTTP 状态码放在 $Script:LastStatus
function Find-FreeModel($key) {
  foreach ($candidate in $FreeModels) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
      $job = Start-Job -ArgumentList $ZhipuBaseUrl, $key, $candidate -ScriptBlock {
        param($base, $k, $m)
        $body = @{ model = $m; input = 'Reply with exactly one word: pong'; max_output_tokens = 16 } | ConvertTo-Json -Compress
        # 智谱在 Key 无效时也回 HTTP 200，正文是 {"code":1000,"msg":"身份验证失败。","success":false}
        try { $resp = Invoke-RestMethod -Method Post -Uri "$base/responses" -Headers @{ Authorization = "Bearer $k" } -ContentType 'application/json' -Body $body -TimeoutSec 60; if ($resp.success -eq $false) { 401 } else { 200 } }
        catch { [int]$_.Exception.Response.StatusCode }
      }
      $since = Get-Date
      while ($job.State -eq 'Running') { Wait-Tick 0.3 "测试智谱免费模型 $candidate" $since }
      Clear-Line
      $Script:LastStatus = Receive-Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
      Remove-Job $job -Force -ErrorAction SilentlyContinue
      if ($Script:LastStatus -eq 200) { return $candidate }
      if ($Script:LastStatus -ne 429) { break }
      Start-Sleep -Seconds 3
    }
  }
  return $null
}

# ================= 开始 =================
$Steps = 3
try {
  Header 'CODEX INSTALLER' 'Codex 一键安装 · 国产模型版 · 不用科学上网 · 不花钱'

  # ---------- 准备：系统检测、线路测速，然后在后台开始下载 ----------
  Section '系统检测' ''
  $os = Get-CimInstance Win32_OperatingSystem
  Ok "$($os.Caption -replace 'Microsoft ', '') · $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM' } else { 'x64' })"
  $codexPackage = Get-CodexPackage
  $source = $null
  if ($codexPackage) {
    Ok '已经装过 Codex，这次不用下载'
  } else {
    $freeGb = [int]((Get-PSDrive ($env:LOCALAPPDATA.Substring(0, 1))).Free / 1GB)
    if ($freeGb -lt 4) { Fail "硬盘空间不够：装 Codex 需要约 4GB，现在只剩 ${freeGb}GB。清理一些文件后，重新运行这行命令。" }
    Ok "硬盘可用 $freeGb GB，够装 Codex"
    $source = Select-Source
    if ($source) { Start-Download $source.Url $source.Name $source.File }
  }

  # ---------- [1/3] 智谱账号（唯一需要用户动手的一步） ----------
  Say '登录智谱'
  $configPath = Join-Path $CodexHome 'config.toml'
  $authPath = Join-Path $CodexHome 'auth.json'
  $utf8NoBom = [Text.UTF8Encoding]::new($false)
  # 以前用这个脚本配好过、Key 还能用：不用再扫码，也不再新建 Key
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
        $ZhipuApiKey = $outcome
        Ok '已登录，自动创建好 API Key'
      } else {
        switch -Wildcard ($outcome) {
          'CANCELLED' { Info '登录窗口被关闭了，改用手动方式。' }
          'TIMEOUT'   { Info '等待登录超时，改用手动方式。' }
          default     { Info "自动创建没成功（$($outcome -replace '^ERROR:', '')），改用手动方式。" }
        }
        $ZhipuApiKey = Get-ZhipuKeyFromClipboard
        if (-not $ZhipuApiKey) { Fail '15 分钟内没有读到 API Key。' }
        Ok '已读到 API Key'
      }
    }
    if ($ZhipuApiKey -notmatch $ZhipuKeyPattern) { Fail 'API Key 格式不对。' }
    $Model = Find-FreeModel $ZhipuApiKey
    if (-not $Model) { Fail "智谱免费模型暂时不可用（HTTP $Script:LastStatus），请稍后重新运行这行命令。" }
  }
  Ok "智谱免费模型可以用：$Model"

  # ---------- [2/3] 安装 Codex ----------
  Say '安装 Codex'
  if ($codexPackage) {
    Ok "已经装过 Codex $($codexPackage.Version)，跳过"
  } else {
    $installed = $false
    if ($Script:Dl) {
      if (-not $Script:Dl.Done) {
        Info "下载 Codex（$($Script:Dl.Name)，约 $([int]($Script:Dl.Total / 1MB)) MB；中断后重新运行会接着下）"
        Show-DownloadProgress
      }
      if ($Script:Dl.Done) {
        Ok "下载完成（$(MB (Get-DownloadedBytes)) MB）"
        $installed = Install-FromMsix $Script:Dl.File
      } else { Info '镜像下载失败，改用微软商店' }
    }
    if (-not $installed) { Install-FromStore }
    $codexPackage = Get-CodexPackage
    if (-not $codexPackage) {
      Start-Process "ms-windows-store://pdp/?ProductId=$CodexStoreId" -ErrorAction SilentlyContinue
      Fail '没能自动安装 Codex。已为你打开微软商店的 Codex 页面：点「获取」装好后，重新运行这行命令。'
    }
    Ok "Codex $($codexPackage.Version) 已装好"
  }

  # ---------- [3/3] 写配置、试一句、打开 ----------
  # 只改 model、model_provider 和 [model_providers.zhipu]，其余配置原样保留；内容有变化时才备份原文件。UTF-8 不带 BOM。
  Say '配置并打开 Codex'
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
  $newConfig = (@("model_provider = `"zhipu`"", "model = `"$Model`"", '') + $keptLines + @(
    '', '[model_providers.zhipu]', 'name = "智谱 GLM"', "base_url = `"$ZhipuBaseUrl`"", 'wire_api = "responses"', 'requires_openai_auth = true') -join "`n") + "`n"
  $newAuth = "{`"OPENAI_API_KEY`":`"$ZhipuApiKey`"}`n"
  $backedUp = $false
  foreach ($pair in @(@($configPath, $newConfig), @($authPath, $newAuth))) {
    $path, $content = $pair
    if ((Test-Path $path) -and [IO.File]::ReadAllText($path, $utf8NoBom) -eq $content) { continue }
    if (Test-Path $path) { Copy-Item $path ($path + $backupSuffix); $backedUp = $true }
    [IO.File]::WriteAllText($path, $content, $utf8NoBom)
  }
  Ok "已写入 $($configPath -replace [regex]::Escape($env:USERPROFILE), '~')"
  if ($backedUp) { Info "原来的配置已备份为 *$backupSuffix" }

  $codexCli = Join-Path $codexPackage.InstallLocation 'app\resources\codex.exe'
  if (Test-Path $codexCli) {
    # 不关掉标准输入 codex 会一直等；用后台任务限时 120 秒
    $job = Start-Job -ArgumentList $codexCli, $CodexHome, $WorkDir -ScriptBlock {
      param($cli, $codexHomeDir, $dir)
      $env:CODEX_HOME = $codexHomeDir
      [Console]::OutputEncoding = [Text.UTF8Encoding]::new()   # codex 输出 UTF-8，不设的话中文回复会乱码
      Set-Location $dir
      cmd /c "`"$cli`" exec --ephemeral --skip-git-repo-check `"只回复两个字：好了`" < NUL 2>NUL"
    }
    $since = Get-Date
    while ($job.State -eq 'Running' -and ((Get-Date) - $since).TotalSeconds -lt 120) { Wait-Tick 0.3 '让 Codex 回一句话' $since }
    Clear-Line
    $reply = if ($job.State -ne 'Running') { Receive-Job $job | Select-Object -Last 1 } else { Stop-Job $job; $null }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($reply) { Ok "Codex 回复：$reply" } else { Info 'Codex 没有回复，打开后可以直接试用' }
  }
  if (-not $env:CODEX_SETUP_NO_OPEN) {
    $appId = (Get-AppxPackageManifest $codexPackage).Package.Applications.Application.Id | Select-Object -First 1
    Start-Process "shell:AppsFolder\$($codexPackage.PackageFamilyName)!$appId"
  }
  Finish "Codex 已经打开，用的是智谱免费模型 $Model"

  # ---------- 点亮 humanslive.ai/tools 上的这个工具 ----------
  # HL_TOKEN 来自安装页上复制的命令（网站签名，7 天有效）；没有就跳过，请求失败也不影响安装结果。
  if ($env:HL_TOKEN) {
    try { Invoke-RestMethod -TimeoutSec 6 -Method Post -ContentType 'application/json' -Body (@{ token = $env:HL_TOKEN } | ConvertTo-Json) 'https://humanslive.ai/api/tools/progress/claim' | Out-Null } catch { }
  }

  # ---------- 结尾：HumansLive 的其他免费工具和商城 ----------
  # 内容和排版来自网站（每行 kind<TAB>a<TAB>b），这里只按 kind 上色；拿不到就只打一行网址，不影响安装结果。
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
  if ("$_" -ne 'HL_FAIL') { throw }
} finally {
  # Ctrl+C 或出错退出时，连同后台下载一起停掉；已下载的部分留在缓存里，重新运行会接着下
  Stop-Download
  Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}
