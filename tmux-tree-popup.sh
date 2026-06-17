#!/bin/sh
# Orchestrator for `prefix P`: open a popup showing a choose-tree of all
# sessions/windows; on selection the popup is repurposed to show the chosen
# window's session (isolated via a grouped throwaway session). Runs in the
# main client's context (invoked from the key binding's run-shell).
#
# tmux-tree-select.sh runs inside the popup and drives choose-tree;
# tmux-tree-pick.sh is the choose-tree selection callback.

nav="_popup_nav_$$"

# Throwaway navigator session the popup attaches to. Default shell; we leave
# destroy-unattached off so it survives the detach long enough to be reaped here.
tmux new-session -d -s "$nav"
tmux set-option -t "$nav" status off

# Blocking popup: returns only when the popup is dismissed.
tmux display-popup -E -w 80% -h 80% "$HOME/dotfiles/tmux-tree-select.sh '$nav'"

# Reap the navigator session and any grouped pick session left behind.
tmux kill-session -t "$nav" 2>/dev/null
for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^_popup_grp_'); do
  tmux kill-session -t "$s" 2>/dev/null
done
