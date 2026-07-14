# `grab`: preview follows the highlighted candidate's actual position

## Goal

`grab`'s preview window (see
[grab-preview-window.md](../completed/grab-preview-window.md) and
[grab-preview-follow-scroll.md](../completed/grab-preview-follow-scroll.md))
currently always shows a static, always-bottom view of the captured
screen, with no relationship to which candidate is highlighted. Make the
preview jump to and show context around wherever the highlighted
candidate's text actually appears in the captured screen.

## Design

Two approaches were considered:

- **B (position-tagged):** tokenizers emit `<linenum>\t<token>`, hidden
  via `--delimiter`/`--with-nth`, driving fzf's native `--preview-window
  '+{1}-OFFSET'` scroll offset over the *unmodified full file*. Exact
  (no ambiguity about which occurrence), preserves full scrollability.
  Verified working in a real tmux session (a `5/10`-line scroll offset
  landed exactly where expected). Rejected: requires restructuring the
  tokenizer output format and the dedup logic (currently keys on the
  whole candidate line; would need to key on just the token field),
  plus checking interaction with `--header-lines=1`.
- **A (search-based, chosen):** the preview *command* itself searches
  `$tmpdir/raw` for the current candidate's text at render time and
  shows a window of context around it. No tokenizer/dedup changes at
  all. Verified working in a real tmux session (jumped from a line-3
  match to a line-8 match correctly). Trade-off, explicitly accepted:
  content is a truncated window (not the full file), and — found while
  testing — a plain fixed-string search can match as a *substring*
  inside an unrelated longer word (e.g. searching for the fine-mode
  token `in` would also match inside `runn`**`in`**`g`), risking a wrong
  jump. Mitigated (not eliminated) with word-boundary matching; the
  residual risk is accepted, mainly affecting short/common "fine"-mode
  tokens.

### Mechanism (approach A, as chosen)

New internal `grab` subcommand, dispatched the same way `--cycle`
already is:

```
grab --preview-context <rawfile> <candidate-text>
```

```bash
PREVIEW_CONTEXT_LINES=25

cmd_preview_context() {
	local raw="$1" needle="$2" n
	n=$(grep -nFw -- "$needle" "$raw" | tail -1 | cut -d: -f1)
	if [ -z "$n" ]; then
		tail -n "$((PREVIEW_CONTEXT_LINES * 2))" "$raw"
		return
	fi
	sed -n "$(( n>PREVIEW_CONTEXT_LINES ? n-PREVIEW_CONTEXT_LINES : 1 )),$(( n+PREVIEW_CONTEXT_LINES ))p" "$raw"
}
```

- **`grep -nFw`** — fixed-string (`-F`, no regex metacharacter surprises
  from tokens like `load_config(path=...)`) *and* whole-word (`-w`).
  Verified directly: `-w` correctly rejects `in` as a substring of
  `running`, still matches a standalone `in`, and works correctly for
  multi-word "line"-mode candidates (`grep -Fw -- "src/foo/bar.py:123:
  in load_config"`) and punctuation-heavy "word"-mode tokens
  (`--flag=value`) — `-w`'s boundary check only applies at the start/end
  of the whole matched string, not internally.
- **`tail -1`** — the *last* (most recent) occurrence, matching dedup's
  own "most recent occurrence wins" semantics (dedup runs on the
  `rev_lines`-reversed stream, so the occurrence it keeps for any given
  token is always the highest original line number) — the line shown is
  always the same occurrence the candidate was deduped from, not an
  arbitrary earlier one.
- **`PREVIEW_CONTEXT_LINES=25`** (revised after brainstorming — see
  below) — a plain tunable constant (same pattern as the existing
  `SCROLLBACK_LINES=2000`), *not* derived from `$FZF_PREVIEW_LINES`/pane
  height. Symmetric: `PREVIEW_CONTEXT_LINES` lines before and after the
  match. Explicitly a starting point for empirical tuning during real
  use, not a precisely-optimized number.
- **Fallback (match not found — shouldn't happen by construction, since
  every candidate is extracted from `raw` itself, but kept defensive):**
  show the last `PREVIEW_CONTEXT_LINES * 2` lines — keeps the "most
  recent" bias from the prior sub-project rather than reverting to the
  top of the file.

**Context-window sizing (revised after brainstorming):** the original
draft derived the window size from `$FZF_PREVIEW_LINES` (the actual
pane height) so the content exactly filled the pane with no scrolling
needed. Revisited after the user raised a real concern: if the search
lands on a slightly-wrong occurrence (the accepted residual risk from
`grep -Fw`'s substring-collision mitigation), a window sized to exactly
fill the pane has no margin — you see nothing beyond that tight
snippet. Considered three options, tested against realistic multi-section
content:
- **Exactly-pane-fitting (original):** no margin.
- **Symmetric, generous, decoupled from pane height:** more buffer
  either direction, but — found while testing — since fzf always starts
  rendering a preview command's output from line 1, a symmetric window
  bigger than the pane pushes the match itself below the initially
  visible area; you'd need to scroll down partway to even see it.
- **Asymmetric (small lead-in, generous trailing buffer):** keeps the
  match immediately visible at the top while still providing a large
  safety margin — but only in one direction.

User's call: **symmetric and generous**, explicitly accepting that the
match won't be immediately visible at the very top of the pane and an
initial scroll may be needed to center on it, in exchange for equal
context both before and after.

### Changes to `main()`

Replace:
```bash
	emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
		--preview "cat \"$tmpdir/raw\"" \
		--preview-window=down,60%,follow \
		--bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
		--bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
```
with:
```bash
	emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
		--preview "grab --preview-context \"$tmpdir/raw\" {}" \
		--preview-window=down,60% \
		--bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
		--bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
```

**`{}` quoting note (verified before writing this doc):** fzf
auto-quotes `{}` itself when substituting it into a shell command
template — writing your own quotes around it is the documented "common
mistake." Confirmed directly: a candidate containing an embedded single
quote (`it's a test`) was correctly passed through as one argument with
no extra quoting needed on our part. `{}` is used bare here, exactly
matching this verified behavior.

**`,follow` is dropped** — superseded by this feature. "Always scroll to
the bottom on every re-render" (the prior sub-project) and "always
scroll to the match" can't coexist; the user confirmed this tradeoff is
fine, since candidates are already reverse-ordered (most-recent-first),
so the initial top candidate before typing anything is normally the
most recent line anyway.

## Files touched

- `~/dotfiles/bin/grab` — add `cmd_preview_context()`, add `--preview-context` to the CLI dispatch, modify `main()`'s fzf invocation (2 lines)

## Verification plan

- CTRL-G in a pane with varied content: initial preview shows context
  around whatever the top (most-recent) candidate's match is, not
  necessarily the literal last line of the file, but typically close to
  it.
- Navigate the candidate list (arrow keys or typing that changes the top
  match): preview jumps to a different context window matching the new
  candidate's actual position.
- `ctrl-w` mode cycling and `ctrl-y` copy still work unaffected — neither
  reads or writes the preview.
- A deliberately short/common "fine"-mode token that also appears as a
  substring of a longer, unrelated word: confirm `-w` prevents the
  substring false-match (spot check, not exhaustive — the residual risk
  for genuinely ambiguous short tokens is accepted, not fully eliminated).
- No-match fallback (contrived test input where the searched text isn't
  found): shows the last `PREVIEW_CONTEXT_LINES * 2` lines rather than
  erroring.
- Symmetric generous window: confirm the shown range extends
  `PREVIEW_CONTEXT_LINES` before *and* after the match (not just
  filling whatever the pane happens to show).

---

# `grab` preview-follows-match Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `cmd_preview_context()` to `bin/grab`, wire it into the CLI dispatch as `--preview-context`, and change `main()`'s fzf invocation to use it (dropping `,follow`).

**Architecture:** One new function plus one new CLI dispatch case, both following the exact patterns `cmd_cycle`/`--cycle` already established in this file. `main()`'s fzf `--preview`/`--preview-window` arguments change; nothing else in the file changes.

**Tech Stack:** bash, POSIX `grep -F` (fixed-string) + `-w` (whole-word), `sed`, `tail`, fzf 0.70 (`{}` placeholder).

## Global Constraints

- Search must be fixed-string (`-F`) and whole-word (`-w`) — no plain substring matching (verified: without `-w`, a short token like `in` can falsely match inside an unrelated longer word like `running`).
- The occurrence used must be the *last* (most recent) match (`tail -1`) — matches dedup's own "most recent occurrence wins" semantics.
- Context window size is a plain constant, `PREVIEW_CONTEXT_LINES=25` (same pattern as the existing `SCROLLBACK_LINES=2000`) — symmetric, *not* derived from `$FZF_PREVIEW_LINES`/pane height, and not hidden behind an environment variable.
- `{}` in the `--preview` command string must be used bare, with no extra quotes added around it — fzf auto-quotes it, and adding your own quotes on top is the documented "common mistake."
- `,follow` is removed from `--preview-window` — superseded by this feature, not layered alongside it.

---

### Task 1: Add `cmd_preview_context()` and wire it in

**Files:**
- Modify: `~/dotfiles/bin/grab` (add `PREVIEW_CONTEXT_LINES` and `cmd_preview_context()` after `cmd_cycle()`; add a `--preview-context` case to the CLI dispatch; modify `main()`'s fzf invocation)

**Interfaces:**
- Produces: `cmd_preview_context <rawfile> <needle>` — prints a window of `PREVIEW_CONTEXT_LINES` lines before and after the last whole-word match of `<needle>` in `<rawfile>`, or the last `PREVIEW_CONTEXT_LINES * 2` lines of `<rawfile>` if no match is found.
- Consumes: nothing new from earlier tasks — this is a single, self-contained task.

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p /tmp/grab-tests
cat > /tmp/grab-tests/test_preview_context.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$1"
PREVIEW_CONTEXT_LINES=3  # override the file's default (25) with a small value for a readable fixture

raw=$(mktemp)
cat >"$raw" <<'RAW'
line 1 filler
line 2 filler
Traceback: src/foo/bar.py:123: in load_config(path="~/x.yaml")
line 4 filler
line 5 filler
line 6 filler
line 7 filler
line 8 filler
running: --flag=value --other=1
line 10 filler
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

got1=$(cmd_preview_context "$raw" "running: --flag=value --other=1")
want1=$'line 6 filler\nline 7 filler\nline 8 filler\nrunning: --flag=value --other=1\nline 10 filler'
check "match on line 9, symmetric PREVIEW_CONTEXT_LINES window" "$got1" "$want1"

got2=$(cmd_preview_context "$raw" "in")
want2=$'line 1 filler\nline 2 filler\nTraceback: src/foo/bar.py:123: in load_config(path="~/x.yaml")\nline 4 filler\nline 5 filler\nline 6 filler'
check "word-boundary match on line 3, not the substring inside 'running' on line 9" "$got2" "$want2"

got3=$(cmd_preview_context "$raw" "xyz123nonexistent")
want3=$'line 5 filler\nline 6 filler\nline 7 filler\nline 8 filler\nrunning: --flag=value --other=1\nline 10 filler'
check "no-match fallback shows last PREVIEW_CONTEXT_LINES*2 lines" "$got3" "$want3"

rm -f "$raw"
exit $fail
EOF
chmod +x /tmp/grab-tests/test_preview_context.sh
```

Note: Test 2 is the key regression guard for the word-boundary requirement — the fixture deliberately places the standalone `in` (line 3, inside `"... 123: in load_config..."`) *before* the substring-only occurrence inside `running` (line 9), so that a naive non-word-boundary search would incorrectly pick line 9 (the later line) instead of the correct line 3. The test overrides `PREVIEW_CONTEXT_LINES` to `3` *after* sourcing `bin/grab` (sourcing runs the file's own `PREVIEW_CONTEXT_LINES=25` assignment, so the override must come after, not before) — `cmd_preview_context` reads the variable at call time, so this is safe and doesn't require touching the real file's default.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/grab-tests/test_preview_context.sh ~/dotfiles/bin/grab`
Expected: FAIL — `cmd_preview_context: command not found` (function doesn't exist yet).

- [ ] **Step 3: Write the implementation**

In `~/dotfiles/bin/grab`, add immediately after the `cmd_cycle()` function (before `main()`):

```bash
PREVIEW_CONTEXT_LINES=25

cmd_preview_context() {
	local raw="$1" needle="$2" n
	n=$(grep -nFw -- "$needle" "$raw" | tail -1 | cut -d: -f1)
	if [ -z "$n" ]; then
		tail -n "$((PREVIEW_CONTEXT_LINES * 2))" "$raw"
		return
	fi
	sed -n "$(( n>PREVIEW_CONTEXT_LINES ? n-PREVIEW_CONTEXT_LINES : 1 )),$(( n+PREVIEW_CONTEXT_LINES ))p" "$raw"
}
```

Add a `--preview-context` case to the CLI dispatch — replace:
```bash
	case "${1:-}" in
	--cycle) cmd_cycle "$2" ;;
	"") main ;;
	*)
		echo "grab: unknown argument '$1'" >&2
		exit 1
		;;
	esac
```
with:
```bash
	case "${1:-}" in
	--cycle) cmd_cycle "$2" ;;
	--preview-context) cmd_preview_context "$2" "$3" ;;
	"") main ;;
	*)
		echo "grab: unknown argument '$1'" >&2
		exit 1
		;;
	esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/grab-tests/test_preview_context.sh ~/dotfiles/bin/grab`
Expected:
```
PASS: match on line 9, symmetric PREVIEW_CONTEXT_LINES window
PASS: word-boundary match on line 3, not the substring inside 'running' on line 9
PASS: no-match fallback shows last PREVIEW_CONTEXT_LINES*2 lines
```
(Verified in planning — this exact test, run against this exact implementation, produced exactly this output.)

- [ ] **Step 4b: Confirm the real (unoverridden) default actually shows a symmetric window bigger than a typical pane**

```bash
cat > /tmp/grab-tests/test_preview_context_default.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$1"

raw=$(mktemp)
cat >"$raw" <<'RAW'
line 1 filler
line 2 filler
Traceback: src/foo/bar.py:123: in load_config(path="~/x.yaml")
line 4 filler
line 5 filler
line 6 filler
line 7 filler
line 8 filler
running: --flag=value --other=1
line 10 filler
RAW

echo "PREVIEW_CONTEXT_LINES default: $PREVIEW_CONTEXT_LINES"
echo "line count with default sizing (window bigger than this 10-line fixture, so whole file):"
cmd_preview_context "$raw" "running: --flag=value --other=1" | wc -l

rm -f "$raw"
EOF
chmod +x /tmp/grab-tests/test_preview_context_default.sh
bash /tmp/grab-tests/test_preview_context_default.sh ~/dotfiles/bin/grab
```
Expected: `PREVIEW_CONTEXT_LINES default: 25` and `10` (the whole 10-line fixture, since a ±25 window covers a 10-line file entirely — confirms the real, unoverridden default is genuinely larger than this small test fixture, consistent with being generous for real-sized captures).

- [ ] **Step 5: Update `main()`'s fzf invocation**

In `~/dotfiles/bin/grab`, replace:
```bash
	emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
		--preview "cat \"$tmpdir/raw\"" \
		--preview-window=down,60%,follow \
		--bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
		--bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
```
with:
```bash
	emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
		--preview "grab --preview-context \"$tmpdir/raw\" {}" \
		--preview-window=down,60% \
		--bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
		--bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
```

- [ ] **Step 6: End-to-end verification via a detached tmux session**

```bash
tmux new-session -d -s previewmatch -x 120 -y 30
tmux send-keys -t previewmatch "export PATH=\"$HOME/.local/bin:\$PATH\"" Enter
sleep 0.3
tmux send-keys -t previewmatch "clear; for i in \$(seq 1 60); do echo \"line number \$i with some padding text here\"; done" Enter
sleep 0.5
tmux send-keys -t previewmatch "grab" Enter
sleep 1.5
tmux capture-pane -p -t previewmatch
```
Expected: preview shows context centered around wherever the initial top (most-recent) candidate's text actually appears — since candidates are reverse-ordered, this is normally near the end of the captured content, similar in spirit to the prior sub-project's always-bottom behavior but now driven by an actual match rather than a fixed anchor.

```bash
tmux send-keys -t previewmatch Down
sleep 0.5
tmux capture-pane -p -t previewmatch
```
Expected: preview content changes to a different window, centered around the newly-highlighted candidate's own position — confirms the preview is now following the selection, not static.

```bash
tmux send-keys -t previewmatch Escape
sleep 0.3
tmux kill-session -t previewmatch 2>/dev/null
```

- [ ] **Step 7: Regression-check `ctrl-w`, `ctrl-y`, and Enter**

```bash
tmux new-session -d -s previewmatch2 -x 120 -y 30
tmux send-keys -t previewmatch2 "export PATH=\"$HOME/.local/bin:\$PATH\"" Enter
sleep 0.3
tmux send-keys -t previewmatch2 "clear; echo 'Traceback: src/foo/bar.py:123: in load_config(path=\"~/x.yaml\")'; echo 'running: --flag=value --other=1'" Enter
sleep 0.3
tmux send-keys -t previewmatch2 "sel=\$(grab); echo \"RESULT:[\$sel]\" RC:\$?" Enter
sleep 1
tmux send-keys -t previewmatch2 C-w
sleep 0.5
tmux capture-pane -p -t previewmatch2
```
Expected: header switches to `mode: line ...` — `ctrl-w` still works with the new preview wiring.

```bash
tmux send-keys -t previewmatch2 "flag"
sleep 0.3
tmux send-keys -t previewmatch2 Enter
sleep 0.5
tmux capture-pane -p -t previewmatch2
```
Expected: `RESULT:[--flag=value] RC:0` — Enter-to-insert contract unaffected.

```bash
tmux kill-session -t previewmatch2 2>/dev/null
```

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add bin/grab
git commit -m "grab: preview follows the highlighted candidate's actual position"
```

---

## Self-Review

**Spec coverage:** `cmd_preview_context()` matching all documented behaviors (symmetric `PREVIEW_CONTEXT_LINES` window sizing, word-boundary correctness, most-recent-occurrence, no-match fallback) — Step 1/4, real-default-value check — Step 4b. CLI dispatch wiring — Step 3. `main()`'s `--preview`/`--preview-window` change (bare `{}`, `,follow` dropped) — Step 5. Real end-to-end preview-follows-selection behavior — Step 6. `ctrl-w`/`ctrl-y`/Enter regression — Step 7. Every spec requirement has a step.

**Placeholder scan:** none — every step has literal code and literal expected output, all verified during planning against this exact implementation.

**Type/name consistency:** `cmd_preview_context` takes `(raw, needle)` consistently between its definition (Step 3) and its CLI dispatch call (`cmd_preview_context "$2" "$3"`, Step 3) and its invocation from `main()` (`grab --preview-context "$tmpdir/raw" {}`, Step 5) — `$2`/`$3` map to `<rawfile>`/`<candidate-text>` in that order throughout.
