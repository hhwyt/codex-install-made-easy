#!/usr/bin/env bash
# Daily job (a LaunchAgent on the Mac, see README): when the Microsoft Store has a Codex App version the private archive
# does not have yet, keep it as a release of the archive, then run the upgrade test from the previous archived version
# to it. Exits 0 without doing anything when there is no new version.
#
# The PC asks the Store for the link (its endpoint uses a Microsoft root only Windows trusts) and checks the signature;
# the Mac downloads, because the test PC's link to the Store CDN stalls (IPv6 ~0.1 MB/s, IPv4 sometimes stuck).
set -euo pipefail

HOST="${HWY_PC:-hwy-pc}"
ARCHIVE="${CODEX_APP_ARCHIVE:-hhwyt/codex-app-archive}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REMOTE='hl-upgrade'

notify() { osascript -e "display notification \"$1\" with title \"Codex 升级回归测试\"" 2>/dev/null || true; }

ssh "$HOST" "New-Item -ItemType Directory -Force $REMOTE\\fe3 | Out-Null"
scp -q "$HERE/store-links.ps1" "$HERE/verify-msix.ps1" "$HOST:$REMOTE/"
scp -q "$HERE"/fe3/*.xml "$HOST:$REMOTE/fe3/"

# The Store's current x64 package: "<name> <url>"
link="$(ssh "$HOST" "powershell -NoProfile -ExecutionPolicy Bypass -File $REMOTE\\store-links.ps1" | tr -d '\r' | grep '_x64_' | head -1)"
package="${link%% *}"; url="${link#* }"
version="$(echo "$package" | sed -nE 's/^OpenAI\.Codex_([0-9.]+)_x64__.*/\1/p')"
[ -n "$version" ] || { notify "查不到商店里的 Codex 版本"; echo "no version from the Store: '$link'" >&2; exit 1; }
echo "$(date '+%F %T') Store has Codex $version"
if gh release view "v$version" --repo "$ARCHIVE" >/dev/null 2>&1; then exit 0; fi

name="$package.msix"
# A fixed folder, so a download cut off in one run resumes in the next; the file is removed once it is archived
tmp="$HOME/Library/Caches/codex-app-archive"
mkdir -p "$tmp"
# Resume by hand: curl's own --retry starts over, and the 1 GB download often drops midway
downloaded=no
for _ in $(seq 1 30); do curl -fsSL --connect-timeout 20 -C - -o "$tmp/$name" "$url" && { downloaded=yes; break; }; sleep 5; done
[ "$downloaded" = yes ] || { notify "下载 Codex $version 失败"; exit 1; }
ssh "$HOST" "New-Item -ItemType Directory -Force $REMOTE\\packages | Out-Null"
scp -q "$tmp/$name" "$HOST:$REMOTE/packages/$package.part.msix"
ssh "$HOST" "powershell -NoProfile -ExecutionPolicy Bypass -File $REMOTE\\verify-msix.ps1 -Path $REMOTE\\packages\\$package.part.msix" \
  || { notify "Codex $version 的安装包签名不对，没有存"; exit 1; }
sha="$(shasum -a 256 "$tmp/$name" | cut -d' ' -f1)"
gh release create "v$version" "$tmp/$name" --repo "$ARCHIVE" --title "Codex $version (x64)" \
  --notes "Microsoft Store package, signature checked on Windows (OpenAI's Store publisher, Microsoft CA). sha256 $sha. Archived $(date '+%F')."
echo "archived v$version"
rm -f "$tmp/$name"

if "$HERE/run.sh"; then notify "Codex $version：升级、降级全部通过"; else notify "Codex $version：升级回归测试失败，看 tests/upgrade/results"; exit 1; fi
