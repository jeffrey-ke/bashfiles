#!/usr/bin/env bash
# Fork the current Claude Code conversation into a new tmux pane of the window
# this process is running in. See SKILL.md for why each guard is here.
set -euo pipefail

die() { printf 'fork-pane: %s\n' "$*" >&2; exit 1; }
warn() { printf 'fork-pane: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
usage: fork-pane.sh [-v] [-s SIZE] [-d] [-m MODEL] [-S SESSION_ID] [-C DIR] [-W] [PROMPT...]

  -v          split vertically (stacked) instead of side-by-side
  -s SIZE     new pane size: 40% or 80 (lines/cols)
  -d          leave focus in the current pane
  -m MODEL    pin the fork's model (a fork otherwise inherits the transcript's)
  -S ID       fork this session ID instead of the current one
  -C DIR      run the fork in DIR (e.g. a git worktree, for divergent edits)
  -W          open a new window instead of splitting the current one
  -n NAME     override the fork's display name (default: "<parent> ⑂ <seed>")
  -A          skip the forked-from-a-live-session system prompt notice
  PROMPT...   optional seed prompt the fork starts working on immediately
EOF
}

vertical=0 size="" nofocus=0 model="" sid="" cwd="" newwin=0 name="" notice=1
while getopts ':vs:dm:S:C:Wn:Ah' opt; do
  case $opt in
    v) vertical=1 ;;
    s) size=$OPTARG ;;
    d) nofocus=1 ;;
    m) model=$OPTARG ;;
    S) sid=$OPTARG ;;
    C) cwd=$OPTARG ;;
    W) newwin=1 ;;
    n) name=$OPTARG ;;
    A) notice=0 ;;
    h) usage; exit 0 ;;
    :) die "option -$OPTARG requires an argument" ;;
    \?) die "unknown option -$OPTARG (try -h)" ;;
  esac
done
shift $((OPTIND - 1))
prompt="$*"

# --- preconditions ----------------------------------------------------------
[ -n "${TMUX:-}" ] || die "not running inside tmux; nothing to split (start Claude in a tmux pane)"
command -v tmux >/dev/null 2>&1 || die "tmux not on PATH"
command -v claude >/dev/null 2>&1 || die "claude not on PATH"

cwd=${cwd:-$PWD}
[ -d "$cwd" ] || die "-C target is not a directory: $cwd"

# --- resolve the session to fork -------------------------------------------
# Prefer the env var Claude exports; it is exact. Fall back to the newest
# transcript only as a last resort -- that guesses wrong when several Claudes
# share this directory.
if [ -z "$sid" ]; then
  sid=${CLAUDE_CODE_SESSION_ID:-}
fi
if [ -z "$sid" ]; then
  proj="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr '/.' '--')"
  newest=$(ls -t "$proj"/*.jsonl 2>/dev/null | head -1 || true)
  [ -n "$newest" ] || die "cannot determine session ID (CLAUDE_CODE_SESSION_ID unset, no transcripts in $proj); pass -S <uuid>"
  sid=$(basename "$newest" .jsonl)
  warn "CLAUDE_CODE_SESSION_ID unset; guessing newest transcript $sid -- verify this is the intended session"
fi
[[ $sid =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] \
  || die "session ID is not a UUID: $sid"

# --- resolve MY window (not the attached client's) --------------------------
if [ -n "${TMUX_PANE:-}" ]; then
  target=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}') \
    || die "TMUX_PANE=$TMUX_PANE is not a live pane"
else
  target=$(tmux display-message -p '#{session_name}:#{window_index}')
  warn "TMUX_PANE unset; falling back to the attached client's window ($target), which may not be this process's window"
fi

# --- match what the in-app /branch gives a fork -----------------------------
# `claude --resume --fork-session` alone produces an unlabelled session with no
# idea it is a fork. /branch (verified in the 2.1.235 bundle) additionally passes
# --name "<parent> ⑂ <what>" and an --append-system-prompt telling the fork the
# parent is still live in this checkout. Both are plain CLI flags, so reproduce
# them here. What cannot be reproduced is the job-registry lineage
# (forkParentSessionId et al.): it is only read for background/roster sessions,
# via CLAUDE_CODE_RESUME_SOURCE_ALIVE when CLAUDE_JOB_DIR is set. A pane fork is
# not a job, so it never shows up in the roster as a branch of its parent.
FORK_GLYPH=$'\u2442'   # U+2442 OCR FORK -- the same glyph /branch uses

# The parent's display name and cwd live in ~/.claude/sessions/<pid>.json,
# keyed by pid, so find the record whose sessionId is the one we are forking.
parent_name="" parent_cwd=""
for f in "$HOME/.claude/sessions"/*.json; do
  [ -r "$f" ] || continue
  # `|| true` is load-bearing: these files have no trailing newline, so read
  # exits 1 with $j still set -- and this script runs under `set -e`.
  IFS= read -r j < "$f" || true
  [ -n "$j" ] || continue
  [[ $j == *"\"sessionId\":\"$sid\""* ]] || continue
  [[ $j =~ \"name\":\"([^\"]*)\" ]] && parent_name=${BASH_REMATCH[1]}
  [[ $j =~ \"cwd\":\"([^\"]*)\" ]] && parent_cwd=${BASH_REMATCH[1]}
  break
done

if [ -z "$name" ]; then
  # /branch builds "<parent name> <glyph> <description>", description being its
  # [name] argument; the seed prompt is the closest equivalent we have.
  desc=${prompt:0:50}
  [ ${#prompt} -gt 50 ] && desc="${desc}…"
  name="${parent_name:+$parent_name }$FORK_GLYPH${desc:+ $desc}"
fi

# Only claim the parent is "still working in this checkout" when that is true:
# it must still be live (a record in sessions/ means running) and the fork must
# share its directory. With -C into a worktree the fork is already isolated.
fork_notice=""
if [ "$notice" -eq 1 ] && [ -n "$parent_cwd" ] && [ "$parent_cwd" = "$cwd" ]; then
  fork_notice="This conversation was forked from a session that is still working in this checkout ($cwd). Before making code changes, create a new worktree of your own with EnterWorktree so your edits don't land where the original session is editing."
fi

# --- build the fork command -------------------------------------------------
# printf %q throughout: the notice contains an apostrophe ("don't"), which kills
# a naively single-quoted split-window command outright.
cmd="exec claude --resume $(printf '%q' "$sid") --fork-session"
[ -n "$name" ] && cmd+=" --name $(printf '%q' "$name")"
[ -n "$fork_notice" ] && cmd+=" --append-system-prompt $(printf '%q' "$fork_notice")"
[ -n "$model" ] && cmd+=" --model $(printf '%q' "$model")"
[ -n "$prompt" ] && cmd+=" $(printf '%q' "$prompt")"

split_args=(-c "$cwd" -P -F '#{pane_id}')
[ "$nofocus" -eq 1 ] && split_args+=(-d)

if [ "$newwin" -eq 1 ]; then
  # new-window has no -l; size is meaningless for a whole window.
  [ -n "$size" ] && warn "-s ignored with -W (a new window has no split size)"
  pane=$(tmux new-window -a -t "$target" -n "fork-${sid:0:8}" "${split_args[@]}" "$cmd")
else
  [ -n "$size" ] && split_args+=(-l "$size")
  if [ "$vertical" -eq 1 ]; then split_args+=(-v); else split_args+=(-h); fi
  pane=$(tmux split-window -t "$target" "${split_args[@]}" "$cmd")
fi
[ -n "$pane" ] || die "tmux created no pane"

# Keep a crashed pane open long enough to read the error; cleared once ready.
tmux set-option -p -t "$pane" remain-on-exit on 2>/dev/null || true
# Best-effort label only: Claude Code overwrites the pane title with its own
# conversation summary once it starts, so this does not persist. The parent
# session ID is printed in the report below -- that is the durable record.
tmux select-pane -t "$pane" -T "fork:${sid:0:8}" 2>/dev/null || true

# --- verify it came up ------------------------------------------------------
# Do NOT verify by looking for a new *.jsonl: the fork's transcript is not
# written until its first message, so an idle fork looks like a failure.
# 30s, not 10s: replaying a large transcript can take well over 10s to draw the UI.
ready=0
for _ in $(seq 1 120); do
  # Query the pane directly: with -W it lives in a different window than $target.
  if [ "$(tmux display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null || echo 1)" != 0 ]; then
    printf 'fork-pane: pane %s died during startup:\n' "$pane" >&2
    tmux capture-pane -p -t "$pane" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -20 >&2 || true
    die "fork failed to start"
  fi
  if tmux capture-pane -p -t "$pane" 2>/dev/null | grep -qe 'ctx:' -e '❯'; then
    ready=1; break
  fi
  sleep 0.25
done
tmux set-option -p -t "$pane" remain-on-exit off 2>/dev/null || true

# --- report -----------------------------------------------------------------
focus_note=$([ "$nofocus" -eq 1 ] && echo ', focus unchanged' || echo ', focus moved there')
# Report where the pane actually landed -- with -W that is not $target.
where=$(tmux display-message -p -t "$pane" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || echo "$target")
cat <<EOF
pane:      $pane   (at $where$focus_note)
forked:    $sid
name:      $name
cwd:       $cwd
seeded:    ${prompt:-<none, idle at prompt>}
status:    $([ "$ready" -eq 1 ] && echo ready || echo 'launched (not confirmed ready)')
undo:      tmux kill-pane -t $pane
inspect:   tmux capture-pane -p -t $pane | tail -15
EOF
[ "$ready" -eq 1 ] || warn "prompt box not seen within 30s; the pane is alive and may still be replaying -- inspect it"
