#!/usr/bin/env bash
# Smoke-test Sun's native package and give it its public release filename.
set -euo pipefail
cd "$(dirname "$0")/.."
version=${1:?Usage: package.sh VERSION TARGET COMMIT_SHA}
target=${2:?Missing target}
revision=${3:?Missing commit SHA}
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$revision" =~ ^[0-9a-f]{40}$ ]] || exit 1
case "$(uname -s):$(uname -m):$target" in
  Linux:x86_64:linux-x86_64) triple=x86_64-linux-gnu ;;
  Linux:aarch64:linux-arm64|Linux:arm64:linux-arm64) triple=aarch64-linux-gnu ;;
  Darwin:arm64:macos-arm64) triple=arm64-apple-darwin ;;
  *) echo 'Packages must be tested on their native architecture.' >&2; exit 1 ;;
esac
root=$PWD
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf '%s\n' bin/system_monitor package.json share/system_monitor/dashboard.html > "$work/expected-files"
tar -tzf "dist/system_monitor-$triple.tar.gz" | LC_ALL=C sort > "$work/actual-files"
diff -u "$work/expected-files" "$work/actual-files"
tar -xzf "dist/system_monitor-$triple.tar.gz" -C "$work"
test -f "$work/package.json"
cmp assets/dashboard.html "$work/share/system_monitor/dashboard.html"
# Run outside the checkout, with only the package's resource tree available.
(
  cd "$work"
  [[ "$(bin/system_monitor --version)" == "system_monitor $revision" ]]
  bin/system_monitor --help >/dev/null
  bin/system_monitor --samples 2 --interval .1 --top 1 >/dev/null
  PM_BIN="$work/bin/system_monitor" PM_DASHBOARD="$work/share/system_monitor/dashboard.html" \
    "$root/build/acceptance" --package
)
archive="system_monitor-$version-$target.tar.gz"
mkdir -p dist/release
cp "dist/system_monitor-$triple.tar.gz" "dist/release/$archive"
(cd dist/release; if command -v sha256sum >/dev/null; then sha256sum "$archive"; else shasum -a 256 "$archive"; fi) > "dist/release/$archive.sha256"
