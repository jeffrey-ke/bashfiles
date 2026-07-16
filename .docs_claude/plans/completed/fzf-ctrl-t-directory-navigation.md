# fzf Ctrl-T directory navigation

## Context

Started from a simple question: is Ctrl-T's search root configurable, since sometimes the
wanted file is one directory up from cwd. fzf's shell integration has no built-in way to
change the walker's root mid-search — `FZF_CTRL_T_COMMAND`/`--walker-root` are fixed at
launch. The fix that emerged uses fzf 0.70's `become` action (execve-replaces the current
fzf process with a new command) to `cd` and relaunch fzf rooted at a different directory —
a real process-level cwd change, not a cosmetic re-listing, so repeated presses compose
correctly across multiple hops.

The scope grew through the conversation into a small yazi-style in-picker file browser:
up a level, descend into a highlighted directory, jump back to the origin, always insert
the selected path relative to wherever Ctrl-T was originally pressed regardless of how
far the picker wandered, and finally display the current directory in the picker itself
so the wandering is actually visible.

## Approach

Bindings (yazi hjkl mnemonics), added to `.bash_tools`'s existing `fzf --bash` block:

- **Ctrl-H** — up to the parent directory (repeatable)
- **Ctrl-L** — descend into the highlighted directory (no-op on files)
- **Ctrl-D** — jump back to the directory Ctrl-T was originally opened in

Each is `become(function_name)`. The functions `cd` then call a shared
`_fzf_ctrl_t_relaunch`, which rebuilds `FZF_DEFAULT_OPTS`/`FZF_DEFAULT_COMMAND` from
`FZF_CTRL_T_COMMAND`/`FZF_CTRL_T_OPTS` (mirroring fzf's own `__fzf_select__`) and execs
`fzf` again — inheriting the new cwd, so the walker re-roots there. `FZF_CTRL_T_OPTS`
itself carries the three binds, so it's self-referential: each relaunch's fzf instance
gets the same three binds again, letting hops repeat indefinitely.

Origin tracking: fzf's own Ctrl-T widget (`fzf-file-widget`) doesn't remember where it
started, so Ctrl-T itself is rebound to a wrapper (`_fzf_ctrl_t_widget`) that stamps
`_FZF_CTRL_T_ORIGIN=$PWD` before launching, which `_fzf_ctrl_t_origin` reads back on
Ctrl-D.

Relative-path rebasing (the final ask): env vars set *inside* the `become` chain can't
propagate back to the widget, because the whole chain runs inside `__fzf_select__`'s
`$(...)` command substitution — a subshell, whose exports die with it. So there's no way
for the widget to directly ask "what cwd did the final accept happen in?" The fix is a
temp file as the return channel (same pattern `y()`'s yazi `--cwd-file` already uses
lower in the same file): `_fzf_ctrl_t_relaunch` stamps its `$PWD` into
`_FZF_CTRL_T_CWDFILE` every time it's about to launch fzf, so by the time the whole chain
exits the file holds the cwd of whichever fzf instance was alive at accept. The widget
reads it back, and rebases the raw selection (relative to that final cwd) onto the origin
dir with `realpath --relative-to`, re-escaping with `%q` before insertion (handles
multi-select and filenames with spaces correctly — see Verification).

Current-directory display (the final ask): `_fzf_ctrl_t_relaunch` passes
`--header="$PWD"` on every launch, so the header always reflects whichever directory
that particular fzf instance is rooted in — no dynamic update mechanism needed, since
every hop is already a fresh fzf process by construction.

## What didn't work, and why

### `transform` silently stops firing on any process reached via `become`

First design for Ctrl-L used a conditional: `ctrl-l:transform:[ -d {} ] && echo
"become(_fzf_ctrl_t_down {})" || echo ignore`, so it would only descend into actual
directories. Worked perfectly in a standalone, non-chained `fzf` invocation. Once wired
into the real Ctrl-H → Ctrl-L chain, it silently did nothing — no error, the transform's
shell command never even ran (confirmed by instrumenting it to log to a file, which
stayed empty). Isolated with a minimal repro outside `.bash_tools` entirely: one `become`
hop, then bind a key to `transform`, and it never fires; the exact same key bound to
`execute-silent` or another `become`, on the exact same post-`become` process, fires
fine. So the bug is specific to `transform` (which needs to run synchronously and read
the command's stdout to decide the next action) on a process that itself arrived via
`become` — plausibly a tty/pty state issue from the execve, not something fixable from
the config side. This is against fzf 0.70; not verified on other versions.

Fixed by dropping `transform` entirely: Ctrl-L always `become`s
(`ctrl-l:become(_fzf_ctrl_t_down {})`), and the directory check moved inside
`_fzf_ctrl_t_down` itself (`[ -d "$1" ] && cd -- "$1"`) — not-a-directory is a harmless
no-op relaunch in place, no conditional dispatch needed before the become fires.

### `__fzf_select__` doesn't know about `_fzf_ctrl_t_relaunch`'s custom options

First cut of the header only added `--header="$PWD"` inside `_fzf_ctrl_t_relaunch`,
reasoning that every fzf launch — initial and every hop — goes through it. False: the
*initial* Ctrl-T launch was still going through fzf's own `__fzf_select__` (called
directly from `_fzf_ctrl_t_widget`), which builds its own `FZF_DEFAULT_OPTS` via fzf's
`__fzf_defaults` helper and has no knowledge of anything `_fzf_ctrl_t_relaunch` does. The
header was silently invisible until the first Ctrl-H/L/D hop, which *does* go through
`_fzf_ctrl_t_relaunch`. Caught with a scripted pty test that set a real terminal window
size (`ioctl(TIOCSWINSZ)`) and checked the rendered screen for the path string right
after the bare Ctrl-T press, before any hop. Fixed by having `_fzf_ctrl_t_widget` call
`_fzf_ctrl_t_relaunch` for the initial launch too, wrapped in the same `%q`-escaping
pipe `__fzf_select__` itself uses (`| while read -r item; do printf '%q ' "$item"; done`)
— so escaping is still applied exactly once, at the outermost layer, for both the
initial launch and every subsequent hop.

### Key binding overrides and their tradeoffs

Ctrl-H/L/D override fzf defaults: Ctrl-H is `backward-delete-char` (the *physical*
Backspace key sends a separate `bspace` code, so real backspacing is unaffected — only
the literal Ctrl-H chord is repurposed), Ctrl-L is `clear-screen`, Ctrl-D is
`delete-char`/abort-if-query-empty. Ctrl-C still aborts/restarts the query in all cases.
The user was walked through this tradeoff explicitly (originally proposed Ctrl-Alt-U to
avoid any collision at all, then asked to switch to the colliding Ctrl-U/Ctrl-H/Ctrl-L
bindings once they understood what each one gives up) rather than picked unilaterally.

## Files

- `~/dotfiles/.bash_tools` — new block inside the existing `if command -v fzf` guard:
  `_fzf_ctrl_t_relaunch`/`_fzf_ctrl_t_up`/`_fzf_ctrl_t_down`/`_fzf_ctrl_t_origin`,
  `FZF_CTRL_T_OPTS` bind string, and `_fzf_ctrl_t_widget` (replaces the default
  `fzf-file-widget` binding on Ctrl-T in all three readline keymaps) with the
  relative-path rebasing logic

## Verification

All of this is interactive TUI behavior — no way to observe it through a plain piped
`fzf < input > output` run, since the binds fire on real keypresses against a live
terminal. Verified with a Python harness (`pty.fork()` + a real bash `--rcfile` session),
responding to fzf's `ESC[6n` cursor-position-report query so it doesn't hang waiting for
a real terminal, then writing raw key bytes (`\x08` Ctrl-H, `\x0c` Ctrl-L, `\x04` Ctrl-D,
`\t` Tab for multi-select) and reading back either debug-log side-effects or the final
inserted command-line text:

- Up (Ctrl-H) three times from a nested dir walked the cwd up three real levels
  (confirmed via a file only findable from the grandparent).
- Ctrl-D correctly jumped back to the origin after two Ctrl-H hops (found a file with no
  path prefix, proving cwd was exactly restored).
- Full combined sequence — Ctrl-H → Ctrl-L (descend into a sibling) → Ctrl-H → Ctrl-D —
  landed back at the exact origin.
- Relative-path rebasing: plain select unaffected; select-after-Ctrl-H produced
  `../sibling/file.txt`; select-after-descend produced `../sibling/deep/deepfile.txt`;
  select-after-Ctrl-D (back at origin) had no prefix; multi-select with a
  space-containing filename round-tripped correctly (`../sibling/has\ space.txt`).
- Regression: `source ~/.bashrc` twice in the same session (picking up config changes
  without a new terminal) produces no syntax errors after these changes.
- Header: with a real pty window size set, the current directory is visible in the
  rendered screen immediately after the bare Ctrl-T press (not just after the first
  hop), and updates correctly on each subsequent Ctrl-H/L hop.
