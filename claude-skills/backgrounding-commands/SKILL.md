---
name: backgrounding-commands
description: Detaches commands with bgrun and streams their logs with bgfind. Use for backgrounded, long-running, or nohup-style jobs.
allowed-tools: Bash(bgrun *), Bash(bgfind --list), Bash(bgfind --preview *), Bash(cat ~/.local/state/bg/*), Bash(tail ~/.local/state/bg/*)
---

# Backgrounding commands

`bgrun` starts a detached command into a session directory; `bgfind` is an fzf picker over
those directories. They share nothing but an on-disk layout, so either works alone.

Both live in `~/dotfiles/bin`, symlinked to `~/.local/bin`. Linux only (`setsid` is
util-linux). Full rationale is in each script's header: `bgrun -h`, `bgfind -h`.

## The layout (the whole interface)

```
$BG_DIR (default ~/.local/state/bg)/<slug>-<YYYYmmdd-HHMMSS>/
    out      stdout          meta     key: value — name, started, host, cwd, cmd, pgid, ended
    err      stderr          status   exit code, written ONLY on exit
```

`meta` and `status` are reserved; every other file is opaque payload. **No `status` file means
still running** — that is the liveness check, not a `ps` lookup.

## Starting a job

```bash
bgrun -- long-training-job --flag          # argv form
bgrun -n simtest -c 'a=$(mktemp) && b ...' # -c for pipes, &&, $(), redirects, heredocs
```

Stdout is the session dir and nothing else, so capture it: `d=$(bgrun ...)`. Returns in ~20 ms
regardless of job length. Chatter goes to stderr.

Pass `-n` whenever the first word of a `-c` string is not a program name — the auto-slug of
`req=$(mktemp ...)` is `req__mktemp`, which is unreadable in the picker.

## Driving it as an agent

**Never launch bare `bgfind`** — it is a full-screen fzf app and there is no tty. Use:

```bash
bgfind --list                 # one line per session: name, state, size, cmd
bgfind --preview <name>       # meta + file table + tail of the newest file
cat "$d/status"; tail -50 "$d/err"
```

Prefer the Bash tool's own `run_in_background` when the job only needs to outlive the current
turn — the harness then re-invokes on exit, which is cheaper than polling. Reach for `bgrun`
when the job must outlive the **session** (terminal closes, Claude exits) or when the user
wants to find it later in the picker.

To wait for a job, use the Monitor tool with an until-loop on `test -f "$d/status"`. Do not
foreground-`sleep` in a poll loop; it is blocked.

## Teaching the user the picker

```
bgfind                # newest activity first
bgfind -p             # print the chosen session dir instead of streaming
bgfind -d /some/dir   # any directory-of-directories works
```

| Key | Does |
|---|---|
| `enter` | stream the session's most recently written file |
| `ctrl-f` | choose which file to stream |
| `ctrl-o` | open the session dir in `$EDITOR` |
| `ctrl-r` | redraw the preview (it does not auto-follow) |

Streaming is `less +F`: `Ctrl-C` leaves follow mode for a normal pager so they can scroll back,
`F` resumes, `q` quits.

## Gotchas

- **bgrun's exit code is not the job's.** It reports only whether the spawn succeeded, and is
  `0` even when the command does not exist. So `bgrun foo && next` runs `next` immediately, in
  the *foreground*, while a `127` sits unread in `$d/status`. Success and liveness both come
  from `status`; `$?` only ever means "did bgrun manage to fork".
- **It wraps one command, not a paste.** bgrun is in the `nohup`/`setsid`/`time` family: it sees
  a single command and cannot look past a `&&`, a `;`, or a newline. Prefixed to a multi-line
  block it backgrounds the first fragment and leaves the rest running in the terminal. The
  caller's shell also expands `$(...)` before bgrun starts, so `bgrun req=$(mktemp)` hands it the
  one word `req=/tmp/tmp.XYZ` -- not a program, exit 127.
- **The argv form is a simple command, not `bash file`.** It runs the way typing the name at a
  prompt does: PATH lookup and shell builtins both work (`bgrun ulimit -n` is fine), but a script
  needs its exec bit and a shebang, neither of which `bash foo` requires. Missing exec bit is 126.
- **Heredocs inside `-c` fail two ways -- put them in a script file instead.** In a
  single-quoted `-c` string the outer shell eats the quotes of `<<'EOF'`, silently leaving
  `<<EOF`, so the body gets expanded; write `<<\EOF`, whose backslash survives the single
  quotes. And the terminator must be at column 0 -- an indented `  EOF` (easy to get from
  copying a rendered code block) never closes the heredoc, so the rest of the script becomes
  payload, `cat` succeeds, and the session exits **0** having run nothing.
- **Killing:** `kill -- -$(sed -n 's/^pgid: *//p' "$d/meta")` takes down the job and every
  child. The supervisor traps TERM/INT and records 143/130, so the session still gets a
  `status`. `kill -9` is untrappable and leaves the session reading as "running" forever.
- **`meta`'s `cmd` is `%q`-escaped** onto one line, so it stays re-runnable and greppable but
  reads badly for shell strings. To log a command verbatim, have the caller write its own
  payload file into the session dir — that is the layout working as intended, not a patch to
  either script.
- Session names are unique by construction, so nothing ever clobbers a previous run's log.
  Old sessions accumulate; `rm -rf` directories under `$BG_DIR` freely, no index to update.
