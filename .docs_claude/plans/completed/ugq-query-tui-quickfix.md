# `ugq`: ug's -Q TUI selections → nvim quickfix

## Goal

Keep the exact interactive workflow of the `ug` alias (`ug -Q -Z`: type a pattern,
live fuzzy results) but fix its one gap: CTRL-Y only ever opens the *file* — ugrep's
`--view`/`$EDITOR` handoff is given a filename, never a line number. `ugq` wraps the
same TUI so that lines selected inside it land in an nvim quickfix list with accurate
line *and column* jumps. Bare `ugq` must behave like bare `ug`: straight into the TUI,
pattern typed live.

## Final solution

`ugq()` in `.functions.sh`:

```bash
ugq() {
	local out pattern=
	if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
		pattern="$1"; shift
	fi
	out=$(command ug -Q -Z -n -k -H --no-heading --no-initial-tab ${pattern:+-e "$pattern"} "$@" \
		| sed $'s/\x1b\\[[0-9;]*[mK]//g')
	if [ -z "$out" ] && [ -n "$pattern" ]; then
		out=$(command ug -Z -n -k -H --no-heading --no-initial-tab -e "$pattern" "$@")
	fi
	[ -n "$out" ] || return 0
	nvim -q <(printf '%s\n' "$out") -c 'cwindow'
}
```

Workflow: `ugq [pattern] [dir|file|ug-flags...]` (all args optional) → ugrep's own -Q
TUI → `Enter` toggles selection mode → `Enter`/`Del` toggle lines, `A` selects all →
`Ctrl-Q` exits and prints the selected rows → nvim opens at the first selection's
line:col with the rest in the quickfix window (`:cn`, `:copen`).

No-selection fallback (added on user request after first use): quitting the TUI with
nothing selected batch re-runs the *seeded* pattern and loads ALL its matches into
quickfix. A pattern typed or refined live in the TUI is not recoverable after exit —
verified in source: the TUI's history/bookmark state is in-memory only (a
`std::stack`, no file I/O) and `--save-config` writes options, never the query — so
bare `ugq` keeps the clean exit (use `Enter`,`A`,`Ctrl-Q` for select-all there), and a
seeded-but-refined pattern falls back to the original seed. Since exit status can't
distinguish Esc from Ctrl-Q (`main` returns `Stats::found_any_file()` either way),
Esc on a seeded run also triggers the fallback — bail with `:qa!`.

## Why each flag — verified against ugrep v5.0.0 source (installed version)

The design hinges on facts read directly out of ugrep v5.0.0's source
(`screen.cpp`, `query.cpp`, `ugrep.cpp` — fetched from GitHub at tag v5.0.0):

- **`$(...)` capture is safe around the TUI**: `Screen::setup()` opens `/dev/tty`
  O_RDWR directly (`screen.cpp:272`); stdout is only a fallback when `/dev/tty` fails.
  The TUI draws on the terminal while command substitution captures only what
  `Query::print()` (`query.cpp:3573`) writes to stdout on exit — the selection-mode
  rows. ugrep's README demos exactly this pattern:
  ``unzip project.zip `zipinfo -1 project.zip | ugrep -Q` ``.
- **`-e "$pattern"`**: with `-Q`, positional args are FILEs; "a PATTERN argument
  requires option -e" (man page). This is also what makes the pattern *optional* —
  no `-e` means the TUI starts with an empty prompt.
- **`--no-heading`**: `ug` + `-Q` force-enables `--pretty` → `--heading`
  (`ugrep.cpp:7287,7312`), whose per-file heading blocks nvim can't parse.
- **`-H --no-initial-tab`**: without them the rows come out as `    17: 11:\ttext` —
  filename omitted for single-file searches (grep convention) and numbers
  space-padded + tabbed by pretty's initial-tab. With them: `file:17:11:text`,
  exactly nvim's default `errorformat` `%f:%l:%c:%m`. (Found empirically via the
  tmux probe below; the padding disappears with `--no-initial-tab`.)
- **the `sed` strip**: `-Q` forces `--color=always` even when stdout is a pipe
  (`ugrep.cpp:7271`) so the TUI stays colored, and `Query::print()` only strips CSI
  sequences when color is *off*. `--color=never` would render the whole TUI
  monochrome, so instead the SGR/EL codes (`\e[...m`, `\e[...K`) are stripped
  shell-side. NUL pathname markers are already stripped by `Query::print()` itself.
- **`command ug`** bypasses the `ug -Q -Z` alias but still auto-loads `~/.ugrep`
  (ignore-binary/hidden/gitignore/sort defaults) — config loading is keyed off the
  binary name, not the alias.
- A leading-dash first arg is passed through as a flag rather than a pattern
  (`ugq -i` → case-insensitive TUI, pattern typed live).

Cosmetic tradeoff accepted: `--no-heading` means the TUI lists `file:line:col: text`
rows instead of the pretty per-file heading groups. Inherent to making the output
parseable; plain `ug` keeps the pretty view.

## What didn't work, and why

1. **fzf as the interactivity layer (two prior `ugq` iterations).** A batch
   `ug -r -n -k -Z` scan piped into `fzf --multi` with a preview pane. Wrong on
   design: it required the pattern up front (no live re-querying), never showed
   ugrep's TUI, and its preview broke in real use (`/bin/bash` error) despite passing
   a synthetic check — `fzf --filter` mode never exercises `--preview`, so the
   "verification" verified nothing. Replaced wholesale by ugrep's native selection
   mode, which needs no second UI.
2. **Scripting the -Q TUI in a raw pty** (python `pty` module): always fails with
   `ugrep: no ANSI terminal screen detected`. Root cause is not stdout redirection —
   `Screen::setup()` probes the terminal by writing a cursor-position query and
   *reading the response back* (`screen.cpp:300`); a bare pty with no terminal
   emulator behind it never answers. tmux does answer, which is why all verification
   is tmux-driven.

## Files touched

- `~/dotfiles/.functions.sh` — `ugq()` + comment block (replaced the fzf version)
- `~/dotfiles/.docs_claude/plans/completed/ugq-query-tui-quickfix.md` (this doc)
- `~/dotfiles/.docs_claude/PLANS_TOC.md` — chronological + topic entries

## Verification (tmux-driven, 2026-07-12)

From a detached `tmux` session (200×50):

- **Capture-format probe**: `out=$(command ug -Q -Z -n -k -H --no-heading
  --no-initial-tab -e tmux .bash_aliases | sed ...)` driven with send-keys
  (`Enter` → `A` → `C-q`), output dumped through `cat -A`: four clean
  `/home/jeffk/dotfiles/.bash_aliases:17:11:alias ta='tmux attach'`-style rows,
  no `^[[` escapes, no NULs, no padding.
- **`ugq tmux ~/dotfiles/.bash_aliases`**: TUI up with seeded pattern; selection
  mode, toggled 2 of 4 rows, `C-q` → nvim opened at `.bash_aliases` 17:11
  ("(1 of 2)"), quickfix held exactly the 2 selected entries with correct line/col.
- **Bare `ugq`** (the headline fix): TUI opened immediately with empty prompt from
  `~/dotfiles`; typed `prefix` live → results updated across `.bash_prompt`,
  `.functions.sh`, `.tmux.conf` (hidden files in, `.git` out — `~/.ugrep` honored);
  selected 2 rows → nvim at `.bash_prompt` 4:52, `:copen` showed both entries.
- **Abort path**: bare `ugq`, `Esc` + confirm → shell prompt back, no nvim, exit 0.
- **Regression**: `ug` alias untouched (`.bash_aliases` not modified).
- `bash -n .functions.sh` clean.

Fallback round (same tmux method):

- `ugq tmux .bash_aliases` → `Ctrl-Q` immediately, no selection → nvim at 17:11,
  "(1 of 4)", `:copen` listed all 4 matches.
- Bare `ugq`, typed `prefix` live, `Ctrl-Q` with no selection → clean exit 0, no nvim.
- Selection still wins over fallback: seeded run, one line toggled → quickfix "(1 of 1)".
