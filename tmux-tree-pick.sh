#!/bin/sh
# choose-tree selection callback. Given the chosen target ($1) and the
# navigator session name ($2), open the chosen window's session in the popup
# via a grouped throwaway session so the user's real session/current-window is
# never disturbed.

target="$1"
nav="$2"

sess=$(tmux display-message -t "$target" -p '#{session_name}' 2>/dev/null) || exit 0
idx=$(tmux display-message -t "$target" -p '#{window_index}' 2>/dev/null) || exit 0

# The popup client is the one currently attached to the navigator session.
client=$(tmux list-clients -t "$nav" -F '#{client_name}' 2>/dev/null | head -1)
[ -z "$client" ] && exit 0

grp="_popup_grp_$$"
tmux new-session -d -s "$grp" -t "$sess"
tmux select-window -t "$grp:$idx"
tmux switch-client -c "$client" -t "$grp:$idx"
