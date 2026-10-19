// CodexSetup.exe：双击即可运行的 Windows 安装器。它只是一层外壳：用系统自带的 PowerShell
// 下载并执行 https://agentv1.com/codex.ps1（和「一行命令」安装的是同一个脚本），所以脚本更新后 exe 不用重发。
// 没有代码签名：首次运行会弹出「Windows 已保护你的电脑」，点「更多信息」→「仍要运行」。
// 编译：在 Windows 上运行同目录的 build.bat（用系统自带的 .NET Framework 编译器，不需要安装任何东西）。
using System;
using System.Diagnostics;
using System.Text;

internal static class CodexSetup
{
    private const string ScriptUrl = "https://agentv1.com/codex.ps1";

    private static int Main()
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.Title = "Codex 一键安装";
        Console.WriteLine("Codex 一键安装：会安装官方 Codex，并帮你接上智谱免费模型。");
        Console.WriteLine("过程中会弹出智谱登录窗口，用手机微信扫码即可。");

        // 强制 TLS 1.2：老版本 Windows 的 PowerShell 默认可能连不上 https
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
        Console.WriteLine(exitCode == 0 ? "安装结束。" : "安装没有完成，请把上面的文字截图发给客服。");
        Console.WriteLine("按回车键关闭这个窗口。");
        Console.ReadLine();
        return exitCode;
    }
}
