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
cmd_preview_context() {
	local raw="$1" needle="$2" n half
	n=$(grep -nFw -- "$needle" "$raw" | tail -1 | cut -d: -f1)
	if [ -z "$n" ]; then
		tail -n "${FZF_PREVIEW_LINES:-20}" "$raw"
		return
	fi
	half=$(( ${FZF_PREVIEW_LINES:-20} / 2 ))
	sed -n "$(( n>half ? n-half : 1 )),$(( n+half ))p" "$raw"
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
- **`$FZF_PREVIEW_LINES`** — fzf exports the actual current preview pane
  height to preview commands (verified: `15` on a 30-row terminal at
  `down,60%`). Halved above/below the match so the window roughly fills
  whatever the pane's actual size is, not a hardcoded guess, and the
  match lands roughly centered.
- **Fallback (match not found — shouldn't happen by construction, since
  every candidate is extracted from `raw` itself, but kept defensive):**
  show the last `$FZF_PREVIEW_LINES` lines — keeps the "most recent"
  bias from the prior sub-project rather than reverting to the top of
  the file.

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
  found): shows the last `$FZF_PREVIEW_LINES` lines rather than erroring.
