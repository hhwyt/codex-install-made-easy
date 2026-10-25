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
cat > "$WORK_DIR/fx.pl" <<'FX'
# 终端动效（macOS 自带 perl，不用装东西）。只在真终端里调用；全部输出到 stderr。
#   rain <宽> <行数> <毫秒>          数字雨，结束后擦掉
#   decode <颜色> <文字>             乱码逐字解码成文字（只打乱 ASCII，中文原样）
#   race <数量> {名字 标签 文件 进程号}...   测速赛跑，实时刷新；结束后在 stdout 输出「最快的序号 各条速度…」，都失败时序号是 -1
use strict; use warnings; use utf8;
use Time::HiRes qw(sleep time);
binmode STDERR, ':utf8'; binmode STDOUT, ':utf8';
$| = 1; select((select(STDERR), $| = 1)[0]);
@ARGV = map { utf8::decode($_); $_ } @ARGV;

my $BLUE = "\e[38;5;33m"; my $HEAD = "\e[38;5;153m"; my $DIM = "\e[2m"; my $DEEP = "\e[38;5;25m";
my $BOLD = "\e[1m"; my $RESET = "\e[0m";
my @GLYPHS = (('0' .. '9'), map { chr } 0xFF66 .. 0xFF9D);
sub glyph { $GLYPHS[int rand @GLYPHS] }
sub width {
  my $w = 0;
  for (split //, shift) {
    my $o = ord;
    $w += (($o >= 0x1100 && $o <= 0x115F) || ($o >= 0x2E80 && $o <= 0xA4CF) || ($o >= 0xAC00 && $o <= 0xD7A3) || ($o >= 0xF900 && $o <= 0xFAFF)
      || ($o >= 0xFE30 && $o <= 0xFE4F) || ($o >= 0xFF00 && $o <= 0xFF60) || ($o >= 0xFFE0 && $o <= 0xFFE6)) ? 2 : 1;
  }
  $w
}

my $cmd = shift @ARGV;

if ($cmd eq 'rain') {
  my ($cols, $rows, $ms) = @ARGV;
  my @cols = grep { $_ % 2 == 0 } 0 .. $cols - 1;
  my %drop = map { $_ => -int(rand($rows * 2)) } @cols;
  my %len = map { $_ => 3 + int rand 5 } @cols;
  my $frames = int($ms / 45);
  print STDERR "\n" x $rows;
  for my $f (1 .. $frames) {
    my $out = "\e[${rows}A";
    for my $r (0 .. $rows - 1) {
      my $line = '';
      for my $c (0 .. $cols - 1) {
        if ($c % 2) { $line .= ' '; next }
        my $d = $drop{$c} - $r;
        if ($d == 0) { $line .= $HEAD . glyph() . $RESET }
        elsif ($d > 0 && $d < $len{$c}) { $line .= ($d < 3 ? $BLUE : $DEEP) . glyph() . $RESET }
        else { $line .= ' ' }
      }
      $out .= "\r\e[K  $line\n";
    }
    print STDERR $out;
    $drop{$_}++ for @cols;
    for (@cols) { if ($drop{$_} - $len{$_} > $rows) { $drop{$_} = -int(rand($rows)); $len{$_} = 3 + int rand 5 } }
    sleep 0.045;
  }
  print STDERR "\e[${rows}A" . ("\r\e[K\n" x $rows) . "\e[${rows}A";
}
elsif ($cmd eq 'decode') {
  my ($color, $text) = @ARGV;
  my @ch = split //, $text;
  my $steps = 14;
  for my $s (0 .. $steps) {
    my $shown = int(@ch * $s / $steps);
    my $line = '';
    for my $i (0 .. $#ch) {
      my $c = $ch[$i];
      if ($i < $shown || $c !~ /[!-~]/) { $line .= $c }
      else { $line .= $DIM . ('0' .. '9', 'A' .. 'Z')[int rand 36] . $RESET . $color }
    }
    print STDERR "\r\e[K  $color$line$RESET";
    sleep 0.025;
  }
  print STDERR "\n";
}
elsif ($cmd eq 'race') {
  my $n = shift @ARGV;
  my (@name, @tag, @file, @pid, @end, @speed);
  for my $i (0 .. $n - 1) { ($name[$i], $tag[$i], $file[$i], $pid[$i]) = splice @ARGV, 0, 4 }
  my $cols = $ENV{FX_COLS} || 80;
  my $namew = 0; for (@name) { my $w = width($_); $namew = $w if $w > $namew }
  my $tagw = 0; for (@tag) { my $w = width($_); $tagw = $w if $w > $tagw }
  # 一行 = 缩进 5 + 标记 2 + 名字 + 2 + 标签 + 2 + 进度条 + 2 + 速度 10 + 「  最快」6，再留 2 列不贴边
  my $barw = $cols - 5 - 2 - $namew - 2 - $tagw - 2 - 2 - 10 - 6 - 2;
  $barw = 24 if $barw > 24;
  $barw = 0 if $barw < 6;
  my @frames = qw(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏);
  my $start = time; my $tick = 0;
  my $mb = sub { my $b = shift; $b > 0 ? sprintf('%5.1f MB/s', $b / 1048576) : '   连不上 ' };
  my $draw = sub {
    my ($final, $best) = @_;
    my $max = 1048576; for (@speed) { $max = $_ if defined $_ && $_ > $max }
    my $out = '';
    for my $i (0 .. $n - 1) {
      my $sp = $speed[$i] // 0;
      my $fill = $barw ? int($barw * $sp / $max + 0.5) : 0; $fill = $barw if $fill > $barw;
      my $bar = $barw ? $BLUE . ('━' x $fill) . $RESET . $DIM . ('─' x ($barw - $fill)) . $RESET . '  ' : '';
      my $mark = !$final ? ($end[$i] ? $BLUE . '·' . $RESET : $BLUE . $frames[$tick % 10] . $RESET)
               : $i == $best ? $BLUE . $BOLD . '✓' . $RESET : $DIM . '·' . $RESET;
      my $label = $name[$i] . (' ' x ($namew - width($name[$i]))) . '  ' . $DIM . $tag[$i] . (' ' x ($tagw - width($tag[$i]))) . $RESET;
      my $tail = $final && $i == $best ? "  $BLUE${BOLD}最快$RESET" : '';
      my $num = ($final && $i != $best) ? $DIM . $mb->($sp) . $RESET : $mb->($sp);
      $num = $DIM . '   测速中 ' . $RESET if !$final && !$end[$i] && !$sp;
      $out .= "\r\e[K     $mark $label  $bar$num$tail\n";
    }
    print STDERR "\e[${n}A$out";
  };
  print STDERR "\n" x $n;
  while (1) {
    my $alive = 0;
    for my $i (0 .. $n - 1) {
      my $size = -s $file[$i] || 0;
      my $el = ($end[$i] // time) - $start;
      $speed[$i] = $el > 0.3 ? $size / $el : 0 unless $end[$i];
      if (!$end[$i]) { if (kill 0, $pid[$i]) { $alive = 1 } else { $end[$i] = time; $speed[$i] = $el > 0 ? $size / $el : 0 } }
    }
    last unless $alive;
    $draw->(0);
    $tick++; sleep 0.08;
  }
  my $best = -1; my $bs = 100 * 1024;
  for my $i (0 .. $n - 1) { if (($speed[$i] // 0) > $bs) { $bs = $speed[$i]; $best = $i } }
  # 第一条（国内镜像）只要不比最快的慢 30% 以上就用它：对不开代理的用户更稳
  $best = 0 if $best > 0 && ($speed[0] // 0) * 1.3 >= $bs;
  $draw->(1, $best);
  print STDOUT join(' ', $best, map { int($_ // 0) } @speed), "\n";
}
FX

# ---------- 终端输出 ----------
# 只有一个强调色（蓝），次要信息用灰色，红色只用于出错；不是终端（被重定向）或设了 NO_COLOR 时不上色、不画动画。
# 所有提示都写到 stderr：标准输出留给 $(...) 取值用。
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_BLUE=$'\033[38;5;33m' C_RED=$'\033[31m'
  LIVE=1
else
  C_RESET="" C_BOLD="" C_DIM="" C_BLUE="" C_RED="" LIVE=""
fi
STEP=0
# 路径里的家目录显示成 ~，短一些
short_path() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
term_cols() { local cols; cols=$( { stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2); [ "${cols:-0}" -gt 0 ] 2>/dev/null && echo "$cols" || echo 80; }
# 开场：一小段数字雨，标题从乱码解码出来（不到 1.5 秒）
header() {
  local cols; cols=$(term_cols)
  printf '\n' >&2
  if [ -n "$LIVE" ]; then
    perl "$WORK_DIR/fx.pl" rain $((cols > 76 ? 70 : cols - 6)) 6 900 || true
    perl "$WORK_DIR/fx.pl" decode "$C_BLUE$C_BOLD" "HUMANSLIVE.AI ▸ $1" || printf '  %s\n' "$1" >&2
  else
    printf '  %sHUMANSLIVE.AI ▸ %s%s\n' "$C_BLUE$C_BOLD" "$1" "$C_RESET" >&2
  fi
  printf '  %s%s%s\n' "$C_DIM" "$2" "$C_RESET" >&2
}
# 不编号的准备阶段（系统检测、线路测速）
section() { printf '\n  %s▸%s %s%s%s  %s%s%s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" "$C_DIM" "${2:-}" "$C_RESET" >&2; }
say()  { STEP=$((STEP + 1)); printf '\n  %s[%d/%d]%s %s%s%s\n' "$C_BLUE$C_BOLD" "$STEP" "$STEPS" "$C_RESET" "$C_BOLD" "$*" "$C_RESET" >&2; }
info() { printf '       %s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }
ok()   { printf '     %s✓%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
todo() { printf '     %s→%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET" >&2; }
done_line() {
  local took="$((SECONDS % 60)) 秒"; [ "$SECONDS" -lt 60 ] || took="$((SECONDS / 60)) 分 $took"
  printf '\n' >&2
  if [ -n "$LIVE" ]; then perl "$WORK_DIR/fx.pl" decode "$C_BLUE$C_BOLD" "✓ ALL SYSTEMS GO · 全部完成"
  else printf '  ✓ ALL SYSTEMS GO · 全部完成\n' >&2; fi
  printf '     %s用时 %s%s\n     %s\n' "$C_DIM" "$took" "$C_RESET" "$*" >&2
}
fail() {
  [ -z "$LIVE" ] || printf '\r\033[K' >&2
  printf '\n  %s✗ 出错了%s\n     %s\n     %s需要帮助：截图发到社群 https://humanslive.ai/community%s\n\n' "$C_RED$C_BOLD" "$C_RESET" "$*" "$C_DIM" "$C_RESET" >&2
  exit 1
}

# 转圈那一行末尾的附加信息（比如后台下载进度），默认没有
spin_note() { :; }

# 等一个后台进程结束，期间转圈并显示已等了多久；返回它的退出码。用法：spin <pid> <文字>
spin() {
  local pid=$1 text=$2 start=$SECONDS i=0 note=""
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  if [ -n "$LIVE" ]; then
    while kill -0 "$pid" 2>/dev/null; do
      [ $((i % 10)) -ne 0 ] || note=$(spin_note)
      printf '\r\033[K     %s%s%s %s  %s%ds%s%s' "$C_BLUE" "${frames[i % 10]}" "$C_RESET" "$text" "$C_DIM" $((SECONDS - start)) "$note" "$C_RESET" >&2
      i=$((i + 1)); sleep 0.1
    done
    printf '\r\033[K' >&2
  fi
  wait "$pid"
}

file_size() { stat -f %z "$1" 2>/dev/null || echo 0; }
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time * 1000'; }
mb() { printf '%d.%d' $(($1 / 1048576)) $(($1 % 1048576 * 10 / 1048576)); }

# 进度条：长度固定（右边的数字定宽），速度按最近约 2 秒算，数字不乱跳
draw_progress() {
  local pid=$1 out=$2 total=$3 size elapsed speed=0 pct width filled bar stats cols t_prev s_prev t_now
  cols=$(term_cols)
  t_prev=$(now_ms); s_prev=$(file_size "$out")
  while kill -0 "$pid" 2>/dev/null; do
    size=$(file_size "$out")
    t_now=$(now_ms); elapsed=$((t_now - t_prev))
    if [ "$elapsed" -ge 2000 ]; then
      speed=$(((size - s_prev) * 1000 / elapsed)); t_prev=$t_now; s_prev=$size
    fi
    if [ "$total" -gt 0 ]; then
      pct=$((size * 100 / total)); [ "$pct" -le 100 ] || pct=100
      if [ "$speed" -gt 0 ]; then
        stats=$(printf '%3d%%  %6s / %s MB  %5s MB/s' "$pct" "$(mb "$size")" "$(mb "$total")" "$(mb "$speed")")
      else
        stats=$(printf '%3d%%  %6s / %s MB  %10s' "$pct" "$(mb "$size")" "$(mb "$total")" "")
      fi
      width=$((cols - 9 - ${#stats})); [ "$width" -le 28 ] || width=28
      if [ "$width" -ge 8 ]; then
        filled=$((pct * width / 100))
        bar=$C_BLUE$(printf '%*s' "$filled" '' | sed 's/ /━/g')$C_RESET$C_DIM$(printf '%*s' $((width - filled)) '' | sed 's/ /─/g')$C_RESET
        printf '\r\033[K     %s  %s' "$bar" "$stats" >&2
      else
        printf '\r\033[K     %s' "$stats" >&2
      fi
    else
      printf '\r\033[K     已下载 %s MB  %s MB/s' "$(mb "$size")" "$(mb "$speed")" >&2
    fi
    sleep 0.25
  done
  printf '\r\033[K' >&2
}

[ "$(uname -s)" = "Darwin" ] || fail "这个脚本只支持 Mac。Windows 请用 PowerShell 版本。"
STEPS=3
header "CODEX INSTALLER" "Codex 一键安装 · 国产模型版 · 不用科学上网 · 不花钱"

APP_DIR="${CODEX_SETUP_APP_DIR:-/Applications}"
CACHE_DIR="${CODEX_SETUP_CACHE_DIR:-$HOME/Library/Caches/HumansLive}"
CONFIG="$CODEX_HOME/config.toml"
AUTH="$CODEX_HOME/auth.json"
DL_PID=""

# Ctrl+C 或出错退出时，连同后台下载一起停掉；已下载的部分留在缓存里，重新运行会接着下
cleanup() {
  if [ -n "$DL_PID" ]; then pkill -P "$DL_PID" 2>/dev/null || true; kill "$DL_PID" 2>/dev/null || true; fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'printf "\n\n  已停止。重新运行这行命令会接着之前的进度。\n\n" >&2; exit 130' INT TERM

# ---------- Codex App：没装的话一开始就在后台下载，用户扫码的同时在下 ----------
find_codex_app() {
  local app
  for app in "$APP_DIR/Codex.app" "$APP_DIR/ChatGPT.app" /Applications/Codex.app /Applications/ChatGPT.app \
    "$HOME/Applications/Codex.app" "$HOME/Applications/ChatGPT.app"; do
    if [ -d "$app" ] && [ "$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)" = "$CODEX_BUNDLE_ID" ]; then
      echo "$app"; return 0
    fi
  done
  return 1
}

# 版本号比较：version_ge 15.2 14.0 成立
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 } exit 0 }'
}

# 后台下载选中的线路到缓存目录（断了重新运行会接着下）。用法：download_codex_dmg <网址> <线路名> <文件>
# 选好的线路、文件、大小写进 $WORK_DIR/dl.info，结果（0 成功）写进 $WORK_DIR/dl.rc。
download_codex_dmg() {
  local url=$1 name=$2 file=$3 headers total etag size
  headers=$(curl -sIL --connect-timeout 15 --max-time 20 "$url" 2>/dev/null | tr -d '\r')
  total=$(awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }' <<< "$headers")
  etag=$(awk 'tolower($1) == "etag:" { e = $2 } END { print e }' <<< "$headers")
  # 上次没下完、而源上已经换了新版本：旧的半截文件不能续，删掉重下
  if [ -f "$file.etag" ] && [ "$(cat "$file.etag")" != "$etag" ]; then rm -f "$file"; fi
  printf '%s' "$etag" > "$file.etag"
  printf '%s\n%s\n%s\n' "$name" "$file" "$total" > "$WORK_DIR/dl.info"
  size=$(file_size "$file")
  if [ "$total" -gt 0 ] && [ "$size" -gt "$total" ]; then rm -f "$file"; size=0; fi
  if [ "$total" -gt 0 ] && [ "$size" -eq "$total" ]; then return 0; fi
  for _ in 1 2 3 4 5; do
    curl -fsSL -C - --retry 3 --connect-timeout 15 -o "$file" "$url" && return 0
    sleep 2
  done
  return 1
}

# 所有下载线路同时测 8 秒，画成赛跑，选最快的。镜像在中国大陆走国内节点，不用科学上网也快；
# 开着代理的用户可能官方源更快。测速下载的那一段直接留给正式下载接着用。
race_sources() {
  local urls names tags keys pids i n best probe code result speeds fastest other ratio
  if [ "$(uname -m)" = "arm64" ]; then
    urls=("https://codexapp.agentsmirror.com/latest/mac-arm64" "https://persistent.oaistatic.com/codex-app-prod/Codex.dmg")
    names=("国内镜像" "OpenAI 官方源"); tags=("不用科学上网" "需要科学上网"); keys=(mirror official)
  else
    urls=("https://codexapp.agentsmirror.com/latest/mac-intel"); names=("国内镜像"); tags=("不用科学上网"); keys=(mirror)
  fi
  n=${#urls[@]}
  section "线路测速" "同时探测 $n 条下载线路，选最快的"
  pids=()
  for ((i = 0; i < n; i++)); do
    curl -sL -r 0-33554431 --connect-timeout 8 --max-time 8 -w '%{http_code}' -o "$WORK_DIR/probe.$i" "${urls[i]}" \
      </dev/null >"$WORK_DIR/probe.$i.code" 2>/dev/null &
    pids[i]=$!
  done
  local args=()
  for ((i = 0; i < n; i++)); do args+=("${names[i]}" "${tags[i]}" "$WORK_DIR/probe.$i" "${pids[i]}"); done
  if [ -n "$LIVE" ]; then
    result=$(FX_COLS=$(term_cols) perl "$WORK_DIR/fx.pl" race "$n" "${args[@]}") || result=-1
  else
    result=$(perl "$WORK_DIR/fx.pl" race "$n" "${args[@]}" 2>/dev/null) || result=-1
  fi
  wait 2>/dev/null || true
  read -r best speeds <<< "$result"
  [ -n "$LIVE" ] || for ((i = 0; i < n; i++)); do info "${names[i]}：$(mb "$(echo $speeds | cut -d' ' -f$((i + 1)))") MB/s"; done
  [ "$best" -ge 0 ] 2>/dev/null || fail "下载线路都连不上。检查网络后重新运行这行命令。"
  SOURCE_URL=${urls[best]}; SOURCE_NAME=${names[best]}; SOURCE_FILE="$CACHE_DIR/Codex-${keys[best]}.dmg"
  # 测速下的这一段就是文件开头：缓存里没有更长的，就直接接着用
  probe="$WORK_DIR/probe.$best"; code=$(cat "$probe.code" 2>/dev/null)
  if [ "$code" = 206 ] || [ "$code" = 200 ]; then
    if [ "$(file_size "$probe")" -gt "$(file_size "$SOURCE_FILE")" ]; then mv "$probe" "$SOURCE_FILE"; rm -f "$SOURCE_FILE.etag"; fi
  fi
  fastest=$(echo $speeds | cut -d' ' -f$((best + 1)))
  other=0; [ "$n" -lt 2 ] || other=$(echo $speeds | cut -d' ' -f$((2 - best)))
  if [ "$other" -gt 0 ] && [ $((fastest / other)) -ge 2 ]; then
    ok "下载线路：${SOURCE_NAME}，比另一条快 $((fastest / other)) 倍"
  else
    ok "下载线路：${SOURCE_NAME}"
  fi
}

# 转圈时附在后面的后台下载进度
download_note() {
  local file total
  if [ "$(cat "$WORK_DIR/dl.rc" 2>/dev/null)" = 0 ]; then printf '  · Codex 已在后台下载好'; return; fi
  [ -f "$WORK_DIR/dl.info" ] || { printf '  · 正在准备下载 Codex'; return; }
  file=$(sed -n 2p "$WORK_DIR/dl.info"); total=$(sed -n 3p "$WORK_DIR/dl.info")
  if [ "${total:-0}" -gt 0 ]; then printf '  · 后台下载 Codex %d%%' $(($(file_size "$file") * 100 / total)); else printf '  · 后台下载 Codex 中'; fi
}

install_codex_app() {
  local dmg=$1 mount_point app_in_dmg team need target
  mount_point=$(hdiutil attach -nobrowse -readonly "$dmg" | tail -1 | awk -F'\t' '{print $NF}')
  app_in_dmg=$(ls -d "$mount_point"/*.app | head -1)
  codesign --verify --deep --strict "$app_in_dmg" </dev/null 2>/dev/null &
  spin $! "核对 OpenAI 官方签名" || {
    hdiutil detach "$mount_point" -quiet; rm -f "$dmg"
    fail "下载的安装包不完整或被改动过，已经删掉。重新运行这行命令即可。"
  }
  team=$(codesign -dv "$app_in_dmg" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [ "$team" = "$OPENAI_TEAM_ID" ] || { hdiutil detach "$mount_point" -quiet; rm -f "$dmg"; fail "安装包不是 OpenAI 官方签名（${team}），已停止安装。"; }
  ok "已确认是 OpenAI 官方原版"
  need=$(defaults read "$app_in_dmg/Contents/Info.plist" LSMinimumSystemVersion 2>/dev/null || echo 0)
  version_ge "$(sw_vers -productVersion)" "$need" || {
    hdiutil detach "$mount_point" -quiet
    fail "Codex 需要 macOS ${need} 或更新的系统，这台 Mac 是 $(sw_vers -productVersion)。先在「系统设置 → 通用 → 软件更新」里升级，再重新运行这行命令。"
  }
  # 不是管理员账号写不了「应用程序」文件夹，就装到自己的「应用程序」里
  target="$APP_DIR"; [ -w "$target" ] || { target="$HOME/Applications"; mkdir -p "$target"; }
  ditto "$app_in_dmg" "$target/$(basename "$app_in_dmg")" </dev/null &
  spin $! "安装到「应用程序」文件夹" || { hdiutil detach "$mount_point" -quiet; fail "复制到「应用程序」文件夹失败。"; }
  hdiutil detach "$mount_point" -quiet
}

# ---------- 准备：系统检测、线路测速，然后在后台开始下载 ----------
section "系统检测"
if [ "$(uname -m)" = "arm64" ]; then CHIP="Apple 芯片"; else CHIP="Intel 芯片"; fi
ok "macOS $(sw_vers -productVersion) · $CHIP"
CODEX_APP=$(find_codex_app || true)
if [ -n "$CODEX_APP" ]; then
  ok "已经装过 Codex，这次不用下载"
else
  mkdir -p "$CACHE_DIR"
  free_mb=$(df -m "$CACHE_DIR" | awk 'NR == 2 { print $4 }')
  [ "${free_mb:-0}" -ge 3000 ] || fail "硬盘空间不够：装 Codex 需要约 3GB，现在只剩 $((${free_mb:-0} / 1024))GB。清理一些文件后，重新运行这行命令。"
  ok "硬盘可用 $((free_mb / 1024)) GB，够装 Codex"
  race_sources
  ( if download_codex_dmg "$SOURCE_URL" "$SOURCE_NAME" "$SOURCE_FILE"; then echo 0; else echo 1; fi > "$WORK_DIR/dl.rc" ) </dev/null >/dev/null 2>&1 &
  DL_PID=$!
  spin_note() { download_note; }
fi

# ---------- 第 1 段：智谱账号（唯一需要用户动手的一步） ----------
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
  window.title = '登录智谱：用微信扫码';
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
  todo "已在浏览器打开智谱的 API Key 页面："
  todo "① 点「新建 API Key」，名字随便填，点「确定」"
  todo "② 点「复制」，复制后这里会自动继续"
  info "（会先清空剪贴板，用来识别你复制的 Key）"
  local clip waited=0
  pbcopy < /dev/null
  while [ $waited -lt 900 ]; do
    clip=$(pbpaste 2>/dev/null | tr -d '[:space:]')
    if [[ "$clip" =~ $ZHIPU_KEY_PATTERN ]]; then
      pbcopy < /dev/null
      [ -z "$LIVE" ] || printf '\r\033[K' >&2
      echo "$clip"; return 0
    fi
    [ -z "$LIVE" ] || printf '\r\033[K       %s等待复制 API Key  %ds%s%s' "$C_DIM" "$waited" "$(spin_note)" "$C_RESET" >&2
    sleep 1; waited=$((waited + 1))
  done
  return 1
}

# 用这个 Key 依次试智谱免费模型，能用就输出模型名；不能用时最后的 HTTP 状态码留在 $WORK_DIR/status
find_free_model() {
  local key=$1 candidate status
  for candidate in $FREE_MODELS; do
    for _ in 1 2 3; do
      curl -s -o "$WORK_DIR/reply.json" -w '%{http_code}' --max-time 60 \
        -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
        -d "{\"model\":\"$candidate\",\"input\":\"Reply with exactly one word: pong\",\"max_output_tokens\":16}" \
        "$ZHIPU_BASE_URL/responses" </dev/null >"$WORK_DIR/status" 2>/dev/null &
      spin $! "测试智谱免费模型 $candidate" || true
      status=$(cat "$WORK_DIR/status" 2>/dev/null); status=${status:-000}
      # 智谱在 Key 无效时也回 HTTP 200，正文是 {"code":1000,"msg":"身份验证失败。","success":false}
      if [ "$status" = "200" ] && grep -q '"success":false' "$WORK_DIR/reply.json" 2>/dev/null; then
        status=401; printf '%s' "$status" > "$WORK_DIR/status"
      fi
      [ "$status" = "200" ] && { echo "$candidate"; return 0; }
      [ "$status" = "429" ] || break
      sleep 3
    done
  done
  return 1
}

say "登录智谱"
# 以前用这个脚本配好过、Key 还能用：不用再扫码，也不再新建 Key
OLD_KEY=""
if [ -f "$AUTH" ] && grep -Eq '^model_provider = "zhipu"' "$CONFIG" 2>/dev/null; then
  OLD_KEY=$(sed -n 's/^{"OPENAI_API_KEY":"\(.*\)"}$/\1/p' "$AUTH")
fi
MODEL=""
if [ -z "${CODEX_SETUP_ZHIPU_KEY:-}" ] && [[ "$OLD_KEY" =~ $ZHIPU_KEY_PATTERN ]] && MODEL=$(find_free_model "$OLD_KEY"); then
  ZHIPU_API_KEY="$OLD_KEY"
  ok "之前已经登录过智谱，Key 还能用，这次不用扫码"
else
  if [ -n "${CODEX_SETUP_ZHIPU_KEY:-}" ]; then
    ZHIPU_API_KEY="$CODEX_SETUP_ZHIPU_KEY"
    ok "使用环境变量里提供的 Key"
  else
    todo "在弹出的智谱窗口里，用手机微信扫码登录"
    info "第一次用智谱的话，扫码后还要填手机号、收一次验证码"
    [ -n "$CODEX_APP" ] || info "Codex 同时在后台下载，不用等"
    osascript -l JavaScript "$WORK_DIR/zhipu_login.js" </dev/null >"$WORK_DIR/login.txt" 2>/dev/null &
    spin $! "等待扫码登录" || true
    login_outcome=$(tail -1 "$WORK_DIR/login.txt" 2>/dev/null || true)
    if [[ "$login_outcome" =~ $ZHIPU_KEY_PATTERN ]]; then
      ZHIPU_API_KEY="$login_outcome"
      ok "已登录，自动创建好 API Key"
    else
      case "$login_outcome" in
        CANCELLED) info "登录窗口被关闭了，改用手动方式。" ;;
        TIMEOUT)   info "等待登录超时，改用手动方式。" ;;
        *)         info "自动创建没成功（${login_outcome#ERROR:}），改用手动方式。" ;;
      esac
      ZHIPU_API_KEY=$(zhipu_key_by_clipboard) || fail "15 分钟内没有读到 API Key。"
      ok "已读到 API Key"
    fi
  fi
  [[ "$ZHIPU_API_KEY" =~ $ZHIPU_KEY_PATTERN ]] || fail "API Key 格式不对。"
  MODEL=$(find_free_model "$ZHIPU_API_KEY") || fail "智谱免费模型暂时不可用（HTTP $(cat "$WORK_DIR/status" 2>/dev/null)），请稍后重新运行这行命令。"
fi
ok "智谱免费模型可以用：$MODEL"

# ---------- 第 2 段：下载并安装 Codex ----------
say "安装 Codex"
if [ -n "$CODEX_APP" ]; then
  ok "已经装过 Codex，跳过"
else
  spin_note() { :; }
  if [ -n "$LIVE" ] && kill -0 "$DL_PID" 2>/dev/null; then
    ( while [ ! -f "$WORK_DIR/dl.info" ] && kill -0 "$DL_PID" 2>/dev/null; do sleep 0.3; done ) </dev/null &
    spin $! "连接${SOURCE_NAME}" || true
    if [ -f "$WORK_DIR/dl.info" ]; then
      info "下载 Codex（${SOURCE_NAME}，约 800MB；中断后重新运行会接着下）"
      draw_progress "$DL_PID" "$(sed -n 2p "$WORK_DIR/dl.info")" "$(sed -n 3p "$WORK_DIR/dl.info")"
    fi
  fi
  wait "$DL_PID" 2>/dev/null || true
  DL_PID=""
  [ "$(cat "$WORK_DIR/dl.rc" 2>/dev/null)" = 0 ] || fail "Codex 下载失败。检查网络后重新运行这行命令，已经下载的部分会接着下。"
  DMG=$(sed -n 2p "$WORK_DIR/dl.info")
  ok "下载完成（$(mb "$(file_size "$DMG")") MB）"
  install_codex_app "$DMG"
  rm -f "$DMG" "$DMG.etag"
  CODEX_APP=$(find_codex_app) || fail "安装后没找到 Codex App。"
  ok "Codex 已装好"
fi

# ---------- 第 3 段：写配置、试一句、打开 ----------
# 只改 model、model_provider 和 [model_providers.zhipu]，其余配置原样保留；内容有变化时才备份原文件
say "配置并打开 Codex"
mkdir -p "$CODEX_HOME"
BACKUP_SUFFIX=".bak-$(date +%Y%m%d%H%M%S)"
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
( umask 077; printf '{"OPENAI_API_KEY":"%s"}\n' "$ZHIPU_API_KEY" > "$WORK_DIR/auth.json" )
BACKED_UP=""
for pair in "config.toml:$CONFIG" "auth.json:$AUTH"; do
  new="$WORK_DIR/${pair%%:*}"; dest="${pair#*:}"
  cmp -s "$new" "$dest" && continue
  if [ -f "$dest" ]; then cp "$dest" "$dest$BACKUP_SUFFIX"; BACKED_UP=1; fi
  mv "$new" "$dest"
done
chmod 600 "$AUTH"
ok "已写入 $(short_path "$CONFIG")"
[ -z "$BACKED_UP" ] || info "原来的配置已备份为 *${BACKUP_SUFFIX}"

# 新 Mac 没有苹果的「命令行开发者工具」，Codex 第一次启动会触发系统弹窗；先说清楚，再由这里弹出
if ! xcode-select -p >/dev/null 2>&1; then
  todo "系统会弹窗问要不要安装「命令行开发者工具」：这是苹果官方组件，Codex 要用到，点「安装」就行"
  info "它自己在后台装，不影响现在用 Codex"
  xcode-select --install >/dev/null 2>&1 || true
fi

CODEX_CLI="$CODEX_APP/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
if [ -x "$CODEX_CLI" ]; then
  # Mac 没有 timeout 命令：后台运行，最多等 120 秒
  ( cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" "$CODEX_CLI" exec --ephemeral --skip-git-repo-check "只回复两个字：好了" < /dev/null > "$WORK_DIR/verify.txt" 2>/dev/null ) &
  verify_pid=$!
  ( sleep 120; pkill -P "$verify_pid" 2>/dev/null; kill "$verify_pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  watchdog_pid=$!
  spin "$verify_pid" "让 Codex 回一句话" || true
  pkill -P "$watchdog_pid" 2>/dev/null || true
  reply=$(tail -1 "$WORK_DIR/verify.txt" 2>/dev/null || true)
  if [ -n "$reply" ]; then ok "Codex 回复：$reply"; else info "Codex 没有回复，打开后可以直接试用"; fi
fi
[ -n "${CODEX_SETUP_NO_OPEN:-}" ] || open "$CODEX_APP"
done_line "Codex 已经打开，用的是智谱免费模型 ${C_BOLD}${MODEL}${C_RESET}"

# ---------- 点亮 humanslive.ai/tools 上的这个工具 ----------
# HL_TOKEN 来自安装页上复制的命令（网站签名，7 天有效）；没有就跳过，请求失败也不影响安装结果。
if [ -n "${HL_TOKEN:-}" ]; then
  curl -fsS --max-time 6 -X POST -H 'Content-Type: application/json' -d "{\"token\":\"${HL_TOKEN}\"}" \
    https://humanslive.ai/api/tools/progress/claim >/dev/null 2>&1 || true
fi

# ---------- 结尾：HumansLive 的其他免费工具和商城 ----------
# 内容和排版来自网站（每行 kind<TAB>a<TAB>b），这里只按 kind 上色；拿不到就只打一行网址，不影响安装结果。
show_banner() {
  local banner kind a b reset="" dim="" bold="" blue="" link=""
  banner=$(curl -fsS --max-time 6 "https://humanslive.ai/api/install-banner?f=$1&w=$(term_cols)" 2>/dev/null | tr -d '\033\r') || banner=""
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
printf '\n  %s装好了，可以关掉这个终端窗口。%s\n\n' "$C_BOLD" "$C_RESET" >&2
