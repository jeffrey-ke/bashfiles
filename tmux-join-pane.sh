#!/bin/sh
src="$1"
wname=$(tmux display-message -p -t ":$src" '#{window_name}')
pid=$(tmux display-message -p -t ":$src" '#{pane_id}')
tmux join-pane -h -s ":$src"
tmux set -p -t "$pid" @pane_name "$wname"