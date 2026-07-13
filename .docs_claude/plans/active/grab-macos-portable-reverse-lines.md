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
