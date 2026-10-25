# Codex Install Made Easy · Codex 一键安装

[中文](#中文) · [English](#english)

---

## 中文

让不懂电脑的普通中国人也能装好 [OpenAI Codex](https://developers.openai.com/codex/app) 桌面应用：**一行命令，扫一次码**，就能用上国产大模型。不用科学上网，不用自己找 API Key，不花钱。

### 怎么用

**Mac**
1. 按 ⌘+空格，输入"终端"，回车。
2. 粘贴下面这行，回车：
   ```bash
   curl -fsSL https://humanslive.ai/codex.sh | bash
   ```
3. 屏幕上弹出"登录智谱"的窗口后，用手机微信扫码（新用户扫码即注册）。

**Windows**（两种方式任选一种）
- **一行命令**：在开始菜单搜索"PowerShell"并打开，粘贴下面这行，回车，然后扫码：
  ```powershell
  irm https://humanslive.ai/codex.ps1 | iex
  ```
- **双击下载器**：运行 `CodexSetup.exe`。它没有代码签名，第一次打开会弹出「Windows 已保护你的电脑」，点「更多信息」→「仍要运行」，然后扫码。

扫码之后全部自动完成，最后 Codex 会自己打开，已经可以用了。二维码过期了也不用管，每 4 分钟会自动刷新。

### 仓库里有什么

| 文件 | 作用 |
|---|---|
| `codex.sh` | Mac 版一键安装（国产模型版） |
| `codex.ps1` | Windows 版一键安装（国产模型版） |
| `codex-official.sh` / `codex-official.ps1` | 官方版：先运行 OpenAI 的官方安装命令，成功后在 humanslive.ai/tools 点亮这一站 |
| `windows/CodexSetup.cs` + `build.bat` | Windows 双击下载器：下载并运行 `codex.ps1`，脚本更新后 exe 不用重发 |

两个平台的脚本用同一套界面：数字雨开场、标题从乱码解码出来、转圈、进度条、线路测速、结尾的「ALL SYSTEMS GO」。

本仓库是源码。网站上的 `public/codex*.sh`、`public/codex*.ps1` 是副本，改动后要同步过去。

### 它做了什么

1. **系统检测和线路测速**：已经装过 Codex 就跳过下载；没装的话先测速，然后在后台开始下载，用户扫码的同时在下，支持断点续传。
   - Mac：Apple 芯片同时测国内镜像和 OpenAI 官方源，国内镜像只要不比最快的慢 30% 以上就用它；Intel 芯片只有国内镜像。安装前确认是 OpenAI 官方签名（Team ID `2DC432GLL2`）。
   - Windows：测国内镜像，够快就从镜像下载官方安装包，核对包名、发布者和微软商店签名后，**不用管理员权限**解压到 `%LOCALAPPDATA%\Programs\Codex`，再核对主程序的 OpenAI 签名，建开始菜单和桌面快捷方式「Codex」。镜像太慢或核对没通过，就改从微软商店安装（商品 ID `9PLM9XGG6VKS`，这条要点一次管理员确认）。
2. **登录智谱**：用系统自带的浏览器内核开一个登录窗口（Mac 是 Safari 内核，Windows 是 Edge 的独立临时窗口，不碰你自己的浏览器数据）。
3. **自动创建 API Key**：你扫码登录后，脚本在这个窗口里调用智谱控制台自己的「新建 API Key」接口，和你手动点按钮走的是同一个接口。完整的 Key 只在创建时返回一次，脚本直接接住，不显示、不进剪贴板。
4. **测试模型**：先试智谱永久免费的 `glm-4.5-flash`，不可用就换 `glm-4.7-flash`。
5. **写配置**（拿到 Key 马上写，后面出错重跑不用再扫码）：只改 `config.toml` 里的 `model`、`model_provider` 和 `[model_providers.zhipu]`，其余原样保留；原文件先备份为 `*.bak-时间戳`。Key 写进 `auth.json`。配置目录在 Mac 上是 `~/.codex`，在 Windows 上是 `%USERPROFILE%\.codex`。
6. **验证并打开 Codex**：先让 Codex 回答一句话确认能用，再打开。

扫码窗口最多等 60 分钟，二维码会自动刷新；窗口被关掉或超时，重新运行这行命令就行。只有自动创建 Key 失败（比如智谱改版了）时，脚本才会打开智谱的 Key 页面，你点「新建」「复制」，脚本自动从剪贴板读取，读完立即清空剪贴板。

**日志**：每次运行都写一份日志，Mac 在 `~/Library/Logs/HumansLive/`，Windows 在 `%LOCALAPPDATA%\HumansLive\logs\`。出错时屏幕上会显示日志位置并自动打开所在文件夹，把这个文件发给我们就能查。日志里不写 Key。

### 须知

- 免费模型能力有限，适合简单任务。想用更强的模型，在[智谱开放平台](https://bigmodel.cn)充值后，把 `config.toml` 里的 `model` 改成付费模型即可。
- 「新建 API Key」用的是智谱控制台的内部接口，不是公开 API，智谱改版后可能失效，失效时会自动改用手动方式。
- Windows 上的 Codex（实测 26.1021.3705.0）自带一个系统服务（`CodexSandboxService`），正常安装（双击、微软商店）都要管理员确认。所以脚本默认解压到用户目录、不装这个服务。代价：不会自动更新（重新运行这行命令会装最新版）；Codex 执行命令时用不需要管理员的沙箱模式。卸载：删掉 `%LOCALAPPDATA%\Programs\Codex` 和两个快捷方式。
- Codex 的窗口标题叫「ChatGPT」（OpenAI 把 Codex 并进了 ChatGPT 桌面版），就是它。
- 本项目与 OpenAI、智谱均无关联。

### 编译 Windows 下载器

在 Windows 上运行 `windows\build.bat`，会用系统自带的 .NET Framework 编译器生成 `windows\CodexSetup.exe`，不需要安装 Visual Studio。

### 许可

私有项目，未开源。

---

## English

Get the [OpenAI Codex](https://developers.openai.com/codex/app) desktop app running for anyone in China, even people who barely use a computer: **one command, one QR scan**, and Codex is working with a Chinese model. No VPN, no hunting for API keys, no cost.

### Usage

**Mac**
1. Press ⌘+Space, type "Terminal", press Return.
2. Paste this line and press Return:
   ```bash
   curl -fsSL https://humanslive.ai/codex.sh | bash
   ```
3. When the Zhipu login window appears, scan its QR code with WeChat on your phone (scanning also registers new users).

**Windows** (either way works)
- **One command**: search the Start menu for "PowerShell", open it, paste this line, press Enter, then scan:
  ```powershell
  irm https://humanslive.ai/codex.ps1 | iex
  ```
- **Double-click installer**: run `CodexSetup.exe`. It is not code-signed, so the first launch shows "Windows protected your PC"; click "More info" → "Run anyway", then scan.

After the scan everything is automatic, and Codex opens ready to use. If the QR code expires, ignore it: it refreshes every 4 minutes.

### What's in this repo

| File | Purpose |
|---|---|
| `codex.sh` | One-command installer for Mac (Chinese-model edition) |
| `codex.ps1` | One-command installer for Windows (Chinese-model edition) |
| `codex-official.sh` / `codex-official.ps1` | Official edition: runs OpenAI's own install command, then lights this stop on humanslive.ai/tools |
| `windows/CodexSetup.cs` + `build.bat` | Double-click installer for Windows: downloads and runs `codex.ps1`, so the exe needs no reissue when the script changes |

Both platforms share one terminal UI: a digital-rain intro, a title that decodes out of noise, spinners, progress bars, the download-source race and a closing "ALL SYSTEMS GO".

This repo is the source. The `public/codex*.sh` and `public/codex*.ps1` files on the website are copies; sync them after every change.

### What it does

1. **Checks the system and races download sources**: skips the download if Codex is already installed; otherwise measures the sources and starts downloading in the background while you scan, resuming interrupted downloads.
   - Mac: on Apple silicon, races the China mirror against OpenAI's official source and uses the mirror unless it is more than 30% slower than the fastest; Intel Macs use the mirror. Installs only after confirming OpenAI's signature (Team ID `2DC432GLL2`).
   - Windows: measures the China mirror; if it is fast enough, downloads the official package from it, checks the package name, publisher and Microsoft Store signature, then unpacks it **without administrator rights** into `%LOCALAPPDATA%\Programs\Codex`, checks OpenAI's signature on the main program, and adds "Codex" shortcuts to the Start menu and desktop. If the mirror is too slow or a check fails, installs from the Microsoft Store (product ID `9PLM9XGG6VKS`; this route needs one administrator confirmation).
2. **Opens a Zhipu login window** using the browser engine built into the system: Safari's engine on Mac, and a separate temporary Edge window on Windows that never touches your own browser data.
3. **Creates an API key automatically**: after you log in, the script calls the Zhipu console's own "create API key" endpoint inside that window, the same request the button sends. The full key is returned only once, at creation; the script takes it directly, never showing it or putting it on the clipboard.
4. **Tests a model**: tries Zhipu's permanently free `glm-4.5-flash`, then `glm-4.7-flash`.
5. **Writes the config** (as soon as the key exists, so a rerun after a later failure needs no new scan): changes only `model`, `model_provider` and `[model_providers.zhipu]` in `config.toml`, keeps everything else, and backs up the original as `*.bak-<timestamp>`. The key goes into `auth.json`. The config directory is `~/.codex` on Mac and `%USERPROFILE%\.codex` on Windows.
6. **Verifies and opens Codex**: asks Codex for a one-line reply to confirm it works, then opens it.

The login window waits up to 60 minutes and refreshes the QR code by itself; if it is closed or times out, just run the command again. Only when automatic key creation fails (for example after a Zhipu redesign) does the script open Zhipu's key page: click "Create" and "Copy", and the script reads the key from the clipboard, then clears the clipboard.

**Logs**: every run writes a log, under `~/Library/Logs/HumansLive/` on Mac and `%LOCALAPPDATA%\HumansLive\logs\` on Windows. On failure the screen shows where it is and opens its folder; send us that file and we can debug. Keys are never logged.

### Notes

- The free models are limited and suit simple tasks. For stronger models, top up on the [Zhipu platform](https://bigmodel.cn) and set `model` in `config.toml` to a paid model.
- Key creation uses an internal Zhipu console endpoint, not a public API. It may break after a Zhipu redesign, in which case the script falls back to the manual steps.
- Codex for Windows (verified on 26.1021.3705.0) ships a system service (`CodexSandboxService`), so every normal install (double-click, Microsoft Store) asks for administrator confirmation. The script therefore unpacks it into the user's folder by default, without the service. Trade-offs: no automatic updates (rerun the command to get the latest version), and Codex runs commands in its non-administrator sandbox mode. To uninstall, delete `%LOCALAPPDATA%\Programs\Codex` and the two shortcuts.
- The Codex window is titled "ChatGPT" (OpenAI merged Codex into the ChatGPT desktop app); that is it.
- This project is not affiliated with OpenAI or Zhipu.

### Building the Windows installer

On Windows, run `windows\build.bat`. It builds `windows\CodexSetup.exe` with the .NET Framework compiler that ships with Windows; no Visual Studio needed.

### License

Private project; not open source.
