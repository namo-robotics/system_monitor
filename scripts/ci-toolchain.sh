#!/usr/bin/env bash
# Install the latest rolling Sun compiler and matching standard libraries.
set -euo pipefail
cd "$(dirname "$0")/.."
prefix="$PWD/.ci/toolchain"
release=https://github.com/namo-robotics/sun/releases/download/dev
mkdir -p "$prefix"
download=$(mktemp -d)
trap 'rm -rf "$download"' EXIT

case "$(uname -s):$(uname -m)" in
  Linux:x86_64)
    native=x86_64-linux-gnu
    targets=("$native" aarch64-linux-gnu)
    curl --fail --location --retry 3 "$release/sun_0.dev_amd64.deb" -o "$download/sun.deb"
    dpkg-deb -x "$download/sun.deb" "$download/package"
    cp -R "$download/package/usr/." "$prefix/"
    ;;
  Darwin:arm64)
    native=arm64-apple-darwin
    targets=("$native")
    curl --fail --location --retry 3 "$release/sun-0.dev-arm64-apple-darwin.tar.gz" -o "$download/sun.tar.gz"
    tar -xzf "$download/sun.tar.gz" -C "$prefix"
    ;;
  *) echo 'Build Linux ARM64 packages using the x86_64 cross compiler.' >&2; exit 1 ;;
esac
for target in "${targets[@]}"; do
  mkdir -p "$prefix/lib/sun/$target"
  curl --fail --location --retry 3 "$release/stdlib-$target.moon" \
    -o "$prefix/lib/sun/$target/stdlib.moon"
done
cp "$prefix/lib/sun/$native/stdlib.moon" "$prefix/lib/sun/stdlib.moon"
"$prefix/bin/sun" --version
