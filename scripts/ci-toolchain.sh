#!/usr/bin/env bash
# Install the rolling Sun compiler with the standard libraries in its package.
set -euo pipefail
cd "$(dirname "$0")/.."
prefix="$PWD/.ci/toolchain"
release=https://github.com/namo-robotics/sun/releases/download/dev
mkdir -p "$prefix"
download=$(mktemp -d)
trap 'rm -rf "$download"' EXIT

case "$(uname -s):$(uname -m)" in
  Linux:x86_64)
    curl --fail --location --retry 3 "$release/sun_0.dev_amd64.deb" -o "$download/sun.deb"
    dpkg-deb -x "$download/sun.deb" "$download/package"
    cp -R "$download/package/usr/." "$prefix/"
    ;;
  Darwin:arm64)
    curl --fail --location --retry 3 "$release/sun-0.dev-arm64-apple-darwin.tar.gz" -o "$download/sun.tar.gz"
    tar -xzf "$download/sun.tar.gz" -C "$prefix"
    ;;
  *) echo 'Build Linux ARM64 packages using the x86_64 cross compiler.' >&2; exit 1 ;;
esac
"$prefix/bin/sun" --version
