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

# Walk up from the pane's cwd noting project context the agent can consult.
# Claude Code ALREADY auto-loads CLAUDE.md from this walk-up (we cd into $cwd
# below), so those are listed only for reference. .docs_claude/ is this repo's
# own plan/notes convention and is NOT auto-loaded — point the agent at any we
# find. --add-dir grants the read-only tools access when a hit lives in a
# parent of $cwd (the cwd itself is always reachable).
context_note=""
add_dirs=()
d="$cwd"
while [ -n "$d" ]; do
  found=0
  if [ -f "$d/CLAUDE.md" ]; then
    context_note+="  CLAUDE.md       $d/CLAUDE.md  (already loaded into your context)"$'\n'
    found=1
  fi
  if [ -d "$d/.docs_claude" ]; then
    context_note+="  .docs_claude/   $d/.docs_claude/  (PLANS_TOC.md indexes plans; notes/ holds project gotchas)"$'\n'
    found=1
  fi
  [ "$found" = 1 ] && [ "$d" != "$cwd" ] && add_dirs+=("$d")
  [ "$d" = "/" ] && break
  d=$(dirname "$d")
done

# Also note CLAUDE.md in the IMMEDIATE children of $cwd. Meta-repos (submodule
# workspaces) keep the useful per-module CLAUDE.md one level down, which the
# upward walk never sees. Children live under $cwd so Read already reaches them
# (no --add-dir needed). Immediate depth only — no recursion, naturally bounded.
for child in "$cwd"/*/; do
  [ -f "${child}CLAUDE.md" ] && context_note+="  CLAUDE.md       ${child}CLAUDE.md  (immediate child / submodule)"$'\n'
done

context_block=""
if [ -n "$context_note" ]; then
  context_block="
--- project context (found walking up from $cwd) ---
Consult these ONLY if the failure relates to this project's own tooling or
conventions; ignore them for a generic bash/OS mistake. Read .docs_claude
files if relevant — do not re-read CLAUDE.md, it is already in your context.
$context_note"
fi

add_dir_args=()
[ ${#add_dirs[@]} -gt 0 ] && add_dir_args=(--add-dir "${add_dirs[@]}")

prompt="Below is the full scrollback of a developer's terminal. Diagnose only the
MOST RECENT command — the last one run before the final prompt at the bottom;
everything earlier is context. Explain WHY it went wrong as a bash/OS
mechanism lesson (PATH lookup, argument parsing, permissions, etc.) — a longer
explanation is fine when the mechanism merits it, but keep it to one sentence
for a trivial typo. If you have a clear corrected command, end your reply with
exactly one line, with nothing after it:
FIX: <corrected command>
Omit that line entirely if you are not confident in a fix.
$context_block
--- terminal scrollback ---
$capture"

response=$(cd "$cwd" 2>/dev/null && claude -p \
  --permission-mode dontAsk \
  --allowedTools "Bash(ls*) Bash(cat*) Bash(stat*) Bash(which*) Bash(find*) Grep Glob Read" \
  --disallowedTools "Edit Write Bash(rm*) Bash(git push*) Bash(find* -delete*) Bash(find* -exec*)" \
  "${add_dir_args[@]}" \
  --model sonnet \
  --effort low \
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

if [ -n "$fix" ] && [ "$key" = "f" ]; then
  tmux send-keys -t "$pane_id" -l -- "$fix"
fi

# Always succeed: display-popup -E propagates our exit status to the run-shell
# wrapper, which would otherwise report a dismiss-without-fix (the common path)
# as `'…' returned 1`. The popup's exit status has no other consumer.
exit 0
