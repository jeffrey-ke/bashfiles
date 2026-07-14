# `grab`: auto-centered preview with match highlighting

## Goal

Supersedes
[grab-preview-follow-match.md](../completed/grab-preview-follow-match.md).
Real usage revealed that approach's search-based design (the preview
command searches `$tmpdir/raw` for the candidate's text at render time)
cannot auto-center the match: fzf always starts rendering a preview
command's output from line 1, so a context window bigger than the pane
(`PREVIEW_CONTEXT_LINES=25`) pushes the match below the initially-visible
area, requiring a manual scroll that lands wherever the user stops, not
centered. Switch to the position-tagged approach considered and rejected
during that feature's original brainstorm — tokenizers carry each
candidate's source line number, driving fzf's *native* preview scroll
(which auto-centers correctly, since it isn't limited to "render from line
1 of the command's output"). Also add: highlight the matched line within
the preview, so it's visually distinct from surrounding context.

## Design

### Tokenizers carry a line-number field

`main()` numbers `$tmpdir/raw` once (before any reversal), producing
`$tmpdir/numbered`:
```bash
awk '{print NR"\t"$0}' "$tmpdir/raw" > "$tmpdir/numbered"
```
Each tokenizer still calls the existing `rev_lines` (unchanged) on this
numbered file, then splits the *text* portion (field 2) per its mode while
carrying that line's original number through to every token it emits, and
dedupes on the text field only (not the whole `<n>\t<token>` line, which
would defeat dedup since the same token from different lines would no
longer collide):

```bash
tokenize_word() { rev_lines "$1" | awk -F'\t' '{ n=$1; text=$2; ntok=split(text, toks, /[ \t]+/); for(i=1;i<=ntok;i++) if(toks[i]!="") print n"\t"toks[i] }' | awk -F'\t' '!seen[$2]++'; }
tokenize_line() { rev_lines "$1" | awk -F'\t' 'NF>1 && $2!="" && !seen[$2]++'; }
tokenize_fine() { rev_lines "$1" | awk -F'\t' '{ n=$1; text=$2; while (match(text, /[A-Za-z0-9_]+/)) { print n"\t"substr(text, RSTART, RLENGTH); text = substr(text, RSTART+RLENGTH) } }' | awk -F'\t' '!seen[$2]++'; }
```

`tokenize_mode`'s dispatch and `tokenize_word`/`tokenize_line`/
`tokenize_fine`'s `<file>` argument all now take `$tmpdir/numbered`
instead of `$tmpdir/raw` — `main()` and `cmd_cycle` both switch their
call sites accordingly. `$tmpdir/raw` (unnumbered) is still needed
separately, for the preview command's display/highlighting.

All three modes verified directly against a real fixture during
brainstorming, confirming: word-mode tokens carry the correct source line
number; line-mode candidates are the numbered+reversed line as-is (just
filtered for blanks); fine-mode's extraction loop (`match`/`RSTART`/
`RLENGTH`) carries the line number through each extracted run; and dedup
correctly keeps the *most recent* occurrence's line number in all three
cases (verified with a token that appears on multiple lines — the earlier,
already-seen duplicate is dropped, leaving only the later line's entry).

### Display hides the line-number field

```
--delimiter '\t' --with-nth=2..
```
Fuzzy matching and display both operate on the text field only — typing a
query behaves exactly as before, nothing about the search experience
changes. **Found while testing:** `--header-lines` also applies
`--with-nth`'s reformatting to the header line, so `emit_mode` must prefix
its header line with a dummy leading field too:
```bash
emit_mode() {
	local mode="$1" raw="$2"
	printf '0\t'
	header_line "$mode"
	printf '\n'
	tokenize_mode "$mode" "$raw"
}
```
(`header_line` itself is unchanged — only the new `printf '0\t'` prefix is
added in `emit_mode`.)

### Native scroll, auto-centered

```
--preview "grab --preview-context \"$tmpdir/raw\" {1}"
--preview-window "down,60%,+{1}-$offset"
```
`{1}` is now the *line number* field (not searched-for text) — `main()`
already knows it exactly, no runtime search needed. `$offset` is computed
once in `main()`, before launching fzf, from the actual current tmux pane
height:
```bash
pane_height=$(tmux display-message -p '#{pane_height}')
offset=$(( (pane_height * 60 / 100 - 3) / 2 ))
```
**Verified empirically** (3 data points: pane heights 20/30/50 → measured
`$FZF_PREVIEW_LINES` 9/15/27 inside a real preview command) that
`floor(pane_height * 0.6) - 3` matches this repo's fzf/border-style
`down,60%` layout consistently — the `-3` accounts for border and layout
overhead specific to this configuration, not a universal fzf constant.
Halving that gives the offset that lands the match roughly in the vertical
middle of the pane; confirmed directly in a real tmux session (match line
appeared at row 9 of a 15-row visible box, ~50%). This replaces
`PREVIEW_CONTEXT_LINES` entirely — there is no separate "content window"
constant anymore, since the preview command always shows the *whole*
`$tmpdir/raw` file; only the initial scroll position is computed.

**Note on staleness:** `$offset` is computed once when `grab` launches (a
single tmux `display-message` call), not re-queried per keystroke or
mode-cycle. If the user resizes their terminal while the picker is open,
centering won't re-adapt until the next `grab` invocation — an accepted,
rare edge case, not handled specially.

### Highlighting

```bash
cmd_preview_context() {
	local raw="$1" n="$2"
	awk -v n="$n" '{ if (NR==n) printf "\033[7m%s\033[0m\n", $0; else print }' "$raw"
}
```
Reverse-video (`\033[7m`...`\033[0m`) — terminal-default inverted
colors, adapts to the user's actual color scheme rather than a hardcoded
color. **Verified fzf's preview pane renders ANSI escape codes natively**,
with no `--ansi` flag needed (that flag only affects the main candidate
list, not the preview pane) — confirmed via `tmux capture-pane -e`
showing the literal `\033[7m` sequence correctly wrapping the target line
and nothing else.

### `cmd_preview_context`'s argument meaning changes

The previous (superseded) design passed the *candidate's text* as the
second argument and searched for it; this design passes the *line
number* directly (already known, no search needed) — same dispatch shape
(`--preview-context <rawfile> <arg>`), same function name, different
meaning for `<arg>`. `grep -nFw`/`tail -1`/`PREVIEW_CONTEXT_LINES` are all
removed — no longer needed now that the line number is known exactly
rather than searched for.

## Files touched

- `~/dotfiles/bin/grab` — restructure `tokenize_word`/`tokenize_line`/
  `tokenize_fine` (line-number tracking), `emit_mode` (dummy header
  field), replace `cmd_preview_context` (highlight by line number instead
  of search), `main()` (create `$tmpdir/numbered`, compute `$offset`,
  update the fzf invocation's `--delimiter`/`--with-nth`/`--preview`/
  `--preview-window`), `cmd_cycle` (switch its tokenize call site from
  `raw` to `numbered`)

## Verification plan

- Re-run the existing tokenizer tests, adapted for the new `<n>\t<token>`
  output shape — word/line/fine each carry the correct source line
  number, dedup keeps the most-recent occurrence's line number.
- CTRL-G in a pane with enough content to scroll: preview opens already
  scrolled near the vertical center of the pane, match line visible and
  reverse-video highlighted, without any manual scrolling.
- Navigate the candidate list: preview jumps to a new position, still
  centered, still highlighting the newly-selected candidate's own line —
  not the previous one.
- Typing a fuzzy query: candidate list still filters correctly (fuzzy
  matching is unaffected by `--with-nth` hiding the line-number field).
- `ctrl-w` mode cycling, `ctrl-y` copy, and Enter-to-insert all still work
  unaffected — none of them read or write the preview or the line-number
  field.
- Header line displays correctly (mode name + keybinding hint), not the
  literal `0` prefix leaking through.
