# mg — run a command inside a memory-capped group

`mg`, `mgls`, `mgbazel` and the `bazel()` wrapper live in `.functions.sh`, next
to `z`. `mg` puts a command — and everything it ever forks — into a named group
with a memory cap, so a runaway job is killed inside its own group instead of
taking the rest of the machine with it.

```bash
mg -M 40G bazel bazel build //x   # run in bazel.slice, capped at 40G combined
mg -M 8G nb jupyter lab           # any name; the group is made on first use
mgls                              # what is in each group, memory used / cap
mgls -o pid,args bazel            # ps-style columns; args is what pkill -f matches
mgls -p bazel | xargs kill        # bare pids
systemctl --user stop bazel.slice # end everything in a group at once
```

## Why it exists

On 2026-10-16 at 12:54:50, `systemd-oomd` killed 23 units on jke-desktop in
about one second: most tmux panes (and with them most Claude Code sessions),
GNOME Shell, and tracker. The machine did not crash; the tmux server survived
with the four sessions that happened to have no killed panes.

The trigger was an uncapped Bazel build in a fresh `~/repo/xtraffic` checkout
(`--jobs=192` from the workspace `.bazelrc`, on a 62 GB box). Two of the killed
panes had peaked at 48.6G and 44.1G. The same thing had happened on 2026-09-02
(16 scopes) and 2026-09-03 (3 scopes).

Two things made it a sweep rather than one dead build:

- **oomd watches your whole login as one group.** On Ubuntu,
  `user@.service.d/10-oomd-user-service-defaults.conf` sets
  `ManagedOOMMemoryPressure=kill` at 50% for 20s on `user@<uid>.service` —
  everything you run. When that whole group stalls on memory, oomd picks
  victims among the groups inside it.
- **It does not pick the biggest user.** It picks groups whose memory the
  kernel is busy reclaiming. Idle Claude sessions holding ~1 GB each are exactly
  what gets reclaimed under pressure, so they look like good victims; the build
  was one pane among 20-odd.

Capping `--jobs` (`~/.bazelrc`: `build --jobs=64 --local_ram_resources=HOST_RAM*.5`)
lowers the odds but is not a hard bound — fetches and some subprocesses run
outside the jobs budget. A memory cap on a group is a hard bound.

## The program model

### Groups (cgroups) form a tree, and you cannot leave yours by forking

Linux puts every process in exactly one **cgroup**. Groups form a tree, which
is a real directory tree under `/sys/fs/cgroup/`. A child process starts in its
parent's group and **stays there after the parent exits** — backgrounding,
`setsid`, double-forking and daemonizing do not move it. A limit set on a group
applies to its whole subtree **combined**.

```
user@1889656275.service            ← your login; oomd watches this
├── app.slice                        GNOME apps
├── background.slice
├── session.slice                    session daemons
├── tmux-spawn-….scope   (×N)        one per tmux pane
└── bazel.slice  MemoryMax=40G       ← made by mg on first use
    ├── run-….scope   bazel client → bazel server (xtraffic) → compiles
    └── run-….scope   bazel client → bazel server (sirens)   → compiles
```

### Slices, scopes and leaves

- A **leaf** is a group with nothing under it. The kernel only lets processes
  live in leaves.
- A **slice** is systemd's name for a folder in the tree. It holds limits, never
  processes. With no cap it just *sums* what is under it; with a cap, everything
  under it competes for that one budget.
- A **scope** is a leaf holding a command that someone already started — you,
  or tmux for each pane. systemd did not launch it; it only wraps it so it can
  be tracked and capped. (A **service** is the other kind of leaf: systemd
  starts and manages the program itself, e.g. `org.gnome.Shell@x11.service`.)

`mg <name> cmd` = `systemd-run --user --scope --slice=<name>.slice -- cmd`: a
fresh scope (leaf) for `cmd`, inside the `<name>` slice (folder).

### Cgroups are not process groups

| | Process group (pgid) | Cgroup |
|---|---|---|
| For | Terminal job control — Ctrl-C/Ctrl-Z go to the foreground pgid | Kernel accounting and limits: memory, CPU, pids |
| Can a process leave? | Freely, with `setsid`/`setpgid`; daemons always do | Not by forking or daemonizing — only by deliberately writing itself into another group, which is what systemd does on your behalf |
| Limits | None | `MemoryMax`, `RuntimeMaxSec`, … |

This is why `z` caps with a scope rather than `timeout` (see
`.docs_claude/notes/timeout-cannot-cap-a-forking-launcher.md`), and why `mg`
works on Bazel at all.

### Bazel is a client plus a long-lived server

The `bazel` you type is a thin client. Per checkout there is one **server**
(Java), forked by whichever `bazel` command first ran there, and it idles for up
to 3 hours (`--max_idle_secs=10800`). The server detaches from your terminal —
new session, new pgid, so Ctrl-C never reaches it — but it stays in the cgroup
of the pane that started it. The compiles are the **server's** children:

```
├── pane A: bash → bazel (client, exits) → bazel server → compile, compile, …
└── pane C: bazel (client) — only sends a request to pane A's server
```

So wrapping one `bazel run` line in a per-command cap misses the compiles
unless that same command is the one that started the server. The cap has to sit
on a **shared, persistent** slice that every `bazel` call enters, so whichever
call starts a server places it there. One slice also caps all checkouts'
servers **combined**, so several warm checkouts cannot add up past it either.

## What happens at the cap

With `-M`, the slice gets `MemoryMax` and `MemorySwapMax=0`. When everything
in it together reaches the cap, the kernel cannot swap it out, reclaims what
cache it can, then OOM-kills the largest process **inside the slice** — a
compile or a Bazel server. The build fails with an error; your panes are
untouched, and oomd never fires because the rest of the machine still has
~22 GB free.

`mg` also sets `OOMPolicy=continue` on each scope. A scope's default is to stop
the *whole scope* after any OOM kill, which turns one oversized compile into a
dead Bazel server and a cold cache. Measured: a 600M allocation under a 200M cap
was SIGKILLed (137) while its parent shell carried on; without the property the
parent was SIGTERMed too (143).

## How to use it

- **Typed `bazel`** goes through `bazel()` → `mgbazel` → `mg -M 40G bazel bazel …`
  automatically, in any shell that sourced `.functions.sh`.
- **Scripts that call bazel themselves** (e.g. `learning/behavior/workflow/launcher.sh`)
  run the binary, not the shell function. Start them with `mgbazel <script>`.
  The `btrain` and `bft` snippets in `nvim/luasnippets/sh.lua` already do;
  `bce` and `simtest` call `bazel` directly and get the wrapper for free.
- **Anything else memory-hungry**: `mg -M <cap> <name> <cmd>`. Reuse a name to
  share a budget; use a new name for a separate one.
- **Look before you kill**: `mgls`, `mgls -o pid,etime,rss,args <name>`.

## Traps

- **A server started outside the slice stays outside.** `mg` cannot move an
  existing process. If `mgls bazel` does not list a checkout's server, run
  `bazel shutdown` there once (or let it idle out).
- **A dash in the name nests.** `mg bazel-xtraffic …` lands in
  `bazel.slice/bazel-xtraffic.slice` and counts against `bazel`'s cap — useful
  for a sub-budget, surprising otherwise. `mgls` lists a nested slice as its own
  entry, not under its parent.
- **`<command>` must be a program.** `systemd-run` execs it, so shell functions
  and aliases are not visible. That is also why `bazel()` reaching the real
  binary does not recurse.
- **Only shells that sourced `.functions.sh` get `bazel()`.** Claude Code's
  Bash tool does not, so a server Claude starts is uncapped. A `bazel` shim on
  `PATH` ahead of `/usr/bin/bazel` would close that gap and would also cover
  scripts.
- **Caps are `--runtime`.** They live in `/run/user/<uid>/systemd/user.control/`
  and vanish at reboot; any call that passes `-M`/`-H` sets them again, which
  `mgbazel` does every time. Nothing accumulates in `~/.config/systemd`.
- **No user systemd** (macOS, a PSC compute node): `mg` warns and runs the
  command uncapped; `mgls` exits 1.

## Looking back at an incident

oomd's kills are not in `dmesg` and not in `memory.events`, since oomd is
userspace. They are in the user journal:

```bash
journalctl --user --since "-6h" | grep -E "systemd-oomd killed|oom-kill"
oomctl    # what oomd monitors, its limits, current pressure
```

oomd's own reasoning log (`journalctl -u systemd-oomd`) needs the `adm` or
`systemd-journal` group.
