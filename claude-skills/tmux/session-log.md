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