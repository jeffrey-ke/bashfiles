# `grab`: portable line-reversal (no `tac` on macOS)

## Goal

Sub-project 1 of 4 in
[grab-macos-support-roadmap.md](../../notes/grab-macos-support-roadmap.md)
(macOS cross-platform support for `grab`). All three tokenizers in
`~/dotfiles/bin/grab` (`tokenize_word`, `tokenize_line`, `tokenize_fine`)
start with `tac "$1"` to get most-recent-line-first ordering before dedup.
`tac` is GNU coreutils — macOS (BSD userland) doesn't ship it. Without a
fix, CTRL-G on macOS opens fzf to an empty candidate list (`tac: command
not found`, silently hidden behind the fullscreen fzf UI).

## Design

Add one new function, `rev_lines()`, and use it in place of `tac` in all
three tokenizers:

```bash
rev_lines() { awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}' "$1"; }
```

Then:
```bash
tokenize_word() { rev_lines "$1" | tr -s '[:space:]' '\n' | awk 'NF && !seen[$0]++'; }
tokenize_line() { rev_lines "$1" | awk 'NF && !seen[$0]++'; }
tokenize_fine() { rev_lines "$1" | grep -oE '[A-Za-z0-9_]+' | awk '!seen[$0]++'; }
```

- **Portable, no branching.** Plain POSIX awk (arrays, `NR`, `END` block,
  a `for` loop) — no GNU extensions. Behaves identically on macOS's BSD
  awk and Linux's gawk; no `command -v`/OS detection needed anywhere.
- **Verified byte-identical to `tac`'s current output** on the same
  fixture used to build/review `bin/grab`'s original tokenizer tests —
  confirmed via a direct diff before writing this doc.
- **Fits existing style.** `bin/grab` already leans on awk for every
  dedup stage (`awk 'NF && !seen[$0]++'`); this keeps the file to one
  utility language for text processing instead of introducing coreutils
  detection logic.
- **No performance concern.** Input is capped at `SCROLLBACK_LINES=2000`
  lines — awk reading 2000 lines into an array is instant either way.
- **All three tokenizers stay parallel.** Each keeps the same
  `rev_lines "$1" | <mode-specific split> | awk dedup` shape they had with
  `tac`, just swapping the first pipeline stage.

## Files touched

- `~/dotfiles/bin/grab` — add `rev_lines()`, change 3 call sites
  (`tokenize_word`, `tokenize_line`, `tokenize_fine`)

## Verification plan

- Re-run the existing tokenizer test fixture (word/line/fine dedup+reverse
  ordering) — output must be byte-identical to the current `tac`-based
  behavior, since this is a pure substitution with no behavior change.
- `grep -c tac bin/grab` returns 0 after the change — no remaining `tac`
  usage anywhere in the file.
- Full CTRL-G smoke test on this machine (Linux/tesu) — must still work
  exactly as before, since this platform never depended on `tac` being
  GNU-specific in the first place; a regression here would indicate a bug
  in `rev_lines()` itself, not a platform issue.
- macOS verification is out of scope for this sub-project (no Mac
  available in this session) — the fix is proven portable by construction
  (plain POSIX awk), not by running on a Mac. Flag in the roadmap note
  that live macOS verification is still open.

---

# `grab` portable line-reversal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace GNU-only `tac` with a portable `rev_lines()` awk helper in `bin/grab`'s three tokenizers.

**Architecture:** One new function (`rev_lines`) added before the tokenizers; each tokenizer's `tac "$1"` call site swapped for `rev_lines "$1"`. No other files change.

**Tech Stack:** bash, POSIX awk (no GNU extensions).

## Global Constraints

- `rev_lines()`'s output must be byte-identical to `tac`'s output for the same input — this is a pure substitution, not a behavior change.
- No runtime OS/tool detection (`command -v tac`, `uname`, etc.) — single portable implementation only.
- `tac` must not appear anywhere in `bin/grab` after this change.

---

### Task 1: Replace `tac` with a portable `rev_lines()` helper

**Files:**
- Modify: `~/dotfiles/bin/grab:12-14` (the three tokenizer functions), and add `rev_lines()` immediately above them.

**Interfaces:**
- Produces: `rev_lines <file>` — prints the file's lines in reverse order (last line first), byte-identical to `tac <file>`.
- Consumes: nothing new — `tokenize_word`/`tokenize_line`/`tokenize_fine` keep their existing `<rawfile>` argument contract unchanged.

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p /tmp/grab-tests
cat > /tmp/grab-tests/test_rev_lines.sh <<'EOF'
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

got=$(rev_lines "$raw")
want=$(tac "$raw")
check "rev_lines matches tac byte-for-byte" "$got" "$want"

got_word=$(tokenize_word "$raw")
want_word=$'done\nrunning:\n--flag=value\n--other=1\nTraceback:\nsrc/foo/bar.py:123:\nin\nload_config(path="~/x.yaml")'
check "tokenize_word unchanged" "$got_word" "$want_word"

got_line=$(tokenize_line "$raw")
want_line=$'done\nrunning: --flag=value --other=1\nTraceback: src/foo/bar.py:123: in load_config(path="~/x.yaml")'
check "tokenize_line unchanged" "$got_line" "$want_line"

got_fine=$(tokenize_fine "$raw")
want_fine=$'done\nrunning\nflag\nvalue\nother\n1\nTraceback\nsrc\nfoo\nbar\npy\n123\nin\nload_config\npath\nx\nyaml'
check "tokenize_fine unchanged" "$got_fine" "$want_fine"

rm -f "$raw"
exit $fail
EOF
chmod +x /tmp/grab-tests/test_rev_lines.sh
```

Note: this test uses `tac` itself (available on this Linux dev machine) as the reference oracle for `rev_lines`'s correctness, plus the same fixed expected strings from the original tokenizer tests to confirm zero behavior change end-to-end.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/grab-tests/test_rev_lines.sh ~/dotfiles/bin/grab`
Expected: FAIL — `rev_lines: command not found` (function doesn't exist yet).

- [ ] **Step 3: Write the implementation**

In `~/dotfiles/bin/grab`, replace:
```bash
tokenize_word() { tac "$1" | tr -s '[:space:]' '\n' | awk 'NF && !seen[$0]++'; }
tokenize_line() { tac "$1" | awk 'NF && !seen[$0]++'; }
tokenize_fine() { tac "$1" | grep -oE '[A-Za-z0-9_]+' | awk '!seen[$0]++'; }
```
with:
```bash
rev_lines() { awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}' "$1"; }

tokenize_word() { rev_lines "$1" | tr -s '[:space:]' '\n' | awk 'NF && !seen[$0]++'; }
tokenize_line() { rev_lines "$1" | awk 'NF && !seen[$0]++'; }
tokenize_fine() { rev_lines "$1" | grep -oE '[A-Za-z0-9_]+' | awk '!seen[$0]++'; }
```
Nothing else in `bin/grab` changes.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/grab-tests/test_rev_lines.sh ~/dotfiles/bin/grab`
Expected:
```
PASS: rev_lines matches tac byte-for-byte
PASS: tokenize_word unchanged
PASS: tokenize_line unchanged
PASS: tokenize_fine unchanged
```

- [ ] **Step 5: Confirm no `tac` remains**

Run: `grep -c tac ~/dotfiles/bin/grab`
Expected: `0`

- [ ] **Step 6: Regression-check via a real detached tmux session**

```bash
tmux new-session -d -s revlinescheck -x 100 -y 25
tmux send-keys -t revlinescheck "export PATH=\"$HOME/.local/bin:\$PATH\"" Enter
sleep 0.3
tmux send-keys -t revlinescheck "clear; echo 'Traceback: src/foo/bar.py:123: in load_config(path=\"~/x.yaml\")'; echo 'running: --flag=value --other=1'" Enter
sleep 0.3
tmux send-keys -t revlinescheck "sel=\$(grab); echo \"RESULT:[\$sel]\" RC:\$?" Enter
sleep 1
tmux send-keys -t revlinescheck "flag"
sleep 0.3
tmux send-keys -t revlinescheck Enter
sleep 0.5
tmux capture-pane -p -t revlinescheck
tmux kill-session -t revlinescheck 2>/dev/null
```
Expected: `RESULT:[--flag=value] RC:0` — full CTRL-G/word-mode/Enter flow still works identically on this Linux machine after the `tac` → `rev_lines` swap.

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles
git add bin/grab
git commit -m "grab: replace GNU-only tac with a portable rev_lines() helper"
```

---

## Self-Review

**Spec coverage:** `rev_lines()` added, byte-identical to `tac` (Step 1/4), all 3 tokenizers switched (Step 3), no `tac` remaining (Step 5), Linux regression check (Step 6). macOS live verification explicitly out of scope per the spec — noted, not silently dropped.

**Placeholder scan:** none — every step has literal code and expected output.

**Type/name consistency:** `rev_lines <file>` used identically across all three tokenizers; no other function signatures change.
