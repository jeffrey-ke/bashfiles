#!/bin/sh
name="$1"
src_window="$2"
[ -z "$name" ] && exit 1
[ -z "$src_window" ] && exit 1
tmux new-session -d -s "$name" -n _placeholder
tmux move-window -s "$src_window" -t "$name"
tmux kill-window -t "$name:_placeholder"