# Starts test-upgrade.ps1 inside the logged-in user's desktop session (an SSH session has no desktop) and returns.
# run.sh calls this over SSH, then polls $Out for result.json.
param([Parameter(Mandatory)][string]$Old, [Parameter(Mandatory)][string]$New, [Parameter(Mandatory)][string]$Out)
$ErrorActionPreference = 'Stop'
if (-not (quser 2>$null | Select-String "^\s*>?$env:USERNAME\s.*\sActive\s")) { throw "$env:USERNAME is not logged in to the desktop: log in on the PC (or over Remote Desktop) first" }
$test = Join-Path $PSScriptRoot 'test-upgrade.ps1'
$installer = Join-Path $PSScriptRoot 'codex.ps1'
# conhost --headless: no console window pops up on the desktop under test
$arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$test`" -Old `"$Old`" -New `"$New`" -Installer `"$installer`" -Out `"$Out`""
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
Register-ScheduledTask -TaskName 'HumansLive upgrade test' -Action (New-ScheduledTaskAction -Execute conhost.exe -Argument $arguments) -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName 'HumansLive upgrade test'
