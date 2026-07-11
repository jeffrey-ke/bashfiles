#!/bin/bash
# tmux-claude-explain.sh — bound to `prefix E`. Captures the ORIGINATING
# pane's most recent command output, asks headless Claude Code to diagnose
# it (read-only tools only), shows the answer in this popup, and offers to
# drop a suggested fix onto that pane's prompt (never auto-run).
#
# display-popup panes cannot emit OSC escapes at all (confirmed tmux/yazi
# limitation — see dotfiles/.docs_claude/notes/tmux-popup-clipboard-ssh.md),
# so there's deliberately no notify() call here: this popup is already open
# and blocking on screen for the whole call, nothing async to announce.

pane_id="$1"
cwd="$2"

echo "Asking Claude to explain pane $pane_id ..."
echo

# Full scrollback, unsliced (history-limit 2000). The prompt tells Claude to
# diagnose only the most recent command; output older than 2000 lines is gone
# from tmux history under any design.
capture=$(tmux capture-pane -p -t "$pane_id" -S -2000)

prompt="Below is the full scrollback of a developer's terminal. Diagnose only the
MOST RECENT command — the last one run before the final prompt at the bottom;
everything earlier is context. Explain WHY it went wrong as a bash/OS
mechanism lesson (PATH lookup, argument parsing, permissions, etc.) — a longer
explanation is fine when the mechanism merits it, but keep it to one sentence
for a trivial typo. If you have a clear corrected command, end your reply with
exactly one line, with nothing after it:
FIX: <corrected command>
Omit that line entirely if you are not confident in a fix.

--- terminal scrollback ---
$capture"

response=$(cd "$cwd" 2>/dev/null && claude -p \
  --permission-mode dontAsk \
  --allowedTools "Bash(ls*) Bash(cat*) Bash(stat*) Bash(which*) Bash(find*) Grep Glob Read" \
  --disallowedTools "Edit Write Bash(rm*) Bash(git push*) Bash(find* -delete*) Bash(find* -exec*)" \
  --model sonnet \
  "$prompt" </dev/null)

printf '%s\n\n' "$response"

fix=$(printf '%s\n' "$response" | sed -n 's/^FIX: //p' | tail -1)
if [ -n "$fix" ]; then
  printf '[f] place on prompt   [any other key] dismiss '
else
  printf '(no FIX found — press any key to dismiss) '
fi

old_stty=$(stty -g)
trap 'stty "$old_stty" 2>/dev/null' EXIT
stty -icanon -echo
IFS= read -r -n1 key
stty "$old_stty"
trap - EXIT
echo

[ -n "$fix" ] && [ "$key" = "f" ] && tmux send-keys -t "$pane_id" -l -- "$fix"
