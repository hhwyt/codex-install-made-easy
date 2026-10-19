# codex-install-made-easy

让中国用户**一行命令**装好 [OpenAI Codex](https://developers.openai.com/codex/app) 桌面版，**用微信扫一次码**就接上国产免费大模型。不用翻墙，不用自己找 API Key，不花钱。

## 怎么用

**Mac**：打开「终端」（按 ⌘+空格，输入"终端"，回车），粘贴下面这行，回车：

```bash
curl -fsSL https://agentv1.com/codex.sh | bash
```

**Windows**：打开 PowerShell（开始菜单搜索"PowerShell"），粘贴下面这行，回车：

```powershell
irm https://agentv1.com/codex.ps1 | iex
```

也可以下载 `CodexSetup.exe` 双击运行。它没有代码签名，第一次打开会弹出「Windows 已保护你的电脑」，点「更多信息」→「仍要运行」。

运行过程中会弹出智谱登录窗口，**用手机微信扫码**（新用户扫码即注册）。之后全自动完成，最后 Codex 会自己打开。

## 它做了什么

| 步骤 | Mac | Windows |
|---|---|---|
| 1. 安装 Codex | 下载官方安装包（官方地址优先，太慢就换[国内镜像](https://github.com/Wangnov/codex-app-mirror)），支持断点续传；**校验是 OpenAI 官方签名**（Team ID `2DC432GLL2`）后才安装 | 从微软商店安装（商品 ID `9PLM9XGG6VKS`）；商店不可用时从国内镜像下载官方安装包，由系统校验签名 |
| 2. 登录智谱 | 用系统自带的 Safari 内核开一个登录窗口 | 用系统自带的 Edge 开一个独立窗口（临时资料目录，不碰你自己的浏览器数据） |
| 3. 创建 API Key | 登录后，在窗口里调用智谱控制台自己的「新建 API Key」接口（和你手动点按钮走同一个接口）。Key 直接交给脚本，不显示、不进剪贴板 | 同左 |
| 4. 测试模型 | 先试免费的 `glm-4.5-flash`，不可用就换 `glm-4.7-flash` | 同左 |
| 5. 写配置 | 只改 `~/.codex/config.toml` 里的 `model`、`model_provider` 和 `[model_providers.zhipu]`，其余原样保留；原文件先备份为 `*.bak-时间戳`；Key 写进 `~/.codex/auth.json`（只有你能读） | 同左，目录是 `%USERPROFILE%\.codex` |
| 6. 打开 Codex | 先让 Codex 回答一句话确认可用，再打开 | 同左 |

自动创建 Key 失败时（比如智谱改版），脚本会退回手动方式：打开智谱的 Key 页面，你点「新建」「复制」，脚本自动从剪贴板读取。

## 说明

- 免费模型能力有限，适合简单任务。想用更强的模型，在[智谱开放平台](https://bigmodel.cn)充值后，把 `config.toml` 里的 `model` 改成付费模型即可。
- 智谱控制台的「新建 API Key」接口不是公开 API，智谱改版后可能失效，届时会自动走手动方式。
- 本项目与 OpenAI、智谱均无关联。

## 编译 Windows 下载器

在 Windows 上运行 `windows\build.bat`，用系统自带的 .NET Framework 编译器生成 `windows\CodexSetup.exe`，不需要安装 Visual Studio。

## 许可证

[MIT](LICENSE)
