# Upgrade/downgrade regression test of the Chinese launcher, run inside the logged-in user's desktop session
# (run.sh starts it through an interactive scheduled task). It installs the Codex App packages itself, so run it only
# on a test PC.
#
#   -Old / -New   x64 .msix files of two Codex App versions (Old may equal New to only test the harness)
#   -Installer    the codex.ps1 under test
#   -Out          folder for result.json, screenshots and launcher logs
param([Parameter(Mandatory)][string]$Old, [Parameter(Mandatory)][string]$New, [Parameter(Mandatory)][string]$Installer,
  [Parameter(Mandatory)][string]$Out)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
Add-Type -Namespace HlTest -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(int flags, int x, int y, int data, int extra);
'@
[void][HlTest.Native]::SetProcessDPIAware()

$family = 'OpenAI.Codex_2p2nqsd0c76g0'
$appUserModelId = "$family!App"
$hlDir = Join-Path $env:LOCALAPPDATA 'HumansLive'
$launcherLog = Join-Path $hlDir 'codex-zh.log'
$shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ChatGPT 汉化版.lnk'
New-Item -ItemType Directory -Force $Out | Out-Null
$results = [Collections.Generic.List[object]]::new()
$progressFile = Join-Path $Out 'progress.txt'
function Note($text) { Add-Content -LiteralPath $progressFile -Value "$(Get-Date -Format HH:mm:ss)  $text" -Encoding UTF8 }

function Package-Version { "$((Get-AppxPackage -Name OpenAI.Codex).Version)" }
function Msix-Version($path) { if ((Split-Path $path -Leaf) -match '_(\d+\.\d+\.\d+\.\d+)_') { $Matches[1] } else { throw "no version in $path" } }
function Codex-Main { Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" | Where-Object { $_.CommandLine -notmatch '--type=' } }
function Launchers { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*codex-zh.ps1*' } }
function Stop-Codex {
  Launchers | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Get-Process ChatGPT -ErrorAction SilentlyContinue | Stop-Process -Force
  for ($i = 0; $i -lt 20 -and (Get-Process ChatGPT -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
}
# What the Store does on an update: shut Codex down and swap the package (-ForceUpdateFromAnyVersion also allows going back)
function Install-Package($msix) {
  # The same version twice (a harness run) is a no-op for Add-AppxPackage, which then leaves Codex running
  if ((Package-Version) -eq (Msix-Version $msix)) { Stop-Codex }
  Add-AppxPackage -Path $msix -ForceUpdateFromAnyVersion -ForceApplicationShutdown
  $want = Msix-Version $msix
  if ((Package-Version) -ne $want) { throw "installed $(Package-Version), expected $want" }
}
function Open-Plain { Start-Process "shell:AppsFolder\$appUserModelId" }
# A double click: the shell opens the .lnk itself (re-running its target and arguments by hand quotes them differently)
function Open-Shortcut {
  Remove-Item -LiteralPath $launcherLog -ErrorAction SilentlyContinue
  Start-Process -FilePath $shortcut
}
function Wait-Until([scriptblock]$condition, [int]$seconds) {
  for ($i = 0; $i -lt $seconds * 2; $i++) { $value = & $condition; if ($value) { return $value }; Start-Sleep -Milliseconds 500 }
  $null
}
function Window-Open { Wait-Until { Get-Process ChatGPT -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } } 60 }
function Log-Has($pattern, [int]$seconds) { Wait-Until { Select-String -LiteralPath $launcherLog -Pattern $pattern -ErrorAction SilentlyContinue } $seconds }

# Reads the page text over the DevTools port the launcher opened
function Page-Text {
  $port = (Select-String -LiteralPath $launcherLog -Pattern 'port=(\d+)' -ErrorAction SilentlyContinue | Select-Object -Last 1).Matches[0].Groups[1].Value
  if (-not $port) { return '' }
  $page = Invoke-RestMethod "http://127.0.0.1:$port/json" | Where-Object { $_.type -eq 'page' -and $_.url -like 'app://*' } | Select-Object -First 1
  $socket = [Net.WebSockets.ClientWebSocket]::new()
  $socket.ConnectAsync([Uri]$page.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
  $request = '{"id":1,"method":"Runtime.evaluate","params":{"expression":"document.body.innerText","returnByValue":true}}'
  $socket.SendAsync([ArraySegment[byte]][Text.Encoding]::UTF8.GetBytes($request), 'Text', $true, [Threading.CancellationToken]::None).Wait()
  $buffer = New-Object byte[] 1048576; $stream = New-Object IO.MemoryStream
  do {
    $received = $socket.ReceiveAsync([ArraySegment[byte]]$buffer, [Threading.CancellationToken]::None).Result
    $stream.Write($buffer, 0, $received.Count)
  } until ($received.EndOfMessage)
  $socket.Dispose()
  ([Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json).result.result.value
}
function Is-Chinese { Wait-Until { $text = try { Page-Text } catch { '' }; if ($text -match '新聊天' -and $text -notmatch 'New chat') { $true } } 60 }

function Find-Dialog([int]$seconds) {
  $name = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, 'ChatGPT 汉化版')
  Wait-Until { [Windows.Automation.AutomationElement]::RootElement.FindFirst('Children', $name) } $seconds
}
# Clicks one of the dialog's two buttons with the real mouse: 0 = 重启成中文, 1 = 先不用
function Click-Dialog($dialog, [int]$button) {
  $pane = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Pane)
  $buttons = @($dialog.FindAll('Descendants', $pane) | Sort-Object { $_.Current.BoundingRectangle.X })
  $r = $buttons[$button].Current.BoundingRectangle
  [void][HlTest.Native]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)); Start-Sleep -Milliseconds 300
  [HlTest.Native]::mouse_event(2, 0, 0, 0, 0); [HlTest.Native]::mouse_event(4, 0, 0, 0, 0)
}
function Shot($name) {
  $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object Drawing.Bitmap $b.Width, $b.Height
  [Drawing.Graphics]::FromImage($bitmap).CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
  $bitmap.Save((Join-Path $Out "$name.png")); $bitmap.Dispose()
}

# Each step: a name, what it checks, and a block that throws on failure. A failed step is recorded and the rest still run
function Step($name, [scriptblock]$body) {
  Note "start $name"
  $started = Get-Date
  try { & $body; $status = 'pass'; $detail = '' } catch { $status = 'fail'; $detail = $_.Exception.Message }
  try { Shot $name } catch {}
  if (Test-Path -LiteralPath $launcherLog) { Copy-Item -LiteralPath $launcherLog (Join-Path $Out "$name.launcher.log") }
  $results.Add([pscustomobject]@{ step = $name; status = $status; detail = $detail; version = (Package-Version); seconds = [int]((Get-Date) - $started).TotalSeconds })
  Note "$status $name $detail"
}
function Expect($condition, $message) { if (-not $condition) { throw $message } }
function Expect-Chinese-From-Shortcut {
  Open-Shortcut
  Expect (Log-Has 'codex ui is up' 150) 'launcher never reported the UI up'
  Expect (Is-Chinese) 'the page is not in Chinese'
}
function Expect-Dialog-Restart {
  Open-Shortcut
  $dialog = Find-Dialog 30; Expect $dialog 'the restart dialog did not show up'
  Click-Dialog $dialog 0
  Expect (Log-Has 'restarting it in chinese' 15) 'restart was not taken'
  Expect (Log-Has 'codex ui is up' 150) 'launcher never reported the UI up after restarting'
  Expect (Is-Chinese) 'the page is not in Chinese after restarting'
}

$oldVersion = Msix-Version $Old; $newVersion = Msix-Version $New
Note "old=$oldVersion new=$newVersion"

Step 'install-old' { Stop-Codex; Install-Package $Old }
Step 'run-installer' {
  $env:CODEX_SETUP_EDITION = 'zh'; $env:CODEX_SETUP_NO_OPEN = '1'
  $transcript = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([IO.File]::ReadAllText('$($Installer -replace "'", "''")', [Text.Encoding]::UTF8))" 2>&1 | Out-String
  [IO.File]::WriteAllText((Join-Path $Out 'installer.txt'), $transcript, [Text.Encoding]::UTF8)
  Expect ($transcript -match 'ALL SYSTEMS GO') 'installer did not finish'
  Expect (Test-Path -LiteralPath $shortcut) 'no desktop shortcut'
  $link = (New-Object -ComObject Shell.Application).Namespace((Split-Path $shortcut)).ParseName((Split-Path $shortcut -Leaf)).GetLink
  Expect ($link.Path -match 'conhost\.exe$') "shortcut target is $($link.Path), not a headless conhost"
}
Step 'old-shortcut-chinese' {
  Stop-Codex
  $terminals = @(Get-Process WindowsTerminal, OpenConsole -ErrorAction SilentlyContinue | ForEach-Object Id)
  Expect-Chinese-From-Shortcut
  # The launcher stays alive next to Codex; it must not sit in the taskbar as a Windows Terminal window
  $opened = @(Get-Process WindowsTerminal, OpenConsole -ErrorAction SilentlyContinue | Where-Object { $terminals -notcontains $_.Id })
  Expect (-not $opened) "the shortcut opened a console window: $(($opened | ForEach-Object ProcessName) -join ', ')"
}
# The user's case: Chinese Codex open, the update lands, Codex restarts itself in English
Step 'upgrade-while-chinese-open' {
  Install-Package $New
  Expect (-not (Codex-Main)) 'codex still running after the package swap'
  Expect (Wait-Until { -not (Launchers) } 30) 'launcher did not exit after codex closed'
  Open-Plain
  Expect (Window-Open) 'codex window did not open after the upgrade'
}
Step 'new-dialog-restart-chinese' { Expect-Dialog-Restart }
Step 'new-dialog-not-now' {
  Stop-Codex; Open-Plain; Expect (Window-Open) 'codex window did not open'
  Open-Shortcut
  $dialog = Find-Dialog 30; Expect $dialog 'the restart dialog did not show up'
  Click-Dialog $dialog 1
  Expect (Log-Has 'kept as is' 15) 'not now was not taken'
  Expect (Wait-Until { -not (Launchers) } 15) 'launcher did not exit'
  Expect (Codex-Main) 'codex was closed'
}
Step 'new-shortcut-chinese-from-closed' { Stop-Codex; Expect-Chinese-From-Shortcut }
Step 'downgrade-while-chinese-open' {
  Install-Package $Old
  Expect (Wait-Until { -not (Launchers) } 30) 'launcher did not exit after codex closed'
  Expect-Chinese-From-Shortcut
}
Step 'upgrade-while-closed' { Stop-Codex; Install-Package $New; Expect-Chinese-From-Shortcut }
Stop-Codex

$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Out 'result.json') -Encoding UTF8
Note "done"
