# Follow-up stages

This file preserves platform-validation follow-ups inherited from process_monitor.
The system_monitor terminal now includes process, disk, service, network and
temperature views. The additional collectors also need native ARM64 and macOS
validation; see README.md for current platform limitations.

## 1. Native Linux ARM64 validation

**Prerequisite:** an ARM64 Linux host and binaries built with the released Sun
x86_64 compiler, ARM64 stdlib, and GNU cross linker. A native ARM64 compiler is
not currently published upstream. This workspace only provides x86_64 runtime
validation; ARM64 object generation has been checked.

- Run the CI native ARM64 test job (or the transferred test binaries and
  `tests/acceptance.sun`). Include a multithreaded CPU workload and a known
  resident-memory allocation; verify one-core CPU semantics, process churn, PID
  identity, permissions, history eviction, and recording/replay.
- Exercise terminal resize, display pause while recording, keyboard quit, and
  SIGTERM restoration on a real terminal.
- Measure overhead with the expected robot process count and history duration.
- Record OS, kernel, architecture, compiler revision, and results in this file.

**Acceptance:** the cross build and all native tests pass, memory stays bounded by retained
history plus documented working buffers, and terminal settings restore reliably.
Only then mark Linux ARM64 runtime support verified in the README.

## 2. Native Apple Silicon validation

**Prerequisite:** a native Apple Silicon Mac, Xcode command-line tools, and a
matching Sun toolchain. Mach-O object generation passes here; no Mac runtime is
available.

- Build with `scripts/build.sh`; verify libproc linkage and the BSD identity layout
  against the installed SDK. Confirm CPU counters use the expected Mach timebase.
- Run unit and integration tests natively. Compare controlled CPU and RSS workloads
  against Activity Monitor or native system tools, allowing for sampling timing.
- Verify process enumeration under churn, protected-process behavior, argv parsing
  without environment leakage, stable start identifiers, and ROS labels.
- Exercise terminal settings and resize handling, signals, recording, and replay.
- Record the macOS release, chip, compiler revision, and results here.

**Acceptance:** native runtime tests pass and CPU percentages match controlled
workloads. Update the README's validation status only after these checks.

## 3. Web dashboard platform expansion

Linux x86_64 web hosting now uses the source-built `sun_serve` dependency.
`--ui web|both` provides a bundled offline dashboard and versioned read-only APIs
using the same samples and bounded history as the terminal. Automated integration
checks cover concurrent clients, recording parity, retention, replay completion,
exited identities, and signal shutdown.

Linux ARM64 and macOS web hosting still require upstream support and compatible
library builds. Terminal builds remain available on those targets.
Native browser rendering and real-terminal/browser interaction should also be
checked on release hosts.

## 4. Optional ROS discovery improvements

Best-effort unscoped ROS remaps and explicit labels are implemented. If live ROS
graph discovery or node-scoped remaps are needed, agree the supported ROS
distributions and PID-mapping strategy first. Preserve process-level accounting:
multiple nodes in one process must not be presented as independently measured.

**Acceptance:** discovery handles multiple nodes per process, renamed nodes,
namespaces, process exits, and absent ROS installations without blocking sampling.

## 5. First CI run and release validation

The native build/test/release matrix is in `.github/workflows/ci.yml`. Run it on
GitHub after pushing, inspect all three native job logs, and address any hosted
runner or platform failures before creating a version tag. The workflow and Linux
archive packaging were checked locally; the remote jobs have not run here.

- Record native results for stages 1 and 2; retain the real-terminal and overhead checks.
- Download each archive on a clean matching host and verify `SHA256SUMS` and startup.
- Verify tagged publication and draft recovery with the first intended release.
- Add Developer ID signing/notarization if macOS distribution requires it.

The package workflow installs the latest rolling Sun compiler and matching
standard libraries. Linux ARM64 is
cross-built on x86_64 and tested on a native ARM64 runner. Validate that link step
and the native macOS job in the next GitHub run. Local builds use the same rolling release.
