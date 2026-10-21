# codex-install-made-easy

[中文](#中文) · [English](#english)

---

## 中文

让不懂电脑的普通中国人也能装好 [OpenAI Codex](https://developers.openai.com/codex/app)：**一行命令，扫一次码**，就能用上国产大模型。不用翻墙，不用自己找 API Key，不花钱。

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

### 它做了什么

1. **安装 Codex**
   - Mac：先试官方下载地址，太慢就换[国内镜像](https://github.com/Wangnov/codex-app-mirror)，支持断点续传；确认是 OpenAI 官方签名（Team ID `2DC432GLL2`）后才安装。
   - Windows：从微软商店安装（商品 ID `9PLM9XGG6VKS`）；商店用不了时，从国内镜像下载官方安装包，由系统校验签名。
2. **登录智谱**：用系统自带的浏览器内核开一个登录窗口（Mac 是 Safari 内核，Windows 是 Edge 的独立临时窗口，不碰你自己的浏览器数据）。
3. **自动创建 API Key**：你扫码登录后，脚本在这个窗口里调用智谱控制台自己的「新建 API Key」接口，和你手动点按钮走的是同一个接口。完整的 Key 只在创建时返回一次，脚本直接接住，不显示、不进剪贴板。
4. **测试模型**：先试智谱永久免费的 `glm-4.5-flash`，不可用就换 `glm-4.7-flash`。
5. **写配置**：只改 `config.toml` 里的 `model`、`model_provider` 和 `[model_providers.zhipu]`，其余原样保留；原文件先备份为 `*.bak-时间戳`。Key 写进 `auth.json`。配置目录在 Mac 上是 `~/.codex`，在 Windows 上是 `%USERPROFILE%\.codex`。
6. **验证并打开 Codex**：先让 Codex 回答一句话确认能用，再打开。

如果自动创建 Key 失败（比如智谱改版了），脚本会打开智谱的 Key 页面，你点「新建」「复制」，脚本自动从剪贴板读取，读完立即清空剪贴板。

### 须知

- 免费模型能力有限，适合简单任务。想用更强的模型，在[智谱开放平台](https://bigmodel.cn)充值后，把 `config.toml` 里的 `model` 改成付费模型即可。
- 「新建 API Key」用的是智谱控制台的内部接口，不是公开 API，智谱改版后可能失效，失效时会自动改用手动方式。
- 本项目与 OpenAI、智谱均无关联。

### 编译 Windows 下载器

在 Windows 上运行 `windows\build.bat`，会用系统自带的 .NET Framework 编译器生成 `windows\CodexSetup.exe`，不需要安装 Visual Studio。

### 许可

私有项目，未开源。

---

## English

Get [OpenAI Codex](https://developers.openai.com/codex/app) running for anyone in China, even people who barely use a computer: **one command, one QR scan**, and Codex is working with a Chinese model. No VPN, no hunting for API keys, no cost.

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

### What it does

1. **Installs Codex**
   - Mac: tries the official download first and falls back to a [mirror in China](https://github.com/Wangnov/codex-app-mirror) if it is slow, resuming interrupted downloads; installs only after confirming OpenAI's signature (Team ID `2DC432GLL2`).
   - Windows: installs from the Microsoft Store (product ID `9PLM9XGG6VKS`); if the Store is unavailable, downloads the official package from the mirror and lets Windows verify its signature.
2. **Opens a Zhipu login window** using the browser engine built into the system: Safari's engine on Mac, and a separate temporary Edge window on Windows that never touches your own browser data.
3. **Creates an API key automatically**: after you log in, the script calls the Zhipu console's own "create API key" endpoint inside that window, the same request the button sends. The full key is returned only once, at creation; the script takes it directly, never showing it or putting it on the clipboard.
4. **Tests a model**: tries Zhipu's permanently free `glm-4.5-flash`, then `glm-4.7-flash`.
5. **Writes the config**: changes only `model`, `model_provider` and `[model_providers.zhipu]` in `config.toml`, keeps everything else, and backs up the original as `*.bak-<timestamp>`. The key goes into `auth.json`. The config directory is `~/.codex` on Mac and `%USERPROFILE%\.codex` on Windows.
6. **Verifies and opens Codex**: asks Codex for a one-line reply to confirm it works, then opens it.

If automatic key creation fails (for example after a Zhipu redesign), the script opens Zhipu's key page instead: click "Create" and "Copy", and the script reads the key from the clipboard, then clears the clipboard.

### Notes

- The free models are limited and suit simple tasks. For stronger models, top up on the [Zhipu platform](https://bigmodel.cn) and set `model` in `config.toml` to a paid model.
- Key creation uses an internal Zhipu console endpoint, not a public API. It may break after a Zhipu redesign, in which case the script falls back to the manual steps.
- This project is not affiliated with OpenAI or Zhipu.

### Building the Windows installer

On Windows, run `windows\build.bat`. It builds `windows\CodexSetup.exe` with the .NET Framework compiler that ships with Windows; no Visual Studio needed.

### License

Private project; not open source.
