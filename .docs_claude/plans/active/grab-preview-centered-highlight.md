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
