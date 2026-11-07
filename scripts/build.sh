#!/usr/bin/env bash
# Build the monitor and tests, verify static linkage, and name release archives.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${SUN_BIN:-}" ]]; then
  if [[ -x "$PWD/.ci/toolchain/bin/sun" ]]; then
    SUN_BIN="$PWD/.ci/toolchain/bin/sun"
  else
    SUN_BIN=sun
  fi
fi
export SUN_DEPENDENCY_CACHE=${SUN_DEPENDENCY_CACHE:-"$PWD/.ci/dependency-cache"}
link_flags=()
host_os=$(uname -s)
if [[ "$host_os" == Darwin ]]; then
  package_target=${SUN_TARGET:-arm64-apple-darwin}
  link_flags+=(--dynamic -lproc)
else
  package_target=${SUN_TARGET:-$(uname -m)-linux-gnu}
  arch=${package_target%%-*}
  export PATH="$PWD/.ci/musl/$arch-linux-musl-cross/bin:$PATH"
  export SUN_CC="$arch-linux-musl-gcc"
  command -v "$SUN_CC" >/dev/null || {
    echo "Missing musl toolchain. Run bash scripts/setup-musl.sh $arch." >&2
    exit 1
  }
  link_flags+=(--static)
  if [[ "$arch" == x86_64 ]]; then
    link_flags+=(--path-var "MUSL_LIB=$PWD/.ci/musl/$arch-linux-musl-cross/$arch-linux-musl/lib")
  fi
fi
if [[ -n "${SUN_TARGET:-}" ]]; then
  link_flags+=(--target "$SUN_TARGET")
fi
mkdir -p build
compiler=$(command -v "$SUN_BIN")
library=${SUN_LIB_ROOT:-$(dirname "$compiler")/../lib/sun}
cp "$library/${SUN_TARGET:+$SUN_TARGET/}stdlib.moon" build/stdlib.moon
"$SUN_BIN" build --config sun-config.json "${link_flags[@]}"
"$SUN_BIN" build --config sun-config.json --entrypoint acceptance "${link_flags[@]}"
build_root=$("$SUN_BIN" describe --config sun-config.json "${link_flags[@]}" --field build_root)
if [[ "$host_os" == Linux ]]; then
  for binary in "$build_root/system_monitor" "$build_root/system_monitor_test" "$build_root/acceptance"; do
    headers=$("$arch-linux-musl-readelf" -wN -lW -dW "$binary")
    if [[ "$headers" == *INTERP* || "$headers" == *NEEDED* ]]; then
      echo "Expected a fully static binary: $binary" >&2
      exit 1
    fi
  done
fi

# Stage executables at the paths used by native tests and CI artifact uploads.
cp "$build_root/system_monitor" "$build_root/system_monitor_test" \
  "$build_root/acceptance" build/

# Stage Sun's package under the release scripts' public filename.
compiler_archive="$build_root/packages/system_monitor.tar.gz"
package_archive="dist/system_monitor-$package_target.tar.gz"
if [[ ! -f "$compiler_archive" ]]; then
  echo "Sun did not produce the expected package: $compiler_archive" >&2
  echo "Available archives:" >&2
  if [[ -d "$build_root/packages" ]]; then
    find "$build_root/packages" -maxdepth 1 -name '*.tar.gz' -print >&2
  fi
  exit 1
fi
mkdir -p dist
cp "$compiler_archive" "$package_archive"
