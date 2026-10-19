@echo off
rem Build CodexSetup.exe with the .NET Framework 4 compiler that ships with Windows (no Visual Studio needed).
setlocal
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
"%CSC%" /nologo /target:exe /codepage:65001 /out:"%~dp0CodexSetup.exe" "%~dp0CodexSetup.cs"
if errorlevel 1 (echo Build failed & exit /b 1)
echo Built %~dp0CodexSetup.exe
