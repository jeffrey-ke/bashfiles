# `timeout` caps only its direct child, so a forking launcher escapes it

Why `timeout 1h some-launcher` returns instantly with status **0**, the limit never
applies, and the program keeps printing into a returned prompt. This is the failure
that made `z` (`.functions.sh`) stop using `timeout` on Linux.

## Mechanism

`timeout` waits on, and signals, **one process**: the child it forked. Descendants are
not its concern. So for any command that starts the real work and returns — a launcher,
a wrapper script, anything that backgrounds a job — `timeout`'s child exits within
milliseconds, `timeout` exits with *the child's* status, and nothing is ever capped.
The orphan keeps the inherited tty and writes on top of the prompt the shell just drew.

Measured on jke-desktop against a five-line launcher that backgrounds a printing loop
and exits (`( while ...; done ) & echo exiting`):

| command | returns after | status | worker after the limit |
|---|---|---|---|
| `timeout --foreground -k 10s 5s ./launcher.sh` | **0.007s** | **0** | still running, ran to completion |
| `systemd-run --user --scope --property=RuntimeMaxSec=5 ./launcher.sh` | 0.01s | 0 | **killed at 5s** |

Two corollaries that are easy to get wrong:

- **Dropping `--foreground` does not fix it.** Without that flag `timeout` puts itself in
  a new process group and signals the whole group, which *would* reach descendants — but
  only on timeout, and there is no timeout, because the direct child already exited. The
  group kill never runs. (It also costs interactivity: a child in its own process group
  never sees Ctrl-C and is stopped by SIGTTIN/SIGTTOU on its first tty read.)
- **`--foreground` makes the tree strictly less reachable**, since it signals the direct
  child *only*. Its documented costs — no descendants, and no enforcement while the child
  is stopped — are the reason it cannot be the answer for a launcher.

## Fix: a cgroup, which a process tree cannot leave

`systemd-run --user --scope --property=RuntimeMaxSec=...` runs the command in a transient
cgroup. Membership is inherited and cannot be shed: fork, double-fork and `setsid` all
stay inside it, and scope units default to `KillMode=control-group`, so the stop signal
goes to every task rather than one pid.

Verified on systemd 255 (255.4-1ubuntu8.17), `XDG_RUNTIME_DIR=/run/user/<uid>`:

| property | how it was checked | result |
|---|---|---|
| Interactivity preserved | `ps -o pgid=,tpgid=` inside the scope, under a real pty | `pgid == tpgid` — it *is* the terminal's foreground group, so Ctrl-C and tty reads reach it |
| Same session | `ps -o sid=` inside vs. the invoking shell | equal; `--scope` does not `setsid` |
| stdin reaches the command | `read -r` inside the scope, under a pty | read the typed line |
| Exit status propagates | `bash -c 'exit 7'` in a scope | `rc=7` |
| Tree is capped | forking launcher, `RuntimeMaxSec=5` | output stopped at 5s, cgroup empty |
| Cap outlives the waiter | SIGINT to the shell running `z`, then watch | shell returned 130, worker survived, systemd killed it anyway |
| Time-span syntax | `systemd-analyze timespan` | `5s`, `45m`, `1h`, `1.5h`, `3600` all accepted — same spellings `timeout` takes, so no conversion needed |

Because the deadline is held by systemd rather than by the shell, the supervising
function is optional: interrupting it gives the prompt back **without** losing the cap.

## Traps

- **`is-active` answers "no" while the tree is still dying.** The instant the cap fires
  the unit enters **`deactivating`**, and `systemctl --user is-active --quiet` already
  exits non-zero — while every process in the cgroup is still running its exit path, for
  up to `TimeoutStopSec`. Polling on `is-active` therefore returns the prompt *mid
  teardown* and the dying program's output lands on top of it, which is the exact
  symptom the supervision exists to prevent. Measured with a descendant that traps
  SIGTERM and prints for 6s:

  | t | `ActiveState` | `is-active --quiet` | descendant alive |
  |---|---|---|---|
  | cap fires | `deactivating` | **no** | yes, printing |
  | +6s | `inactive` | no | no |

  Poll `show -p ActiveState --value` and treat anything other than `inactive`/`failed`/
  empty as live (`_z_scope_live`).
- **`systemctl --user is-active <name>` defaults to `.service`.** Polling a scope by the
  name passed to `--unit=` reports "inactive" immediately while the scope is plainly
  alive. The `.scope` suffix is required. This one silently inverts the result.
- **`--collect` makes `Result` unreadable.** It GCs the unit as soon as it goes inactive,
  so you cannot read back `-p Result --value` to learn whether `RuntimeMaxSec` fired.
  Infer it from elapsed wall clock instead (what `_z_scope` does to return 124).
- **A daemon started inside the cgroup is in the cgroup.** If the capped command is what
  starts a long-lived build server, that server joins the scope, keeps it "active", and
  is killed by the limit. `_z_scope` prints the surviving tasks for exactly this reason.
- **Verifying survivors with `pgrep -f` / `ps | grep` self-matches.** The pattern appears
  in the command line of the checking shell and of any `$( )` subshell it spawns, which
  inflates the count and fakes a survivor. Match on `args$` or check pids directly.
- **Reaping lags the kill.** A count taken immediately after the cgroup dies can still
  show one task; it is gone a second later.

## The cap looks like a crash: glog hijacks SIGTERM

A glog-linked program prints a full failure report when the cap fires — `*** Aborted at
<unix time> ***`, `PC: @ 0x0 (unknown)`, `*** SIGTERM (@0x...) received by PID <pid> from
PID <sender>; stack trace: ***`, then a symbolized stack. It reads like a segfault and is
not one: `InstallFailureSignalHandler` registers SIGTERM alongside the genuine fault
signals, so a perfectly ordinary stop request goes down the crash-reporting path.

Confirmed against nv2's own binary rather than from docs — its glog signal-name table is
exactly the six failure signals, and **SIGINT is not among them**:

```console
$ strings -a .../nuroviewer/run_hermetic_viewer.runfiles/nuro/tool/nuroviewer/nuro_viewer \
    | grep -xE 'SIG(SEGV|ILL|FPE|ABRT|BUS|TERM|INT|HUP|QUIT)' | sort -u
SIGABRT SIGBUS SIGFPE SIGILL SIGSEGV SIGTERM
```

So `z -S INT 1 n nv2 --enable-comms` caps it with no trace at all: glog ignores SIGINT,
and bash also stays quiet (it prints `Terminated` for SIGTERM but nothing for SIGINT).

Two things to read correctly in that report. `from PID <n>` is the *sender* — for a scope
that is `systemd --user`, i.e. the cap firing, not a mystery killer. And the stack is
wherever the main thread happened to be (for nv2, Qt's paint path through NVIDIA GLX);
it says nothing about a fault.

What the crash path does cost is a **graceful shutdown**: glog dumps the trace and
re-raises with the default disposition, so destructors and `atexit` handlers never run.
Nothing leaks — the kernel reclaims memory, mappings and fds, the cgroup guarantees no
orphans, and a check after a run found `/dev/shm` empty, no unattached SysV segments, and
no GPU memory held — but anything a clean exit would have *written* (settings, a window
layout, an orderly unregister from a peer) is simply not written. `-S INT` is the fix
where the program handles it.

## Where this does not apply

macOS, and PSC compute nodes inside a Slurm job, have no user systemd instance
(`$XDG_RUNTIME_DIR/bus` is the test `_z_have_scope` uses). There `z` falls back to
`timeout --foreground`, which is correct for what actually runs on those machines —
training scripts that stay in the foreground — and still cannot cap a launcher.
