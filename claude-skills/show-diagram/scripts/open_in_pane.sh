#!/usr/bin/env bash
# Open a file in nvim in a new tmux pane beside the caller's pane.
# Usage: open_in_pane.sh FILE [-v]   (-v splits below instead of beside)
set -euo pipefail

file=$(realpath "${1:?usage: open_in_pane.sh FILE [-v]}")
split=-h
[[ "${2:-}" == -v ]] && split=-v

[[ -n "${TMUX:-}" ]] || { echo "not inside tmux" >&2; exit 1; }
[[ -s "$file" ]] || { echo "missing or empty: $file" >&2; exit 1; }

tmux split-window "$split" -t "${TMUX_PANE}" -c "$(dirname "$file")" \
  "nvim $(printf '%q' "$file")"
echo "opened $file"
