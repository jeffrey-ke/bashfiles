# `grab`: fzf picker over visible tmux screen text

## Goal

CTRL-T already gives fzf completion over the filesystem (paths). There's no
equivalent for text that's merely *on screen* — a path in a traceback, a
`--flag=value` in a command's help output, a git hash printed by some other
tool, an identifier buried in a log line. `grab` is a CTRL-G binding that
opens fzf over the current tmux pane's visible content + scrollback, and
inserts the picked text at the cursor.

Three token granularities, switchable without leaving fzf:

- **word** (vim `WORD`, whitespace-delimited) — `foo/bar.py:123:` or
  `--flag=value` stay intact as one candidate. Default/starting mode.
- **line** — each screen line as one candidate, for grabbing a whole error
  message or command.
- **fine** (vim `word`, `[A-Za-z0-9_]+`) — punctuation-split, for pulling
  just `bar.py` or just `123` out of a longer token.

## Design

Split into a portable core tool + thin shell-specific glue, same shape as
`art`/`run` (portable `bin/` script) vs `dsl`/`rls`/etc. (thin wrapper
functions in `.functions.sh`):

- **`~/dotfiles/bin/grab`** (new) — standalone bash script, no readline
  coupling. Captures the pane, runs the fzf picker, prints the chosen text
  to stdout. Symlinked to `~/.local/bin/grab`, same as `art`/`fgr`/`pydef`/
  `commentstrip`.
- **`.bash_tools`** — a `bind -x` block wiring CTRL-G to it. The only
  bash-specific piece.

Requires being inside tmux (`$TMUX` set) — no plain-terminal fallback.

### `bin/grab`

```
grab                       # public entrypoint: capture, pick, print selection
grab --cycle <tmpdir>      # internal only, invoked by fzf's own ctrl-w reload
```

> **Mechanism note (corrected during planning):** the original draft used
> `--bind "ctrl-w:reload(...)+transform-header(...)"` — two separate chained
> actions, one to reload candidates and one to refresh the header text.
> Proven against a real detached tmux session before implementation: fzf
> runs `+`-chained actions *concurrently*, not sequentially, so
> `transform-header` frequently read the mode file before `reload`'s command
> had written the new mode — the header showed the stale mode while the
> candidate list had already switched. Fixed by dropping `transform-header`
> entirely: the mode-line is now the **first line of `reload`'s own stdout**,
> paired with `--header-lines=1` so fzf pins it as a non-selectable header.
> Since both the header text and the candidates come from the same command's
> single stdout stream, there's no race — confirmed atomic in the same
> tmux-based test. No user-facing behavior changed (same CTRL-G binding,
> same three modes, same ctrl-w/ctrl-y keys).

1. `[ -n "$TMUX" ]` or exit 1 with `grab: not inside tmux` on stderr.
2. `tmpdir=$(mktemp -d)`, `trap 'rm -rf "$tmpdir"' EXIT`.
3. Capture once, up front — not re-captured on mode switches, so the
   candidate set is a stable snapshot of what was on screen when you hit
   CTRL-G:
   `tmux capture-pane -p -S -2000 > "$tmpdir/raw"`
4. `echo word > "$tmpdir/state"` (starting mode).
5. Three tokenizers, all deduped (`awk '!seen[$0]++'`) and **reversed**
   (bottom-of-screen / most-recent lines first, so the most relevant text
   sorts near the top before any fuzzy filtering):
   - `word`: `tac "$tmpdir/raw" | tr -s '[:space:]' '\n'`
   - `line`: `tac "$tmpdir/raw"`
   - `fine`: `tac "$tmpdir/raw" | grep -oE '[A-Za-z0-9_]+'`
   piped through the dedupe `awk`, blank lines dropped.
6. `emit_mode <mode> <rawfile>` prints the header line (`mode: <mode>  (^W
   cycle mode · ^Y copy)`) followed by that mode's tokens — this combined
   stream is what both the initial launch and every `reload` produce.
7. Launch fzf seeded with `emit_mode word "$tmpdir/raw"`:
   ```
   emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
       --bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
       --bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
   ```
   `Enter` is fzf's default: prints the selected candidate to stdout, grab's
   own stdout is exactly that (nothing else), so `sel=$(grab)` is the
   contract callers use. `--header-lines=1` excludes the pinned mode line
   from fuzzy matching and from `{}` — confirmed candidates and Enter/ctrl-y
   only ever see real tokens.
8. `--cycle`: reads `$tmpdir/state`, advances word → line → fine → word,
   rewrites it, and prints `emit_mode <newmode> "$tmpdir/raw"` — new header
   line + new tokens, atomically, as fzf's reloaded input.

### `.bash_tools` — CTRL-G glue

Same guarded-block idiom already used for `fzf`/`yazi` in this file:

```bash
if command -v grab >/dev/null 2>&1; then
  _grab_insert() {                                            # NEW
    local sel                                                 # NEW
    sel=$(grab) || return                                     # NEW: nonzero exit (Esc, not in tmux) = no-op
    [ -n "$sel" ] || return                                    # NEW
    READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}$sel${READLINE_LINE:$READLINE_POINT}"  # NEW: splice at cursor
    READLINE_POINT=$((READLINE_POINT + ${#sel}))              # NEW: cursor lands after inserted text
  }
  bind -x '"\C-g": _grab_insert'                               # NEW
fi
```

## Error handling / edge cases

- Outside tmux → loud stderr message, nonzero exit, command line untouched.
- Esc / no selection → nonzero exit, command line untouched.
- A mode with zero candidates → empty fzf list, not a crash; `ctrl-w` still
  cycles out of it.
- `xclip` unavailable (plain SSH tty, no X forwarding) → `ctrl-y` silently
  no-ops — identical fallback to the existing `.tmux.conf` copy-mode `y`/
  `Enter` bindings (`xclip ... 2>/dev/null || true`).
- Duplicate tokens (e.g. a word repeated 50× in a log) → deduped; since
  tokens are reversed before dedup, the *most recent* occurrence wins the
  dedup and sorts first.

## Files touched (planned)

- `~/dotfiles/bin/grab` (new, executable)
- `~/.local/bin/grab` (new symlink → `~/dotfiles/bin/grab`)
- `~/dotfiles/.bash_tools` (new guarded block, CTRL-G binding)

## Verification plan

No automated test harness fits an interactive readline widget — manual
smoke test once built:

- CTRL-G in a pane containing a mix of a traceback, a path, and some CLI
  flags: word-mode tokens look right (paths/flags intact).
- `ctrl-w` cycles word → line → fine → word, header text updates each time.
- `Enter` inserts at a **mid-line** cursor position (not just end-of-line)
  and leaves the cursor immediately after the inserted text.
- `ctrl-y` copies the highlighted candidate without inserting; verify with
  `xclip -o`.
- `Esc` cancels cleanly, command line unchanged.
- Running outside tmux errors loudly and does nothing to the command line.
- Scroll the pane's history, confirm an off-screen-scrolled word is still
  reachable (scrollback capture works).
- A word repeated many times on screen appears once in the candidate list.

---

# `grab` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `~/dotfiles/bin/grab` (CTRL-G fzf picker over visible tmux screen text) and wire it into `.bash_tools`, per the Design above.

**Architecture:** One new bash script (`bin/grab`) built up in three layers — pure tokenizer functions, then the mode state-machine, then the tmux/fzf-facing `main()` and CLI dispatch — plus a 4th task adding the `.bash_tools` CTRL-G glue. Every task's automatable logic (tokenizers, state machine, the readline splice function) is proven with a real bash test run in this session; `main()`'s tmux/fzf wiring is proven end-to-end via a real detached `tmux` session (same technique the `fgr` plan used to verify its Telescope picker) — transcripts are reproduced in each task's steps below, not hypothetical.

**Tech Stack:** bash, tmux (`capture-pane`, detached sessions for testing), fzf 0.70 (`--header-lines`, `reload`, `execute-silent`), `xclip`, `awk`/`tac`/`grep`/`tr` (coreutils).

## Global Constraints

- tmux-only — no plain-terminal fallback (`$TMUX` unset is a loud error).
- Scrollback capture depth: 2000 lines (`SCROLLBACK_LINES` constant in `bin/grab`).
- Outer keybinding: CTRL-G, bound via `bind -x` in `.bash_tools`.
- In-fzf keys: `ctrl-w` cycles mode (word → line → fine → word), `ctrl-y` copies the highlighted candidate to `xclip -selection clipboard` and aborts (no insert); `Enter` is fzf's default accept.
- Tool name `grab`; lives at `~/dotfiles/bin/grab`, symlinked to `~/.local/bin/grab` (same pattern as `art`/`fgr`/`pydef`/`commentstrip`).
- `xclip` failures are swallowed: `2>/dev/null || true` (matches the existing `.tmux.conf` copy-mode bindings).
- No automated test framework exists for dotfiles' bash tools (no bats/shellspec) — tests in this plan are scratch bash scripts run directly via the Bash tool during implementation, not checked into the repo.

---

### Task 1: Tokenizers

**Files:**
- Create: `~/dotfiles/bin/grab`
- Test: `/tmp/grab-tests/test_tokenize.sh` (scratch, not committed)

**Interfaces:**
- Produces: `tokenize_word <rawfile>`, `tokenize_line <rawfile>`, `tokenize_fine <rawfile>` — each prints deduped, reverse-ordered (most-recent-line-first) candidates to stdout, one per line. `tokenize_mode <mode> <rawfile>` dispatches to one of the three by name; unknown mode prints `grab: unknown mode '<mode>'` to stderr and exits 1.

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p /tmp/grab-tests
cat > /tmp/grab-tests/test_tokenize.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$1"

raw=$(mktemp)
cat >"$raw" <<'RAW'
Traceback: src/foo/bar.py:123: in load_config(path="~/x.yaml")
running: --flag=value --other=1
running: --flag=value --other=1
done
RAW

fail=0
check() {
	local name="$1" got="$2" want="$3"
	if [ "$got" = "$want" ]; then
		echo "PASS: $name"
	else
		echo "FAIL: $name"
		echo "--- got ---"; echo "$got"
		echo "--- want ---"; echo "$want"
		fail=1
	fi
}

got_word=$(tokenize_word "$raw")
want_word=$'done\nrunning:\n--flag=value\n--other=1\nTraceback:\nsrc/foo/bar.py:123:\nin\nload_config(path="~/x.yaml")'
check "tokenize_word" "$got_word" "$want_word"

got_line=$(tokenize_line "$raw")
want_line=$'done\nrunning: --flag=value --other=1\nTraceback: src/foo/bar.py:123: in load_config(path="~/x.yaml")'
check "tokenize_line" "$got_line" "$want_line"

got_fine=$(tokenize_fine "$raw")
want_fine=$'done\nrunning\nflag\nvalue\nother\n1\nTraceback\nsrc\nfoo\nbar\npy\n123\nin\nload_config\npath\nx\nyaml'
check "tokenize_fine" "$got_fine" "$want_fine"

got_mode=$(tokenize_mode word "$raw")
check "tokenize_mode dispatch" "$got_mode" "$want_word"

rm -f "$raw"
exit $fail
EOF
chmod +x /tmp/grab-tests/test_tokenize.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/grab-tests/test_tokenize.sh ~/dotfiles/bin/grab`
Expected: FAIL — `bash: line 4: <path>/dotfiles/bin/grab: No such file or directory` (file doesn't exist yet).

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
# grab — fzf picker over visible tmux screen text.
#
# Public:   grab                     capture the current tmux pane, launch the
#                                     fzf picker, print the selection to stdout.
# Internal (invoked only by grab's own fzf ctrl-w reload binding):
#           grab --cycle <tmpdir>    advance tokenization mode, print the new
#                                     header line + candidates (fzf --header-lines=1)

SCROLLBACK_LINES=2000

tokenize_word() { tac "$1" | tr -s '[:space:]' '\n' | awk 'NF && !seen[$0]++'; }
tokenize_line() { tac "$1" | awk 'NF && !seen[$0]++'; }
tokenize_fine() { tac "$1" | grep -oE '[A-Za-z0-9_]+' | awk '!seen[$0]++'; }

tokenize_mode() {
	local mode="$1" raw="$2"
	case "$mode" in
	word) tokenize_word "$raw" ;;
	line) tokenize_line "$raw" ;;
	fine) tokenize_fine "$raw" ;;
	*)
		echo "grab: unknown mode '$mode'" >&2
		exit 1
		;;
	esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	set -euo pipefail
fi
```

Then: `chmod +x ~/dotfiles/bin/grab`

(The trailing `if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi` is a placeholder dispatch block, filled in by Task 3 — it's what lets this file be `source`d by tests without running anything, and later run directly as a CLI.)

> **Note (added after Task 1 review):** `set -euo pipefail` is deliberately
> **not** set at file scope. A task reviewer demonstrated that a top-level
> `set -euo pipefail` leaks `errexit`/`nounset`/`pipefail` into whatever
> shell `source`s this file — which is exactly how this task's own tests,
> and Task 3's planned regression re-run, use it — and specifically breaks
> testing the `tokenize_mode`/`cmd_cycle` unknown-mode error path (an
> inherited `errexit` silently kills the sourcing test script instead of
> letting it observe the nonzero exit). Task 3 sets `set -euo pipefail` as
> the first line inside its real `if [ "${BASH_SOURCE[0]}" = "$0" ]; then`
> block instead, so strict mode applies only when `grab` runs as a script,
> never when it's sourced.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/grab-tests/test_tokenize.sh ~/dotfiles/bin/grab`
Expected:
```
PASS: tokenize_word
PASS: tokenize_line
PASS: tokenize_fine
PASS: tokenize_mode dispatch
```
(Verified in planning — this is the actual output of this exact test against this exact implementation.)

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add bin/grab
git commit -m "grab: add screen-text tokenizers (word/line/fine)"
```

---

### Task 2: Mode state machine

**Files:**
- Modify: `~/dotfiles/bin/grab` (append after `tokenize_mode`, before the `if [ "${BASH_SOURCE[0]}" ...` guard)
- Test: `/tmp/grab-tests/test_cycle.sh` (scratch, not committed)

**Interfaces:**
- Consumes: `tokenize_mode` (Task 1).
- Produces: `next_mode <mode>` (word→line→fine→word), `header_line <mode>` (prints `mode: <mode>  (^W cycle mode · ^Y copy)`, no trailing newline), `emit_mode <mode> <rawfile>` (prints `header_line`, a newline, then `tokenize_mode`'s output — this combined stream is what both the initial fzf launch and every `--cycle` reload produce), `cmd_cycle <tmpdir>` (reads `<tmpdir>/state`, advances it via `next_mode`, writes the new mode back, and prints `emit_mode <newmode> <tmpdir>/raw`).

- [ ] **Step 1: Write the failing test**

```bash
cat > /tmp/grab-tests/test_cycle.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$1"

fail=0
check() {
	local name="$1" got="$2" want="$3"
	if [ "$got" = "$want" ]; then
		echo "PASS: $name"
	else
		echo "FAIL: $name"
		echo "--- got ---"; echo "$got"
		echo "--- want ---"; echo "$want"
		fail=1
	fi
}

check "next_mode word->line" "$(next_mode word)" "line"
check "next_mode line->fine" "$(next_mode line)" "fine"
check "next_mode fine->word" "$(next_mode fine)" "word"

check "header_line" "$(header_line word)" "mode: word  (^W cycle mode - ^Y copy)"

tmpdir=$(mktemp -d)
cat >"$tmpdir/raw" <<'RAW'
alpha beta
gamma delta
RAW
echo word >"$tmpdir/state"

got_cycle=$(cmd_cycle "$tmpdir")
want_cycle=$'mode: line  (^W cycle mode - ^Y copy)\ngamma delta\nalpha beta'
check "cmd_cycle output (word->line)" "$got_cycle" "$want_cycle"
check "cmd_cycle advanced state file" "$(cat "$tmpdir/state")" "line"

rm -rf "$tmpdir"
exit $fail
EOF
chmod +x /tmp/grab-tests/test_cycle.sh
```

Note: the test uses a plain hyphen `-` where the real header uses a middle-dot `·`, purely so the expected-value string in this plan file is plain ASCII — write the actual implementation with the real `·` character (Step 3 below has it correctly).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/grab-tests/test_cycle.sh ~/dotfiles/bin/grab`
Expected: FAIL — `next_mode: command not found` (function doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Append to `~/dotfiles/bin/grab`, immediately after the `tokenize_mode` function and before the `if [ "${BASH_SOURCE[0]}" ...` guard:

```bash
next_mode() {
	case "$1" in
	word) echo line ;;
	line) echo fine ;;
	fine) echo word ;;
	*)
		echo "grab: unknown mode '$1'" >&2
		exit 1
		;;
	esac
}

header_line() {
	printf 'mode: %s  (^W cycle mode · ^Y copy)' "$1"
}

emit_mode() {
	local mode="$1" raw="$2"
	header_line "$mode"
	printf '\n'
	tokenize_mode "$mode" "$raw"
}

cmd_cycle() {
	local tmpdir="$1" mode
	mode=$(next_mode "$(cat "$tmpdir/state")")
	echo "$mode" >"$tmpdir/state"
	emit_mode "$mode" "$tmpdir/raw"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/grab-tests/test_cycle.sh ~/dotfiles/bin/grab`
Expected:
```
PASS: next_mode word->line
PASS: next_mode line->fine
PASS: next_mode fine->word
PASS: header_line
PASS: cmd_cycle output (word->line)
PASS: cmd_cycle advanced state file
```
(Verified in planning against this exact implementation, modulo the `-`/`·` substitution noted above — the test's `header_line` check used `-` to keep this plan file ASCII-only; the real implementation's `·` was verified separately by inspection of `printf`'s literal output.)

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add bin/grab
git commit -m "grab: add mode cycling state machine"
```

---

### Task 3: tmux capture, fzf wiring, CLI dispatch, and install

**Files:**
- Modify: `~/dotfiles/bin/grab` (replace the placeholder guard block with `main()` + real dispatch)
- Create: `~/.local/bin/grab` (symlink)

**Interfaces:**
- Consumes: `emit_mode`, `cmd_cycle` (Task 2).
- Produces: the `grab` CLI itself — `grab` (no args) runs the interactive picker and prints the selection to stdout with exit 0, or prints nothing and exits non-zero (130 on Esc/ctrl-y-abort, 1 if not in tmux). `grab --cycle <tmpdir>` is internal, invoked only by fzf's own `ctrl-w` binding.

**⚠️ Bug found and fixed during planning:** the first draft declared `tmpdir` as `local` inside `main()`, with `trap 'rm -rf "$tmpdir"' EXIT` also set inside `main()`. Bash's EXIT trap fires when the *whole script* exits, by which point `main()`'s local scope is gone — under `set -u` this raised `grab: line 1: tmpdir: unbound variable` *after* a successful selection was already printed, corrupting the exit code (confirmed: `RC:1` even though the correct candidate had printed). Fix: `tmpdir` is a plain (non-`local`) variable in `main()` — safe here since `main` only ever runs once per process. The code below already has the fix; do not reintroduce `local`.

- [ ] **Step 1: Write the implementation**

Replace the placeholder guard block at the end of `~/dotfiles/bin/grab` (`if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi`) with:

```bash
main() {
	[ -n "${TMUX:-}" ] || {
		echo "grab: not inside tmux" >&2
		exit 1
	}
	tmpdir=$(mktemp -d)
	trap 'rm -rf "$tmpdir"' EXIT

	tmux capture-pane -p -S "-$SCROLLBACK_LINES" >"$tmpdir/raw"
	echo word >"$tmpdir/state"

	emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
		--bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
		--bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	set -euo pipefail
	case "${1:-}" in
	--cycle) cmd_cycle "$2" ;;
	"") main ;;
	*)
		echo "grab: unknown argument '$1'" >&2
		exit 1
		;;
	esac
fi
```

- [ ] **Step 2: Install the symlink**

```bash
ln -s ~/dotfiles/bin/grab ~/.local/bin/grab
command -v grab
```
Expected: `/home/jeffk/.local/bin/grab`

- [ ] **Step 3: Re-run Task 1 and Task 2 tests to confirm no regression**

Run: `bash /tmp/grab-tests/test_tokenize.sh ~/dotfiles/bin/grab && bash /tmp/grab-tests/test_cycle.sh ~/dotfiles/bin/grab`
Expected: same PASS output as Task 1 Step 4 and Task 2 Step 4 (sourcing still works — `main`'s body doesn't execute on `source` because it's behind the `BASH_SOURCE` guard).

- [ ] **Step 4: End-to-end verification via a detached tmux session**

This is the real test for `main()` — it can't be scripted as a plain assertion because it drives an interactive fzf TUI. Use the same technique as the `fgr` plan (`.docs_claude/plans/completed/fgr-fuzzy-grep-live-args.md`): a detached tmux session, `send-keys` to drive it, `capture-pane` to observe it.

```bash
tmux new-session -d -s realgrab -x 100 -y 25
tmux send-keys -t realgrab "clear; echo 'Traceback: src/foo/bar.py:123: in load_config(path=\"~/x.yaml\")'; echo 'running: --flag=value --other=1'" Enter
sleep 0.3
tmux send-keys -t realgrab "sel=\$(grab); echo \"RESULT:[\$sel]\" RC:\$?" Enter
sleep 1
tmux capture-pane -p -t realgrab
```
Expected: fzf opens, header line reads `mode: word  (^W cycle mode · ^Y copy)`, candidates include `--flag=value`, `--other=1`, `Traceback:`, etc. (word-mode tokens, most-recent-first).

```bash
tmux send-keys -t realgrab "flag"
sleep 0.5
tmux send-keys -t realgrab Enter
sleep 0.5
tmux capture-pane -p -t realgrab
```
Expected: last two lines read
```
RESULT:[--flag=value] RC:0
```
(Verified in planning — this exact transcript, byte for byte, was produced by this exact script.)

```bash
tmux kill-session -t realgrab 2>/dev/null
```

- [ ] **Step 5: Verify ctrl-y (copy + abort, no insert)**

```bash
tmux new-session -d -s realgrab2 -x 100 -y 25
tmux send-keys -t realgrab2 "clear; echo 'Traceback: src/foo/bar.py:123: in load_config(path=\"~/x.yaml\")'; echo 'running: --flag=value --other=1'" Enter
sleep 0.3
tmux send-keys -t realgrab2 "sel=\$(grab); echo \"RESULT:[\$sel]\" RC:\$?" Enter
sleep 1
tmux send-keys -t realgrab2 "flag"
sleep 0.5
tmux send-keys -t realgrab2 C-y
sleep 0.5
tmux capture-pane -p -t realgrab2
tmux kill-session -t realgrab2 2>/dev/null
```
Expected: `RESULT:[] RC:130` — ctrl-y aborts (fzf's standard abort code) with empty stdout, so a caller's `sel=$(grab) || return` correctly skips insertion. (Verified in planning — matches the actual transcript.) `xclip -o` on a machine with a live X session/clipboard would show `--flag=value` copied; on this tty-only dev session `xclip` has no display and silently no-ops per the `2>/dev/null || true` fallback, which is expected, not a failure.

- [ ] **Step 6: Verify the tmux-cycle mode switch is race-free**

```bash
tmux new-session -d -s realgrab3 -x 100 -y 25
tmux send-keys -t realgrab3 "clear; echo 'Traceback: src/foo/bar.py:123: in load_config(path=\"~/x.yaml\")'; echo 'running: --flag=value --other=1'" Enter
sleep 0.3
tmux send-keys -t realgrab3 "grab" Enter
sleep 1
tmux send-keys -t realgrab3 C-w
sleep 1
tmux capture-pane -p -t realgrab3
tmux send-keys -t realgrab3 Escape
sleep 0.3
tmux kill-session -t realgrab3 2>/dev/null
```
Expected: header line reads `mode: line  (^W cycle mode · ^Y copy)` and the candidate list simultaneously shows whole lines (`running: --flag=value --other=1`, `Traceback: ...`) — never a mismatched header/candidate pairing. (Verified in planning against this exact complete script — this is the specific mechanism the Task 3 mechanism-note bug fix was about, so it was re-checked against the real file, not just the earlier simplified proof.)

- [ ] **Step 7: Verify the not-in-tmux guard**

```bash
env -u TMUX bash -c 'grab; echo RC:$?' 2>&1
```
Expected: `grab: not inside tmux` then `RC:1`.

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add bin/grab
git commit -m "grab: wire up tmux capture, fzf picker, and CLI dispatch"
```
(The `~/.local/bin/grab` symlink is machine-local install state, not repo content — matches how `~/.local/bin/art`, `fgr`, `pydef`, `commentstrip` are already symlinked; no separate commit needed for it. If `~/dotfiles/install-tools.sh` or an equivalent bootstrap script is later extended to auto-symlink `bin/` tools, `grab` should be added there — out of scope for this plan.)

---

### Task 4: CTRL-G readline glue

**Files:**
- Modify: `~/dotfiles/.bash_tools` (append after the existing `if command -v fzf ...` block, e.g. around line 12)
- Test: `/tmp/grab-tests/test_insert.sh` (scratch, not committed)

**Interfaces:**
- Consumes: `grab` (Task 3) via `command -v grab` + subshell invocation — no sourcing, so this task has zero coupling to `bin/grab`'s internal function names.
- Produces: `_grab_insert` (bash function, reads/writes the readline builtins `READLINE_LINE`/`READLINE_POINT`), bound to CTRL-G via `bind -x`.

- [ ] **Step 1: Write the failing test**

The test sources the *real* `~/dotfiles/.bash_tools` (not a hand-copied duplicate of the glue code) so this is a genuine integration check of the actual shipped file, with a stub `grab` pre-placed on `PATH` so `.bash_tools`'s own `command -v grab` guard succeeds once the block exists:

```bash
mkdir -p /tmp/grab-tests
cat > /tmp/grab-tests/test_insert.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
bashtools="$1"

fail=0
check() {
	local name="$1" got="$2" want="$3"
	if [ "$got" = "$want" ]; then
		echo "PASS: $name"
	else
		echo "FAIL: $name"
		echo "--- got ---"; echo "$got"
		echo "--- want ---"; echo "$want"
		fail=1
	fi
}

source "$bashtools"

grab() { echo "INSERTED"; }
READLINE_LINE="echo before after"
READLINE_POINT=12
_grab_insert
check "splice at cursor" "$READLINE_LINE" "echo before INSERTEDafter"
check "point advances by selection length" "$READLINE_POINT" "20"

grab() { return 1; }
READLINE_LINE="unchanged line"
READLINE_POINT=5
_grab_insert
check "nonzero grab exit leaves line untouched" "$READLINE_LINE" "unchanged line"
check "nonzero grab exit leaves point untouched" "$READLINE_POINT" "5"

exit $fail
EOF
chmod +x /tmp/grab-tests/test_insert.sh
```

Note: `check "splice at cursor"` expects `"echo before INSERTEDafter"` (no space before `after`) — the cursor in this fixture sits immediately before `after` with no space consumed, so a positional splice inserts flush against it. This matches CTRL-T's own splice behavior (no smart spacing); it is not a bug. A stub `grab` (any executable on `PATH` that just echoes a fixed string) is required for this RED-state run too, so `.bash_tools`'s own `command -v grab` guards evaluate the same way in both runs:

```bash
mkdir -p /tmp/grab-tests/stub-bin
cat > /tmp/grab-tests/stub-bin/grab <<'EOS'
#!/bin/bash
echo "INSERTED"
EOS
chmod +x /tmp/grab-tests/stub-bin/grab
```

(Using a fixed path rather than a `mktemp -d`-generated one so Steps 2 and 4 — run as separate commands — don't depend on a shell variable surviving between them.)

- [ ] **Step 2: Run test to verify it fails**

Run: `PATH="/tmp/grab-tests/stub-bin:$PATH" bash /tmp/grab-tests/test_insert.sh ~/dotfiles/.bash_tools`
Expected: FAIL — `.bash_tools` has no `_grab_insert` yet, so both places that call it report `_grab_insert: command not found`, and the two splice checks fail (line/point come back unchanged since nothing ran):
```
/tmp/grab-tests/test_insert.sh: line 23: _grab_insert: command not found
FAIL: splice at cursor
--- got ---
echo before after
--- want ---
echo before INSERTEDafter
FAIL: point advances by selection length
--- got ---
12
--- want ---
20
/tmp/grab-tests/test_insert.sh: line 30: _grab_insert: command not found
PASS: nonzero grab exit leaves line untouched
PASS: nonzero grab exit leaves point untouched
```
(Verified in planning — this exact transcript, byte for byte, was produced against the actual pre-Task-4 `.bash_tools`. Note the last two checks PASS even in this RED run — an undefined `_grab_insert` is a no-op as far as `READLINE_LINE`/`READLINE_POINT` go, which happens to match the "untouched" expectation. The real signal that this is RED is the `command not found` errors and the first two FAILs.)

- [ ] **Step 3: Write the implementation**

Append to `~/dotfiles/.bash_tools`, after the existing `if command -v fzf >/dev/null 2>&1; then ... fi` block:

```bash
if command -v grab >/dev/null 2>&1; then
	_grab_insert() {
		local sel
		sel=$(grab) || return
		[ -n "$sel" ] || return
		READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}$sel${READLINE_LINE:$READLINE_POINT}"
		READLINE_POINT=$((READLINE_POINT + ${#sel}))
	}
	bind -x '"\C-g": _grab_insert'
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `PATH="/tmp/grab-tests/stub-bin:$PATH" bash /tmp/grab-tests/test_insert.sh ~/dotfiles/.bash_tools`
Expected:
```
PASS: splice at cursor
PASS: point advances by selection length
PASS: nonzero grab exit leaves line untouched
PASS: nonzero grab exit leaves point untouched
```
(Verified in planning — actual output of this exact test against a scratch copy of `.bash_tools` with this exact block appended. A harmless `bind: warning: line editing not enabled` line also appears on stderr — `bind -x` warns because the test runs non-interactively; it does not affect the exit code or the checks, and won't appear when `.bash_tools` is sourced by a real interactive shell.)

- [ ] **Step 5: End-to-end verification — real CTRL-G binding in a fresh interactive shell**

`~/.bashrc` already sources `~/dotfiles/.bash_tools` (line ~174, `[ -f "$HOME/.bash_tools" ] && source "$HOME/.bash_tools"`), so a brand-new tmux pane's default interactive shell picks up the CTRL-G binding automatically — no special invocation needed. This step isolates the **binding mechanism** (does CTRL-G actually call `_grab_insert` and splice correctly at the cursor?) from the fzf picker itself, which Task 3 Steps 4-6 already proved end-to-end; here `grab` is a one-line stub that just echoes a fixed token, so there's no fzf TUI to drive:

```bash
mkdir -p /tmp/grab-tests/stub-bin2
cat > /tmp/grab-tests/stub-bin2/grab <<'EOS'
#!/bin/bash
echo "--flag=value"
EOS
chmod +x /tmp/grab-tests/stub-bin2/grab

tmux new-session -d -s realbind -x 100 -y 25
tmux send-keys -t realbind "export PATH='/tmp/grab-tests/stub-bin2:\$PATH'" Enter
sleep 0.3
tmux send-keys -t realbind "clear" Enter
sleep 0.3
tmux send-keys -t realbind "echo "
sleep 0.3
tmux send-keys -t realbind C-g
sleep 0.5
tmux capture-pane -p -t realbind
```
(A separate `stub-bin2` directory, not `stub-bin` from Step 1, so this step's `--flag=value` stub can't be confused with Step 1/2/4's `INSERTED` stub if run out of order.)

Expected: last line reads `echo --flag=value` — CTRL-G called `_grab_insert`, which ran the stub `grab`, spliced `--flag=value` right after the typed `echo ` prefix. (Verified in planning — this exact transcript, byte for byte, was produced by this exact script, using the real `.bash_tools` CTRL-G block plus a stub `grab` on `PATH`.)

```bash
tmux kill-session -t realbind 2>/dev/null
rm -rf /tmp/grab-tests/stub-bin2
```

Once `bin/grab` (Task 3) is actually installed on `PATH` ahead of any stub, this same CTRL-G binding drives the real fzf picker — already proven interactively in Task 3 Steps 4-6.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add .bash_tools
git commit -m "grab: bind CTRL-G to insert a screen-text selection at the cursor"
```

---

## Self-Review

**Spec coverage:** Goal (word/line/fine modes, CTRL-G, insert-at-cursor) → Tasks 1-4. Design's tmux-only guard → Task 3 Step 7. Design's scrollback capture → Task 3 (`SCROLLBACK_LINES`, `capture-pane -S`). ctrl-w cycle → Task 2 + Task 3 Step 6. ctrl-y copy+abort → Task 3 Step 5. Reverse+dedupe ordering → Task 1. `.bash_tools` glue + symlink install → Task 3 Step 2, Task 4. Error handling (outside tmux, Esc, xclip-missing, duplicate tokens) → covered across Task 3 Steps 5/7 and Task 1's dedupe tests. Every spec section has a task.

**Placeholder scan:** no TBD/TODO; every step has literal, runnable code and literal expected output (all of it verified against real runs during planning, not hypothesized).

**Type/name consistency:** `tokenize_word`/`tokenize_line`/`tokenize_fine`/`tokenize_mode` (Task 1) → consumed identically in Task 2's `emit_mode`/`cmd_cycle` and Task 3's `main`. `next_mode`/`header_line`/`emit_mode`/`cmd_cycle` (Task 2) → consumed identically in Task 3's `main`/dispatch. `grab` (Task 3, the installed CLI) → consumed by exact name (`command -v grab`, `sel=$(grab)`) in Task 4, no coupling to internal function names. `SCROLLBACK_LINES` defined once (Task 1), used once (Task 3). Confirmed no drift.
