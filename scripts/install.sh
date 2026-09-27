#!/usr/bin/env bash
# Install the latest published Sun package after verifying its release checksum.
set -euo pipefail

# Select the archive matching the current operating system and CPU architecture.
case "$(uname -s):$(uname -m)" in
  Linux:x86_64) target=linux-x86_64 ;;
  Linux:aarch64|Linux:arm64) target=linux-arm64 ;;
  Darwin:arm64) target=macos-arm64 ;;
  *) echo 'Supported targets: Linux x86_64/ARM64 and Apple Silicon macOS.' >&2; exit 1 ;;
esac

# Prefer a stable release and use the development build when none exists.
repository=https://github.com/namo-robotics/system_monitor
response=$(curl --silent --show-error --location --output /dev/null --write-out '%{http_code} %{url_effective}' "$repository/releases/latest")
status=${response%% *}
release_url=${response#* }
if [[ "$status" == 404 || ( "$status" == 200 && "$release_url" == "$repository/releases" ) ]]; then
  version=dev
elif [[ "$status" == 200 ]]; then
  version=${release_url##*/}
else
  echo "Could not resolve the latest release (HTTP $status)." >&2
  exit 1
fi
if [[ "$version" != dev && ! "$version" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then
  echo 'No supported published release was found.' >&2
  exit 1
fi
archive="system_monitor-$version-$target.tar.gz"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl --fail --silent --show-error --location "$repository/releases/download/$version/$archive" -o "$work/$archive"
curl --fail --silent --show-error --location "$repository/releases/download/$version/SHA256SUMS" -o "$work/SHA256SUMS"

# Verify just the selected archive using the checksum utility available on the host.
expected=$(awk -v name="$archive" '$2 == name {print $1}' "$work/SHA256SUMS")
if command -v sha256sum >/dev/null; then
  actual=$(sha256sum "$work/$archive")
else
  actual=$(shasum -a 256 "$work/$archive")
fi
if [[ ! "$expected" =~ ^[0-9a-f]{64}$ || "${actual%% *}" != "$expected" ]]; then
  echo 'Release checksum verification failed.' >&2
  exit 1
fi

# Keep the complete package together so resource lookup survives relocation.
prefix="${PREFIX:-$HOME/.local}"
mkdir -p "$prefix/bin" "$prefix/lib/system_monitor"
prefix=$(cd "$prefix" && pwd)
[[ ! -d "$prefix/bin/system_monitor" ]] || { echo "The executable path is a directory." >&2; exit 1; }
payload=$(mktemp -d "$prefix/lib/system_monitor/$version-$target.XXXXXX")
link=''
trap 'rm -rf "$work"; if [[ -n "$payload" ]]; then rm -rf "$payload"; fi; if [[ -n "$link" ]]; then rm -f "$link"; fi' EXIT
tar -xzf "$work/$archive" -C "$payload"
test -x "$payload/bin/system_monitor"
test -f "$payload/share/system_monitor/dashboard.html"
test -f "$payload/package.json"
"$payload/bin/system_monitor" --version
link=$(mktemp "$prefix/bin/.system_monitor.XXXXXX")
ln -sf "$payload/bin/system_monitor" "$link"
mv -f "$link" "$prefix/bin/system_monitor"
payload=''
link=''
printf 'Installed %s\nRun: %s/bin/system_monitor\n' "$version" "$prefix"
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) printf 'Add to your shell PATH: export PATH="%s/bin:$PATH"\n' "$prefix" ;;
esac
