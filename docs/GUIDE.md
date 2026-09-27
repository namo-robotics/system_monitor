# System monitor

A Sun CLI for finding processes that consume CPU and resident memory. It provides
an interactive process table, top-N rankings, colored history plots, best-effort ROS 2
names, and JSON Lines recording/replay. No elevated privileges are required.

The Linux x86_64 build includes an offline web dashboard hosted by the source-built
`sun_serve.moon` library. The terminal selection page also offers disk, service,
network and temperature monitors; see [README.md](../README.md) for their data
sources and platform limits. This guide describes the inherited process view. Platform
validation work is recorded in [FOLLOWUP.md](../FOLLOWUP.md).

## Build and run

Install the latest rolling Sun release, its LLVM and libarchive runtime
dependencies, a native C++ linker, Git, and Bash.
Linux also needs Make and Perl to build the musl native libraries; macOS needs the
Xcode command line tools. The application and acceptance tests are Sun code.
Build and install scripts use standard shell utilities.

```sh
# On x86_64 Linux, install musl and its OpenSSL/zlib archives first.
if [[ $(uname -s) == Linux ]]; then bash scripts/setup-musl.sh; fi
scripts/ci-toolchain.sh
export SUN_BIN="$PWD/.ci/toolchain/bin/sun"
scripts/build.sh
build/system_monitor
build/system_monitor --top 5 --sort memory
build/system_monitor --top all --interval 0.5 --history 300
```

`SUN_BIN=/path/to/sun` selects another compiler installation.
Linux builds use static musl linkage and fail if the musl compiler is missing.
On macOS the build uses dynamic linking and links libproc.
For a direct Linux build after staging with `scripts/build.sh`, run:

```sh
export PATH="$PWD/.ci/musl/x86_64-linux-musl-cross/bin:$PATH"
export SUN_CC=x86_64-linux-musl-gcc
sun -c --static sun-config.json
```

Sun otherwise falls back to static glibc when musl is absent. The build script
sets `SUN_CC` explicitly and checks that Linux binaries have no ELF interpreter
or shared-library dependencies. Rebuild the dev container to get Make and Perl,
then run the musl setup once in the mounted workspace. For ARM64 cross builds,
run `bash scripts/setup-musl.sh aarch64` and build with
`SUN_TARGET=aarch64-linux-gnu scripts/build.sh`.

`system_monitor --version` prints the source commit embedded during the build.
When building without Git metadata, set `BUILD_REVISION` to the full commit SHA;
otherwise the version is reported as `unknown`.

| Target | Implementation | Validation in this workspace |
| --- | --- | --- |
| Linux x86_64 | `/proc` collector, terminal, and web | Native build, unit, workload, PTY, and HTTP tests |
| Linux ARM64 | Same collector, target-specific Sun stdlib | Cross-compiled object; native execution pending |
| Apple Silicon macOS | libproc/sysctl collector and terminal | Cross-compiled object; native execution pending |

ARM64 and macOS runtime support remains provisional until the native acceptance
checks in `FOLLOWUP.md` pass. Cross-compilation is not a substitute for those checks.

## CI and package releases

[The GitHub Actions workflow](../.github/workflows/ci.yml) builds the application
using the latest rolling Sun release. The toolchain script downloads the compiler
and matching standard libraries into `.ci/toolchain` on each run.

`sun-config.json` declares `SUN_SERVE` as a Git source dependency pinned to a
commit, using `src/sun_serve.sun` from that repository. On Linux x86_64, Sun
fetches and compiles the library before building the monitor. The generated
manifest imports `"$SUN_SERVE/sun_serve.moon"`. The dependency is unavailable
on other targets. Its `MUSL_LIB` path variable points to the musl-built OpenSSL and
zlib archives under `.ci/musl`, installed by `scripts/setup-musl.sh`. Sun caches
Git sources and compiled libraries under
`~/.sun/cache/git`; set `SUN_GIT_CACHE` to change that location. The library is
linked into the monitor and is not a separate file in the release package.

`scripts/build.sh` stages the version and target manifest, then runs
`sun -c --static sun-config.json` on Linux (with `--dynamic` on macOS). Sun builds
the binaries and assembles
`dist/system_monitor-<target>/` plus its `.tar.gz`. The package contains
`bin/system_monitor` and `share/system_monitor/dashboard.html`. Sun's
`package.json` records the target, artifacts, and payload hashes. Test executables are excluded from the package.

Linux ARM64 is cross-compiled with its matching stdlib and musl toolchain, then tested
on a native ARM64 runner. Linux x86_64 and macOS also run tests natively. Test
jobs need no Sun compiler: they receive the application, compiled Sun acceptance
suite, unit tests, and the package produced by the compile job. `curl` is needed
for HTTP acceptance checks. Set `SUN_WEB=0` for a terminal-only x86_64 build.

Each successful job uploads a `.tar.gz` archive and SHA-256 checksum as workflow
artifacts. After all three native jobs pass, every branch push updates the same
[`dev` prerelease](https://github.com/namo-robotics/system_monitor/releases/tag/dev),
replacing its archives and `SHA256SUMS`. The `dev` tag and release notes identify
the packaged commit. Publication is serialized across branches to prevent mixed
uploads. Pull requests and manual runs only upload workflow artifacts.

Pushing a version tag such as `v0.1.0` publishes a separate GitHub Release.
Versioned uploads stay in a draft until all assets arrive; a rerun can resume a
draft but will not replace an already published versioned release. Each release
includes all three archives and `SHA256SUMS`. The installer selects the latest
stable release, falling back to the `dev` prerelease when no stable release exists.

Extract the package for your architecture and run `./bin/system_monitor`. Sun is not
needed at runtime. Linux packages include musl and their native libraries through
static linkage and require no glibc installation. macOS packages target
macOS 14 or later on Apple Silicon and are not Developer ID signed or notarized.
Keep `bin/` and `share/` together when moving an extracted package. CI runs the
extracted executable from outside the checkout and verifies that its HTTP server
returns the packaged HTML before uploading it. The installer preserves the full
package under `$PREFIX/lib/system_monitor` and links `$PREFIX/bin/system_monitor`
to it; `PREFIX` defaults to `~/.local`.

The package workflow has not yet completed a run on GitHub. The native support status above remains
provisional until those jobs and the remaining manual checks pass.

## Controls and options

| Key | Action |
| --- | --- |
| `1`–`5` | Select Processes / Disks / Services / Network / Temperature |
| `Tab` | Toggle focus between the horizontal tabs and the current view |
| `b` | Focus the tab bar |
| `←` / `→` | Switch tabs while the tab bar has focus; wrap at either end |
| `↓` / Enter | Enter the current view from the tab bar |
| `↓` / `↑` | Select or scroll rows; Up from the first row focuses the tabs |
| `c` / `m` | Rank processes by CPU / memory |
| `f` / `0` / `a` | Show top 5 / top 10 / all processes |
| `t` / `k` | Send SIGTERM / SIGKILL to the selected live process |
| Space | Pause/resume display; collection and recording continue |
| `?` or `h` | Toggle help |
| `q` or Ctrl-C | Quit and restore the terminal |

Startup opens Processes. The tab bar remains visible above every monitor, with
a yellow highlight when it has keyboard focus. Number shortcuts work from tabs,
content, and paused views. `--monitor NAME` chooses a different initial tab;
the legacy `--monitor menu` option is an alias for Processes.

Process actions work only when the process table has focus. They run immediately
and report success or failure above the table.
`t` requests graceful shutdown; `k` forcibly stops the process. Replay disables
both actions. PID 1, process groups, and the monitor itself are protected.
Linux uses a PID handle and rechecks the start time to prevent signalling a reused
PID. macOS rechecks the start time immediately before `kill`; its POSIX API still
has a small race between that check and signalling. OS permissions apply, and
Linux signalling requires kernel PID-handle support and glibc 2.36 or later.

The highlighted row keeps its identity as rankings change. The history panel is
independent of that selection: it plots the **current top five processes** for the
ranked resource, even if `--top` shows fewer or more rows. Press `c` for CPU or `m`
for resident memory. CPU uses percent of one core; memory uses RSS MiB.

The panel uses colored filled dot areas, a shared vertical scale, and elapsed time on the
horizontal axis (oldest at left, newest at right). A matching legend identifies
processes by PID and name. Colors stay attached to identities while they remain
in the graph, including when their ranks change. Newly entering processes show
their visible history; missing samples leave gaps. The graph grows left to right
over a fixed 60-second span, then scrolls older samples left. Use `--graph-window`
to change that span independently of history retention. The time axis shows
seconds since the first sample; unfilled future time stays blank. Each plotted column fills down to the baseline. Shorter columns appear in front
of taller ones at each time position, including where histories cross. A terminal
cell has one foreground color, so boundaries within a cell use the shorter area’s color. With fewer than five available measurements, only
those processes are plotted. The first CPU sample waits for a counter baseline.

Interactive mode uses cyan table borders and column dividers, a blue selected-row
highlight, and a separate bordered top-five history plot. An asterisk marks the sorted
column. Names are clipped with `~` when space is limited. The layout needs at least
65 columns and 18 rows and scrolls the selected row into view. Redirected output
prints aligned tables and monochrome dot plots without terminal control sequences.

The other terminal tabs use the same borders and selection styling with thin
Braille-dot history lines. Up/Down selects the filesystem, interface, or sensor
to chart. Disk charts show used percent; network charts show receive/send KiB/s;
temperature charts show Celsius and the critical threshold. Service charts show
active and failed counts. Missing measurements and long sampling gaps break lines.
Graphs collect while their tab is open, including while paused, and retain history
across tab changes. `--graph-window` bounds resource history by time, with a shared
2,048-frame cap and one quarter of the interactive `--memory-limit` budget.
Process history receives the remaining budget. Recordings remain process-only.

```text
--ui terminal|web|both default: terminal; web hosting requires Linux x86_64
--port PORT            localhost web port; default: 8080; range: 1..65535
--top N|all             default: 10
--sort cpu|memory       default: cpu
--interval SECONDS     default: 1; range: 0.1 through 604800
--graph-window SECONDS default: 60; same range as interval
--history SECONDS      default: 600; same range as interval
--memory-limit MiB     estimated retained-history budget; default: 64; range: 1..4096
--record FILE          create a new recording; existing files are refused
--replay FILE          stream a recording at the configured display interval
--labels FILE          explicit live-process labels
--samples N            exit after N samples
--help                 show usage
--version              show the build's source commit
```

## Web dashboard

```sh
build/system_monitor --ui both
build/system_monitor --ui web --port 8081
build/system_monitor --ui web --replay session.jsonl
```

Open `http://127.0.0.1:8080` (or the selected port). The server binds only to
loopback; remote access can use SSH port forwarding. `sun_serve.moon` hosts the HTML resource, which contains the CSS and JavaScript
and needs no external services. The server loads it relative to the actual
executable, including when launched through the installer’s symlink from another
working directory. A missing resource fails web startup; terminal mode still works.
The browser opens on the Processes tab and offers horizontal tabs for Disks,
Services, Network, and Temperature. URL fragments such as `#disk` select a tab;
left/right arrow keys navigate the focused tab bar. Each tab has a dedicated
view. Resource data stays live during process replay and refreshes at most once
per second (or at the configured interval when it is longer). Terminal navigation
in `--ui both` does not stop web collection.

The browser polls once per second and reconnects automatically. CPU/memory
ranking, top 5/10/custom/all, display pause, and identity selection operate
independently in each browser. The process table sits above a single top-five
history graph that follows the CPU/memory ranking selection, as in the terminal. Process names are
rendered as text. Process control remains in the terminal.

Both UIs use the same collector, recordings, and bounded history. Web-only mode
does not change terminal settings or print tables. Replay stays hosted at EOF
for inspection until SIGINT/SIGTERM; `--samples` still exits at its limit.
Server workers read serialized publications and never collect processes or
access mutable retained frames. Publication and response buffers add memory
outside `--memory-limit`, and serializing retained history adds work per sample.

Read-only GET/HEAD endpoints (other methods return 405):

| Endpoint | Response |
| --- | --- |
| `/api/v1/resources` | Live resource views under `monitors`, with typed `rows`, availability `message`, legacy text `lines`, sample counts, sampling `interval_ms`, and a publication `timestamp_ms` |
| `/api/v1/view` | One consistent snapshot, history array, and status object |
| `/api/v1/snapshot` | Latest recording-format sample, or null before sampling |
| `/api/v1/status` | Replay/completion state, retention, and initial display settings |
| `/api/v1/history` | Retained recording-format samples, including exited identities |
| `/api/v1/history?id=PID:START` | Elapsed timestamps and process measurements, null when absent |

Identity-scoped requests validate the numeric PID and start marker. Identities
and start markers remain strings to preserve precision; unavailable measurements
remain JSON null. The dashboard uses `/api/v1/view` so its table and graph refer
to the same publication even while collection advances.

Resource rows contain numeric byte counts, bytes-per-second rates, percentages,
and signed Celsius temperatures. Unavailable values are JSON null. Browser tables
sort these numeric fields directly. Filesystem usage bars and temperature bars
show the highest values from the filtered table; service charts count its states.
Network charts have their own interface selector and retain up to a minute of
observed samples in browser memory, bounded independently of process history.
No resource history is added to process recordings.

## Measurements and retention

- CPU is a counter delta divided by actual monotonic elapsed time. **100% means
  one logical core**, so multithreaded processes can exceed 100%. The first sample,
  counter resets, and unavailable counters appear as `N/A`.
- Memory is resident set size (RSS), in MiB and as a percentage of physical RAM.
  It is not private memory: shared pages can be counted in multiple processes.
- Collection always visits every visible process; rankings only affect display.
  Identity combines PID and start time to prevent history crossing PID reuse.
- Processes that exit during reads or whose identity cannot be read are counted
  as skipped. Unavailable measurements within an otherwise readable process stay
  unknown, distinct from zero. Processes hidden completely by the OS cannot be counted.
- History evicts oldest complete frames by duration and a conservative storage
  estimate. The displayed retention window reflects available history. Exited
  processes remain in retained frames. An individual frame larger than the budget
  is displayed and recorded but not retained.
- The memory budget governs estimated retained sample storage, **not total program
  RSS**. Current/baseline frames, vector capacity, parsing, terminal rendering, and
  recording buffers use additional memory.

Visibility follows the current process namespace and OS permissions. A monitor
inside a container sees the processes exposed to that container, not necessarily
all host processes. Processes shorter than the sampling interval can be missed.
Process actions apply only to selected live processes on the local machine.

## ROS 2 labels

The default label is the executable basename. Inside `--ros-args`, unscoped
`__node:=`, `__name:=`, and `__ns:=` remaps provide a best-effort fully qualified
node label. Executables containing `component_container` are marked as shared
containers: their measurements cover the entire process, not individual nodes.
Live graph discovery and node-scoped remaps are deferred.

For ambiguous processes, supply a JSON object:

```json
{"1234": "/robot/camera", "5678": "navigation container"}
```

```sh
build/system_monitor --labels labels.json
```

Overrides bind only to matching process identities in the first live sample.
An absent PID or a later reuse of that PID will not inherit the override. Labels
are not hot-reloaded. Both the PID and derived label remain visible; full
executable paths are preserved in recordings.

## Recording and replay

```sh
build/system_monitor --record session.jsonl --top 5
build/system_monitor --replay session.jsonl --interval 0.2
```

Recordings contain a versioned session header followed by one `sample` object per
line. Samples include wall-clock milliseconds, monotonic elapsed milliseconds,
physical memory, skipped count, and all visible processes. Each process includes
its stable `id`, PID, string start marker, executable, label, CPU percentage, RSS
bytes, and memory percentage. Unknown measurements are JSON `null`. Raw command
arguments and environment variables are not recorded.

Replay uses recorded timestamps and measurements without querying live processes.
`--interval` controls playback cadence. History limits still apply. An unfinished
final line is ignored; malformed complete lines and unsupported versions are
errors. Each input line is limited to 64 MiB. At EOF an interactive replay remains
open for inspection; redirected replay exits. Replay and recording cannot be
combined, and replay uses the labels stored in the recording.

## Development and tests

```sh
scripts/test.sh
scripts/check-targets.sh  # requires target stdlib bundles under SUN_LIB_ROOT
sun fmt --check src tests
```

`src/main.sun` exposes the CLI boundary. Internal code lives in the
`system_monitor` module, separated into focused source units: OS collectors,
sample model and metrics, history, ranking, labels, recording codec and streaming,
CLI options, terminal management, web publication, and pure chart formatting.
`scripts/build-web.sh` generates `build/main.sun` from the terminal manifest,
selects the target implementation, and stages `assets/dashboard.html` for local
runs. `tests/acceptance.sun` checks native workloads, recording/replay, terminal
restoration, and HTTP behavior. `Session` owns the
lifecycle; collectors do not know about the UI or recording. Block comments
explain every module, class, function, and method.

[SUN_FEEDBACK.md](../SUN_FEEDBACK.md) contains prioritized issue-ready Sun feedback.
No issues or pull requests are created by this repository's build or test scripts.
