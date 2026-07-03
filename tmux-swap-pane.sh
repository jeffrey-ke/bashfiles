#!/bin/sh
src="$1"                                   # choose-tree %% target (already qualified)
cur_name=$(tmux display-message -p '#{@pane_name}')
src_name=$(tmux display-message -p -t "$src" '#{window_name}')
tmux swap-pane -s "$src"
tmux rename-window -t "$src" "$cur_name"
tmux set -p @pane_name "$src_name"