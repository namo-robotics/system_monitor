#!/usr/bin/env bash
# Run unit tests and process-level integration checks.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
build/system_monitor_test
build/acceptance
