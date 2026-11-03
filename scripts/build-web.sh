#!/usr/bin/env bash
# Select web support and generate the entrypoint in the requested build directory.
set -euo pipefail
cd "$(dirname "$0")/.."
web_output=${1:-build}
web_target=${SUN_TARGET:-$(uname -m)-$(uname -s)}
mkdir -p "$web_output"
python3 - "$web_output" "$web_target" "${SUN_WEB:-1}" <<'PYTHON'
"""Generate a relocatable entrypoint with explicit source paths and web selection."""
import pathlib
import re
import sys

root = pathlib.Path.cwd()
output = pathlib.Path(sys.argv[1])
text = (root / "src/main.sun").read_text()
if sys.argv[2].startswith("x86_64-") and "linux" in sys.argv[2].lower() and sys.argv[3] != "0":
    text = text.replace('"web-disabled.sun"', '"web.sun"')
    text = text.replace('"stdlib.moon"', '"stdlib.moon", "${namo-robotics/sun_serve}/lib/sun_serve.moon"')


def source_path(match):
    """Anchor literal source paths while leaving config variables unresolved."""
    value = match.group(1)
    return '"' + (value if "$" in value else str((root / "src" / value).resolve())) + '"'


text = re.sub(r'"([^"\n]+\.sun)"', source_path, text)
(output / "main.sun").write_text(text)
PYTHON
