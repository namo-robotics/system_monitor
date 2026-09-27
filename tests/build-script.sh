#!/usr/bin/env bash
# Exercise platform archive naming without requiring each platform's compiler.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/scripts" "$work/bin" "$work/toolchain/bin" "$work/toolchain/lib/sun/aarch64-linux-gnu"
cp "$root/scripts/build.sh" "$work/scripts/build.sh"
printf ':\n' > "$work/scripts/build-version.sh"
printf ':\n' > "$work/scripts/build-web.sh"
printf 'fixture\n' > "$work/toolchain/lib/sun/stdlib.moon"
cp "$work/toolchain/lib/sun/stdlib.moon" "$work/toolchain/lib/sun/aarch64-linux-gnu/stdlib.moon"
cat > "$work/bin/uname" <<'SH'
#!/usr/bin/env bash
case "$1" in
  -s) echo "$TEST_OS" ;;
  -m) echo "$TEST_ARCH" ;;
esac
SH
cat > "$work/toolchain/bin/sun" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == --help ]]; then echo 'sun -c sun-config.json'; exit 0; fi
mkdir -p dist
if [[ "${TEST_MISSING:-0}" != 1 ]]; then
  printf 'fresh package\n' > "dist/system_monitor-$TEST_CANONICAL.tar.gz"
fi
SH
chmod +x "$work/bin/uname" "$work/toolchain/bin/sun"
for arch in x86_64 aarch64; do
  tools="$work/.ci/musl/$arch-linux-musl-cross/bin"
  mkdir -p "$tools"
  for tool in gcc readelf; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tools/$arch-linux-musl-$tool"
    chmod +x "$tools/$arch-linux-musl-$tool"
  done
done
export PATH="$work/bin:$PATH"
export SUN_BIN="$work/toolchain/bin/sun"
unset SUN_LIB_ROOT
export TEST_ARCH=x86_64 TEST_OS=Linux TEST_CANONICAL=x86_64-unknown-linux-gnu SUN_TARGET=
bash "$work/scripts/build.sh"
cmp "$work/dist/system_monitor-$TEST_CANONICAL.tar.gz" "$work/dist/system_monitor-x86_64-linux-gnu.tar.gz"
export SUN_TARGET=aarch64-linux-gnu TEST_CANONICAL=aarch64-unknown-linux-gnu
bash "$work/scripts/build.sh"
cmp "$work/dist/system_monitor-$TEST_CANONICAL.tar.gz" "$work/dist/system_monitor-aarch64-linux-gnu.tar.gz"
export TEST_OS=Darwin TEST_ARCH=arm64 TEST_CANONICAL=aarch64-unknown-darwin SUN_TARGET=
bash "$work/scripts/build.sh"
cmp "$work/dist/system_monitor-$TEST_CANONICAL.tar.gz" "$work/dist/system_monitor-arm64-apple-darwin.tar.gz"
# A stale public archive must not conceal a missing compiler output.
rm "$work/dist/system_monitor-$TEST_CANONICAL.tar.gz"
export TEST_MISSING=1
if bash "$work/scripts/build.sh" > "$work/missing.log" 2>&1; then
  echo 'Build accepted a stale public archive without compiler output.' >&2
  exit 1
fi
grep -q 'Sun did not produce the expected package: dist/system_monitor-aarch64-unknown-darwin.tar.gz' "$work/missing.log"
echo 'PASS build script: Linux x86_64, Linux ARM64, macOS ARM64 archive names and missing-package diagnostics'
