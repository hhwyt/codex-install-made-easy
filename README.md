<div align="center">

# Codex Install Made Easy

**一行命令，扫一次码，Codex 就能用。**

为中国用户打造的 [OpenAI Codex](https://developers.openai.com/codex/app) 桌面应用一键安装器：<br>
国内网络直连、自动接入智谱免费大模型、全程零配置。

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-lightgrey)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

[中文](#中文) · [English](#english)

</div>

---

## 中文

### 快速开始

**Mac**：按 ⌘+空格，输入「终端」并回车，粘贴下面这行：

```bash
curl -fsSL https://humanslive.ai/codex.sh | bash
```

**Windows**：在开始菜单搜索「PowerShell」并打开，粘贴下面这行：

```powershell
irm https://humanslive.ai/codex.ps1 | iex
```

弹出「登录智谱」窗口后，用手机微信扫码（新用户扫码即注册）。剩下的全部自动完成，最后 Codex 会自己打开，可以直接用。

> 不想用命令行的 Windows 用户，也可以运行双击安装器 `CodexSetup.exe`（见[编译 Windows 安装器](#编译-windows-安装器)）。它没有代码签名，第一次打开时点「更多信息」→「仍要运行」。

### 亮点

- **一次登录，其余全自动**：整个过程只有扫码这一步需要你动手（Windows 还要点一次系统确认框）。下载、校验、安装、创建 API Key、写配置、验证，全部自动完成。
- **国内网络直连**：自动测速，选国内镜像还是官方源；扫码的同时在后台下载，断点续传。
- **只装官方原版**：Mac 校验 OpenAI 的代码签名（Team ID `2DC432GLL2`）；Windows 校验包名、发布者和微软商店签名，不通过就改从微软商店安装。
- **免费模型开箱即用**：自动在你自己的智谱账号下创建 API Key，接入智谱免费模型 `glm-4.7-flash`。
- **零依赖**：只用系统自带的工具（Mac 用 bash、perl、WebKit，Windows 用 PowerShell 5.1、curl.exe、Edge），不用另外装任何东西。
- **尊重你的电脑**：只改必须改的配置项，改之前先备份；重复运行是安全的，配好过就不会再让你扫码。
- **出错讲人话**：每一步都写日志，出错时屏幕上说清楚怎么办，并直接打开日志所在的文件夹。

### 工作原理

1. **系统检测与线路测速**：已经装过 Codex 就跳过下载。没装的话，测 8 秒各条下载线路的速度，然后在后台开始下载。
   - Mac：Apple 芯片同时测国内镜像和 OpenAI 官方源，国内镜像只要不比最快的那条慢 30% 以上就用它；Intel 芯片只走国内镜像。
   - Windows：开头弹一次系统确认框（「你要允许此应用对你的设备进行更改吗？」，点「是」），只用来安装 Codex。国内镜像够快就从镜像下载官方安装包，否则改从微软商店安装（商品 ID `9PLM9XGG6VKS`）。装完一律再查一次是否真的装上，因为 winget 没装上也会报成功。
2. **登录智谱**：用系统自带的浏览器内核开一个独立的登录窗口：Mac 用 WebKit，Windows 用临时配置的 Edge，不会碰你自己的浏览器数据。二维码每 4 分钟自动刷新，最多等 60 分钟。
3. **创建 API Key**：登录后，脚本在这个窗口里调用智谱控制台自己的「新建 API Key」接口，和你手动点按钮发的是同一个请求。完整的 Key 只在创建时返回一次，脚本直接接住，不显示、不进剪贴板。
4. **测试模型**：先试 `glm-4.7-flash`，不行再试 `glm-4.5-flash`。
5. **写配置**：一拿到 Key 就写配置，这样后面哪一步出错，重新运行也不用再扫码。`config.toml` 里只改 `model`、`model_provider` 和 `[model_providers.zhipu]`，其余原样保留；内容有变化时，先把原文件备份成 `*.bak-时间戳`。Key 写进 `auth.json`，权限只有你自己能读。
6. **验证并打开**：先让 Codex 回一句话，确认能用，再把它打开。

### 安全与隐私

- **Key 只在你自己的电脑上**：Key 是用你自己的智谱账号创建的，只保存在本机的 `~/.codex/auth.json`（Windows 是 `%USERPROFILE%\.codex\auth.json`），不经过我们的服务器，也不写进日志。随时可以在智谱控制台删掉，名字以 `Codex-` 开头。
- **只装官方原版**：安装包的签名核对不通过就删掉，不会安装。
- **不读剪贴板**：没有「手动复制 Key」这一步。读剪贴板会被 Windows Defender 当成盗号脚本拦截，用户也不该多做一步。
- **先看再运行**：脚本都在本仓库里，网站上发的就是这几份文件。不放心的话，可以先下载下来看一遍，再运行：

  ```bash
  curl -fsSL https://humanslive.ai/codex.sh -o codex.sh && less codex.sh && bash codex.sh
  ```

### 日志

每次运行都写一份日志：Mac 在 `~/Library/Logs/HumansLive/`，Windows 在 `%LOCALAPPDATA%\HumansLive\logs\`。出错时，屏幕上会显示日志位置并打开所在文件夹，把这个文件发到[社群](https://humanslive.ai/community)，我们就能帮你查。

### 仓库结构

| 文件 | 作用 |
|---|---|
| `codex.sh` | Mac 一键安装（国产模型版） |
| `codex.ps1` | Windows 一键安装（国产模型版） |
| `codex-official.sh` / `codex-official.ps1` | 官方版：运行 OpenAI 的官方安装命令，并清掉国产模型版留下的智谱配置，之后用自己的 ChatGPT 账号登录 |
| `windows/CodexSetup.cs` + `build.bat` | Windows 双击安装器：只是一层外壳，下载并运行 `codex.ps1`，所以脚本更新后 exe 不用重新发布 |

两个平台的脚本是同一套终端界面：数字雨开场、标题从乱码里解码出来、转圈、进度条、线路测速赛跑，最后是「ALL SYSTEMS GO」。

### 须知

- 免费模型能力有限，适合简单任务，用得太频繁会被限速。想用更强的模型，在[智谱开放平台](https://bigmodel.cn)充值后，把 `config.toml` 里的 `model` 换成付费模型即可。
- 创建 API Key 用的是智谱控制台的内部接口，不是公开 API。智谱改版后可能失效，失效时脚本会停下并给出日志，我们会尽快更新。
- Windows 版 Codex 带一个系统服务（`CodexSandboxService`），Codex 跑命令时的沙盒靠它，Windows 规定安装它要管理员确认，所以要点一次「是」。这一步省不掉：不装成正式的包，沙盒每跑一条命令都要管理员确认，而且永远收不到新版本。装好之后，跑命令、更新都不用再确认。当前账号不是管理员时，脚本会说明原因并停下。
- Codex 的窗口标题是「ChatGPT」，因为 OpenAI 把 Codex 并进了 ChatGPT 桌面版。
- 本项目与 OpenAI、智谱均无关联。

### 编译 Windows 安装器

在 Windows 上运行 `windows\build.bat`。它用系统自带的 .NET Framework 编译器生成 `windows\CodexSetup.exe`，不需要安装 Visual Studio。

### 参与贡献

欢迎提 Issue 和 PR。改动前请注意：

- `codex.sh` 和 `codex.ps1` 的界面、步骤和文字保持一致，改一边要同步改另一边，并在两个平台上实测。
- 新增的步骤要写日志，日志里不能出现 Key。
- 面向用户的文字用中文大白话，代码注释用英文。

### 许可

[MIT](LICENSE)

---

## English

### Quick start

**Mac**: press ⌘+Space, type "Terminal", press Return, and paste:

```bash
curl -fsSL https://humanslive.ai/codex.sh | bash
```

**Windows**: search the Start menu for "PowerShell", open it, and paste:

```powershell
irm https://humanslive.ai/codex.ps1 | iex
```

When the Zhipu login window appears, scan the QR code with WeChat (first-time users are signed up by the scan). Everything else is automatic, and Codex opens ready to use.

> Windows users who prefer not to use a terminal can run the double-click installer `CodexSetup.exe` (see [Building the Windows installer](#building-the-windows-installer)). It is not code-signed; on first launch click "More info" → "Run anyway".

### Highlights

- **One login, everything else automatic**: scanning the QR code is the only manual step (plus one system prompt on Windows). Download, verification, installation, API key creation, configuration and a smoke test all happen on their own.
- **Works on China's networks**: races the download sources, picks the China mirror or the official source, and downloads in the background while you scan, with resume support.
- **Official builds only**: on Mac it verifies OpenAI's code signature (Team ID `2DC432GLL2`); on Windows it verifies the package name, publisher and Microsoft Store signature, falling back to the Microsoft Store if any check fails.
- **A free model out of the box**: creates an API key in your own Zhipu account and connects Codex to Zhipu's free `glm-4.7-flash`.
- **Zero dependencies**: uses only what ships with the OS (bash, perl and WebKit on Mac; PowerShell 5.1, curl.exe and Edge on Windows).
- **Respects your machine**: changes only the settings it must, backs up first, and is safe to rerun; if it has set you up before, it will not ask you to scan again.
- **Clear errors**: every step is logged; on failure the screen says what to do and opens the log's folder.

### How it works

1. **System check and source race**: skips the download if Codex is already installed. Otherwise it measures each download source for 8 seconds and starts downloading in the background.
   - Mac: on Apple silicon it races the China mirror against OpenAI's official source and keeps the mirror unless it is more than 30% slower than the fastest; Intel Macs use the mirror.
   - Windows: one system prompt at the start ("Do you want to allow this app to make changes to your device?" → Yes), used only to install Codex. If the China mirror is fast enough it downloads the official package from it; otherwise it installs from the Microsoft Store (product ID `9PLM9XGG6VKS`). Afterwards it always checks that Codex really is installed, because winget reports success even when nothing was installed.
2. **Zhipu login**: opens a separate login window with the browser engine built into the OS (WebKit on Mac, a temporary Edge profile on Windows), never touching your own browser data. The QR code refreshes every 4 minutes, for up to 60 minutes.
3. **API key creation**: after login, the script calls the Zhipu console's own "create API key" endpoint inside that window, the same request the button sends. The full key is returned only once and goes straight to the script: never displayed, never on the clipboard.
4. **Model test**: tries `glm-4.7-flash`, then `glm-4.5-flash`.
5. **Configuration**: written as soon as the key exists, so a rerun after a later failure needs no new scan. Only `model`, `model_provider` and `[model_providers.zhipu]` in `config.toml` change; everything else is kept, and the original is backed up as `*.bak-<timestamp>` whenever the content changes. The key goes into `auth.json`, readable only by you.
6. **Verify and open**: asks Codex for a one-line reply to confirm it works, then opens it.

### Security and privacy

- **Your key stays on your machine**: it is created in your own Zhipu account and stored only in `~/.codex/auth.json` (`%USERPROFILE%\.codex\auth.json` on Windows). It never passes through our servers and is never logged. You can delete it any time in the Zhipu console; its name starts with `Codex-`.
- **Official builds only**: a package that fails signature verification is deleted, never installed.
- **No clipboard access**: there is no copy-the-key step. Reading the clipboard gets a script flagged by Windows Defender as a credential stealer, and the user should not need an extra step anyway.
- **Read before you run**: the scripts in this repo are exactly what the website serves. To inspect one before running it:

  ```bash
  curl -fsSL https://humanslive.ai/codex.sh -o codex.sh && less codex.sh && bash codex.sh
  ```

### Logs

Every run writes a log, under `~/Library/Logs/HumansLive/` on Mac and `%LOCALAPPDATA%\HumansLive\logs\` on Windows. On failure the screen shows where it is and opens its folder; send that file to our [community](https://humanslive.ai/community) and we can help.

### Repository layout

| File | Purpose |
|---|---|
| `codex.sh` | One-command installer for Mac (Chinese-model edition) |
| `codex.ps1` | One-command installer for Windows (Chinese-model edition) |
| `codex-official.sh` / `codex-official.ps1` | Official edition: runs OpenAI's official install command and removes the Zhipu config left by the Chinese-model edition, after which you sign in with your own ChatGPT account |
| `windows/CodexSetup.cs` + `build.bat` | Double-click installer for Windows: a thin shell that downloads and runs `codex.ps1`, so the exe needs no reissue when the script changes |

Both platforms share one terminal UI: a digital-rain intro, a title that decodes out of noise, spinners, progress bars, a download-source race and a closing "ALL SYSTEMS GO".

### Notes

- The free models are limited, suit simple tasks, and are rate-limited under heavy use. For stronger models, top up on the [Zhipu platform](https://bigmodel.cn) and set `model` in `config.toml` to a paid model.
- Key creation uses an internal Zhipu console endpoint, not a public API. It may break after a Zhipu redesign; the script then stops with a log, and we will update it.
- Codex for Windows ships a system service (`CodexSandboxService`) that its command sandbox relies on, and Windows requires administrator consent to install it, hence the one "Yes". It cannot be avoided: without a properly installed package, the sandbox asks for elevation on every command and the app never updates. Once installed, running commands and updating need no further confirmation. If the current account is not an administrator, the script explains why and stops.
- The Codex window is titled "ChatGPT" because OpenAI merged Codex into the ChatGPT desktop app.
- This project is not affiliated with OpenAI or Zhipu.

### Building the Windows installer

On Windows, run `windows\build.bat`. It builds `windows\CodexSetup.exe` with the .NET Framework compiler that ships with Windows; no Visual Studio needed.

### Contributing

Issues and PRs are welcome. Before changing anything:

- Keep `codex.sh` and `codex.ps1` identical in UI, steps and wording; change both together and test on both platforms.
- Log every new step, and never log a key.
- User-facing text is plain Chinese; code comments are English.

### License

[MIT](LICENSE)
