#!/usr/bin/env bash
# Install the latest published Sun package after verifying its release checksum.
# Optionally register the web dashboard as a systemd service. Run as a regular
# user it installs under the home directory for that user only; run as root it
# installs system-wide for every user.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: install.sh [--uninstall] [--help]
  --uninstall   stop and remove the daemon, the executable and the package
  --help        show this help
As a regular user this installs under ~/.local and any daemon runs in that
user's systemd session. As root it installs under /usr/local for all users and
any daemon runs as a system service under an unprivileged dynamic account.
On Linux x86_64 the installer asks on the terminal whether to also run the web
dashboard as a background service, and on which port; the default is no.
Environment: PREFIX overrides the install root. DAEMON=0|1 and PORT answer the
questions ahead of time for unattended installs. UNIT_DIR overrides where the
systemd unit is written.
HELP
}

daemon="${DAEMON:-}"
uninstall=0
port="${PORT:-29583}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) uninstall=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done
[[ -z "$daemon" || "$daemon" == 0 || "$daemon" == 1 ]] || { echo 'DAEMON must be 0 or 1.' >&2; exit 1; }
[[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || { echo 'PORT must be between 1 and 65535.' >&2; exit 1; }

# Root installs for every user; anyone else installs for themselves. The scope
# decides the prefix, the unit directory and which systemd instance to talk to.
if [[ "$(id -u)" == 0 ]]; then
  scope=system
  prefix="${PREFIX:-/usr/local}"
  units="${UNIT_DIR:-/etc/systemd/system}"
  systemctl_cmd=(systemctl)
else
  scope=user
  prefix="${PREFIX:-$HOME/.local}"
  units="${UNIT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"
  systemctl_cmd=(systemctl --user)
fi
unit="$units/system_monitor.service"

# Remove everything a previous run in this scope created: the daemon unit, the
# executable link and every retained package version. Nothing else is touched.
if [[ "$uninstall" == 1 ]]; then
  if [[ -f "$unit" ]]; then
    if command -v systemctl >/dev/null; then
      "${systemctl_cmd[@]}" disable --now system_monitor.service || true
    fi
    rm -f "$unit"
    if command -v systemctl >/dev/null; then
      "${systemctl_cmd[@]}" daemon-reload || true
    fi
    echo "Removed daemon: $unit"
  fi
  if [[ -L "$prefix/bin/system_monitor" || -f "$prefix/bin/system_monitor" ]]; then
    rm -f "$prefix/bin/system_monitor"
    echo "Removed executable: $prefix/bin/system_monitor"
  fi
  if [[ -d "$prefix/lib/system_monitor" ]]; then
    rm -rf "$prefix/lib/system_monitor"
    echo "Removed packages: $prefix/lib/system_monitor"
  fi
  echo "Uninstalled system_monitor ($scope)."
  exit 0
fi

# Select the archive matching the current operating system and CPU architecture.
case "$(uname -s):$(uname -m)" in
  Linux:x86_64) target=linux-x86_64 ;;
  Linux:aarch64|Linux:arm64) target=linux-arm64 ;;
  Darwin:arm64) target=macos-arm64 ;;
  *) echo 'Supported targets: Linux x86_64/ARM64 and Apple Silicon macOS.' >&2; exit 1 ;;
esac

# Ask about the daemon when DAEMON did not decide it, but only where it can run and a
# terminal is attached. Piped installs read the answer from /dev/tty; without one
# the answer defaults to no.
if [[ -z "$daemon" ]]; then
  daemon=0
  if [[ "$target" == linux-x86_64 ]] && command -v systemctl >/dev/null && { : < /dev/tty; } 2>/dev/null; then
    if [[ "$scope" == system ]]; then
      question='Also run the web dashboard as a system service for all users? [y/N] '
    else
      question='Also run the web dashboard as a background service? [y/N] '
    fi
    read -r -p "$question" answer < /dev/tty || answer=''
    case "$answer" in
      [Yy]|[Yy][Ee][Ss]) daemon=1 ;;
    esac
    # Ask for the port once the daemon is wanted, unless PORT already chose one.
    if [[ "$daemon" == 1 && -z "${PORT:-}" ]]; then
      while true; do
        read -r -p "Localhost port for the dashboard [$port]: " answer < /dev/tty || answer=''
        [[ -n "$answer" ]] || break
        if [[ "$answer" =~ ^[0-9]+$ && "$answer" -ge 1 && "$answer" -le 65535 ]]; then
          port=$answer
          break
        fi
        echo 'Enter a port between 1 and 65535.' >&2
      done
    fi
  fi
fi

# The daemon serves the web dashboard, which is only built for Linux x86_64.
if [[ "$daemon" == 1 ]]; then
  if [[ "$target" != linux-x86_64 ]]; then
    echo 'The daemon requires the web dashboard, which is only available on Linux x86_64.' >&2
    exit 1
  fi
  if ! command -v systemctl >/dev/null; then
    echo 'The daemon requires systemd; see the README for manual service setup.' >&2
    exit 1
  fi
fi

# Prefer a stable release and use the development build when none exists.
repository=https://github.com/namo-robotics/system_monitor
response=$(curl --silent --show-error --location --output /dev/null --write-out '%{http_code} %{url_effective}' "$repository/releases/latest")
status=${response%% *}
release_url=${response#* }
if [[ "$status" == 404 || ( "$status" == 200 && "$release_url" == "$repository/releases" ) ]]; then
  version=dev
elif [[ "$status" == 200 ]]; then
  version=${release_url##*/}
else
  echo "Could not resolve the latest release (HTTP $status)." >&2
  exit 1
fi
if [[ "$version" != dev && ! "$version" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then
  echo 'No supported published release was found.' >&2
  exit 1
fi
archive="system_monitor-$version-$target.tar.gz"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl --fail --silent --show-error --location "$repository/releases/download/$version/$archive" -o "$work/$archive"
curl --fail --silent --show-error --location "$repository/releases/download/$version/SHA256SUMS" -o "$work/SHA256SUMS"

# Verify just the selected archive using the checksum utility available on the host.
expected=$(awk -v name="$archive" '$2 == name {print $1}' "$work/SHA256SUMS")
if command -v sha256sum >/dev/null; then
  actual=$(sha256sum "$work/$archive")
else
  actual=$(shasum -a 256 "$work/$archive")
fi
if [[ ! "$expected" =~ ^[0-9a-f]{64}$ || "${actual%% *}" != "$expected" ]]; then
  echo 'Release checksum verification failed.' >&2
  exit 1
fi

# Keep the complete package together so resource lookup survives relocation.
mkdir -p "$prefix/bin" "$prefix/lib/system_monitor"
prefix=$(cd "$prefix" && pwd)
[[ ! -d "$prefix/bin/system_monitor" ]] || { echo "The executable path is a directory." >&2; exit 1; }
payload=$(mktemp -d "$prefix/lib/system_monitor/$version-$target.XXXXXX")
link=''
trap 'rm -rf "$work"; if [[ -n "$payload" ]]; then rm -rf "$payload"; fi; if [[ -n "$link" ]]; then rm -f "$link"; fi' EXIT
tar -xzf "$work/$archive" -C "$payload"
test -x "$payload/bin/system_monitor"
test -f "$payload/share/system_monitor/dashboard.html"
test -f "$payload/package.json"
"$payload/bin/system_monitor" --version
# System installs must stay readable by every user, whatever root's umask is.
if [[ "$scope" == system ]]; then
  chmod -R a+rX "$payload"
fi
link=$(mktemp "$prefix/bin/.system_monitor.XXXXXX")
ln -sf "$payload/bin/system_monitor" "$link"
mv -f "$link" "$prefix/bin/system_monitor"
payload=''
link=''
if [[ "$scope" == system ]]; then
  audience='all users'
else
  audience='this user'
fi
printf 'Installed %s for %s\nRun: %s/bin/system_monitor\n' "$version" "$audience" "$prefix"
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) printf 'Add to your shell PATH: export PATH="%s/bin:$PATH"\n' "$prefix" ;;
esac

# Register a service that hosts the dashboard on loopback and restarts on failure.
# The system unit runs under a dynamic unprivileged account and starts at boot;
# the user unit starts with that user's session.
if [[ "$daemon" == 1 ]]; then
  mkdir -p "$units"
  if [[ "$scope" == system ]]; then
    service_extra='DynamicUser=yes'
    wanted_by=multi-user.target
  else
    service_extra=''
    wanted_by=default.target
  fi
  cat > "$unit" <<EOF
[Unit]
Description=System Monitor web dashboard
After=network.target

[Service]
ExecStart=$prefix/bin/system_monitor --ui web --port $port
${service_extra:+$service_extra
}Restart=on-failure
RestartSec=5

[Install]
WantedBy=$wanted_by
EOF
  "${systemctl_cmd[@]}" daemon-reload
  "${systemctl_cmd[@]}" enable --now system_monitor.service
  if [[ "$scope" == system ]]; then
    printf 'Daemon enabled for all users: http://127.0.0.1:%s\nStatus: systemctl status system_monitor\n' "$port"
  else
    printf 'Daemon enabled: http://127.0.0.1:%s\nStatus: systemctl --user status system_monitor\n' "$port"
    if command -v loginctl >/dev/null && [[ "$(loginctl show-user "$(id -un)" --property=Linger --value 2>/dev/null)" != yes ]]; then
      printf 'To keep it running after logout: loginctl enable-linger %s\n' "$(id -un)"
    fi
  fi
fi
