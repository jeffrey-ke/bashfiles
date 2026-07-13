# `grab`: preview window starts at the bottom and stays there

## Goal

`grab`'s preview window (see
[grab-preview-window.md](../completed/grab-preview-window.md)) currently
starts scrolled to the top of the captured screen and jumps back to the top
on every re-render (typing that reorders the top match, or arrow
navigation) — the opposite of useful, since the most relevant context is
usually the most recent (bottom) lines. Make it start at the bottom, and
re-anchor to the bottom instead of the top on every re-render, while still
letting the user manually scroll up to peek.

## Design

One flag value change to `bin/grab`'s existing `main()` fzf invocation:

```
--preview-window=down,60%        # before
--preview-window=down,60%,follow # after
```

fzf's `follow` preview-window flag ("automatically scroll to the bottom...
similarly to how tail -f works") does exactly this. Verified directly
against a real tmux session before writing this doc, against both a
synthetic fixture and the actual `bin/grab` binary:

- **Starts at the bottom.** A fresh `grab` invocation opens with the preview
  already scrolled to the last lines of the capture, not line 1.
- **Manual scroll-up still works.** `shift-up`/`shift-down` (fzf's default
  preview-scroll keys) move the preview freely while the query/selection
  is unchanged — confirmed by scrolling up 30 lines and observing the
  preview stay there.
- **Re-anchors to the bottom (not the top) on re-render.** This is a hard
  fzf constraint, not a design choice: any re-render of the preview
  (triggered whenever the highlighted candidate changes — via typing that
  reorders the top match, or via arrow navigation) resets scroll to a fixed
  point. Without `follow` that point is line 1 (confirmed: scrolling up 30
  lines then pressing Down twice snapped back to line 1). With `follow`
  that point is the bottom instead (confirmed: same sequence snapped back
  to the last lines, not line 1). There is no fzf mechanism found that
  preserves an arbitrary manually-scrolled position across a re-render —
  the choice is "always top" vs. "always bottom" on re-render, and the
  user confirmed "always bottom" is the wanted behavior.

## Files touched

- `~/dotfiles/bin/grab` (one flag value change, `main()`'s fzf invocation)

## Verification plan

- CTRL-G in a pane with enough content to scroll: preview opens already
  scrolled to the bottom (most recent lines), not the top.
- Manually scroll the preview up (shift-up): moves freely, content visible
  matches what was actually on screen at that point.
- Type a query character that changes the top-ranked candidate: preview
  re-anchors to the bottom (not the top, and not wherever it was manually
  scrolled to — this is the known, accepted limitation).
- `ctrl-w` mode cycling and `ctrl-y` copy still work unaffected (regression
  check — this task doesn't touch either binding).

---

# `grab` preview follow-scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change `bin/grab`'s `--preview-window` value from `down,60%` to `down,60%,follow`.

**Architecture:** One flag-value edit to the single existing `fzf` call in `main()`. No new files, no new functions.

**Tech Stack:** bash, fzf 0.70 (`--preview-window`'s `follow` option), tmux (verification).

## Global Constraints

- The change is exactly the `follow` suffix on `--preview-window` — nothing else in the fzf invocation changes.
- `ctrl-w` (mode cycle) and `ctrl-y` (copy+abort) must be unaffected.

---

### Task 1: Add `follow` to the preview window

**Files:**
- Modify: `~/dotfiles/bin/grab:72` (the `--preview-window` line inside `main()`)

**Interfaces:** None — single-line value change, no new interfaces.

- [ ] **Step 1: Confirm the current value**

```bash
grep -n "preview-window" ~/dotfiles/bin/grab
```
Expected: `72:\t\t--preview-window=down,60% \`

- [ ] **Step 2: Write the implementation**

In `~/dotfiles/bin/grab`, change:
```bash
		--preview-window=down,60% \
```
to:
```bash
		--preview-window=down,60%,follow \
```

- [ ] **Step 3: End-to-end verification via a detached tmux session**

```bash
tmux new-session -d -s followcheck -x 120 -y 35
tmux send-keys -t followcheck "export PATH=\"$HOME/.local/bin:\$PATH\"" Enter
sleep 0.3
tmux send-keys -t followcheck "clear; for i in \$(seq 1 60); do echo \"line number \$i with some padding text here\"; done" Enter
sleep 0.5
tmux send-keys -t followcheck "grab" Enter
sleep 1.5
tmux capture-pane -p -t followcheck
```
Expected: the bordered preview pane shows lines near 60 (e.g. `47/64` or similar — the bottom of the capture), not lines 1-14.

```bash
tmux send-keys -t followcheck "ls"
sleep 0.5
tmux capture-pane -p -t followcheck
```
Expected: preview still shows the same bottom-anchored lines, not reset to the top.

```bash
tmux send-keys -t followcheck Escape
sleep 0.3
tmux kill-session -t followcheck 2>/dev/null
```

- [ ] **Step 4: Regression-check `ctrl-w` and `ctrl-y`**

```bash
tmux new-session -d -s followcheck2 -x 120 -y 35
tmux send-keys -t followcheck2 "export PATH=\"$HOME/.local/bin:\$PATH\"" Enter
sleep 0.3
tmux send-keys -t followcheck2 "clear; echo 'Traceback: src/foo/bar.py:123: in load_config(path=\"~/x.yaml\")'; echo 'running: --flag=value --other=1'" Enter
sleep 0.3
tmux send-keys -t followcheck2 "sel=\$(grab); echo \"RESULT:[\$sel]\" RC:\$?" Enter
sleep 1
tmux send-keys -t followcheck2 C-w
sleep 0.5
tmux capture-pane -p -t followcheck2
```
Expected: header switches to `mode: line ...`, candidate list becomes whole lines — `ctrl-w` still works.

```bash
tmux send-keys -t followcheck2 "flag"
sleep 0.3
tmux send-keys -t followcheck2 Enter
sleep 0.5
tmux capture-pane -p -t followcheck2
```
Expected: `RESULT:[--flag=value] RC:0` — Enter-to-insert contract unaffected.

```bash
tmux kill-session -t followcheck2 2>/dev/null
```

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add bin/grab
git commit -m "grab: preview window starts at the bottom and follows on reload"
```

---

## Self-Review

**Spec coverage:** starts-at-bottom and re-anchors-at-bottom-on-rerender (Step 3), manual scroll-up unaffected (already proven in the spec doc, not re-tested here since `follow` doesn't change fzf's default preview-scroll keys), `ctrl-w`/`ctrl-y`/Enter regression (Step 4). Every spec requirement covered.

**Placeholder scan:** none — every step has literal commands and expected output.

**Type/name consistency:** N/A, single-line value change, no interfaces introduced.
