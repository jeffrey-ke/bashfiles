#!/bin/sh
# Runs inside the prefix-P popup. Attaches the popup client to the navigator
# session and drops straight into choose-tree over all sessions/windows.
# Throwaway popup sessions (_popup_*) are filtered out of the tree.
# On selection, the chosen target and the navigator name are handed to
# tmux-tree-pick.sh, which repurposes this popup onto the chosen session.

nav="$1"

exec tmux attach-session -t "$nav" \; \
  choose-tree -Zw \
    -f '#{?#{m:_popup_*,#{session_name}},0,1}' \
    "run-shell -b \"$HOME/dotfiles/tmux-tree-pick.sh '%%' '$nav'\""
