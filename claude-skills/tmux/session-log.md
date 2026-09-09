# tmux Configuration Session Log

Record of what was attempted, what failed, and what worked when building tmux keybindings and scripts. Read this before implementing new bindings to avoid repeating mistakes.

---

## 2026-04-09 — Break Window Into New Session (`prefix D`)

### Goal

Create a keybinding that breaks the current window out of its session into a brand-new session, prompting the user for the session name with the current window name pre-filled — matching the existing statusline-prompt pattern used by `B`, `M`, `S`, and `N`.

### What Was Implemented

**Keybinding** (`prefix D`) in `.tmux.conf`:
```
bind-key D run-shell 'wins=$(tmux list-windows -F "##I:##W" | tr "\n" "|" | sed "s/|$//; s/|/ | /g"); wid=$(tmux display-message -p "#{window_id}"); wname=$(tmux display-message -p "#W"); tmux command-prompt -I "$wname" -p "[$wins] Break to session:" "run-shell \"$HOME/dotfiles/tmux-break-session.sh %% $wid\""'
```

**Helper script** (`~/dotfiles/tmux-break-session.sh`):
```sh
#!/bin/sh
name="$1"
src_window="$2"
[ -z "$name" ] && exit 1
[ -z "$src_window" ] && exit 1
tmux new-session -d -s "$name" -n _placeholder
tmux move-window -s "$src_window" -t "$name"
tmux kill-window -t "$name:_placeholder"
```

### Attempt 1 — FAILED: `move-window` without `-s`

The first script did not capture or pass the source window identity:

```sh
tmux new-session -d -s "$name" -n _placeholder
tmux move-window -t "$name"          # <-- no -s flag
tmux kill-window -t "$name:_placeholder"
```

The keybinding also used bare `#W` in `-I` without thinking through expansion layers, and did not capture `#{window_id}`.

**Why it failed:** `move-window` without `-s` tries to move the "current" window, but the script runs inside `run-shell` spawned by `command-prompt` — at that point, there is no reliable "current window" context. tmux silently fails or targets the wrong thing.

**Lesson:** When a script runs inside a `command-prompt` → `run-shell` chain, you cannot rely on implicit "current window/pane" targeting. Capture the target identity explicitly in the outer `run-shell` (where context is still valid) and pass it as an argument.

### Attempt 2 — FAILED: Wrong `##` escaping for captured values

The second attempt tried to capture the window ID and name using `display-message`, but used `##` (double-hash) for the format variables:

```
wid=$(tmux display-message -p "##window_id")
wname=$(tmux display-message -p "##W")
```

**Why it failed:** Inside `run-shell '...'`, tmux expands format variables before passing to the shell. `##window_id` becomes the literal string `#window_id` — it does NOT expand to the actual window ID. To get the *value*, you need single `#`: `#{window_id}` and `#W`. The `##` escape is for when you want a literal `#` to survive into the shell (e.g., `list-windows -F "##I:##W"` where you want the shell to see `#I:#W` so that `list-windows` can do its own expansion).

**Lesson — the `##` rule precisely stated:** Use `##` when you want a literal `#` to reach the *shell command* (because `run-shell` will eat one `#`). Use single `#` when you want *tmux to expand the format* before the shell sees it. The question to ask: "Do I want tmux to resolve this, or do I want the `#` to pass through to a downstream tmux command?"

### Attempt 3 — WORKED

Captured `#{window_id}` (single `#`, so tmux expands it to e.g. `@117`) and `#W` (expanded to the window name) in the outer `run-shell`. Stored both in shell variables. Passed the window ID through the `command-prompt` callback as a second argument to the script. The script uses `move-window -s "$src_window"` with the explicit source.

### Key Takeaways

1. **Capture identity early, pass explicitly.** In a `run-shell` → `command-prompt` → `run-shell` chain, the outer `run-shell` has valid tmux context (current session/window/pane). The inner `run-shell` (inside `command-prompt` callback) does not reliably inherit it. Always capture IDs like `#{window_id}` or `#{pane_id}` in the outer layer and pass them as script arguments.

2. **`##` vs `#` depends on who needs to expand.** If the current `run-shell` should expand the value: single `#`. If a downstream tmux command (like `list-windows -F`) should expand it: `##` to survive the current layer.

3. **`new-session` + `move-window` + `kill-window` is the pattern for "break to session".** There is no single tmux command for this. The `_placeholder` window name lets us reliably kill the empty default window after the move.

4. **Test `move-window` with explicit `-s` always.** Even outside `run-shell` chains, relying on implicit "current window" for `move-window` is fragile.
---

## 2026-08-18 — Fork This Pane's Claude Conversation (`prefix X`)

### Goal

`prefix X` should fork the Claude Code conversation running in the current pane into a
sibling pane (`prefix C-x` into a new window) with no round trip through Claude itself —
the same fork the `fork-conversation-pane` skill performs, done in pure tmux.

### What Was Implemented

```
bind-key X   run-shell -b '$HOME/dotfiles/tmux-fork-claude.sh "#{pane_id}"'
bind-key C-x run-shell -b '$HOME/dotfiles/tmux-fork-claude.sh "#{pane_id}" -W'
```

The script resolves pane → Claude session id by scanning `~/.claude/sessions/<pid>.json`
(Claude Code >= 2.1.235 records `"tmux":"<session>:@<win>.%<pane>"` there itself), then
delegates to the skill's `fork-pane.sh`, which runs
`claude --resume <id> --fork-session`.

### The Trap — `$TMUX_PANE` Cannot Identify the Caller

The obvious script reads `$TMUX_PANE` to learn which pane invoked it. That is wrong under
`run-shell`, and wrong in the worst way: the variable is usually *present but stale*,
because a `run-shell` child inherits the tmux **server's** environment, not the calling
pane's. Measured on a scratch server: the same `run-shell` saw `#{pane_id}` = `%0` (the
real pane) while `$TMUX_PANE` = `%11` — a pane on an entirely different server, leaked in
from the shell that happened to start that server. A `$TMUX_PANE` script therefore forks
the *wrong* conversation silently instead of failing.

**Fix:** expand `#{pane_id}` in the binding, where tmux has valid context, and pass it as
`$1`. Same rule as the 2026-04-09 `move-window` case: capture identity early, pass
explicitly.

### Related Trap — `display-popup` Does Not Expand Formats on 3.4

The sibling binding `prefix e` (headless Claude diagnosis of the pane's last output) needs
`#{pane_id}` inside a `display-popup -E` command. On tmux 3.4 the popup's shell-command is
*not* format-expanded (3.5 is), so `#{pane_id}` arrives literally. The fix is a `run-shell
-b` hop, which does expand, wrapping the `display-popup` call:

```
bind-key e run-shell -b 'tmux display-popup -E -w 80% -h 80% "$HOME/dotfiles/tmux-claude-explain.sh \"#{pane_id}\" \"#{pane_current_path}\""'
```

### Key Takeaways

1. **Neither `$TMUX_PANE` nor implicit targeting survives `run-shell`.** Formats do. Pass
   `#{pane_id}` / `#{window_id}` as arguments, always.
2. **A stale env var is worse than a missing one** — it turns a crash into a wrong target.
3. **Check whether the command you are nesting expands formats at all** on the installed
   version. `run-shell` always does; `display-popup` only from 3.5.
4. The four remaining traps in the pane → Claude-session lookup (`sdk-cli` one-shots, no
   `TMUX_PANE` under `run-shell`, `read` exiting 1 on a missing trailing newline, no
   `/proc` on macOS) are written up in
   `~/dotfiles/.docs_claude/notes/claude-session-tmux-pane-lookup.md`.

---

## 2026-08-21 — Label Only the Active Pane's Border

### Goal

Show a label ("ACTIVE", or the pane's name) in a top corner of the focused pane's border,
and have it disappear when focus moves away.

### Measuring It Without Touching the Live Session

`capture-pane` returns a pane's *content*, so it can never show a border. The rig that
worked: run the config under test on socket `inner`, then attach to it from a pane on
socket `outer`, and `capture-pane` the outer pane — the inner client's borders arrive as
plain text. Both servers `-f /dev/null`, so the real `.tmux.conf` is not involved. See
"Testing Config Changes Without Touching Your Session" in `SKILL.md`.

### Findings (tmux 3.4)

1. **`pane-border-format` is evaluated per pane**, so `#{?pane_active,LABEL,}` is all the
   conditional needed. An empty expansion leaves an ordinary unbroken border line.
2. **`#[align=right]` works here.** This was the open question — `align` is a
   `format_draw` feature and much of `#[...]` handling in non-status contexts goes through
   `screen_write_cnputs`, which ignores it. Measured: with `align=right` the label sat at
   the active pane's right edge; without it, at the left edge inset 2 cells. Alignment is
   per *pane*, not per window, so each pane labels its own corner.
3. **A single-pane window still spends the border row** (verified by killing the second
   pane — the label stayed and the row was not reclaimed). Hook it back:
   ```
   set-hook -g window-layout-changed 'if -F "#{==:#{window_panes},1}" "set -w pane-border-status off" "set -w pane-border-status top"'
   ```
   Confirmed: splitting flipped it to `top`, killing back down to one pane flipped it to
   `off` and returned the row to the pane.
4. **`top` and `bottom` are exclusive.** There is no way to keep persistent names on the
   bottom border and an active marker on the top one — one label line per pane, total.

### Key Takeaway

Don't reason about which `#[...]` directives survive in a non-status-line format — the
answer differs per option and per version. The two-socket rig answers it in about thirty
seconds.
