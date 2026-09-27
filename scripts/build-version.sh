#!/usr/bin/env bash
# Generate the source commit identity embedded in native and cross builds.
set -euo pipefail
cd "$(dirname "$0")/.."
revision=${BUILD_REVISION:-$(git rev-parse --verify HEAD 2>/dev/null || printf unknown)}
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ && "$revision" != unknown ]]; then
  echo 'BUILD_REVISION must be a full commit SHA or unknown.' >&2
  exit 1
fi
mkdir -p build
cat > build/version.sun <<EOF
/* Identifies the source commit used to build this executable. */
public module system_monitor {
  /* Returns the commit identity embedded at build time. */
  function build_revision() std.String {
    return std.String("$revision");
  }
}
EOF
