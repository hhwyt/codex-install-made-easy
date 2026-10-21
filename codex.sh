#!/bin/bash
# Codex 一键安装（Mac）：装好官方 Codex App，用微信扫码登录智谱后自动创建 API Key，接上智谱免费模型。
# 用法：curl -fsSL https://humanslive.ai/codex.sh | bash
# 只做这几件事：下载并校验官方 Codex、打开智谱登录窗口、新建一个 API Key、写 ~/.codex 下的配置、打开 Codex。
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
OPENAI_TEAM_ID="2DC432GLL2"
CODEX_BUNDLE_ID="com.openai.codex"
ZHIPU_BASE_URL="https://open.bigmodel.cn/api/v1"
ZHIPU_KEY_PAGE="https://bigmodel.cn/usercenter/proj-mgmt/apikeys"
ZHIPU_KEY_PATTERN='^[0-9a-f]{32}\.[A-Za-z0-9]{16}$'
FREE_MODELS="glm-4.5-flash glm-4.7-flash"
WORK_DIR="$(mktemp -d -t codex-setup)"
trap 'rm -rf "$WORK_DIR"' EXIT

say()  { printf '\n\033[1m%s\033[0m\n' "$*" >&2; }
info() { printf '  %s\n' "$*" >&2; }
fail() { printf '\n\033[31m出错了：%s\033[0m\n如需帮助，把上面的文字截图发给客服。\n' "$*"; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "这个脚本只支持 Mac。Windows 请用 PowerShell 版本。"

# ---------- 第 1 步：安装 Codex App ----------
find_codex_app() {
  local app
  for app in /Applications/Codex.app /Applications/ChatGPT.app "$HOME/Applications/Codex.app" "$HOME/Applications/ChatGPT.app"; do
    if [ -d "$app" ] && [ "$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)" = "$CODEX_BUNDLE_ID" ]; then
      echo "$app"; return 0
    fi
  done
  return 1
}

# 下载前先试 8 秒，速度太慢就换下一个源；正式下载支持断点续传
download_codex_dmg() {
  local arch_name official mirror source bytes_per_second
  if [ "$(uname -m)" = "arm64" ]; then
    official="https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
    mirror="https://codexapp.agentsmirror.com/latest/mac-arm64"
  else
    official=""
    mirror="https://codexapp.agentsmirror.com/latest/mac-intel"
  fi
  for source in $official $mirror; do
    info "测速：$source"
    bytes_per_second=$(curl -sL -r 0-4194303 -o /dev/null --connect-timeout 8 --max-time 8 -w '%{speed_download}' "$source" 2>/dev/null || echo 0)
    if [ "${bytes_per_second%.*}" -gt 300000 ] 2>/dev/null; then
      info "下载中（约 800MB，断了会自动续传）……"
      for _ in 1 2 3 4 5; do
        curl -fL -C - --retry 3 --connect-timeout 15 -# -o "$WORK_DIR/Codex.dmg" "$source" && return 0
        info "网络中断，继续下载……"
      done
    fi
  done
  return 1
}

install_codex_app() {
  local mount_point app_in_dmg team
  download_codex_dmg || fail "Codex 下载失败，请检查网络后重试。"
  mount_point=$(hdiutil attach -nobrowse -readonly "$WORK_DIR/Codex.dmg" | tail -1 | awk -F'\t' '{print $NF}')
  app_in_dmg=$(ls -d "$mount_point"/*.app | head -1)
  codesign --verify --deep --strict "$app_in_dmg" 2>/dev/null || { hdiutil detach "$mount_point" -quiet; fail "下载的安装包签名校验失败，已停止安装。"; }
  team=$(codesign -dv "$app_in_dmg" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [ "$team" = "$OPENAI_TEAM_ID" ] || { hdiutil detach "$mount_point" -quiet; fail "安装包不是 OpenAI 官方签名（${team}），已停止安装。"; }
  info "已确认是 OpenAI 官方原版，正在安装……"
  ditto "$app_in_dmg" "/Applications/$(basename "$app_in_dmg")"
  hdiutil detach "$mount_point" -quiet
}

say "第 1 步：安装 Codex"
if CODEX_APP=$(find_codex_app); then
  info "已安装：${CODEX_APP}，跳过"
else
  install_codex_app
  CODEX_APP=$(find_codex_app) || fail "安装后没找到 Codex App。"
  info "安装完成：$CODEX_APP"
fi

# ---------- 第 2 步：智谱 API Key ----------
# 打开一个 Safari 内核的小窗口（系统自带，不用装浏览器），用户扫码登录后在页面里调用控制台自己的
# 「新建 API Key」接口。完整 Key 只在创建时返回一次，直接交给本脚本，不显示、不进剪贴板。
cat > "$WORK_DIR/zhipu_login.js" <<'JXA'
ObjC.import('Cocoa');
ObjC.import('WebKit');
function run() {
  const app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyRegular);
  const window = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, 1000, 760), 1 | 2 | 4 | 8, $.NSBackingStoreBuffered, false);
  window.releasedWhenClosed = false;
  const configuration = $.WKWebViewConfiguration.alloc.init;
  configuration.websiteDataStore = $.WKWebsiteDataStore.nonPersistentDataStore;
  const webView = $.WKWebView.alloc.initWithFrameConfiguration(window.contentView.bounds, configuration);
  webView.customUserAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
  window.contentView = webView;
  window.title = '登录智谱：用微信扫码（新用户扫码即注册）';
  window.center;
  window.makeKeyAndOrderFront(null);
  app.activateIgnoringOtherApps(true);
  webView.loadRequest($.NSURLRequest.requestWithURL($.NSURL.URLWithString('https://bigmodel.cn/login?redirect=%2Fapikey%2Fplatform')));

  const pumpEvents = (seconds) => {
    const until = $.NSDate.dateWithTimeIntervalSinceNow(seconds);
    for (;;) {
      const event = app.nextEventMatchingMaskUntilDateInModeDequeue(0xFFFFFFFF, until, $('kCFRunLoopDefaultMode'), true);
      if (!event || event.isNil()) break;
      app.sendEvent(event);
    }
  };
  // 页面里的结果通过 document.title 传回来（窗口标题是单独设置的，不会显示它）
  const evaluate = (code) => { webView.evaluateJavaScriptCompletionHandler(code, (result, error) => {}); };
  const readTitle = () => ObjC.unwrap(webView.title) || '';
  const READ_STATE = `(() => {
    const token = (document.cookie.split('; ').find(c => c.startsWith('bigmodel_token_production=')) || '').split('=').slice(1).join('=');
    const ready = Boolean(token && localStorage.getItem('Bigmodel-Organization') && localStorage.getItem('Bigmodel-Project'));
    if (ready && !location.pathname.startsWith('/apikey') && !location.pathname.startsWith('/usercenter')) location.href = '/apikey/platform';
    document.title = 'STATE:' + (ready ? 'ready' : 'waiting');
  })()`;
  const CREATE_KEY = `(async () => {
    try {
      const token = (document.cookie.split('; ').find(c => c.startsWith('bigmodel_token_production=')) || '').split('=').slice(1).join('=');
      const organization = localStorage.getItem('Bigmodel-Organization');
      const project = localStorage.getItem('Bigmodel-Project');
      const response = await fetch('/api/biz/v1/organization/' + organization + '/projects/' + project + '/api_keys', {
        method: 'POST', credentials: 'include',
        headers: { 'Content-Type': 'application/json', Authorization: token, 'Bigmodel-Organization': organization, 'Bigmodel-Project': project },
        body: JSON.stringify({ name: (() => { const d = new Date(), p = n => String(n).padStart(2, '0'); return 'Codex-' + String(d.getFullYear()).slice(2) + p(d.getMonth() + 1) + p(d.getDate()) + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds()); })(), keyType: 1, usageScene: 2 }),
      }).then(r => r.json());
      document.title = response.code === 200 && response.data ? 'KEY:' + response.data.apiKey + '.' + response.data.secretKey : 'ERROR:' + (response.msg || response.code);
    } catch (e) { document.title = 'ERROR:' + e.message; }
  })()`;

  const deadline = Date.now() + 15 * 60 * 1000;
  let outcome = 'TIMEOUT';
  let lastRefresh = Date.now();
  while (Date.now() < deadline) {
    pumpEvents(1.5);
    if (!window.isVisible) { outcome = 'CANCELLED'; break; }
    evaluate(READ_STATE);
    pumpEvents(0.5);
    if (readTitle() !== 'STATE:ready') {
      // 微信二维码几分钟就过期：没登录的话每 4 分钟自动刷新一次
      if (Date.now() - lastRefresh > 4 * 60 * 1000) { webView.reload; lastRefresh = Date.now(); }
      continue;
    }
    evaluate(CREATE_KEY);
    for (let i = 0; i < 30 && !/^(KEY|ERROR):/.test(readTitle()); i++) pumpEvents(0.5);
    const title = readTitle();
    outcome = title.startsWith('KEY:') ? title.slice(4) : (title || 'ERROR:no response');
    break;
  }
  window.orderOut(null);
  return outcome;
}
JXA

# 自动创建失败时的退路：在用户自己的 Safari 里打开 Key 页面，用户点「新建」「复制」，脚本从剪贴板读
zhipu_key_by_clipboard() {
  open "$ZHIPU_KEY_PAGE"
  info "已在浏览器打开智谱的 API Key 页面："
  info "  ① 点「新建 API Key」，名字随便填，点「确定」"
  info "  ② 点「复制」，复制后这里会自动继续"
  local clip waited=0
  pbcopy < /dev/null
  while [ $waited -lt 900 ]; do
    clip=$(pbpaste 2>/dev/null | tr -d '[:space:]')
    if [[ "$clip" =~ $ZHIPU_KEY_PATTERN ]]; then pbcopy < /dev/null; echo "$clip"; return 0; fi
    sleep 1; waited=$((waited + 1))
  done
  return 1
}

say "第 2 步：登录智谱，自动创建 API Key"
if [ -n "${CODEX_SETUP_ZHIPU_KEY:-}" ]; then
  ZHIPU_API_KEY="$CODEX_SETUP_ZHIPU_KEY"
  info "使用环境变量里提供的 Key"
else
  info "马上会弹出智谱登录窗口，用手机微信扫码即可（新用户扫码就是注册）。"
  login_outcome=$(osascript -l JavaScript "$WORK_DIR/zhipu_login.js" 2>/dev/null | tail -1 || true)
  if [[ "$login_outcome" =~ $ZHIPU_KEY_PATTERN ]]; then
    ZHIPU_API_KEY="$login_outcome"
    info "已自动创建 API Key"
  else
    case "$login_outcome" in
      CANCELLED) info "登录窗口被关闭了，改用手动方式。" ;;
      TIMEOUT)   info "等待登录超时，改用手动方式。" ;;
      *)         info "自动创建没成功（${login_outcome#ERROR:}），改用手动方式。" ;;
    esac
    ZHIPU_API_KEY=$(zhipu_key_by_clipboard) || fail "15 分钟内没有读到 API Key。"
    info "已读到 API Key"
  fi
fi
[[ "$ZHIPU_API_KEY" =~ $ZHIPU_KEY_PATTERN ]] || fail "API Key 格式不对。"

# ---------- 第 3 步：确认免费模型可用 ----------
say "第 3 步：测试智谱免费模型"
MODEL=""
for candidate in $FREE_MODELS; do
  for _ in 1 2 3; do
    status=$(curl -s -o "$WORK_DIR/reply.json" -w '%{http_code}' --max-time 60 \
      -H "Authorization: Bearer $ZHIPU_API_KEY" -H 'Content-Type: application/json' \
      -d "{\"model\":\"$candidate\",\"input\":\"Reply with exactly one word: pong\",\"max_output_tokens\":16}" \
      "$ZHIPU_BASE_URL/responses" || echo 000)
    [ "$status" = "200" ] && { MODEL="$candidate"; break 2; }
    [ "$status" = "429" ] || break
    sleep 3
  done
done
[ -n "$MODEL" ] || fail "智谱免费模型暂时不可用（HTTP ${status}），请稍后重新运行本脚本。"
info "可用：$MODEL"

# ---------- 第 4 步：写 Codex 配置 ----------
# 只改 model、model_provider 和 [model_providers.zhipu]，其余配置原样保留；原文件先备份
say "第 4 步：写入 Codex 配置"
mkdir -p "$CODEX_HOME"
CONFIG="$CODEX_HOME/config.toml"
AUTH="$CODEX_HOME/auth.json"
BACKUP_SUFFIX=".bak-$(date +%Y%m%d%H%M%S)"
BACKED_UP=""
if [ -f "$CONFIG" ]; then cp "$CONFIG" "$CONFIG$BACKUP_SUFFIX"; BACKED_UP=1; fi
if [ -f "$AUTH" ]; then cp "$AUTH" "$AUTH$BACKUP_SUFFIX"; BACKED_UP=1; fi
{
  printf 'model_provider = "zhipu"\nmodel = "%s"\n\n' "$MODEL"
  if [ -f "$CONFIG" ]; then
    # 删掉表头之前的顶层 model / model_provider，以及旧的 [model_providers.zhipu] 整张表
    awk '
      /^\[/ { in_table = 1; skip = ($0 == "[model_providers.zhipu]") }
      !in_table && /^[[:space:]]*(model|model_provider)[[:space:]]*=/ { next }
      !skip { print }
    ' "$CONFIG"
  fi
  printf '\n[model_providers.zhipu]\nname = "智谱 GLM"\nbase_url = "%s"\nwire_api = "responses"\nrequires_openai_auth = true\n' "$ZHIPU_BASE_URL"
} > "$WORK_DIR/config.toml"
mv "$WORK_DIR/config.toml" "$CONFIG"
( umask 077; printf '{"OPENAI_API_KEY":"%s"}\n' "$ZHIPU_API_KEY" > "$AUTH" )
info "已写入 $CONFIG${BACKED_UP:+（原文件备份为 *${BACKUP_SUFFIX}）}"

# ---------- 第 5 步：验证并打开 Codex ----------
say "第 5 步：验证 Codex"
CODEX_CLI="$CODEX_APP/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
if [ -x "$CODEX_CLI" ]; then
  # Mac 没有 timeout 命令：后台运行，最多等 120 秒
  ( cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" "$CODEX_CLI" exec --ephemeral --skip-git-repo-check "只回复两个字：好了" < /dev/null > "$WORK_DIR/verify.txt" 2>/dev/null ) &
  verify_pid=$!
  for _ in $(seq 1 120); do kill -0 "$verify_pid" 2>/dev/null || break; sleep 1; done
  kill "$verify_pid" 2>/dev/null || true
  reply=$(tail -1 "$WORK_DIR/verify.txt" 2>/dev/null || true)
  info "Codex 回复：${reply:-（没有回复，打开后可直接试用）}"
fi
[ -n "${CODEX_SETUP_NO_OPEN:-}" ] || open "$CODEX_APP"
say "完成！Codex 已经打开，用的是智谱免费模型 ${MODEL}。"

# ---------- 结尾：HumansLive 的其他免费工具和商城 ----------
# 内容和排版来自网站（每行 kind<TAB>a<TAB>b），这里只按 kind 上色；拿不到就只打一行网址，不影响安装结果。
show_banner() {
  local banner kind a b reset="" dim="" bold="" blue="" link=""
  banner=$(curl -fsS --max-time 6 "https://humanslive.ai/api/install-banner?f=$1" 2>/dev/null | tr -d '\033\r') || banner=""
  if [ -z "$banner" ]; then printf '\n  更多免费工具和服务：https://humanslive.ai\n\n' >&2; return 0; fi
  if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    reset=$'\033[0m' dim=$'\033[2m' bold=$'\033[1m' blue=$'\033[1;38;5;33m' link=$'\033[4;38;5;33m'
  fi
  while IFS=$'\t' read -r kind a b; do
    case "$kind" in
      rule)  printf '  %s%s%s\n' "$dim" "$a" "$reset" ;;
      brand) printf '  %s%s%s%s\n' "$bold" "$a" "$reset" "$b" ;;
      head)  printf '  %s%s%s  %s%s%s\n' "$blue" "$a" "$reset" "$dim" "$b" "$reset" ;;
      row)   printf '    %s%s%s%s\n' "$a" "$dim" "$b" "$reset" ;;
      link)  printf '    %s%s%s\n' "$link" "$a" "$reset" ;;
      *)     printf '\n' ;;
    esac
  done <<< "$banner" >&2
  return 0
}
show_banner codex
