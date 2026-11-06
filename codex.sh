#!/bin/bash
# Codex one-command installer (macOS): installs the official Codex app, creates a Zhipu API key after a
# WeChat QR login, and wires Codex to Zhipu's free model.
# Usage: curl -fsSL https://humanslive.ai/codex.sh | bash
# It only: downloads and verifies the official Codex, opens a Zhipu login window, creates one API key,
# writes the config under ~/.codex, and opens Codex.
# Every run writes a log to ~/Library/Logs/HumansLive for debugging. Keys are never logged.
set -euo pipefail

# ---------- Log: one line per step, so a user can send us the file when something fails ----------
LOG_FILE="$HOME/Library/Logs/HumansLive/codex-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${LOG_FILE%/*}" 2>/dev/null || true
log() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*" | sed $'s/\033\\[[0-9;]*m//g' >> "$LOG_FILE" 2>/dev/null || true; }

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
OPENAI_TEAM_ID="2DC432GLL2"
CODEX_BUNDLE_ID="com.openai.codex"
ZHIPU_BASE_URL="${CODEX_SETUP_ZHIPU_BASE_URL:-https://open.bigmodel.cn/api/v1}"
ZHIPU_KEY_PATTERN='^[0-9a-f]{32}\.[A-Za-z0-9]{16}$'
FREE_MODELS="glm-4.7-flash glm-4.5-flash"   # Zhipu now routes 4.5-flash to 4.7-flash; try the newer one first
# Codex's model menu lists OpenAI's GPT models (and suggests switching to them) whatever the provider is, and picking one
# writes it into config.toml; Zhipu has none of them, so every message then fails with "This model isn't available".
# This catalog (codex-models.json in the repository) replaces that list with Zhipu models only
MODEL_CATALOG_URL="https://humanslive.ai/codex-models.json"
WORK_DIR="$(mktemp -d -t codex-setup)"
trap 'rm -rf "$WORK_DIR"' EXIT
cat > "$WORK_DIR/fx.pl" <<'FX'
# Terminal effects, in the perl that ships with macOS. Only called on a real terminal; all output goes to stderr.
#   rain <cols> <rows> <ms>          digital rain, erased when done
#   decode <color> <text>            text decodes out of noise (only ASCII is scrambled; CJK stays as is)
#   race <n> {name tag file pid}...  live download-speed race; prints "<best index> <speed>..." to stdout, index -1 if all failed
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
  # One row = indent 5 + mark 2 + name + 2 + tag + 2 + bar + 2 + speed 10 + "fastest" label 6, plus a 2-column margin
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
  # Prefer the first source (China mirror) unless it is over 30% slower than the fastest: steadier without a proxy
  $best = 0 if $best > 0 && ($speed[0] // 0) * 1.3 >= $bs;
  $draw->(1, $best);
  print STDOUT join(' ', $best, map { int($_ // 0) } @speed), "\n";
}
FX

# ---------- Terminal output ----------
# One accent color (blue), gray for secondary text, red only for errors. No color or animation when stderr is
# not a terminal or NO_COLOR is set.
# All messages go to stderr; stdout is reserved for $(...) captures.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_BLUE=$'\033[38;5;33m' C_RED=$'\033[31m' C_LINK=$'\033[4;38;5;33m'
  LIVE=1
else
  C_RESET="" C_BOLD="" C_DIM="" C_BLUE="" C_RED="" C_LINK="" LIVE=""
fi
STEP=0
# Show the home directory as ~
term_cols() { local cols; cols=$( { stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2); [ "${cols:-0}" -gt 0 ] 2>/dev/null && echo "$cols" || echo 80; }
# Intro: a short digital rain, then the title decodes out of noise (under 1.5 s)
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
# Unnumbered preparation sections (system check, source race)
section() { log "== $1 ${2:-}"; printf '\n  %s▸%s %s%s%s  %s%s%s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" "$C_DIM" "${2:-}" "$C_RESET" >&2; }
say()  { STEP=$((STEP + 1)); log "[$STEP/$STEPS] $*"; printf '\n  %s[%d/%d]%s %s%s%s\n' "$C_BLUE$C_BOLD" "$STEP" "$STEPS" "$C_RESET" "$C_BOLD" "$*" "$C_RESET" >&2; }
info() { log "   $*"; printf '       %s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }
ok()   { log "ok $*"; printf '     %s✓%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
todo() { log "-> $*"; printf '     %s→%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET" >&2; }
done_line() {
  local took="$((SECONDS % 60)) 秒"; [ "$SECONDS" -lt 60 ] || took="$((SECONDS / 60)) 分 $took"
  log "done in $took"
  printf '\n' >&2
  if [ -n "$LIVE" ]; then perl "$WORK_DIR/fx.pl" decode "$C_BLUE$C_BOLD" "✓ ALL SYSTEMS GO · 全部完成"
  else printf '  ✓ ALL SYSTEMS GO · 全部完成\n' >&2; fi
  printf '     %s用时 %s%s\n     %s\n' "$C_DIM" "$took" "$C_RESET" "$*" >&2
}
# After the key is created, tell the user where it lives and who can see it
key_note() {
  printf '       %s🔒%s %s安全说明%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$C_RESET" >&2
  info "这个 Key 是用你自己的智谱账号建的，只保存在你的电脑上，绝对安全"
  info "随时可以在智谱控制台删掉（名字以 Codex- 开头）"
}
# After install: how to open Codex, free-model rate limits and top-ups, stronger models. Usage: next_steps <app>
next_steps() {
  local app_name; app_name=$(basename "$1" .app)
  section "以后怎么打开"
  printf '     「启动台」或「应用程序」里的「%s」就是 Codex  %sOpenAI 把 Codex 并进了 ChatGPT 桌面版%s\n' "$app_name" "$C_DIM" "$C_RESET" >&2
  section "关于免费模型"
  printf '     不扣费，用得太频繁会被限速，等一会儿就恢复\n' >&2
  printf '     %s不想被限速：在智谱充值，再在 Codex 右下角的模型菜单里选「付费」的模型%s\n' "$C_DIM" "$C_RESET" >&2
  printf '     %shttps://bigmodel.cn/finance/pay%s\n' "$C_LINK" "$C_RESET" >&2
  section "想用更强的模型" "我们帮你开通"
  printf '     %sOpenAI 官方 GPT 模型%s\n     %sClaude 模型%s\n' "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET" >&2
  printf '     %s→%s 来社群找我们：%shttps://humanslive.ai/community%s\n' "$C_BLUE" "$C_RESET" "$C_LINK" "$C_RESET" >&2
}
# On failure: say what to do, show the log path and reveal the file in Finder so it is easy to send
show_error() {
  [ -z "$LIVE" ] || printf '\r\033[K' >&2
  printf '\n  %s✗ 出错了%s\n     %s\n     %s日志：%s%s\n     %s需要帮助：把这个日志文件发到社群 https://humanslive.ai/community%s\n\n' \
    "$C_RED$C_BOLD" "$C_RESET" "$*" "$C_DIM" "$LOG_FILE" "$C_RESET" "$C_DIM" "$C_RESET" >&2
  [ -n "${CODEX_SETUP_NO_OPEN:-}" ] || open -R "$LOG_FILE" 2>/dev/null || true
}
FAILED=""
fail() {
  log "FAIL $*"
  FAILED=1
  show_error "$*"
  exit 1
}
# Unexpected errors (set -e stops the script): log the line and command; the EXIT trap shows a short message
trap 'log "ERROR line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# Extra text at the end of the spinner line (e.g. background download progress); empty by default
spin_note() { :; }

# Wait for a background process while showing a spinner and elapsed time; returns its exit code. Usage: spin <pid> <text>
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

# Progress bar: fixed width (fixed-width numbers on the right); speed is averaged over ~2 s so it does not jitter
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
header "CODEX INSTALLER" "Codex 一键安装 · 国产模型版 · 不用科学上网 · 不花一分钱"
printf '  %s→%s 遇到问题来社群找我们：%shttps://humanslive.ai/community%s\n' "$C_BLUE" "$C_RESET" "$C_LINK" "$C_RESET" >&2

APP_DIR="${CODEX_SETUP_APP_DIR:-/Applications}"
CACHE_DIR="${CODEX_SETUP_CACHE_DIR:-$HOME/Library/Caches/HumansLive}"
CONFIG="$CODEX_HOME/config.toml"
AUTH="$CODEX_HOME/auth.json"
DL_PID=""

# On Ctrl+C or error, stop the background download too; the partial file stays in the cache and a rerun resumes it
cleanup() {
  local rc=$?
  if [ -n "$DL_PID" ]; then pkill -P "$DL_PID" 2>/dev/null || true; kill "$DL_PID" 2>/dev/null || true; fi
  rm -rf "$WORK_DIR"
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 130 ] && [ -z "$FAILED" ]; then show_error "安装中途出了意外（退出码 $rc）。"; fi
}
trap cleanup EXIT
trap 'printf "\n\n  已停止。重新运行这行命令会接着之前的进度。\n\n" >&2; exit 130' INT TERM

# ---------- Codex app: if missing, download in the background while the user scans the QR code ----------
find_codex_app() {
  local app
  # APP_DIR is /Applications unless CODEX_SETUP_APP_DIR overrides it (the installer tests use a temp folder)
  for app in "$APP_DIR/Codex.app" "$APP_DIR/ChatGPT.app" "$HOME/Applications/Codex.app" "$HOME/Applications/ChatGPT.app"; do
    if [ -d "$app" ] && [ "$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)" = "$CODEX_BUNDLE_ID" ]; then
      echo "$app"; return 0
    fi
  done
  return 1
}

# Version comparison: version_ge 15.2 14.0 is true
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 } exit 0 }'
}

# Download the chosen source into the cache (resumable). Usage: download_codex_dmg <url> <source name> <file>
# Writes source, file and size to $WORK_DIR/dl.info; the result (0 = success) goes to $WORK_DIR/dl.rc.
download_codex_dmg() {
  local url=$1 name=$2 file=$3 headers total etag size
  headers=$(curl -sIL --connect-timeout 15 --max-time 20 "$url" 2>/dev/null | tr -d '\r')
  total=$(awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }' <<< "$headers")
  etag=$(awk 'tolower($1) == "etag:" { e = $2 } END { print e }' <<< "$headers")
  # A partial file from an older release cannot be resumed; delete it and start over
  if [ -f "$file.etag" ] && [ "$(cat "$file.etag")" != "$etag" ]; then rm -f "$file"; fi
  printf '%s' "$etag" > "$file.etag"
  printf '%s\n%s\n%s\n' "$name" "$file" "$total" > "$WORK_DIR/dl.info"
  size=$(file_size "$file")
  if [ "$total" -gt 0 ] && [ "$size" -gt "$total" ]; then rm -f "$file"; size=0; fi
  if [ "$total" -gt 0 ] && [ "$size" -eq "$total" ]; then return 0; fi
  log "download $name total=$total etag=$etag cached=$size"
  for try in 1 2 3 4 5; do
    curl -fsSL -C - --retry 3 --connect-timeout 15 -o "$file" "$url" && { log "download try $try ok size=$(file_size "$file")"; return 0; }
    log "download try $try failed size=$(file_size "$file")"
    sleep 2
  done
  return 1
}

# Race all download sources for 8 s and pick the fastest. The mirror is served from mainland China, so it is fast
# without a proxy;
# users with a proxy may get the official source faster. The bytes fetched while racing are reused by the real download.
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
  log "race: best=$best speeds=$speeds"
  [ -n "$LIVE" ] || for ((i = 0; i < n; i++)); do info "${names[i]}：$(mb "$(echo $speeds | cut -d' ' -f$((i + 1)))") MB/s"; done
  [ "$best" -ge 0 ] 2>/dev/null || fail "下载线路都连不上。检查网络后重新运行这行命令。"
  SOURCE_URL=${urls[best]}; SOURCE_NAME=${names[best]}; SOURCE_FILE="$CACHE_DIR/Codex-${keys[best]}.dmg"
  # The probe is the start of the file: keep it unless the cache already has more
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

# Background download progress shown after the spinner
download_note() {
  local file total
  if [ "$(cat "$WORK_DIR/dl.rc" 2>/dev/null)" = 0 ]; then printf '  · Codex 已在后台下载好'; return; fi
  [ -f "$WORK_DIR/dl.info" ] || { printf '  · 正在准备下载 Codex'; return; }
  file=$(sed -n 2p "$WORK_DIR/dl.info"); total=$(sed -n 3p "$WORK_DIR/dl.info")
  if [ "${total:-0}" -gt 0 ]; then printf '  · 后台下载 Codex %d%%' $(($(file_size "$file") * 100 / total)); else printf '  · 后台下载 Codex 中'; fi
}

install_codex_app() {
  local dmg=$1 mount_point app_in_dmg team need target name partial
  mount_point=$(hdiutil attach -nobrowse -readonly "$dmg" | tail -1 | awk -F'\t' '{print $NF}')
  app_in_dmg=$(ls -d "$mount_point"/*.app | head -1)
  codesign --verify --deep --strict "$app_in_dmg" </dev/null 2>/dev/null &
  spin $! "核对 OpenAI 官方签名" || {
    hdiutil detach "$mount_point" -quiet; rm -f "$dmg"
    fail "下载的安装包不完整或被改动过，已经删掉。重新运行这行命令即可。"
  }
  team=$(codesign -dv "$app_in_dmg" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  log "codesign team=$team app=$(basename "$app_in_dmg") version=$(defaults read "$app_in_dmg/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)"
  [ "$team" = "$OPENAI_TEAM_ID" ] || { hdiutil detach "$mount_point" -quiet; rm -f "$dmg"; fail "安装包不是 OpenAI 官方签名（${team}），已停止安装。"; }
  ok "已确认是 OpenAI 官方原版"
  need=$(defaults read "$app_in_dmg/Contents/Info.plist" LSMinimumSystemVersion 2>/dev/null || echo 0)
  version_ge "$(sw_vers -productVersion)" "$need" || {
    hdiutil detach "$mount_point" -quiet
    fail "Codex 需要 macOS ${need} 或更新的系统，这台 Mac 是 $(sw_vers -productVersion)。先在「系统设置 → 通用 → 软件更新」里升级，再重新运行这行命令。"
  }
  # Standard (non-admin) accounts cannot write /Applications; fall back to ~/Applications
  target="$APP_DIR"; [ -w "$target" ] || { target="$HOME/Applications"; mkdir -p "$target"; }
  # Copy under a hidden name, then swap it in: an interrupted copy never looks installed, and a rerun starts clean
  name=$(basename "$app_in_dmg"); partial="$target/.$name.installing"
  rm -rf "$partial"
  ditto "$app_in_dmg" "$partial" </dev/null &
  spin $! "安装到「应用程序」文件夹" || { rm -rf "$partial"; hdiutil detach "$mount_point" -quiet; fail "复制到「应用程序」文件夹失败。"; }
  hdiutil detach "$mount_point" -quiet
  # Only ever replace a (broken) Codex: an unrelated app with the same name is the user's, never deleted
  if [ -e "$target/${name:?}" ]; then
    if [ "$(defaults read "$target/$name/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)" != "$CODEX_BUNDLE_ID" ]; then
      rm -rf "$partial"
      fail "「应用程序」文件夹里已经有一个不是 Codex 的 $name。把它拖到废纸篓（或改个名字），再重新运行这行命令。"
    fi
    rm -rf "$target/$name" 2>/dev/null || { rm -rf "$partial"; fail "旧的 $name 删不掉。先把「应用程序」文件夹里的 $name 拖到废纸篓，再重新运行这行命令。"; }
  fi
  mv "$partial" "$target/$name"
  INSTALLED_APP="$target/$name"
  # The broken copy found at the start lived somewhere else: remove it so only the working one is left
  if [ -n "$BROKEN_APP" ] && [ "$BROKEN_APP" != "$target/$name" ] && ! rm -rf "$BROKEN_APP" 2>/dev/null; then
    info "旧的 Codex（${BROKEN_APP}）删不掉，可以自己拖到废纸篓"
  fi
}

# ---------- Preparation: system check, source race, then start the background download ----------
section "系统检测"
if [ "$(uname -m)" = "arm64" ]; then CHIP="Apple 芯片"; else CHIP="Intel 芯片"; fi
log "macOS $(sw_vers -productVersion) build=$(sw_vers -buildVersion) arch=$(uname -m) shell=$BASH_VERSION term=${TERM_PROGRAM:-?} live=${LIVE:-0} proxy=$([ -n "${https_proxy:-${HTTPS_PROXY:-}}" ] && echo 1 || echo 0)"
ok "macOS $(sw_vers -productVersion) · $CHIP"
CODEX_APP=$(find_codex_app || true)
# An install that was interrupted (or a damaged app) still looks installed: check the signature and reinstall if broken
BROKEN_APP="" INSTALLED_APP="" app_ok=""
if [ -n "$CODEX_APP" ]; then
  codesign --verify --deep --strict "$CODEX_APP" </dev/null >/dev/null 2>&1 &
  spin $! "检查已安装的 Codex" && app_ok=1 || app_ok=""
fi
if [ -n "$CODEX_APP" ] && [ -z "$app_ok" ]; then
  log "codex app broken, reinstalling: $CODEX_APP"
  info "上次的 Codex 没装完整，这次重新装"
  BROKEN_APP=$CODEX_APP; CODEX_APP=""
fi
if [ -n "$CODEX_APP" ]; then
  log "codex already installed: $CODEX_APP $(defaults read "$CODEX_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)"
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

# ---------- Step 1: Zhipu account (the only step that needs the user) ----------
# Open a small WebKit window (built into macOS, no browser needed). After the QR login, call the console's own
# "create API key" endpoint from the page. The full key is returned only once and goes straight to this script:
# never displayed, never on the clipboard.
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
  // Page results come back through document.title (the window title is set separately, so it is never shown)
  const evaluate = (code) => { webView.evaluateJavaScriptCompletionHandler(code, (result, error) => {}); };
  const readTitle = () => ObjC.unwrap(webView.title) || '';
  // One create-key request per page: its result is kept in the page (window.__hlResult) until read, so a slow answer is
  // neither sent twice nor overwritten. Only a page reload (which loses the request) leads to another one.
  const READ_STATE = `(() => {
    if (window.__hlResult) {
      const result = window.__hlResult;
      if (result.startsWith('RETRY:')) window.__hlResult = window.__hlCreate = null;
      document.title = result;
      return;
    }
    if (window.__hlCreate) { document.title = 'STATE:creating'; return; }
    const token = (document.cookie.split('; ').find(c => c.startsWith('bigmodel_token_production=')) || '').split('=').slice(1).join('=');
    const ready = Boolean(token && localStorage.getItem('Bigmodel-Organization') && localStorage.getItem('Bigmodel-Project'));
    const onConsole = location.pathname.startsWith('/apikey') || location.pathname.startsWith('/usercenter');
    // Report ready only once we are on a console page: calling the API while the page is navigating
    // makes WebKit cancel the request ("Load failed")
    if (ready && !onConsole) location.href = '/apikey/platform';
    document.title = 'STATE:' + (ready && onConsole ? 'ready' : 'waiting');
  })()`;
  const CREATE_KEY = `(() => {
    if (window.__hlCreate) return;
    window.__hlCreate = (async () => {
      try {
        const token = (document.cookie.split('; ').find(c => c.startsWith('bigmodel_token_production=')) || '').split('=').slice(1).join('=');
        const organization = localStorage.getItem('Bigmodel-Organization');
        const project = localStorage.getItem('Bigmodel-Project');
        const response = await fetch('/api/biz/v1/organization/' + organization + '/projects/' + project + '/api_keys', {
          method: 'POST', credentials: 'include',
          headers: { 'Content-Type': 'application/json', Authorization: token, 'Bigmodel-Organization': organization, 'Bigmodel-Project': project },
          body: JSON.stringify({ name: (() => { const d = new Date(), p = n => String(n).padStart(2, '0'); return 'Codex-' + String(d.getFullYear()).slice(2) + p(d.getMonth() + 1) + p(d.getDate()) + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds()); })(), keyType: 1, usageScene: 2 }),
        }).then(r => r.json());
        window.__hlResult = response.code === 200 && response.data ? 'KEY:' + response.data.apiKey + '.' + response.data.secretKey : 'ERROR:' + (response.msg || response.code);
      } catch (e) { window.__hlResult = 'RETRY:' + e.message; }
      document.title = window.__hlResult;
    })();
  })()`;

  const deadline = Date.now() + 60 * 60 * 1000;
  let outcome = 'TIMEOUT';
  let lastRefresh = Date.now();
  let loadingSince = 0;
  let requests = 0;
  while (Date.now() < deadline) {
    pumpEvents(1.5);
    if (!window.isVisible) { outcome = 'CANCELLED'; break; }
    // Let a navigation finish first, but do not wait forever on a page whose trackers never stop loading
    if (webView.isLoading) { loadingSince = loadingSince || Date.now(); if (Date.now() - loadingSince < 20 * 1000) continue; } else loadingSince = 0;
    evaluate(READ_STATE);
    pumpEvents(0.5);
    const title = readTitle();
    if (title.startsWith('KEY:')) { outcome = title.slice(4); break; }
    if (title.startsWith('ERROR:')) { outcome = title; break; }
    // The request never reached Zhipu (network error, page reloaded mid-request): try again, 3 requests at most
    if (title.startsWith('RETRY:')) { outcome = 'ERROR:' + title.slice(6); if (requests >= 3) break; continue; }
    if (title === 'STATE:creating') continue;
    if (title === 'STATE:ready') {
      if (requests >= 3) { if (outcome === 'TIMEOUT') outcome = 'ERROR:no response'; break; }
      requests++;
      evaluate(CREATE_KEY);
      continue;
    }
    // WeChat QR codes expire within minutes: reload every 4 minutes until the user logs in
    if (!requests && Date.now() - lastRefresh > 4 * 60 * 1000) { webView.reload; lastRefresh = Date.now(); }
  }
  window.orderOut(null);
  return outcome;
}
JXA


# Try each free Zhipu model with this key and print the first that works; the last HTTP status is left in $WORK_DIR/status
find_free_model() {
  local key=$1 candidate status
  # Pass the key through a private header file, not argv, so other local users cannot see it in ps
  ( umask 077; printf 'Authorization: Bearer %s\n' "$key" > "$WORK_DIR/auth.header" )
  for candidate in $FREE_MODELS; do
    for _ in 1 2 3; do
      curl -s -o "$WORK_DIR/reply.json" -w '%{http_code}' --max-time 60 \
        -H @"$WORK_DIR/auth.header" -H 'Content-Type: application/json' \
        -d "{\"model\":\"$candidate\",\"input\":\"Reply with exactly one word: pong\",\"max_output_tokens\":16}" \
        "$ZHIPU_BASE_URL/responses" </dev/null >"$WORK_DIR/status" 2>/dev/null &
      spin $! "测试智谱免费模型 $candidate" || true
      status=$(cat "$WORK_DIR/status" 2>/dev/null); status=${status:-000}
      log "model test $candidate: HTTP $status"
      # Zhipu answers HTTP 200 even for an invalid key, with a body like {"code":1000,...,"success":false}
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
# Already set up by this script and the key still works: no new scan, no new key
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
      log "login outcome: key created"
      ZHIPU_API_KEY="$login_outcome"
      ok "已登录，自动创建好 API Key"
      key_note
    else
      # Like the Windows version, there is no manual copy-the-key fallback: a closed window, no scan or a Zhipu
      # API error all ask the user to rerun, with the reason in the log
      log "login outcome: ${login_outcome:-empty}"
      case "$login_outcome" in
        CANCELLED) fail "智谱登录窗口被关掉了。重新运行这行命令，扫码登录就行。" ;;
        TIMEOUT)   fail "一个小时内没有扫码登录。重新运行这行命令，扫码登录就行。" ;;
        *)         fail "自动创建 API Key 没成功（${login_outcome#ERROR:}），可能是智谱的网站改版了。重新运行这行命令再试一次；还不行的话，把下面的日志发给我们，我们来修。" ;;
      esac
    fi
  fi
  [[ "$ZHIPU_API_KEY" =~ $ZHIPU_KEY_PATTERN ]] || fail "API Key 格式不对。"
  MODEL=$(find_free_model "$ZHIPU_API_KEY") || fail "智谱免费模型暂时不可用（HTTP $(cat "$WORK_DIR/status" 2>/dev/null)），请稍后重新运行这行命令。"
fi
ok "智谱免费模型可以用：$MODEL"

# A running Codex reads its config, key and language only at startup, so quit it before writing; it is reopened at the end
if [ -n "$CODEX_APP" ] && pgrep -qf "$CODEX_APP/Contents/MacOS/"; then
  log "codex app running: quitting before writing the config"
  info "Codex 正开着，先关掉，配置写好后会重新打开"
  osascript -e "tell application id \"$CODEX_BUNDLE_ID\" to quit" </dev/null >/dev/null 2>&1 || true
  for _ in $(seq 20); do pgrep -qf "$CODEX_APP/Contents/MacOS/" || break; sleep 0.5; done
  pkill -9 -f "$CODEX_APP/Contents/MacOS/" 2>/dev/null || true
fi
# ---------- Write the config as soon as the key exists, so a rerun after a later failure needs no new scan ----------
# Only touch model, model_provider and [model_providers.zhipu]; keep everything else. Back up only if content changes.
mkdir -p "$CODEX_HOME"
# The model menu shows only Zhipu models: fetch the catalog (see MODEL_CATALOG_URL); without it, the menu stays as it is
CATALOG="$CODEX_HOME/humanslive-models.json"
CATALOG_LINE=""
if curl -fsS --max-time 20 "$MODEL_CATALOG_URL" -o "$WORK_DIR/catalog.json" 2>/dev/null &&
   grep -q "\"slug\": \"$MODEL\"" "$WORK_DIR/catalog.json"; then
  CATALOG_LINE="model_catalog_json = \"$(printf '%s' "$CATALOG" | sed 's/[\\"]/\\&/g')\""
else
  log "model catalog skipped"
fi
BACKUP_SUFFIX=".bak-$(date +%Y%m%d%H%M%S)"
{
  printf 'model_provider = "zhipu"\nmodel = "%s"\n' "$MODEL"
  [ -z "$CATALOG_LINE" ] || printf '%s\n' "$CATALOG_LINE"
  kept=""
  if [ -f "$CONFIG" ]; then
    # Drop top-level model / model_provider (before the first table) and the whole old [model_providers.zhipu] table.
    # Blank lines left at the start and end are dropped (the parts this script adds bring their own), so a rerun
    # writes the same bytes; everything in between, including multi-line strings, stays exactly as the user wrote it.
    kept=$(awk '
      { line = $0; sub(/\r$/, "", line) }
      /^\[/ { in_table = 1; skip = (line == "[model_providers.zhipu]") }
      !in_table && /^[[:space:]]*(model|model_provider|model_catalog_json)[[:space:]]*=/ { next }
      skip { next }
      /^[[:space:]]*$/ { if (printed) blanks = blanks $0 "\n"; next }
      { printf "%s", blanks; blanks = ""; print; printed = 1 }
    ' "$CONFIG")
  fi
  [ -z "$kept" ] || printf '\n%s\n' "$kept"
} > "$WORK_DIR/config.toml"
# Codex follows the system language by default; force Simplified Chinese on every run (the Language setting, stored
# under [desktop]): replace any other value in place, so an already-Chinese config stays byte-identical
awk '
  /^\[/ { in_desktop = ($0 ~ /^\[desktop\][ \t]*\r?$/); seen = seen || in_desktop }
  in_desktop && /^[[:space:]]*localeOverride[[:space:]]*=/ { eol = ($0 ~ /\r$/) ? "\r" : ""; $0 = "localeOverride = \"zh-CN\"" eol; found = 1 }
  { print }
  END { exit found ? 0 : seen ? 2 : 3 }
' "$WORK_DIR/config.toml" > "$WORK_DIR/config.toml.new" && locale_status=0 || locale_status=$?
mv "$WORK_DIR/config.toml.new" "$WORK_DIR/config.toml"
case "$locale_status" in
  2) # Match the line ending of the [desktop] line (files edited on Windows use CRLF) instead of mixing them
     awk '{ print } /^\[desktop\][ \t]*\r?$/ && !done { eol = ($0 ~ /\r$/) ? "\r" : ""; print "localeOverride = \"zh-CN\"" eol; done = 1 }' "$WORK_DIR/config.toml" > "$WORK_DIR/config.toml.new"
     mv "$WORK_DIR/config.toml.new" "$WORK_DIR/config.toml" ;;
  3) if grep -q $'\r$' "$WORK_DIR/config.toml"; then
       printf '\r\n[desktop]\r\nlocaleOverride = "zh-CN"\r\n' >> "$WORK_DIR/config.toml"
     else
       printf '\n[desktop]\nlocaleOverride = "zh-CN"\n' >> "$WORK_DIR/config.toml"
     fi ;;
esac
printf '\n[model_providers.zhipu]\nname = "智谱 GLM"\nbase_url = "%s"\nwire_api = "responses"\nrequires_openai_auth = true\n' "$ZHIPU_BASE_URL" >> "$WORK_DIR/config.toml"
( umask 077; printf '{"OPENAI_API_KEY":"%s"}\n' "$ZHIPU_API_KEY" > "$WORK_DIR/auth.json" )
BACKED_UP=""
for pair in "config.toml:$CONFIG" "auth.json:$AUTH"; do
  new="$WORK_DIR/${pair%%:*}"; dest="${pair#*:}"
  cmp -s "$new" "$dest" && continue
  if [ -f "$dest" ]; then cp "$dest" "$dest$BACKUP_SUFFIX"; BACKED_UP=1; fi
  mv "$new" "$dest"
done
chmod 600 "$AUTH"
[ -z "$CATALOG_LINE" ] || mv "$WORK_DIR/catalog.json" "$CATALOG"
log "config written: $CONFIG"
ok "已把 Key 和模型写进 Codex 的配置"
[ -z "$BACKED_UP" ] || info "原来的配置已备份为 *${BACKUP_SUFFIX}"
# Menu items macOS adds itself (Edit > AutoFill / Start Dictation, Window > Fill / Enter Full Screen…) and system panels
# follow the app's AppleLanguages, not localeOverride, so on a non-Chinese system they stay English without this
if [ "$(defaults read "$CODEX_BUNDLE_ID" AppleLanguages 2>/dev/null | tr -d ' \n')" != '("zh-Hans")' ]; then
  defaults write "$CODEX_BUNDLE_ID" AppleLanguages -array zh-Hans
  log "AppleLanguages set: $CODEX_BUNDLE_ID"
fi


# ---------- Step 2: download and install Codex ----------
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
  # Use the copy just installed (a broken one that could not be removed may still come first in find_codex_app)
  CODEX_APP=$INSTALLED_APP
  ok "Codex 已装好"
fi

# ---------- Step 3: smoke test, then open ----------
say "打开 Codex"
# A fresh Mac lacks the Command Line Developer Tools and Codex would trigger the system prompt on first launch;
# explain it first, then trigger it here
if ! xcode-select -p >/dev/null 2>&1; then
  todo "系统会弹窗问要不要安装「命令行开发者工具」：这是苹果官方组件，Codex 要用到，点「安装」就行"
  info "它自己在后台装，不影响现在用 Codex"
  xcode-select --install >/dev/null 2>&1 || true
fi

CODEX_CLI="$CODEX_APP/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
if [ -x "$CODEX_CLI" ]; then
  # macOS has no timeout(1): run in the background and give up after 120 s. If Codex rejects the model catalog (it
  # then ignores the whole config), drop the catalog and ask again
  for attempt in 1 2; do
    ( cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" "$CODEX_CLI" exec --ephemeral --skip-git-repo-check "只回复两个字：好了" < /dev/null > "$WORK_DIR/verify.txt" 2>"$WORK_DIR/verify-err.txt" ) &
    verify_pid=$!
    ( sleep 120; pkill -P "$verify_pid" 2>/dev/null; kill "$verify_pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
    watchdog_pid=$!
    spin "$verify_pid" "让 Codex 回一句话" || true
    pkill -P "$watchdog_pid" 2>/dev/null || true
    reply=$(tail -1 "$WORK_DIR/verify.txt" 2>/dev/null || true)
    log "verify reply: $reply"
    if [ -n "$reply" ] || [ -z "$CATALOG_LINE" ] || ! grep -q model_catalog_json "$WORK_DIR/verify-err.txt" 2>/dev/null; then break; fi
    log "model catalog rejected: $(grep -m1 model_catalog_json "$WORK_DIR/verify-err.txt")"
    grep -vxF "$CATALOG_LINE" "$CONFIG" > "$WORK_DIR/config.toml.new" || true
    mv "$WORK_DIR/config.toml.new" "$CONFIG"
    rm -f "$CATALOG"; CATALOG_LINE=""
  done
  if [ -n "$reply" ]; then ok "Codex 回复：$reply"; else info "Codex 没有回复，打开后可以直接试用"; fi
fi
[ -n "${CODEX_SETUP_NO_OPEN:-}" ] || open "$CODEX_APP"
done_line "Codex 已经打开，用的是智谱免费模型 ${C_BOLD}${MODEL}${C_RESET}"
next_steps "$CODEX_APP"

# ---------- Closing banner: other free HumansLive tools ----------
# Content and layout come from the website (one kind<TAB>a<TAB>b per line); this only colors by kind.
# If it cannot be fetched, print one URL instead; the install result is unaffected.
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
