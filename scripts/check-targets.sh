#!/usr/bin/env bash
# Verify target code generation; native runtime validation is a separate stage.
set -euo pipefail
cd "$(dirname "$0")/.."
SUN_BIN=${SUN_BIN:-sun}
SUN_LIB_ROOT=${SUN_LIB_ROOT:-/usr/lib/sun}
mkdir -p build
bash scripts/build-version.sh
# The workspace search path wins over --lib-path; restore its bundle after checks.
backup=$(mktemp -d)
if [[ -f build/stdlib.moon ]]; then cp build/stdlib.moon "$backup/stdlib.moon"; fi
trap 'if [[ -f "$backup/stdlib.moon" ]]; then cp "$backup/stdlib.moon" build/stdlib.moon; else rm -f build/stdlib.moon; fi; rm -rf "$backup"' EXIT
for target in aarch64-linux-gnu arm64-apple-darwin; do
  cp "$SUN_LIB_ROOT/$target/stdlib.moon" build/stdlib.moon
  "$SUN_BIN" --emit-obj --target "$target" --lib-path "$SUN_LIB_ROOT/$target" \
    -o "build/system_monitor-$target.o" src/main.sun
done
