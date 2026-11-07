# 升级 / 降级回归测试（Windows 汉化版）

用户装好汉化版后，Codex App 会通过微软商店自动升级，升级完会自己重启成英文版。这套测试在一台真的 Windows 电脑上，用真实的旧版、新版安装包把下面每一步跑一遍，每步截图、存启动器日志：

| 步骤 | 检查什么 |
| --- | --- |
| `install-old` | 装上旧版 App |
| `run-installer` | 跑本仓库的 `codex.ps1`（汉化版），桌面有「ChatGPT 汉化版」，快捷方式经无窗口的 conhost 启动 |
| `old-shortcut-chinese` | 点快捷方式：界面是中文，任务栏没有多出终端窗口 |
| `upgrade-while-chinese-open` | 汉化版开着时升级（和商店一样：先关 App 再换包），启动器跟着退出，App 能正常打开 |
| `new-dialog-restart-chinese` | App 是英文时点快捷方式：弹出「ChatGPT 现在是英文界面」，点「重启成中文」后变中文 |
| `new-dialog-not-now` | 同上，点「先不用」：英文版保持开着，启动器退出 |
| `new-shortcut-chinese-from-closed` | App 关着时点快捷方式：直接是中文 |
| `downgrade-while-chinese-open` | 汉化版开着时降回旧版，点快捷方式还是中文 |
| `upgrade-while-closed` | App 关着时升级，点快捷方式是中文 |

## 安装包从哪来

商店只给最新版，升级时还会删掉旧版，所以每个版本出来时就要存一份。安装包存在私有仓库 [hhwyt/codex-app-archive](https://github.com/hhwyt/codex-app-archive) 的 Releases 里（每个版本一个 `v<版本号>`）。这些是 OpenAI 的程序，只用来测试，**不要公开**。

- `store-links.ps1`：在 Windows 上向微软商店自己的接口（`displaycatalog`、`fe3.delivery.mp.microsoft.com`）要当前版本的下载链接。请求模板在 `fe3/`，来自 StoreLib（MPL-2.0，见 `fe3/NOTICE.md`）。
- `verify-msix.ps1`：在 Windows 上核对签名：有效，签给 OpenAI 的商店发布者 `CN=50BDFD77-…`，颁发者是微软。不对就删掉。
- `archive.sh`（Mac）：商店有新版本就下载 → 传到 Windows 验签 → 存进私有仓库 → 从上一个版本升到新版本跑一遍测试。没有新版本时什么都不做。

## 怎么跑

前提：Mac 能 `ssh hwy-pc`，Mac 上 `gh` 已登录，测试电脑**桌面上有人登录着**（本机或远程桌面都行，没人登录就没有桌面，App 打不开）。测试会改测试电脑上的 App 版本和 Codex 配置，只在测试电脑上跑。

```bash
tests/upgrade/run.sh                              # 私有仓库里最新的两个版本：旧 → 新
tests/upgrade/run.sh 26.1103.3517.0 26.1103.4239.0  # 指定版本
```

一轮大约 10 分钟，结果（`result.json`、每步截图、启动器日志、安装脚本输出）在 `tests/upgrade/results/<时间>/`。私有仓库里只有一个版本时，旧版 = 新版，只能验证测试本身，测不到真正的升级、降级。

改了汉化启动器（`codex.ps1` 里的 `codex-zh.ps1`、快捷方式、弹窗）后，发布前跑一遍 `run.sh`。

每天自动检查新版本（Mac 的 LaunchAgent，每天 10:00；Mac 关机时下次开机补跑）：

```bash
cp tests/upgrade/com.humanslive.codex-upgrade-test.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.humanslive.codex-upgrade-test.plist
```

结果用 Mac 通知提示，日志在 `/tmp/codex-upgrade-test.log`。

---

# Upgrade / downgrade regression test (Windows Chinese edition)

After the Chinese edition is installed, the Codex App updates itself through the Microsoft Store and restarts in English. This test runs every step above on a real Windows PC with real old and new App packages, taking a screenshot and the launcher log at each step.

- Packages: the Store serves only the latest version and an update deletes the old one, so each version is archived when it appears, as a release of the private repository [hhwyt/codex-app-archive](https://github.com/hhwyt/codex-app-archive). They are OpenAI's binaries, kept for testing only: never make them public.
- `store-links.ps1` (Windows) asks the Store's own endpoints for the current download links; request templates in `fe3/` come from StoreLib (MPL-2.0). `verify-msix.ps1` (Windows) keeps a package only if its signature is valid, issued to OpenAI's Store publisher by a Microsoft CA. `archive.sh` (Mac, daily LaunchAgent) archives a new version and runs the test from the previous one to it.
- Run `tests/upgrade/run.sh [OLD [NEW]]` from the Mac (needs `ssh hwy-pc`, a logged-in `gh`, and someone logged in to the PC's desktop). Results go to `tests/upgrade/results/<time>/`. With a single archived version, OLD = NEW only exercises the harness.
- Run it before publishing changes to the Chinese launcher, its shortcut or its dialog.
