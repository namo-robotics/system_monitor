#!/usr/bin/env bash
# Exercise the installer's package verification and daemon option with stubbed network and systemd.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/release/bin" "$work/release/share/system_monitor" "$work/home"
export HOME="$work/home" PREFIX="$work/prefix" XDG_CONFIG_HOME="$work/home/.config"

# Build a fake release archive with a runnable executable and its checksum list.
printf '#!/usr/bin/env bash\necho "system_monitor fixture"\n' > "$work/release/bin/system_monitor"
chmod +x "$work/release/bin/system_monitor"
printf '<html></html>\n' > "$work/release/share/system_monitor/dashboard.html"
printf '{}\n' > "$work/release/package.json"
version=v1.2.3
for target in linux-x86_64 linux-arm64; do
  tar -czf "$work/system_monitor-$version-$target.tar.gz" -C "$work/release" bin share package.json
done
(cd "$work" && sha256sum system_monitor-$version-*.tar.gz > SHA256SUMS)

# Stub the tools the installer calls so no network or service manager is needed.
cat > "$work/bin/uname" <<'SH'
#!/usr/bin/env bash
case "$1" in
  -s) echo "$TEST_OS" ;;
  -m) echo "$TEST_ARCH" ;;
esac
SH
cat > "$work/bin/curl" <<SH
#!/usr/bin/env bash
out=''
url=''
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) out=\$2; shift ;;
    --write-out) shift ;;
    -*) ;;
    *) url=\$1 ;;
  esac
  shift
done
case "\$url" in
  */releases/latest) printf '200 https://github.com/namo-robotics/system_monitor/releases/tag/$version' ;;
  */releases/download/*) cp "$work/\${url##*/}" "\$out" ;;
  *) exit 1 ;;
esac
SH
cat > "$work/bin/systemctl" <<SH
#!/usr/bin/env bash
echo "systemctl \$*" >> "$work/systemctl.log"
SH
cat > "$work/bin/id" <<'SH'
#!/usr/bin/env bash
case "$1" in
  -u) echo "${TEST_UID:-1000}" ;;
  -un) echo tester ;;
esac
SH
cat > "$work/bin/loginctl" <<'SH'
#!/usr/bin/env bash
echo no
SH
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
export TEST_OS=Linux TEST_ARCH=x86_64

# Without a terminal the daemon question defaults to no and nothing touches systemd.
bash "$root/scripts/install.sh" < /dev/null > "$work/default.log"
test -x "$work/prefix/bin/system_monitor"
grep -q "Installed $version" "$work/default.log"
test ! -e "$work/systemctl.log"
test ! -e "$XDG_CONFIG_HOME/systemd/user/system_monitor.service"

# DAEMON=1 answers the question for unattended installs, writing and enabling a
# user unit for the web dashboard on the PORT given.
DAEMON=1 PORT=8090 bash "$root/scripts/install.sh" > "$work/daemon.log"
unit="$XDG_CONFIG_HOME/systemd/user/system_monitor.service"
grep -q "^ExecStart=$work/prefix/bin/system_monitor --ui web --port 8090\$" "$unit"
grep -q '^WantedBy=default.target$' "$unit"
grep -q '^systemctl --user daemon-reload$' "$work/systemctl.log"
grep -q '^systemctl --user enable --now system_monitor.service$' "$work/systemctl.log"
grep -q 'http://127.0.0.1:8090' "$work/daemon.log"
grep -q 'loginctl enable-linger' "$work/daemon.log"

# Invalid ports and unknown options are refused.
if PORT=70000 bash "$root/scripts/install.sh" > "$work/port.log" 2>&1; then
  echo 'Installer accepted an out-of-range port.' >&2
  exit 1
fi
grep -q 'PORT must be between 1 and 65535' "$work/port.log"
if bash "$root/scripts/install.sh" --daemon > "$work/flag.log" 2>&1; then
  echo 'Installer accepted a removed flag.' >&2
  exit 1
fi
grep -q 'Unknown option: --daemon' "$work/flag.log"

# Targets without the web dashboard reject the daemon before downloading anything.
export TEST_ARCH=aarch64
if DAEMON=1 bash "$root/scripts/install.sh" > "$work/arm.log" 2>&1; then
  echo 'Installer accepted a daemon on a target without the web dashboard.' >&2
  exit 1
fi
grep -q 'only available on Linux x86_64' "$work/arm.log"
echo 'PASS install script: non-interactive default, DAEMON and PORT answers, option and target validation'

# With a terminal attached the installer asks first. Enter keeps the default of
# no; yes asks for a port, rejecting bad values; DAEMON=0 skips the questions.
# Needs util-linux script for the pseudo-terminal.
if script --version 2>/dev/null | grep -q util-linux; then
  export TEST_ARCH=x86_64
  rm -f "$work/systemctl.log" "$unit"
  printf '\n' | script -qfec "bash '$root/scripts/install.sh'" /dev/null > "$work/ask-no.log"
  grep -q 'background service? \[y/N\]' "$work/ask-no.log"
  test ! -e "$work/systemctl.log"
  printf 'y\n99999\n8100\n' | script -qfec "bash '$root/scripts/install.sh'" /dev/null > "$work/ask-yes.log"
  grep -q 'Localhost port for the dashboard \[29583\]' "$work/ask-yes.log"
  grep -q 'Enter a port between 1 and 65535' "$work/ask-yes.log"
  grep -q -- '--port 8100$' "$unit"
  grep -q '^systemctl --user enable --now system_monitor.service$' "$work/systemctl.log"
  rm "$work/systemctl.log"
  printf 'y\n\n' | script -qfec "bash '$root/scripts/install.sh'" /dev/null > "$work/ask-default-port.log"
  grep -q -- '--port 29583$' "$unit"
  rm "$work/systemctl.log"
  printf 'y\n' | script -qfec "DAEMON=0 bash '$root/scripts/install.sh'" /dev/null > "$work/skip.log"
  if grep -q '\[y/N\]' "$work/skip.log"; then
    echo 'Installer asked about the daemon despite DAEMON=0.' >&2
    exit 1
  fi
  test ! -e "$work/systemctl.log"
  echo 'PASS install script: terminal prompt default, yes with port, and DAEMON=0'
fi

# Uninstall removes the daemon unit, the executable link and retained packages.
export TEST_ARCH=x86_64
rm -f "$work/systemctl.log"
DAEMON=1 bash "$root/scripts/install.sh" > /dev/null
test -f "$unit"
test -L "$work/prefix/bin/system_monitor"
rm "$work/systemctl.log"
bash "$root/scripts/install.sh" --uninstall > "$work/uninstall.log"
test ! -e "$unit"
test ! -e "$work/prefix/bin/system_monitor"
test ! -e "$work/prefix/lib/system_monitor"
test -d "$work/prefix/bin"
grep -q '^systemctl --user disable --now system_monitor.service$' "$work/systemctl.log"
grep -q '^systemctl --user daemon-reload$' "$work/systemctl.log"
grep -q 'Uninstalled system_monitor' "$work/uninstall.log"
# A second uninstall, and one without any daemon, succeeds without touching systemd.
rm "$work/systemctl.log"
bash "$root/scripts/install.sh" --uninstall > /dev/null
test ! -e "$work/systemctl.log"
echo 'PASS install script: uninstall removes daemon, executable and packages'

# As root the install goes to a shared prefix and the daemon becomes a system
# unit under a dynamic account, managed without --user and started at boot.
export TEST_UID=0 PREFIX="$work/system" UNIT_DIR="$work/etc/systemd/system"
DAEMON=1 PORT=8200 bash "$root/scripts/install.sh" > "$work/system.log"
system_unit="$UNIT_DIR/system_monitor.service"
test -L "$work/system/bin/system_monitor"
grep -q 'Installed v1.2.3 for all users' "$work/system.log"
grep -q "^ExecStart=$work/system/bin/system_monitor --ui web --port 8200\$" "$system_unit"
grep -q '^DynamicUser=yes$' "$system_unit"
grep -q '^WantedBy=multi-user.target$' "$system_unit"
grep -q '^systemctl daemon-reload$' "$work/systemctl.log"
grep -q '^systemctl enable --now system_monitor.service$' "$work/systemctl.log"
if grep -q -- '--user' "$work/systemctl.log" || grep -q 'enable-linger' "$work/system.log"; then
  echo 'System install used user-session commands.' >&2
  exit 1
fi
if script --version 2>/dev/null | grep -q util-linux; then
  printf '\n' | script -qfec "bash '$root/scripts/install.sh'" /dev/null > "$work/system-ask.log"
  grep -q 'system service for all users? \[y/N\]' "$work/system-ask.log"
fi
rm "$work/systemctl.log"
bash "$root/scripts/install.sh" --uninstall > "$work/system-uninstall.log"
test ! -e "$system_unit"
test ! -e "$work/system/bin/system_monitor"
test ! -e "$work/system/lib/system_monitor"
grep -q '^systemctl disable --now system_monitor.service$' "$work/systemctl.log"
grep -q 'Uninstalled system_monitor (system)' "$work/system-uninstall.log"
echo 'PASS install script: root installs for all users with a system unit'
