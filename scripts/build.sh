#!/usr/bin/env bash
# Build the monitor with the latest installed Sun compiler.
set -euo pipefail
cd "$(dirname "$0")/.."
SUN_BIN=${SUN_BIN:-sun}
link_flags=()
if [[ $(uname -s) == Darwin ]]; then
  link_flags+=(--dynamic -lproc)
else
  target=${SUN_TARGET:-$(uname -m)}
  arch=${target%%-*}
  export PATH="$PWD/.ci/musl/$arch-linux-musl-cross/bin:$PATH"
  export SUN_CC="$arch-linux-musl-gcc"
  command -v "$SUN_CC" >/dev/null || {
    echo "Missing musl toolchain. Run bash scripts/setup-musl.sh $arch." >&2
    exit 1
  }
  link_flags+=(--static)
fi
if [[ -n "${SUN_TARGET:-}" ]]; then
  link_flags+=(--target "$SUN_TARGET")
fi
mkdir -p build
compiler=$(command -v "$SUN_BIN")
library=${SUN_LIB_ROOT:-$(dirname "$compiler")/../lib/sun}
if [[ -n "${SUN_TARGET:-}" ]]; then
  cp "$library/$SUN_TARGET/stdlib.moon" build/stdlib.moon
else
  cp "$library/stdlib.moon" build/stdlib.moon
fi
bash scripts/build-version.sh
bash scripts/build-web.sh
"$SUN_BIN" -c sun-config.json "${link_flags[@]}"
if [[ $(uname -s) == Linux ]]; then
  for binary in build/system_monitor build/system_monitor_test build/acceptance; do
    headers=$("$arch-linux-musl-readelf" -wN -lW -dW "$binary")
    if [[ "$headers" == *INTERP* || "$headers" == *NEEDED* ]]; then
      echo "Expected a fully static binary: $binary" >&2
      exit 1
    fi
  done
fi

# Normalize LLVM's canonical triples to the release scripts' public filenames.
if [[ $(uname -s) == Darwin ]]; then
  package_target=${SUN_TARGET:-arm64-apple-darwin}
  canonical_target=aarch64-apple-darwin
else
  package_target=${SUN_TARGET:-$(uname -m)-linux-gnu}
  canonical_target="${package_target%%-*}-unknown-linux-gnu"
fi
canonical_archive="dist/system_monitor-$canonical_target.tar.gz"
package_archive="dist/system_monitor-$package_target.tar.gz"
if [[ "$canonical_archive" != "$package_archive" && -f "$canonical_archive" ]]; then
  cp "$canonical_archive" "$package_archive"
fi
test -f "$package_archive"
