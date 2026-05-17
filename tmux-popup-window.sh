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
