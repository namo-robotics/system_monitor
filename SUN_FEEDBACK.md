# Sun feedback

Each numbered item below is an independent, issue-ready proposal, ordered by
impact on this project. Each item links to its tracking issue in
`namo-robotics/sun`. Compiler reproducers
were rechecked with the latest released `sun 0.dev (99d822c1060d)` on Linux
x86_64 and still fail in LLVM verification. API-gap proposals were checked
against that revision's stdlib sources. The scoped terminal API proposal
([#294](https://github.com/namo-robotics/sun/issues/294)) has been implemented
upstream and removed from this list.

Some unsafe calls can be removed by refactoring without upstream changes:
`std.process.pid()`, `kill()`, and child helpers already exist. `std.env.Env.args`
also copies argv, although its raw-pointer entry interface still leaves the caller
responsible for pointer validity. New API names below describe proposals.

## 1. P1 — Diagnose conflicting native symbol signatures before LLVM verification

**Issue:** [namo-robotics/sun#293](https://github.com/namo-robotics/sun/issues/293)

**Type:** compiler diagnostic/FFI compatibility bug.

Importing stdlib and declaring a correctly typed POSIX signal callback produces
an LLVM verifier error because stdlib already binds `signal` using integers.

```sun
using std;
extern "C" function install(sig: i32, handler: function (i32) void) raw_ptr<u8> as "signal";
function callback(sig: i32) void {}
function main() i32 {
  unsafe { install(2, callback); };
  return 0;
}
manifest { libraries: ["stdlib.moon"] }
```

Run `sun --emit-obj -o repro.o repro.sun`.

**Actual:** `Call parameter type does not match function signature!`, followed by
`Function verification failed: main`.

**Expected:** a source-level diagnostic identifying both conflicting declarations
and the shared native symbol, or supported ABI-compatible signature adaptation.
A typed stdlib signal-registration API would avoid redeclaration entirely.

**Impact/workaround:** terminal shutdown must reliably restore terminal settings.
The monitor currently mirrors stdlib's integer signature and explicitly converts
the callback address at its small unsafe FFI boundary (`src/posix.sun`).

**Acceptance:** the example either compiles with correct ABI behavior or fails
with a precise source diagnostic; incompatible extern declarations imported from
moons are covered by compiler tests.

## 3. P2 — Add safe borrowed streams and bounds-checked byte I/O

**Issue:** [namo-robotics/sun#295](https://github.com/namo-robotics/sun/issues/295)

**Type:** standard-library safety and ergonomics.

`File.read_into` and `write_bytes` currently accept a raw pointer and a separate
length. Merely calling these through a safe-looking method does not prove the
buffer is valid or large enough. The monitor also needs stdin/stdout/stderr without
adopting ownership and accidentally closing shared descriptors.

**Proposed capability:** borrowed standard streams with `read` into a mutable
bounded slice, `write_all` from a read-only slice, and explicit EOF/would-block
results. Handle partial operations and EINTR inside the implementation. Include
bounds-checked native-endian integer decoding for OS response buffers.

**Impact:** replaces raw reads/writes, pointer offsets, and Darwin argv integer
loads in `src/posix.sun`, `src/terminal.sun`, `src/app.sun`, and `src/darwin.sun`.

**Acceptance:** short-I/O, interruption, empty-buffer, invalid-range, and borrowed
ownership tests; safe APIs cannot request access beyond a supplied buffer.

## 4. P2 — Provide signal events and a lock-free atomic flag

**Issue:** [namo-robotics/sun#296](https://github.com/namo-robotics/sun/issues/296)

**Type:** missing standard-library capability.

The monitor registers POSIX callbacks through an integer ABI and uses raw atomic
intrinsics to communicate shutdown. An ordinary callback abstraction is not enough:
allocating or acquiring locks inside a native signal handler can deadlock.

**Proposed capability:** a scoped signal subscription that exposes events to the
existing poller; handlers perform only documented async-signal-safe operations.
Also provide an atomic Boolean with documented memory ordering and lock-free
behavior on supported targets. Keep handler installation and restoration explicit.

**Impact:** removes callback-address conversions and atomic pointer operations
from `src/app.sun` and `src/posix.sun`.

**Acceptance:** repeated SIGINT/SIGTERM delivery, event-loop wakeup, handler
restoration, and signal-context safety on Linux and macOS. A generic atomic API
must not claim signal safety if its implementation can fall back to locks.

## 5. P2 — Add process inspection and identity-bound process handles

**Issue:** [namo-robotics/sun#297](https://github.com/namo-robotics/sun/issues/297)

**Type:** missing standard-library capability.

The existing `std.process.pid()`, `kill()`, and child-process APIs cover some of
our bindings already. They do not replace portable enumeration/resource snapshots
or an identity-bound handle to an arbitrary visible process.

**Proposed capability:** process identity (PID plus start marker), cumulative CPU
time with explicit units, RSS, executable/arguments, system physical memory, and
page size. Return unavailable data distinctly. Provide an owned process handle
with terminate/kill and explicit platform guarantees for PID reuse protection.
Linux can use pidfds; do not silently promise equivalent atomic protection for a
macOS implementation that only checks identity before POSIX kill.

**Impact:** centralizes the libproc, sysctl, sysconf, readlink, and pidfd bindings
currently maintained in `src/linux.sun`, `src/darwin.sun`, and `src/control.sun`.

**Acceptance:** native tests for exits, permission errors, reused identities,
units, handle closure, and unsupported kernel facilities. Inspection requires no
privileges beyond those of the caller.

## 6. P2 — Reject bare returns in value-returning functions during semantic analysis

**Issue:** [namo-robotics/sun#298](https://github.com/namo-robotics/sun/issues/298)

**Type:** compiler diagnostic bug.

```sun
using std;
function invalid() bool { return; }
function main() i32 {
  if (invalid()) { return 0; }
  return 1;
}
manifest { libraries: ["stdlib.moon"] }
```

Run `sun --emit-obj -o repro.o repro.sun`.

**Actual:** `Function return type does not match operand type of return inst!`,
then an LLVM function-verification failure.

**Expected:** a source diagnostic at `return;` explaining that a Boolean value is
required. Check nested branches and unsafe blocks as well as direct returns.

**Impact/workaround:** changing a terminal input method from `void` to `bool`
exposed this; the application now supplies explicit values on every return path.

**Acceptance:** semantic analysis rejects every reachable bare return in a
non-void function, without relying on LLVM verification.

## 7. P3 — Strengthen typed FFI declarations and ABI validation

**Issue:** [namo-robotics/sun#299](https://github.com/namo-robotics/sun/issues/299)

**Type:** language/FFI improvement.

Handwritten bindings currently use opaque aligned buffers, manually mirrored C
layouts, integer request codes, and an integer callback workaround. Removing the
`unsafe` keyword around these operations would not establish their correctness.

**Proposed capability:** typed C callbacks with a declared calling convention,
explicit C-layout declarations with size/alignment/offset checks, and a documented
binding-generation path using target SDK headers. Support scoped buffer borrowing
at FFI boundaries so pointers cannot outlive their backing storage. Diagnose
conflicting declarations before code generation, as in [item 1](https://github.com/namo-robotics/sun/issues/293).

**Impact:** makes terminal and macOS collector wrappers smaller and easier to
audit. Keep unverifiable foreign contracts inside a small unsafe implementation.

**Acceptance:** ABI tests against native C layouts on all supported architectures,
callback mismatch diagnostics, and examples that reject escaped borrowed pointers.

## 8. P3 — Add bounded buffered line reading for arbitrary files

**Issue:** [namo-robotics/sun#300](https://github.com/namo-robotics/sun/issues/300)

**Type:** missing standard-library convenience/API.

`std.io.read_line` reads standard input; `File.read_all` reads an entire file.
Streaming recordings need a buffered line reader attached to an arbitrary file,
with a maximum line length and an explicit incomplete-final-line result.

**Proposed capability:** a reusable reader returning complete lines, EOF, and
truncated final data distinctly, while handling short reads and interrupted I/O.

**Impact/workaround:** `Replay` in `src/recording.sun` maintains its own bounded
buffer so a long recording is not loaded into memory at once.

**Acceptance:** tests cover empty files, partial reads, large files, overlong
lines, newline boundaries across buffers, and interrupted final records.
