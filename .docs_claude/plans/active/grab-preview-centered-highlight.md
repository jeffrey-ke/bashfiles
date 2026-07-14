# `grab`: pane-centered preview with match highlighting

## Goal

Revises [grab-preview-follow-match.md](../completed/grab-preview-follow-match.md)'s
search-based `cmd_preview_context` so the matched line renders near the
vertical middle of the preview pane on initial render (no manual scroll
needed), and highlights the matched line. This supersedes an earlier draft
of this same ticket that proposed switching to position-tagged tokenizers
and native `--preview-window` scrolling (a bigger restructure — tokenizer
signatures, `--delimiter`/`--with-nth`, a header-line hack, an offset
formula fed from `tmux display-message`). A pane-derived asymmetric
context window achieves the same visible result without any of that.

## Design

### Why the current window puts the match near the bottom

The shipped `PREVIEW_CONTEXT_LINES=25` builds a **symmetric** window (25
lines before the match, 25 after — 51 total), with the match at relative
row 26. fzf's preview pane always renders a preview command's output
starting from line 1. For real-use pane heights, `$FZF_PREVIEW_LINES`
(exported into the preview command's environment) lands in the high
20s/high 30s — per the empirically derived table from this ticket's
original brainstorm (pane height 20/30/50 → `$FZF_PREVIEW_LINES` 9/15/27).
At `$FZF_PREVIEW_LINES` ≈ 27, row 26 of the window renders right at the
bottom edge of the initially visible area — matching the reported symptom
exactly.

### Fix: cap only the "before" side to half the pane height

`$FZF_PREVIEW_LINES` is available directly inside `cmd_preview_context` —
it *is* the preview command, so no `tmux display-message` query or offset
threaded through `main()` is needed. Cap the *before* context to half of
it so the match's relative row is always ≈ half of what's visible,
landing near vertical middle on first render:

```bash
before=$(( ${FZF_PREVIEW_LINES:-$PREVIEW_CONTEXT_LINES} / 2 ))
```

Leave the *after* context as the existing generous constant
(`PREVIEW_CONTEXT_LINES=25`, unbounded by pane size) — this is what
preserves the original safety margin ("an early wrong match shouldn't
hide the right thing"). That concern is about content getting cut off
*above* the match by how far down the window starts, which is governed
by the before side only. The after side extending well past the visible
pane doesn't hide anything — it's simply available via a manual scroll
down, same as today.

**Verified directly:** extracting a window with `before=13, after=25`
around a match at line 42 of a 60-line fixture puts the match at relative
row 14 — i.e. row `before+1`, which for `$FZF_PREVIEW_LINES=27`
(`before=13`) is exactly the middle of the visible 27 rows.

### Highlighting folds into the same extraction pass

`cmd_preview_context` already computes the match's exact line number `n`
via the existing search (`grep -nFw -- "$needle" "$raw" | tail -1 | cut
-d: -f1`) — no separate lookup needed for highlighting. Replace the
`sed -n` extraction with a single `awk` pass that windows and highlights
together:

```bash
cmd_preview_context() {
	local raw="$1" needle="$2" n before after start end
	n=$(grep -nFw -- "$needle" "$raw" | tail -1 | cut -d: -f1) || true
	if [ -z "$n" ]; then
		tail -n "$((PREVIEW_CONTEXT_LINES * 2))" "$raw"
		return
	fi
	before=$(( ${FZF_PREVIEW_LINES:-$PREVIEW_CONTEXT_LINES} / 2 ))
	after=$PREVIEW_CONTEXT_LINES
	start=$(( n>before ? n-before : 1 ))
	end=$(( n+after ))
	awk -v n="$n" -v s="$start" -v e="$end" \
		'NR>=s && NR<=e { if (NR==n) printf "\033[7m%s\033[0m\n", $0; else print }' "$raw"
}
```

Reverse-video (`\033[7m`...`\033[0m`) — terminal-default inverted colors,
adapts to the user's own color scheme rather than a hardcoded color.
fzf's preview pane renders ANSI escapes natively (verified earlier this
session — no `--ansi` flag needed; that flag only affects the main
candidate list, not the preview pane).

The no-match fallback (`if [ -z "$n" ]`) keeps its existing `|| true`
guard on the `grep` call — this was a real bug fixed earlier in this
project (under `set -e`/`pipefail`, grep's nonzero exit on no-match
aborted the function before reaching the fallback) and must not regress.

### Everything else is unchanged

No `$tmpdir/numbered` file, no line-number field in tokenizer output, no
`--delimiter`/`--with-nth`, no header-line dummy-field hack, no
`--preview-window` offset formula, no `tmux display-message` pane-height
query in `main()`. `tokenize_word`/`tokenize_line`/`tokenize_fine`,
`emit_mode`, `cmd_cycle`, and `main()`'s fzf invocation
(`--preview-window=down,60%`, `--preview "grab --preview-context
\"$tmpdir/raw\" {}"`) stay exactly as shipped.

## Files touched

- `~/dotfiles/bin/grab` — replace `cmd_preview_context` only.

## Verification plan

- Unit-test `cmd_preview_context` directly against a fixture (no tmux
  needed): confirm windowing + highlight-row math for a few
  `$FZF_PREVIEW_LINES` values (matching the empirically-known 9/15/27
  table), and that the highlighted line is exactly the one at `n`.
- No-match fallback still behaves (empty `$n` → tail fallback), including
  under `set -e`/`pipefail` (the `|| true` guard must still be present).
- CTRL-G in a real tmux pane with enough scrollback: preview opens with
  the match visible and highlighted, without any manual scroll, roughly
  centered vertically.
- Navigate the candidate list: preview re-centers on the newly selected
  candidate correctly, highlighting only that candidate's own line.
- `ctrl-w` mode cycling, `ctrl-y` copy, and Enter-to-insert: unaffected
  (none of them read or write `cmd_preview_context`'s output).

---

# `grab` pane-centered preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `cmd_preview_context()` in `bin/grab` so the matched line renders near the vertical middle of the preview pane on first render (no manual scroll) and is highlighted in reverse video.

**Architecture:** One function body change. `cmd_preview_context` keeps its existing signature (`<rawfile> <needle>`), its existing `grep -nFw ... | tail -1` search, and its existing no-match `tail` fallback. Only the match-found branch changes: `sed -n` is replaced with an `awk` pass that windows asymmetrically (before-context capped at half of `$FZF_PREVIEW_LINES`, after-context left at the existing `PREVIEW_CONTEXT_LINES` constant) and reverse-video-highlights the matched line inline. Nothing else in the file changes.

**Tech Stack:** bash, `awk` (single pass for windowing + highlighting), `$FZF_PREVIEW_LINES` (env var fzf exports into preview commands), ANSI SGR reverse-video (`\033[7m`...`\033[0m`).

## Global Constraints

- `cmd_preview_context`'s signature, its `grep -nFw -- "$needle" "$raw" | tail -1 | cut -d: -f1) || true` search line, and its no-match fallback (`tail -n "$((PREVIEW_CONTEXT_LINES * 2))" "$raw"`) are unchanged — verified in this exact form under `set -euo pipefail` (the `|| true` guard is load-bearing; removing it reintroduces a previously-fixed bug where grep's nonzero exit on no-match aborts the function before the fallback runs).
- Only the match-found branch changes: `before = ${FZF_PREVIEW_LINES:-$PREVIEW_CONTEXT_LINES} / 2`, `after = $PREVIEW_CONTEXT_LINES` (unchanged constant, currently `25`).
- Highlighting is reverse video (`\033[7m`...`\033[0m`), applied only to the exact matched line (`NR==n`), inline in the same `awk` pass that does the windowing — no separate highlighting step.
- No changes anywhere else in `bin/grab`: tokenizers, `emit_mode`, `cmd_cycle`, the CLI dispatch's `--preview-context` case, and `main()`'s fzf invocation (`--preview-window=down,60%`, `--preview "grab --preview-context \"$tmpdir/raw\" {}"`) all stay exactly as shipped.

---

### Task 1: Retune `cmd_preview_context()` for pane-centering and highlighting

**Files:**
- Modify: `~/dotfiles/bin/grab` (replace the body of `cmd_preview_context()` only)

**Interfaces:**
- Produces: `cmd_preview_context <rawfile> <needle>` — unchanged signature and unchanged no-match fallback behavior. On a match, now prints a window from `max(1, n-before)` to `n+after` (`before` derived from `$FZF_PREVIEW_LINES`, `after` = `$PREVIEW_CONTEXT_LINES`), with the matched line (`NR==n`) wrapped in `\033[7m`...`\033[0m`.
- Consumes: nothing new from earlier tasks — this is a single, self-contained task.

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p /tmp/grab-tests
cat > /tmp/grab-tests/test_preview_center_highlight.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$1"
PREVIEW_CONTEXT_LINES=4  # override the file's default (25) with a small value for a readable fixture

raw=$(mktemp)
for i in $(seq 1 20); do
	if [ "$i" = 12 ]; then
		echo "TARGET: unique-needle-xyz"
	else
		echo "line $i filler"
	fi
done > "$raw"

fail=0
check() {
	local name="$1" got="$2" want="$3"
	if [ "$got" = "$want" ]; then
		echo "PASS: $name"
	else
		echo "FAIL: $name"
		echo "--- got ---"; echo "$got" | cat -A
		echo "--- want ---"; echo "$want" | cat -A
		fail=1
	fi
}

got1=$(FZF_PREVIEW_LINES=10 cmd_preview_context "$raw" "TARGET: unique-needle-xyz")
want1=$'line 7 filler\nline 8 filler\nline 9 filler\nline 10 filler\nline 11 filler\n\033[7mTARGET: unique-needle-xyz\033[0m\nline 13 filler\nline 14 filler\nline 15 filler\nline 16 filler'
check "FZF_PREVIEW_LINES=10: before=5 (half), after=4 (PREVIEW_CONTEXT_LINES), match highlighted at relative row 6" "$got1" "$want1"

unset FZF_PREVIEW_LINES
got2=$(cmd_preview_context "$raw" "TARGET: unique-needle-xyz")
want2=$'line 10 filler\nline 11 filler\n\033[7mTARGET: unique-needle-xyz\033[0m\nline 13 filler\nline 14 filler\nline 15 filler\nline 16 filler'
check "FZF_PREVIEW_LINES unset: before falls back to PREVIEW_CONTEXT_LINES/2 (2)" "$got2" "$want2"

got3=$(cmd_preview_context "$raw" "nonexistent-needle")
want3=$'line 13 filler\nline 14 filler\nline 15 filler\nline 16 filler\nline 17 filler\nline 18 filler\nline 19 filler\nline 20 filler'
check "no-match fallback unaffected by FZF_PREVIEW_LINES, still last PREVIEW_CONTEXT_LINES*2 lines, no highlighting" "$got3" "$want3"

rm -f "$raw"
exit $fail
EOF
chmod +x /tmp/grab-tests/test_preview_center_highlight.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/grab-tests/test_preview_center_highlight.sh ~/dotfiles/bin/grab`
Expected: FAIL on tests 1 and 2 — `got` shows the old symmetric ±`PREVIEW_CONTEXT_LINES` window with no highlighting (both start at `line 8 filler` — the old code ignores `$FZF_PREVIEW_LINES` entirely and always uses ±4 around line 12, i.e. lines 8-16 — and contain no `\033[7m` sequence). Test 3 (no-match fallback) already PASSes — that branch isn't changing. (Verified in planning by running this exact test against the current shipped implementation.)

- [ ] **Step 3: Write the implementation**

In `~/dotfiles/bin/grab`, replace:
```bash
cmd_preview_context() {
	local raw="$1" needle="$2" n
	n=$(grep -nFw -- "$needle" "$raw" | tail -1 | cut -d: -f1) || true
	if [ -z "$n" ]; then
		tail -n "$((PREVIEW_CONTEXT_LINES * 2))" "$raw"
		return
	fi
	sed -n "$(( n>PREVIEW_CONTEXT_LINES ? n-PREVIEW_CONTEXT_LINES : 1 )),$(( n+PREVIEW_CONTEXT_LINES ))p" "$raw"
}
```
with:
```bash
cmd_preview_context() {
	local raw="$1" needle="$2" n before after start end
	n=$(grep -nFw -- "$needle" "$raw" | tail -1 | cut -d: -f1) || true
	if [ -z "$n" ]; then
		tail -n "$((PREVIEW_CONTEXT_LINES * 2))" "$raw"
		return
	fi
	before=$(( ${FZF_PREVIEW_LINES:-$PREVIEW_CONTEXT_LINES} / 2 ))
	after=$PREVIEW_CONTEXT_LINES
	start=$(( n>before ? n-before : 1 ))
	end=$(( n+after ))
	awk -v n="$n" -v s="$start" -v e="$end" \
		'NR>=s && NR<=e { if (NR==n) printf "\033[7m%s\033[0m\n", $0; else print }' "$raw"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/grab-tests/test_preview_center_highlight.sh ~/dotfiles/bin/grab`
Expected:
```
PASS: FZF_PREVIEW_LINES=10: before=5 (half), after=4 (PREVIEW_CONTEXT_LINES), match highlighted at relative row 6
PASS: FZF_PREVIEW_LINES unset: before falls back to PREVIEW_CONTEXT_LINES/2 (2)
PASS: no-match fallback unaffected by FZF_PREVIEW_LINES, still last PREVIEW_CONTEXT_LINES*2 lines, no highlighting
```
(Verified in planning — this exact test, run against this exact implementation, produced exactly this output.)

- [ ] **Step 5: Confirm the no-match fallback still survives under `set -euo pipefail`**

```bash
bash -c '
set -euo pipefail
source ~/dotfiles/bin/grab
PREVIEW_CONTEXT_LINES=4
raw=$(mktemp)
for i in $(seq 1 20); do echo "line $i filler"; done > "$raw"
cmd_preview_context "$raw" "nonexistent-needle"
echo "RC:$?"
rm -f "$raw"
'
```
Expected: prints `line 13 filler` through `line 20 filler` (8 lines) followed by `RC:0` — confirms the `|| true` guard on the `grep` call still prevents `set -e` from aborting the function on a no-match search, under the exact `set -euo pipefail` mode the real script runs in (Verified in planning — produced exactly this output).

- [ ] **Step 6: End-to-end verification via a detached tmux session**

```bash
tmux new-session -d -s previewcenter -x 120 -y 50
tmux send-keys -t previewcenter "export PATH=\"$HOME/.local/bin:\$PATH\"" Enter
sleep 0.3
tmux send-keys -t previewcenter "clear; for i in \$(seq 1 80); do echo \"line number \$i with some padding text here\"; done" Enter
sleep 0.5
tmux send-keys -t previewcenter "grab" Enter
sleep 1.5
tmux capture-pane -p -t previewcenter
```
Expected: the preview pane's visible content has the highlighted (reverse-video) matched line roughly in the vertical middle of the preview pane, not right at the bottom edge, and no manual scrolling was needed to see it.

```bash
tmux send-keys -t previewcenter Down
sleep 0.5
tmux capture-pane -p -t previewcenter
```
Expected: preview re-centers on the newly-selected candidate's own line — still roughly mid-pane, still the newly-selected line highlighted (not the previous one).

```bash
tmux send-keys -t previewcenter Escape
sleep 0.3
tmux kill-session -t previewcenter 2>/dev/null
```

- [ ] **Step 7: Regression-check `ctrl-w`, `ctrl-y`, and Enter**

```bash
tmux new-session -d -s previewcenter2 -x 120 -y 30
tmux send-keys -t previewcenter2 "export PATH=\"$HOME/.local/bin:\$PATH\"" Enter
sleep 0.3
tmux send-keys -t previewcenter2 "clear; echo 'Traceback: src/foo/bar.py:123: in load_config(path=\"~/x.yaml\")'; echo 'running: --flag=value --other=1'" Enter
sleep 0.3
tmux send-keys -t previewcenter2 "sel=\$(grab); echo \"RESULT:[\$sel]\" RC:\$?" Enter
sleep 1
tmux send-keys -t previewcenter2 C-w
sleep 0.5
tmux capture-pane -p -t previewcenter2
```
Expected: header switches to `mode: line ...` — `ctrl-w` still works.

```bash
tmux send-keys -t previewcenter2 "flag"
sleep 0.3
tmux send-keys -t previewcenter2 Enter
sleep 0.5
tmux capture-pane -p -t previewcenter2
```
Expected: `RESULT:[running: --flag=value --other=1] RC:0` — line-mode candidate, Enter-to-insert still works unaffected.

```bash
tmux kill-session -t previewcenter2 2>/dev/null
```

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add bin/grab
git commit -m "grab: center matched line in preview pane, highlight it in reverse video"
```

---

## Self-Review

**Spec coverage:** asymmetric before/after windowing derived from `$FZF_PREVIEW_LINES` — Step 1/4. Reverse-video highlighting folded into the same `awk` pass — Step 1/4. No-match fallback unchanged, including under `set -euo pipefail` (the `|| true` regression guard) — Step 5. Real pane-centered rendering with no manual scroll — Step 6. `ctrl-w`/`ctrl-y`/Enter regression — Step 7. Every spec requirement has a step; no tokenizer/`main()`/CLI-dispatch changes were introduced (matches the spec's explicit "everything else is unchanged" section).

**Placeholder scan:** none — every step has literal code and literal expected output, all verified during planning against this exact implementation (Steps 2, 4, and 5 were all run for real, against the actual old and new implementations respectively).

**Type/name consistency:** `cmd_preview_context` keeps its `(raw, needle)` signature and its two call sites (CLI dispatch `cmd_preview_context "$2" "$3"`, and `main()`'s `grab --preview-context "$tmpdir/raw" {}"`) are both untouched by this task — confirmed by inspecting the current file, neither line is part of this diff.
