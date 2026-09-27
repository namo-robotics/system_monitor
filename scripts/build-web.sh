#!/usr/bin/env bash
# Select web support and stage the dashboard beside development binaries.
set -euo pipefail
cd "$(dirname "$0")/.."
target=${SUN_TARGET:-$(uname -m)-$(uname -s)}
mkdir -p build
if [[ "$target" == x86_64-* && "$target" == *[Ll]inux* && "${SUN_WEB:-1}" != 0 ]]; then
  mkdir -p build/share/system_monitor
  cp assets/dashboard.html build/share/system_monitor/dashboard.html
  sed -e 's|"web-disabled.sun"|"web.sun"|' \
      -e 's|libraries: \["stdlib.moon"\]|libraries: ["stdlib.moon", "$SUN_SERVE/sun_serve.moon"]|' \
      -e 's|"\([^"]*\.sun\)"|"../src/\1"|g' src/main.sun > build/main.sun
else
  sed 's|"\([^"]*\.sun\)"|"../src/\1"|g' src/main.sun > build/main.sun
fi
