#!/bin/sh
name="$1"
cur_name=$(tmux display-message -p '#{@pane_name}')
[ -z "$cur_name" ] && cur_name=$(tmux display-message -p '#{window_name}')
tmux new-window -d -n "_new_swap_tmp"
new_win=$(tmux display-message -p -t ":_new_swap_tmp" '#{window_index}')
tmux swap-pane -s ":$new_win"
tmux rename-window -t ":$new_win" "$cur_name"
tmux set -p @pane_name "$name"