# tmux popup-window binding

Added a `prefix P` toggle: prompt for a window, open it in a popup; press `prefix P` again inside the popup to close.

## Changes

**`.tmux.conf`** — new binding right after the existing `D` break-to-session binding:

```tmux
bind-key P if -F '#{m:_popup_*,#{session_name}}' { detach-client } { run-shell 'wins=$(tmux list-windows -F "##I:##W" | tr "\n" "|" | sed "s/|$//; s/|/ | /g"); tmux command-prompt -p "[$wins] Popup window:" "run-shell \"$HOME/dotfiles/tmux-popup-window.sh %%\""' }
```

The `if -F` checks whether the current session name matches `_popup_*` (the transient session created for the popup). If yes, `detach-client` closes the popup. If no, run the existing list-windows → command-prompt → script flow (mirrors `M`, `S`, `N`, `D`).

**`tmux-popup-window.sh`** (new, executable):

```sh
#!/bin/sh
src="$1"
session=$(tmux display-message -p '#S')

case "$session" in
  _popup_*)
    tmux display-message "tmux-popup: already in a popup"
    exit 1
    ;;
esac

if ! tmux display-message -p -t ":$src" '#{window_id}' >/dev/null 2>&1; then
  tmux display-message "tmux-popup: no window matching '$src'"
  exit 1
fi

popup_session="_popup_$$"
tmux new-session -d -s "$popup_session" -t "$session"
tmux select-window -t "${popup_session}:$src"
tmux display-popup -E -w 80% -h 80% "tmux attach-session -t '$popup_session'"
tmux kill-session -t "$popup_session" 2>/dev/null
```

## Design choices

- **Grouped session** (`new-session -t $session`) — popup session shares the main session's window list, then `select-window` focuses the target. Independent active-window pointer per session means the popup can view a different window than the main client without disturbing it.
- **Nesting guard** — `_popup_*` session-name check in both the binding and the script. Binding-level check repurposes `prefix P` as the dismiss key (no new hotkey needed); script-level check is defense in depth.
- **Dismiss via `prefix P`** — chosen over a single-key root binding (e.g. F11, `M-q`) because the open key is already idle inside the popup. Symmetric, uses existing muscle memory, no global root-table pollution, and `C-Space` is always captured by tmux before the inner pane sees it.
- **Cleanup** — `display-popup -E` blocks until the inner `tmux attach` exits; `kill-session` on the line after cleans up the transient session. Linked windows in the main session are untouched (kill-session only removes windows that aren't linked elsewhere).

## Alternatives considered (not adopted)

- **Single-window via `link-window`** — would link only the target window into a fresh standalone popup session instead of grouping. Cleaner scope, but the grouped approach was kept since the popup is already focused on one window and the user didn't request the narrower scope.
- **Root-table dismiss key (F11, `M-q`)** — works via `bind -T root <key> if -F '...' detach-client { send-keys <key> }`, but globally reserves a keystroke. Rejected once `prefix P` toggle was suggested.
- **Custom `key-table popup`** ([Will Richardson pattern](https://willhbr.net/2023/02/07/dismissable-popup-shell-in-tmux/)) — scopes dismiss key to the popup session without touching root, but disables all other bindings inside the popup unless re-forwarded. Overkill once the `prefix P` toggle covered the use case.
