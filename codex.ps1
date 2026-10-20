# Codex 一键安装（Windows）：装好官方 Codex App，用微信扫码登录智谱后自动创建 API Key，接上智谱免费模型。
# 用法（PowerShell）：irm https://agentv1.com/codex.ps1 | iex
# 只做这几件事：从微软商店安装官方 Codex、打开智谱登录窗口、新建一个 API Key、写 %USERPROFILE%\.codex 下的配置、打开 Codex。
# 兼容 Windows 自带的 PowerShell 5.1；不需要管理员权限。

$ErrorActionPreference = 'Continue'   # codex.exe 会往 stderr 写警告，Stop 会把它当成错误中断
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$ProgressPreference = 'SilentlyContinue'

$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$CodexStoreId = '9PLM9XGG6VKS'
$CodexPackageName = 'OpenAI.Codex'
$ZhipuBaseUrl = 'https://open.bigmodel.cn/api/v1'
$ZhipuLoginUrl = 'https://bigmodel.cn/login?redirect=%2Fapikey%2Fplatform'
$ZhipuKeyPage = 'https://bigmodel.cn/usercenter/proj-mgmt/apikeys'
$ZhipuKeyPattern = '^[0-9a-f]{32}\.[A-Za-z0-9]{16}$'
$FreeModels = @('glm-4.5-flash', 'glm-4.7-flash')
$DebugPort = 9333
$WorkDir = Join-Path $env:TEMP ('codex-setup-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $WorkDir | Out-Null

function Say($text)  { Write-Host ''; Write-Host $text -ForegroundColor White }
function Info($text) { Write-Host "  $text" }
function Fail($text) {
  Write-Host ''; Write-Host "出错了：$text" -ForegroundColor Red
  Write-Host '如需帮助，把上面的文字截图发给客服。'
  Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
  throw $text
}

# ---------- 第 1 步：安装 Codex App ----------
function Get-CodexPackage { Get-AppxPackage -Name $CodexPackageName -ErrorAction SilentlyContinue | Select-Object -First 1 }

function Install-CodexFromMirror {
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
  $msix = Join-Path $WorkDir 'Codex.msix'
  Info '微软商店不可用，改从国内镜像下载官方安装包……'
  & curl.exe -fL -C - --retry 5 --connect-timeout 15 -# -o $msix "https://codexapp.agentsmirror.com/latest/$arch"
  if ($LASTEXITCODE -ne 0) { return $false }
  # Add-AppxPackage 自己会校验安装包签名，签名不对装不上
  Add-AppxPackage -Path $msix -ErrorAction SilentlyContinue
  return [bool](Get-CodexPackage)
}

Say '第 1 步：安装 Codex'
$codexPackage = Get-CodexPackage
if ($codexPackage) {
  Info "已安装：$($codexPackage.Version)，跳过"
} else {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Info '正在从微软商店安装（会自动同意商店条款）……'
    winget install --id $CodexStoreId --source msstore --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
  }
  $codexPackage = Get-CodexPackage
  if (-not $codexPackage -and -not (Install-CodexFromMirror)) { Fail 'Codex 安装失败，请检查网络后重试。' }
  $codexPackage = Get-CodexPackage
  Info "安装完成：$($codexPackage.Version)"
}

# ---------- 第 2 步：智谱 API Key ----------
# 用 Windows 自带的 Edge 开一个独立的小窗口（单独的临时资料目录，不碰用户自己的浏览器数据），
# 用户扫码登录后，在页面里调用控制台自己的「新建 API Key」接口。完整 Key 只在创建时返回一次，直接交给本脚本。
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
    $deadline = (Get-Date).AddMinutes(15)
    $lastRefresh = Get-Date
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Seconds 2
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
  Info '已在浏览器打开智谱的 API Key 页面：'
  Info '  ① 点「新建 API Key」，名字随便填，点「确定」'
  Info '  ② 点「复制」，复制后这里会自动继续'
  Set-Clipboard -Value ' '
  for ($i = 0; $i -lt 900; $i++) {
    $clip = ((Get-Clipboard -Raw) -replace '\s', '')
    if ($clip -match $ZhipuKeyPattern) { Set-Clipboard -Value ' '; return $clip }
    Start-Sleep -Seconds 1
  }
  return $null
}

Say '第 2 步：登录智谱，自动创建 API Key'
if ($env:CODEX_SETUP_ZHIPU_KEY) {
  $ZhipuApiKey = $env:CODEX_SETUP_ZHIPU_KEY
  Info '使用环境变量里提供的 Key'
} else {
  Info '马上会弹出智谱登录窗口，用手机微信扫码即可（新用户扫码就是注册）。'
  $outcome = Get-ZhipuKeyAutomatically
  if ($outcome -match $ZhipuKeyPattern) {
    $ZhipuApiKey = $outcome
    Info '已自动创建 API Key'
  } else {
    switch -Wildcard ($outcome) {
      'CANCELLED' { Info '登录窗口被关闭了，改用手动方式。' }
      'TIMEOUT'   { Info '等待登录超时，改用手动方式。' }
      default     { Info "自动创建没成功（$($outcome -replace '^ERROR:', '')），改用手动方式。" }
    }
    $ZhipuApiKey = Get-ZhipuKeyFromClipboard
    if (-not $ZhipuApiKey) { Fail '15 分钟内没有读到 API Key。' }
    Info '已读到 API Key'
  }
}
if ($ZhipuApiKey -notmatch $ZhipuKeyPattern) { Fail 'API Key 格式不对。' }

# ---------- 第 3 步：确认免费模型可用 ----------
Say '第 3 步：测试智谱免费模型'
$Model = $null
$lastStatus = 0
foreach ($candidate in $FreeModels) {
  for ($attempt = 0; $attempt -lt 3; $attempt++) {
    $body = @{ model = $candidate; input = 'Reply with exactly one word: pong'; max_output_tokens = 16 } | ConvertTo-Json -Compress
    try {
      Invoke-RestMethod -Method Post -Uri "$ZhipuBaseUrl/responses" -Headers @{ Authorization = "Bearer $ZhipuApiKey" } `
        -ContentType 'application/json' -Body $body -TimeoutSec 60 | Out-Null
      $Model = $candidate; break
    } catch {
      $lastStatus = [int]$_.Exception.Response.StatusCode
      if ($lastStatus -ne 429) { break }
      Start-Sleep -Seconds 3
    }
  }
  if ($Model) { break }
}
if (-not $Model) { Fail "智谱免费模型暂时不可用（HTTP $lastStatus），请稍后重新运行。" }
Info "可用：$Model"

# ---------- 第 4 步：写 Codex 配置 ----------
# 只改 model、model_provider 和 [model_providers.zhipu]，其余配置原样保留；原文件先备份。UTF-8 不带 BOM。
Say '第 4 步：写入 Codex 配置'
New-Item -ItemType Directory -Force $CodexHome | Out-Null
$configPath = Join-Path $CodexHome 'config.toml'
$authPath = Join-Path $CodexHome 'auth.json'
$backupSuffix = '.bak-' + (Get-Date -Format 'yyyyMMddHHmmss')
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$backedUp = $false
$keptLines = @()
if (Test-Path $configPath) {
  Copy-Item $configPath ($configPath + $backupSuffix); $backedUp = $true
  $inTable = $false; $skipTable = $false
  foreach ($line in [IO.File]::ReadAllLines($configPath, $utf8NoBom)) {
    if ($line -match '^\[') { $inTable = $true; $skipTable = ($line.Trim() -eq '[model_providers.zhipu]') }
    if (-not $inTable -and $line -match '^\s*(model|model_provider)\s*=') { continue }
    if (-not $skipTable) { $keptLines += $line }
  }
}
if (Test-Path $authPath) { Copy-Item $authPath ($authPath + $backupSuffix); $backedUp = $true }
$newConfig = @("model_provider = `"zhipu`"", "model = `"$Model`"", '') + $keptLines + @(
  '', '[model_providers.zhipu]', 'name = "智谱 GLM"', "base_url = `"$ZhipuBaseUrl`"", 'wire_api = "responses"', 'requires_openai_auth = true')
[IO.File]::WriteAllText($configPath, (($newConfig -join "`n") + "`n"), $utf8NoBom)
[IO.File]::WriteAllText($authPath, "{`"OPENAI_API_KEY`":`"$ZhipuApiKey`"}`n", $utf8NoBom)
$backupNote = if ($backedUp) { "（原文件备份为 *$backupSuffix）" } else { '' }
Info "已写入 $configPath$backupNote"

# ---------- 第 5 步：验证并打开 Codex ----------
Say '第 5 步：验证 Codex'
$codexPackage = Get-CodexPackage
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
  $reply = if (Wait-Job $job -Timeout 120) { Receive-Job $job | Select-Object -Last 1 } else { Stop-Job $job; $null }
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  if ($reply) { Info "Codex 回复：$reply" } else { Info 'Codex 回复：（没有回复，打开后可直接试用）' }
}
if (-not $env:CODEX_SETUP_NO_OPEN) {
  $appId = (Get-AppxPackageManifest $codexPackage).Package.Applications.Application.Id | Select-Object -First 1
  Start-Process "shell:AppsFolder\$($codexPackage.PackageFamilyName)!$appId"
}
Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
Say "完成！Codex 已经打开，用的是智谱免费模型 $Model。"
