# `grab`: preview window showing the captured terminal screen

## Goal

`grab` (CTRL-G fzf picker over visible tmux screen text — see
[grab-screen-word-completion.md](../completed/grab-screen-word-completion.md))
currently shows only the tokenized candidate list, with no way to see where a
token came from. Add an fzf preview window that shows the full captured
terminal screen (the same raw `tmux capture-pane` snapshot every tokenization
mode is built from) as context while picking.

## Design

One change to `bin/grab`'s `main()`, in the existing fzf invocation:

```
emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
    --preview 'cat "$tmpdir/raw"' \
    --preview-window=down,60% \
    --bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
    --bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
```

- **Content:** the full captured scrollback (`$tmpdir/raw`, already written once per invocation and shared by all three tokenization modes) — not a truncated tail. Static: the preview does not scroll/highlight to match the currently-selected candidate; it always shows the same view, letting fzf's own preview-window scrolling (mouse/keys) be the user's control.
- **Layout:** below the candidate list, `--preview-window=down,60%`, not a side split. Proven in a real tmux session before writing this doc: fzf runs full-screen (no `--height` set), so a `down` preview gets close to the terminal's actual width — matching the width `tmux capture-pane` originally captured at, so lines render with minimal reflow. A `right,50%` split would halve the effective width and cause more wrapping of exactly the wide content (multi-column `ls`, long log lines, wide prompts) this feature exists to show faithfully.
- **No interaction with mode-cycling or copy:** `ctrl-w` (cycle tokenization mode) and `ctrl-y` (copy) are untouched — neither reads or writes the preview. The preview command is set once at fzf launch and isn't part of the `reload`d candidate stream, so cycling modes doesn't affect it.
- **No ANSI handling needed:** `tmux capture-pane -p` (no `-e`) already captures plain text, so `cat` is sufficient — no `--ansi` flag or color stripping required.

## Files touched

- `~/dotfiles/bin/grab` (modify `main()`'s fzf invocation only — 2 new flags)

## Verification plan

- CTRL-G in a pane with varied content (wide `ls` output, a `tail -f` log,
  some prompt lines): preview below the candidate list shows the full
  captured screen, full width, matching what was actually on screen (spot
  check: multi-column `ls` alignment isn't broken by wrapping).
- Moving the fzf selection up/down does not change the preview content
  (static, confirmed by design).
- `ctrl-w` still cycles tokenization mode correctly; preview content
  unchanged across mode switches.
- `ctrl-y` still copies and aborts correctly; preview unaffected.
- `Enter` still inserts the correct selection at the cursor (regression
  check against the original CTRL-G behavior).

---

# `grab` preview window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an fzf preview window to `bin/grab`'s `main()` that shows the full captured terminal screen below the candidate list.

**Architecture:** Two new flags (`--preview`, `--preview-window`) added to the single existing `fzf` invocation in `main()`. No new functions, no new files — `$tmpdir/raw` (the raw capture) already exists by the time `main()` reaches the `fzf` call.

**Tech Stack:** bash, fzf 0.70 (`--preview`, `--preview-window=down,PERCENT%`), tmux (for verification).

## Global Constraints

- Preview content: the full `$tmpdir/raw` capture, not a truncated tail.
- Preview is static — does not scroll/highlight to the currently-selected candidate.
- Layout: `--preview-window=down,60%` (not a side split) — proven to minimize text reflow since fzf runs full-screen and a `down` split keeps close to the pane's actual captured width.
- No `--ansi` needed — `tmux capture-pane -p` (no `-e`) captures plain text already.
- `ctrl-w` (mode cycle) and `ctrl-y` (copy+abort) must be unaffected — do not touch those bindings.

---

### Task 1: Add preview window to `main()`

**Files:**
- Modify: `~/dotfiles/bin/grab:70-72` (the `fzf` call inside `main()`)

**Interfaces:**
- Consumes: `$tmpdir/raw` (already written at `bin/grab:67` by the time `fzf` runs — no change needed there).
- Produces: nothing new — this is the only task in this plan.

- [ ] **Step 1: Confirm the current (pre-change) fzf call has no preview**

```bash
grep -n -A3 "emit_mode word" ~/dotfiles/bin/grab
```
Expected:
```
70:	emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
71:		--bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
72:		--bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
```
No `--preview` flag present — this is the baseline this task changes.

- [ ] **Step 2: Write the implementation**

In `~/dotfiles/bin/grab`, replace:
```bash
	emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
		--bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
		--bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
```
with:
```bash
	emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
		--preview "cat \"$tmpdir/raw\"" \
		--preview-window=down,60% \
		--bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
		--bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
```
Nothing else in `bin/grab` changes.

- [ ] **Step 3: End-to-end verification via a detached tmux session**

fzf's preview window is a live TUI element — verify it the same way `main()`'s original fzf wiring was verified (see `grab-screen-word-completion.md` Task 3): a detached tmux session, `send-keys` to drive it, `capture-pane` to observe it.

```bash
tmux new-session -d -s previewcheck -x 120 -y 35
tmux send-keys -t previewcheck "clear; echo 'Traceback: src/foo/bar.py:123: in load_config(path=\"~/x.yaml\")'; echo 'running: --flag=value --other=1'" Enter
sleep 0.3
tmux send-keys -t previewcheck "grab" Enter
sleep 1
tmux capture-pane -p -t previewcheck
```
Expected: candidate list on top (word-mode tokens, `mode: word ...` header), a bordered preview pane below taking roughly the bottom 60% of the screen, showing the captured lines (`Traceback: ...`, `running: --flag=value --other=1`, plus the shell prompt lines) at close to full terminal width — no aggressive line-wrapping of the content.

- [ ] **Step 4: Confirm the preview is static across selection changes**

```bash
tmux send-keys -t previewcheck Down
sleep 0.3
tmux capture-pane -p -t previewcheck > /tmp/grab-tests/preview-before-cycle.txt
tmux send-keys -t previewcheck Up
sleep 0.3
tmux capture-pane -p -t previewcheck > /tmp/grab-tests/preview-after-cycle.txt
diff <(sed -n '/─$/,$p' /tmp/grab-tests/preview-before-cycle.txt) <(sed -n '/─$/,$p' /tmp/grab-tests/preview-after-cycle.txt)
```
Expected: no diff output in the preview-pane region — moving the candidate selection up/down doesn't change what the preview shows (confirms "static," not synced to selection, per the design).

- [ ] **Step 5: Regression-check `ctrl-w`, `ctrl-y`, and `Enter`**

```bash
tmux send-keys -t previewcheck C-w
sleep 0.5
tmux capture-pane -p -t previewcheck
```
Expected: header switches to `mode: line ...`, candidate list becomes whole screen lines, preview pane content unchanged (still the full raw capture).

```bash
tmux send-keys -t previewcheck "flag"
sleep 0.3
tmux send-keys -t previewcheck Enter
sleep 0.5
tmux capture-pane -p -t previewcheck
```
Expected: fzf closes, the matched candidate was printed to `grab`'s stdout (same accept behavior as before this change — this task doesn't touch `main()`'s exit/stdout contract, only adds display flags).

```bash
tmux kill-session -t previewcheck 2>/dev/null
rm -f /tmp/grab-tests/preview-before-cycle.txt /tmp/grab-tests/preview-after-cycle.txt
```

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add bin/grab
git commit -m "grab: add preview window showing the captured terminal screen"
```

---

## Self-Review

**Spec coverage:** Content = full raw capture (Step 2, `cat "$tmpdir/raw"`) ✓. Static, not selection-synced (Step 4 verifies) ✓. `down,60%` layout (Step 2, Step 3 verifies full-width rendering) ✓. No ANSI handling (plain `cat`, matches spec's reasoning) ✓. `ctrl-w`/`ctrl-y`/Enter unaffected (Step 5) ✓. Every spec requirement has a task/step.

**Placeholder scan:** no TBD/TODO; every step has literal commands and literal expected output.

**Type/name consistency:** only one task, no cross-task interfaces to drift. `$tmpdir/raw` referenced identically to how `main()` already writes it at `bin/grab:67` (unchanged) and how `cmd_cycle`/`emit_mode` already consume it (unchanged, out of scope for this task).
