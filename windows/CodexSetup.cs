// CodexSetup.exe: a double-click Windows installer. It is only a thin shell: it uses the built-in PowerShell
// to download and run https://humanslive.ai/codex.ps1 (the same script as the one-line install), so the exe never
// needs reissuing when the script changes.
// It is not code-signed: on first run SmartScreen shows "Windows protected your PC"; click More info -> Run anyway.
// Build: run build.bat in this folder on Windows (uses the built-in .NET Framework compiler; nothing to install).
using System;
using System.Diagnostics;
using System.Text;

internal static class CodexSetup
{
    private const string ScriptUrl = "https://humanslive.ai/codex.ps1";

    private static int Main()
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.Title = "Codex 一键安装";
        Console.WriteLine("Codex 一键安装：会安装官方 Codex，并帮你接上智谱免费模型。");
        Console.WriteLine("过程中会弹出智谱登录窗口，用手机微信扫码即可。");

        // Force TLS 1.2: PowerShell on older Windows may otherwise fail to connect over HTTPS
        string command =
            "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " +
            "irm " + ScriptUrl + " | iex";
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -Command \"" + command + "\"",
            UseShellExecute = false,
        };

        int exitCode;
        try
        {
            using (Process powershell = Process.Start(startInfo))
            {
                powershell.WaitForExit();
                exitCode = powershell.ExitCode;
            }
        }
        catch (Exception error)
        {
            Console.WriteLine("没能启动 PowerShell：" + error.Message);
            exitCode = 1;
        }

        Console.WriteLine();
        Console.WriteLine(exitCode == 0 ? "安装结束。" : "安装没有完成。需要帮助：把上面的文字截图发到社群 https://humanslive.ai/community");
        Console.WriteLine("按回车键关闭这个窗口。");
        Console.ReadLine();
        return exitCode;
    }
}
