# prefix+E: headless Claude diagnosis of the current pane's last error

## Why `run.sh` appends straight to `.bashrc` instead of going through `.setup`

Original design put the new `PROMPT_COMMAND` marker in `~/dotfiles/.setup`,
reusing its existing array-safe append idiom. The user then checked `run.sh`
directly and asked the right question: `.setup` was **never actually wired
into `run.sh`** — it's not in the `files` symlink array or the `sources`
array, so the fact that it works on tesu today is a leftover manual setup,
not something dotfiles actually manages. Piggybacking the marker on `.setup`
would have meant fixing *two* problems (wire up `.setup` itself, on top of
adding the marker) and made this feature's portability depend on `.setup`'s
own portability — which was never established.

Simpler: skip `.setup` entirely. `run.sh` already has a proven, idempotent
pattern for appending a managed block straight into `~/.bashrc` — the
`source-machine.sh` migration (its existing lines 27–29: `if ! grep -q
'source-machine.sh' "$BASHRC"; then echo '...' >>"$BASHRC"; fi`). Reusing
that same idempotency pattern for the marker means the feature is
self-contained in `run.sh` + `.bashrc`, with no dependency on `.setup`'s
wiring at all. Bonus: since `.bashrc` is only ever sourced by bash (zsh reads
`.zshrc`, a separate file), the `CURRENT_SHELL == "bash"` guard that wrapped
the equivalent block in `.setup` is unneeded noise here — dropped, not just
relocated. Net effect: 3 files touched instead of 4, no `.setup` changes at
all, and the append logic matches an idiom already proven correct in
`run.sh` itself.

## Context

Working over SSH in tmux (Ghostty on Mac → tesu), the current loop for a bad
command/error is: squint at the output, give up, open a separate Claude Code
session, screenshot or copy-paste the pane content in, wait, read a full
response dump, copy the fix back out. Research into off-the-shelf tools
(tmux-llm, shell-ai, wut-cli, TmuxAI, pay-respects, zsh-ai-assist) turned up
nothing that combines accurate capture, a hotkey-triggered popup, tool-using
diagnosis (not just pattern-matching pasted text), and dropping a corrected
command back on the prompt without a copy-paste round trip — so this hand-rolls
the missing piece as a small tmux feature in `~/dotfiles`.

The design was worked out and independently verified across this conversation:
a background research pass ruled out Ghostty/osascript-side approaches (no
visibility into a remote tmux pane — OSC 133 doesn't cross the SSH+tmux hop);
an Explore agent surveyed `~/dotfiles/.docs_claude/plans/` for prior tmux/popup
work and conventions to follow; a Plan agent then designed the concrete diffs
below and, critically, **empirically caught two wrong premises** before they
could land: `prefix E` is not actually free (it's tmux's built-in "spread
panes evenly," confirmed against a clean `-f /dev/null` tmux server), and
`PROMPT_COMMAND` is not empty (it's a live 4-element array — git-prompt,
vim-tag, zoxide — confirmed via `bash -i -c 'declare -p PROMPT_COMMAND'`; an
earlier non-interactive check had missed this). Both were re-verified
independently before writing this plan. The user chose to keep `E` (its
current binding is unused/uncustomized) and to use `sonnet` for the model.
The user's own follow-up check of `run.sh` then caught the `.setup`
dependency issue explained above.

## What gets touched

| File | Change |
|---|---|
| `~/dotfiles/tmux-claude-explain.sh` | **new** — the popup script |
| `~/dotfiles/.tmux.conf` | +1 `bind-key E` line |
| `~/dotfiles/run.sh` | +1 idempotent block appending the marker directly to `~/.bashrc` |

`.setup` is untouched.

## 1. `~/dotfiles/run.sh` — prompt marker, appended idempotently to `.bashrc`

Inserted right after the existing `source-machine.sh` migration block, same
idempotent-append-to-`$BASHRC` shape, just before the final `install-tools.sh`
call:

```diff
 sed -i '/MACHINE_CONFIG/d' "$BASHRC"
 if ! grep -q 'source-machine.sh' "$BASHRC"; then
 	echo '[ -f "$HOME/dotfiles/source-machine.sh" ] && source "$HOME/dotfiles/source-machine.sh"' >>"$BASHRC"
 fi
 
+# ccexplain marker (see dotfiles/tmux-claude-explain.sh, prefix E) — printed
+# before each new prompt so the popup can find exactly where the current
+# command's output starts, instead of guessing a fixed line count.
+if ! grep -q 'CCEXPLAIN' "$BASHRC"; then
+	cat >>"$BASHRC" <<'EOF'
+
+# ccexplain marker (see dotfiles/tmux-claude-explain.sh, prefix E)
+if declare -p PROMPT_COMMAND &>/dev/null && [[ $(declare -p PROMPT_COMMAND) == "declare -a"* ]]; then
+  PROMPT_COMMAND+=('printf "\n\032CCEXPLAIN\032\n"')
+else
+  PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}printf \"\\n\\032CCEXPLAIN\\032\\n\""
+fi
+EOF
+fi
+
 "$DOTFILES/install-tools.sh" || echo "warning: tool install failed (offline?) — re-run ./install-tools.sh later"
```

Uses a quoted heredoc (`<<'EOF'`) rather than forcing this onto one
`echo '...' >>` line like the single-line blocks above it — the marker logic
has its own nested quotes (`'`, `"`, `\"`) and cramming that into a single
shell-escaped `echo` argument would be a real correctness trap. Still the
same idempotency pattern (`if ! grep -q <marker> "$BASHRC"`) as every other
block in this section, just adapted for a multi-line payload. Safe under
`set -e` (line 2) for the same reason the existing `if ! grep -q ...` blocks
already are — a tested condition, not a bare failing command. Safe to re-run
on tesu: `CCEXPLAIN` isn't in `~/.bashrc` yet, so it appends exactly once,
here and on any other machine.

## 2. `~/dotfiles/.tmux.conf` — the hotkey

Inserted next to the other Claude-related binding, matching this file's
existing `-w 80% -h 80%` popup-sizing convention (used by every popup bind in
the file except the one dashboard that uses 90%/85%):

```diff
 bind-key P if -F '#{m:_popup_*,#{session_name}}' { detach-client } { run-shell '$HOME/dotfiles/tmux-tree-popup.sh' }
 # Popup into a dedicated, persistent "claude" session (attach-or-create); toggle off with C again
 bind-key C if -F '#{==:#{session_name},claude}' { detach-client } { display-popup -E -w 80% -h 80% "tmux new-session -A -s claude" }
+# Headless Claude diagnosis of THIS pane's last command output. Popup shows
+# the answer; [f] drops a suggested fix onto this pane's prompt (no Enter
+# sent — reviewed before running). Overrides tmux's default `select-layout
+# -E` (spread panes evenly), kept deliberately: unused/uncustomized here.
+bind-key E display-popup -E -w 80% -h 80% "$HOME/dotfiles/tmux-claude-explain.sh '#{pane_id}' '#{pane_current_path}'"
 # Rename window with a blank prompt (no need to backspace the current name)
 bind-key , command-prompt -p "Rename window:" "rename-window -- '%%'"
```

`#{pane_id}` / `#{pane_current_path}` are resolved by tmux against the pane
that had focus when the key was pressed — *not* the popup's own pane — before
`display-popup` opens, the same format-expansion pattern already used
elsewhere in this file (e.g. `tmux-break-session.sh`'s binding).

Note for the record: `bind-key C` opens a *persistent interactive* Claude
session; this is a *headless, one-shot* `claude -p` call. Different mechanism,
not a duplicate. There's also no existing precedent anywhere in this repo for
a popup script sending text back into the pane that opened it (`trun()` in
`.functions.sh` only ever creates a brand-new named session) — this feature
establishes that pattern for the first time.

## 3. `~/dotfiles/tmux-claude-explain.sh` — new file, mode 755

```bash
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

# Full scrollback (history-limit is 2000, tmux's own ceiling — not a guess).
capture=$(tmux capture-pane -p -t "$pane_id" -S -2000)

# Keep only what's after the LAST prompt marker, so the captured chunk is
# exactly "since your current command started" — 1 line or 800, whatever it
# actually was. No marker found (pane predates this change, or a shell that
# never sourced the updated .bashrc) -> fall back to the whole capture rather
# than failing.
marker_line=$(printf '%s\n' "$capture" | grep -an 'CCEXPLAIN' | tail -1 | cut -d: -f1)
if [ -n "$marker_line" ]; then
  snippet=$(printf '%s\n' "$capture" | tail -n +"$((marker_line + 1))")
else
  snippet="$capture"
fi

prompt="A developer's bash command produced the terminal output below. Diagnose
what went wrong, and explain WHY as a bash/OS mechanism lesson (PATH lookup,
argument parsing, permissions, etc.) — a longer explanation is fine when the
mechanism merits it, but keep it to one sentence for a trivial typo. If you
have a clear corrected command, end your reply with exactly one line, with
nothing after it:
FIX: <corrected command>
Omit that line entirely if you are not confident in a fix.

--- captured terminal output ---
$snippet"

response=$(cd "$cwd" 2>/dev/null && claude -p \
  --permission-mode dontAsk \
  --allowedTools "Bash(ls*) Bash(cat*) Bash(stat*) Bash(which*) Bash(find*) Grep Glob Read" \
  --disallowedTools "Edit Write Bash(rm*) Bash(git push*) Bash(find* -delete*) Bash(find* -exec*)" \
  --model sonnet \
  "$prompt")

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
```

Notable choices:
- `#!/bin/bash`, not this repo's usual `#!/bin/sh` for `tmux-*.sh` scripts —
  needed for `read -n1` (not POSIX; `run.sh`/`install-tools.sh` are the
  existing bash-shebang precedent in this repo).
- `--disallowedTools` explicitly closes the `find -delete` / `find -exec`
  gap in the `Bash(find*)` allow rule (added on review — a bare `find*`
  allow would otherwise let a single `find /path -delete` through without
  ever touching `rm`, defeating the read-only intent).
- `trap ... EXIT` around the `stty` restore so the pane's terminal doesn't
  get stuck in raw mode if the popup is killed mid-read.

## Verification (manual — personal shell tool, no automated tests)

1. Run `~/dotfiles/run.sh` (adds the `.bashrc` marker block) and
   `tmux source-file ~/.tmux.conf`; open a fresh pane so the edited
   `.bashrc` re-sources.
2. Confirm the marker is actually printing: `tmux capture-pane -p -S -20 | cat -v | tail -20` — look for a `^ZCCEXPLAIN^Z` line before the prompt (`cat -v` renders the otherwise-invisible `\032`).
3. `lsz` (typo) → `prefix E`. Expect: popup opens immediately (before Claude
   responds), shows a one-sentence PATH-lookup explanation, likely `FIX: ls`.
4. Press `f` → popup closes, `ls` sits on the original pane's prompt,
   unexecuted, editable.
5. Trigger something long (e.g. a multi-hundred-line stack trace or
   `python3 -c "for i in range(500): print(i)"` followed by a real error) →
   `prefix E` → confirm the whole thing is captured, not truncated at some
   fixed window, and the explanation scales appropriately.
6. Trigger an error with no confident fix → `prefix E` → press any key other
   than `f` → confirm it just dismisses, nothing sent to the pane.
7. Sanity-check the fallback path once: open a pane, run `lsz` in it, press
   `E` *before* running `run.sh`/resourcing `.bashrc` — should still work via
   the whole-capture fallback since no marker exists yet in that pane.
8. If the popup ever prints `claude: command not found`, PATH isn't reaching
   the popup shell — `bind-key G`'s existing `uv run --script` popup working
   today suggests this won't happen, but worth a first real run to confirm.

## Explicitly out of scope

No async/notify path (the OSC-in-popup limitation makes this moot for a
synchronous, already-on-screen popup), no markdown rendering (glow/bat) layer,
no automated tests. Not touched: `.setup` (deliberately, see top), the stale
`tmux-popup-window.md` doc superseded by `tmux-tree-popup.sh`, and the
undocumented `bind-key C` / `tmux-tree-popup.sh` mechanisms noted in passing
during research.
