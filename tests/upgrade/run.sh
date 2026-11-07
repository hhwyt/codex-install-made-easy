#!/usr/bin/env bash
# Upgrade/downgrade regression test of the Windows Chinese launcher, driven from a Mac over SSH.
#
#   tests/upgrade/run.sh [OLD_VERSION [NEW_VERSION]]
#
# Versions come from the private package archive (default: its two newest; with only one, OLD = NEW tests the
# harness alone). The test PC must be logged in to its desktop. Results land in tests/upgrade/results/<time>/.
set -euo pipefail

HOST="${HWY_PC:-hwy-pc}"
ARCHIVE="${CODEX_APP_ARCHIVE:-hhwyt/codex-app-archive}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
REMOTE='hl-upgrade'                 # under the PC user's home
WINDOWS_HOME="$(ssh "$HOST" 'echo $env:USERPROFILE' | tr -d '\r')"
STAMP="$(date +%Y%m%d-%H%M%S)"

package_name() { echo "OpenAI.Codex_${1}_x64__2p2nqsd0c76g0.msix"; }
ps() { ssh "$HOST" "$1" | tr -d '\r'; }   # the PC's SSH shell is PowerShell

versions="$(gh release list --repo "$ARCHIVE" --limit 100 --json tagName --jq '.[].tagName' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n)"
[ -n "$versions" ] || { echo "no packages in $ARCHIVE" >&2; exit 1; }
NEW="${2:-$(echo "$versions" | tail -1)}"
OLD="${1:-$(echo "$versions" | tail -2 | head -1)}"
echo "▸ Codex $OLD → $NEW on $HOST"

# Each package once on the PC; fetched from the archive when it is not there yet
for version in "$OLD" "$NEW"; do
  name="$(package_name "$version")"
  if [ "$(ps "Test-Path '$REMOTE\\packages\\$name'")" != "True" ]; then
    echo "  copying $name to $HOST"
    tmp="$(mktemp -d)"
    gh release download "v$version" --repo "$ARCHIVE" --pattern "$name" --dir "$tmp"
    ssh "$HOST" "New-Item -ItemType Directory -Force $REMOTE\\packages | Out-Null"
    scp -q "$tmp/$name" "$HOST:$REMOTE/packages/$name"
    rm -rf "$tmp"
  fi
done

# The scripts under test, fresh every run
ssh "$HOST" "New-Item -ItemType Directory -Force $REMOTE\\fe3 | Out-Null"
scp -q "$HERE"/*.ps1 "$ROOT/codex.ps1" "$HOST:$REMOTE/"
scp -q "$HERE"/fe3/*.xml "$HOST:$REMOTE/fe3/"

out="$WINDOWS_HOME\\$REMOTE\\results\\$STAMP"
ssh "$HOST" "powershell -NoProfile -ExecutionPolicy Bypass -File $REMOTE\\start-test.ps1 -Old '$WINDOWS_HOME\\$REMOTE\\packages\\$(package_name "$OLD")' -New '$WINDOWS_HOME\\$REMOTE\\packages\\$(package_name "$NEW")' -Out '$out'"

# Poll the progress file until result.json shows up (a full run takes about 10 minutes)
seen=0
for _ in $(seq 1 360); do
  sleep 5
  progress="$(ps "Get-Content -LiteralPath '$out\\progress.txt' -Encoding UTF8 -ErrorAction SilentlyContinue")" || true
  lines="$(printf '%s\n' "$progress" | grep -c . || true)"
  if [ "$lines" -gt "$seen" ]; then printf '%s\n' "$progress" | tail -n +"$((seen + 1))" | sed 's/^/  /'; seen="$lines"; fi
  if printf '%s\n' "$progress" | grep -q '  done$'; then break; fi
done

local_out="$HERE/results/$STAMP"
mkdir -p "$local_out"
scp -q -r "$HOST:$REMOTE/results/$STAMP/*" "$local_out/" || true
[ -f "$local_out/result.json" ] || { echo "✗ no result.json (timed out); partial output in $local_out" >&2; exit 1; }
python3 -I - "$local_out/result.json" <<'EOF'
import json, sys
steps = json.load(open(sys.argv[1], encoding='utf-8-sig'))
steps = steps if isinstance(steps, list) else [steps]
failed = [s for s in steps if s['status'] != 'pass']
for s in steps:
    print(f"  {'✓' if s['status'] == 'pass' else '✗'} {s['step']:<34} {s['version']:<16} {s['seconds']:>4}s  {s['detail']}")
print(f"{'✓ all passed' if not failed else '✗ %d failed' % len(failed)} — {sys.argv[1].rsplit('/', 1)[0]}")
sys.exit(1 if failed else 0)
EOF
