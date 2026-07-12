# fgc — fuzzy git commit search

## Context

Same interactive-search shape `fgr`/`pydef` proved (live-narrow, Enter to act), applied
to git history instead of files. The design question was where fuzzy matching should
sit relative to git's own content search:

- **fzf's fuzzy engine only ever scores whatever text you hand it** — it doesn't
  understand diff structure, it just fuzzy-matches lines of input.
- Feeding it raw diff content directly (one candidate per changed line) was measured
  and rejected: a naive scattered-subsequence fuzzy query for a 6-character term
  matched **1,100 unrelated lines** out of 67,543 changed lines in just the
  `segmentation` submodule, against only **2** commits that actually touched the term.
  Diff text is too high-entropy (symbol soup, incidental character runs) for
  typo-tolerant fuzzy matching to stay precise.
- Git's own `-G<regex>` pickaxe, by contrast, is exact/regex — no false positives from
  incidental subsequence matches — and only touches the diff once, up front.

So `fgc` puts the exact matcher on the high-entropy corpus (diff content, via `-G`) and
the fuzzy matcher on the small, human-authored, already-filtered result (the oneline
commit list: hash, ref decorations, subject, relative date). Selecting a line in fzf
prints the commit hash to stdout, so it composes with any downstream command.

## Approach

```bash
fgc() {
	[ -z "$1" ] && { echo "Usage: fgc <pattern>"; return 1; }
	local pattern="$1"
	git log --all -G"$pattern" -i --color=always \
		--format='%C(auto)%h%d %s %C(black)%C(bold)%cr' \
		| fzf --ansi --no-sort --reverse \
			--preview 'git show --color=always {1}' \
		| grep -oE '[a-f0-9]{7,40}' | head -1
}
```

- `-G"$pattern" -i` — regex pickaxe, case-insensitive by default (the sensible day-to-day
  default; `-S` would be the stricter "occurrence count changed" variant if ever needed).
- `--all` — searches every ref, not just the current branch.
- `[ -z "$1" ]` guard — without it, a bare `fgc` passes an empty pattern to `-G`, which
  matches every commit in history.
- **Preview uses fzf's own `{1}` field placeholder**, not a hand-rolled grep — see "What
  didn't work" below for why a regex-in-preview approach broke.
- The **final** hash extraction (after fzf exits, plain bash) uses regex
  `[a-f0-9]{7,40}` to pick the first hex run on the accepted line — always the
  abbreviated hash (`%h` is the first token; verified this holds even when `%d` inserts
  a ref decoration mid-line, e.g. `4090a69 (mlflow-tracking) mlflow-tracking: ...`,
  because git's `%d` supplies its own leading space).

## What didn't work, and why

### `{7,40}` inside `--preview` collides with fzf's own placeholder syntax

First draft resolved the hash for the preview pane the same way as the final
extraction: `--preview 'h=$(echo {} | grep -oE "[a-f0-9]{7,40}" | head -1); git show
--color=always "$h"'`. Interactively this always previewed `fatal: ambiguous argument
''`. Root-caused with `set -x` piped to a file from inside the preview command itself
(a live fzf preview pane can't be inspected any other way): fzf parses **any** `{...}`
occurring in a `--preview` template as its own placeholder syntax — including
`{7,40}`, which looks exactly like fzf's comma-separated multi-field reference
(`{f1,f2,...}`). fzf silently substituted it away before grep ever saw the pattern,
so `h` always resolved empty. This is a general trap, not specific to this regex: any
literal curly braces in a `--preview` string are at risk of being intercepted, so
regex interval quantifiers (`{n,m}`) must never appear directly in a preview command.

Fixed by using fzf's own `{1}` field placeholder instead of a hand-rolled regex —
`%h` is always the first whitespace-delimited token (confirmed via `od -c` probing
that `--ansi` strips color codes from placeholder substitutions), so `{1}` is exactly
the hash, with no regex, no braces, and no collision risk. The **outer** (post-fzf)
hash extraction was left as regex, since that code is plain bash run after fzf exits —
it never passes through fzf's template parser, so `{7,40}` there is safe.

## Files

- `~ .functions.sh` — appended `fgc()`, end of file after `gpu2()`

## Verification

- `source ~/.functions.sh && type fgc` — loads with no syntax errors.
- Non-interactive pipeline dry run against `refseg-workspace`'s real `mlflow` history
  (`git log --all -G'mlflow' -i --color=always --format=... | head -1 | grep -oE
  '[a-f0-9]{7,40}'`) → `cb0d703`; `git show --stat -s cb0d703` resolves correctly.
- Interactive end-to-end check via a detached `tmux` pane (a live fzf TUI can't be
  verified through plain piped stdout, and this is exactly what caught the `{7,40}`
  bug above): ran `fgc mlflow`, confirmed both candidates render, confirmed the
  `git show` preview renders a real diff (not the `fatal: ambiguous argument` error
  the first draft produced), pressed `Down` + `Enter` to select the second candidate,
  and confirmed the pane exits with exactly `4090a69` on stdout — the correct hash for
  that commit.
- Confirmed piping composes: the captured stdout from the tmux run was consumed
  directly (`git show --stat -s <hash>`) and matched the previewed commit.
