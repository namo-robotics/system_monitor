# System Monitor

A terminal and web system monitor written in [Sun](https://github.com/namo-robotics/sun),
expanded from [namo-robotics/process_monitor](https://github.com/namo-robotics/process_monitor).

Start `system_monitor` to open **Processes**, with horizontal tabs for all five
monitors in the same terminal window. Press **1–5** to switch directly and **q**
to quit.

| Key | Monitor | Shows |
| --- | --- | --- |
| 1 | Process | CPU, resident memory, process history, ROS 2 labels and process controls |
| 2 | Disk | Mounted filesystems, total/used/available space and capacity percentage |
| 3 | Service | Loaded systemd services, including inactive and failed units; launchd jobs on macOS |
| 4 | Network | Linux interface state, receive/send rates and totals, errors and drops |
| 5 | Temperature | Linux hwmon sensors, Celsius temperatures and critical thresholds; thermal-zone fallback |

Use **Up/Down** to select or scroll rows. **Up** from the first row focuses the
tab bar; **Left/Right** switches tabs, and **Down/Enter** returns to the view.
**Tab** toggles focus between tabs and content; **b** also focuses the tabs.
The focused tab is highlighted yellow. Number shortcuts work from either area,
including while paused. Tabs use shorter labels in narrow terminals.

**Space** pauses the display while collection continues. Long rows are clipped
to the terminal width; widen the terminal to see more. Process controls are
`c/m` to sort, `f/0/a` for top 5/10/all, `t/k` to terminate/kill, and `?` for help.
The top-five shortcut is now **f**, because **5** selects Temperature. Process
actions are available only while the process table has focus.

Each resource terminal tab uses a bordered table and a dotted history graph:

| Tab | Terminal graph |
| --- | --- |
| Disk | Used capacity percentage for the selected filesystem |
| Service | Active and failed service counts |
| Network | Receive/send KiB/s for the selected interface |
| Temperature | Selected sensor temperature and its critical threshold |

Use Up/Down to choose the row to chart. Graphs collect while that tab is open,
including while the display is paused. History survives tab switches; missing
measurements and sampling gaps stay blank. `--graph-window` sets the time span.
Resource charts share one quarter of the interactive `--memory-limit` budget;
process history uses the remainder. Resource history is also capped at 2,048
frames and is not included in process recordings. The styled views need at
least 65 columns and 18 rows. Unsupported collectors show availability details.

## Build and run

Use a current Sun compiler. On Linux x86_64:

```sh
scripts/ci-toolchain.sh
bash scripts/setup-musl.sh
scripts/build.sh
build/system_monitor
```

The build script prefers `.ci/toolchain/bin/sun`, then falls back to `sun` on
`PATH`. Set `SUN_BIN` to override the compiler explicitly.

Or select a view directly:

```sh
build/system_monitor --monitor disk
build/system_monitor --monitor service
build/system_monitor --monitor network --interval 0.5
build/system_monitor --monitor temperature --samples 1
build/system_monitor --monitor process --top 5 --sort cpu
build/system_monitor --monitor process --record session.jsonl
build/system_monitor --replay session.jsonl
```

Redirected input/output defaults to the process view for compatibility with
scripts. Use `--monitor NAME --samples N` for finite resource snapshots without
terminal escape sequences. Network rates display `N/A` on the first sample,
when an interface appears, or after a counter reset.

The web dashboard is available on Linux x86_64, with horizontal tabs for all five monitors.
It opens on **Processes**; select another tab to switch views:

```sh
build/system_monitor --ui both  # http://127.0.0.1:8080
```

The tabs are Processes, Disks, Services, Network, and Temperature. Direct links
such as `http://127.0.0.1:8080/#network` open a specific tab. Each browser selects
its own view independently of the terminal. The four resource tabs show live
host data, including when process recordings are being replayed. Pause affects
only the display; data collection continues. Recording/replay and labels apply
to process data. With web hosting enabled, process collection continues even
when another terminal monitor is selected.

Each tab includes a table and a visualization:

| Monitor | Visualization |
| --- | --- |
| Processes | CPU or memory history for the top five processes |
| Disks | Usage bars for the fullest filesystems |
| Services | Service counts grouped by active state |
| Network | Receive/send traffic history, with an interface selector |
| Temperature | Sensor readings with reported critical-threshold markers |

The four resource tables support filtering and sorting by column. Missing
measurements show `N/A`; charts never substitute zero for unavailable readings.
Network history covers the last minute observed by the browser and continues
collecting while another tab is selected.

## Platforms and data sources

- **Linux x86_64 / ARM64:** process data from procfs, disk capacity via `df`,
  services via `systemctl`, network data from procfs/sysfs, temperatures from sysfs.
- **Apple Silicon macOS:** original process support, disk capacity via `df`,
  current-domain launchd jobs via `launchctl`, and network totals via `netstat`.
  Network rates and temperature sensors are currently Linux-only.
- Missing utilities, service managers, permissions or sensors produce an
  unavailable message. Monitoring does not require root. Service monitoring is
  read-only and lists loaded services, not every installed unit file.

The new views have been exercised on Linux x86_64. Native ARM64 and macOS
validation runs in the inherited CI matrix; it has not been performed locally.

## Tests

```sh
SUN_BIN="$PWD/.ci/toolchain/bin/sun" scripts/test.sh
```

Includes collector calculations, CLI validation, all five terminal tabs,
arrow navigation and focus, and the original process, recording, terminal and HTTP checks.

The dashboard DOM tests cover tables, charts, filtering, sorting, missing data,
and bounded network history. They require Node.js and the test-only `jsdom`
package; the dashboard itself has no external dependencies:

```sh
npm install --prefix /tmp/system-monitor-dom jsdom@29.1.1
NODE_PATH=/tmp/system-monitor-dom/node_modules node tests/dashboard.cjs
```

## Install a published release

After this repository has a release, its installer supports Linux x86_64/ARM64
and Apple Silicon macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/namo-robotics/system_monitor/main/scripts/install.sh | bash
```

[Build and process-monitor details](docs/GUIDE.md). Distributed under the
[MIT license](LICENSE), preserving the original project's attribution.
