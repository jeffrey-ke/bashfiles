#!/usr/bin/env bash
# Fork the Claude Code conversation running in a given tmux pane, straight from a
# tmux key binding -- no round trip through Claude itself.
#
#   tmux-fork-claude.sh <pane-id> [--resolve | fork-pane.sh args...]
#
# The trick is that Claude Code (>= 2.1.235) already publishes the index we need:
# ~/.claude/sessions/<pid>.json holds both "sessionId" and
# "tmux":"<session>:@<window>.%<pane>". So pane -> session ID is a pure lookup;
# nothing has to be stamped onto the pane, no SessionStart hook is needed, and we
# never have to guess "the newest transcript" (which picks the wrong session when
# two Claudes share a directory).
#
# Parsing is pure bash on purpose -- this runs on a keypress, so the only
# subprocesses are the one tmux query and the split itself.
set -uo pipefail

SESSIONS="$HOME/.claude/sessions"
FORK_PANE="$HOME/dotfiles/claude-skills/fork-conversation-pane/fork-pane.sh"
[ -x "$FORK_PANE" ] || FORK_PANE="$HOME/.claude/skills/fork-conversation-pane/fork-pane.sh"

# Errors have to go through tmux: a `run-shell -b` child's stderr is shown nowhere.
bail() { tmux display-message "fork: $*"; exit 1; }

pane=${1:-}
[ -n "$pane" ] || bail "no pane id given (bind with '#{pane_id}')"
shift
[[ $pane == %* ]] || bail "not a pane id: $pane"

# The pane's own pid, used to prefer a Claude that really runs in this pane over
# one that merely inherited TMUX_PANE from it.
pane_pid=$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null) \
  || bail "no such pane: $pane"

# /proc is the fork-free fast path. macOS has none, so fall back to ps there.
HAVE_PROC=0
[ -z "${FORK_CLAUDE_NO_PROC:-}" ] && [ -r /proc/self/stat ] && HAVE_PROC=1

# Read /proc/<pid>/stat past comm: comm (field 2) may contain spaces and parens,
# so cut everything through the last ') '. What remains starts at field 3.
stat_from_state() {
  local rest
  read -r rest < "/proc/$1/stat" 2>/dev/null
  [ -n "$rest" ] || return 1
  printf '%s' "${rest##*') '}"
}

# Alive AND still the process the session file described.
pid_matches() { # <pid> <procStart>
  if [ "$HAVE_PROC" = 1 ]; then
    local rest; rest=$(stat_from_state "$1") || return 1
    local -a f=($rest)
    [ "${f[19]:-}" = "$2" ]   # field 22 (starttime): rules out a recycled pid
  else
    # No comparable starttime here; Claude Code deletes its own file on exit, so
    # liveness alone is close enough.
    kill -0 "$1" 2>/dev/null
  fi
}

ppid_of() {
  if [ "$HAVE_PROC" = 1 ]; then
    local rest; rest=$(stat_from_state "$1") || return 1
    rest=${rest#* }           # drop state, leaving ppid first
    printf '%s' "${rest%% *}"
  else
    ps -o ppid= -p "$1" 2>/dev/null | tr -d '[:space:]'
  fi
}

in_pane_subtree() {
  local pid=$1 hops=0
  while [ "${pid:-0}" -gt 1 ] 2>/dev/null && [ "$hops" -lt 24 ]; do
    [ "$pid" = "$pane_pid" ] && return 0
    pid=$(ppid_of "$pid") || return 1
    hops=$((hops + 1))
  done
  [ "${pid:-0}" = "$pane_pid" ]
}

best_sid="" best_cwd="" best_started=-1 best_subtree=0
for f in "$SESSIONS"/*.json; do
  [ -r "$f" ] || continue
  IFS= read -r j < "$f"      # exits 1 on the absent trailing newline; $j is set
  [ -n "$j" ] || continue

  # Only real interactive CLI sessions. A headless `claude -p` run also records
  # kind:"interactive" and inherits this very pane, but is entrypoint:"sdk-cli";
  # forking that would branch a throwaway one-shot instead of the user's thread.
  [[ $j == *'"entrypoint":"cli"'* ]] || continue

  [[ $j =~ \"tmux\":\"[^\"]*\.(%[0-9]+)\" ]] || continue
  [ "${BASH_REMATCH[1]}" = "$pane" ] || continue

  [[ $j =~ \"pid\":([0-9]+) ]] || continue
  pid=${BASH_REMATCH[1]}
  [[ $j =~ \"procStart\":\"?([0-9]+) ]] || continue
  pid_matches "$pid" "${BASH_REMATCH[1]}" || continue

  [[ $j =~ \"sessionId\":\"([0-9a-fA-F-]{36})\" ]] || continue
  sid=${BASH_REMATCH[1]}
  cwd=""; [[ $j =~ \"cwd\":\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  started=0; [[ $j =~ \"startedAt\":([0-9]+) ]] && started=${BASH_REMATCH[1]}

  sub=0; in_pane_subtree "$pid" && sub=1
  # Prefer a true descendant of this pane; among equals take the newest session,
  # which is the foreground one when a Claude was launched from inside another.
  if [ "$sub" -gt "$best_subtree" ] ||
     { [ "$sub" -eq "$best_subtree" ] && [ "$started" -gt "$best_started" ]; }; then
    best_sid=$sid best_cwd=$cwd best_started=$started best_subtree=$sub
  fi
done

# --resolve prints what the lookup found and stops -- the only practical way to
# debug a key binding whose output otherwise vanishes into the status line.
if [ "${1:-}" = "--resolve" ]; then
  [ -n "$best_sid" ] || { printf 'no Claude session in pane %s\n' "$pane" >&2; exit 1; }
  printf 'pane=%s session=%s cwd=%s in_subtree=%s\n' \
    "$pane" "$best_sid" "$best_cwd" "$best_subtree"
  exit 0
fi

[ -n "$best_sid" ] || bail "no Claude session found in pane $pane"
[ -x "$FORK_PANE" ] || bail "fork-pane.sh not found or not executable"

tmux display-message "fork: branching ${best_sid:0:8} ..."

# fork-pane.sh resolves the window to split from TMUX_PANE, which run-shell does
# not set (unlike Claude's Bash tool) -- hand it the pane we were told about.
export TMUX_PANE="$pane"
out=$(cd "${best_cwd:-$HOME}" 2>/dev/null && "$FORK_PANE" -S "$best_sid" -C "${best_cwd:-$PWD}" "$@" 2>&1) || {
  tmux display-message "fork failed: $(printf '%s' "$out" | tr '\n' ' ' | tail -c 160)"
  exit 1
}
new_pane=$(printf '%s\n' "$out" | sed -n 's/^pane:  *\([^ ]*\).*/\1/p')
tmux display-message "fork: ${best_sid:0:8} -> ${new_pane:-done}  (undo: prefix+x)"
