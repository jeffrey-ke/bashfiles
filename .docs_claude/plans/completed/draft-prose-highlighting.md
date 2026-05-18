# Draft prose highlighting in nvim

## Goal

Make free-form design notes / draft prose embedded in code pop visually so it
doesn't blend in with real code. The user keeps these inline while iterating
on a design.

## Final solution

Backtick-delimited regions with a background-only tint via `matchadd`.

- Open with `` ` ``, close with `` ` `` or end of line.
- Two `matchadd` patterns (one closed, one to-EOL); priority 200 beats treesitter (100).
- Highlight group `DraftProse` sets only the background — foreground stays
  normal so text doesn't read as a comment.
- Applied via `BufWinEnter` / `WinNew` autocmd plus a startup loop that walks
  `nvim_list_wins()` so already-open windows get the match when the config first
  loads.

Code lives in `~/dotfiles/nvim/init.lua` near the other `nvim_set_hl` calls
(search for `DraftProse`).

## What didn't work, and why

### 1. LSP-driven highlight (`DiagnosticUnderlineError` with `bg`)

Plan: override `DiagnosticUnderlineError` to add a background. Spans flagged
by pyright (e.g. unparseable draft prose) would pop.

Why dropped: user didn't want to require an LSP.

### 2. Treesitter `(ERROR)` query

Plan: `after/queries/python/highlights.scm` with `(ERROR) @draft.prose` linked
to a loud highlight group.

Why it failed:
- Treesitter parses optimistically. Tokens inside an ERROR subtree still get
  captured as `@variable.python` / `@type.python` at priority 100. The parent
  ERROR capture is *one layer up* and loses to child captures in tree-sitter's
  per-byte highlight resolution.
- Bumping the parent capture to priority 200 didn't fix it for the user's
  actual draft (`gligen.py:354`, `:364-367`) — the parser had recovered enough
  that no ERROR node covered the cursor at all. `:Inspect` showed only
  `@variable.python` and `@type.python`, no `@draft.prose`.

### 3. Lua extmark walk over ERROR/MISSING nodes

Plan: walk the treesitter tree on `BufEnter`/`TextChanged`, find every
`ERROR`/`MISSING` node, paint its byte range via `vim.hl.range` with an
extmark at priority 200.

Why it failed: same root cause as (2). The parser recovered cleanly across
the user's draft lines and produced no ERROR/MISSING nodes anywhere covering
the prose. Without a node to find, the walker has nothing to mark.

### 4. Comment-prefix sentinel (`#!! draft prose`)

Plan: `matchadd` over `^\s*\(#\|--\|//\)!!.*$` so any line starting with
`<comment-marker>!!` is tinted.

Why dropped: user didn't want to require comment prefixes — they wanted bare
inline drafts.

## Bugs hit along the way (worth remembering)

- **`\n` inside a Vim regex character class does not mean newline.** It means
  `\` and the letter `n`. So `[^`\n]*` excluded the letter 'n' from matches,
  which broke any line containing "n" (e.g. "how many"). Fix: use `[^`]`;
  Vim character classes don't match newlines by default anyway.
- **`matchadd` is per-window.** A pure `BufWinEnter` autocmd misses windows
  already open at config-load time. Walk `nvim_list_wins()` once at startup
  with `nvim_win_call` to backfill.
- **`guibg` is ignored without `termguicolors`.** The user's terminal runs in
  cterm mode (see other highlights in their `init.lua` using `ctermbg`).
  Final highlight sets both `bg = '#4a2a3a'` and `ctermbg = 53` so it works
  in either mode.
- **`:call getmatches()` prints nothing** because `:call` discards the return
  value. Always `:echo getmatches()` when debugging matches.
- **The `\(`\|$\)` alternation in `matchadd` was finicky** in practice.
  Splitting into two patterns (`` `[^`]*` `` and `` `[^`]*$ ``) is clearer
  and works reliably.

## Files touched

- `~/dotfiles/nvim/init.lua` — added `DraftProse` highlight + `matchadd`
  autocmd + startup window loop.

## Files created and removed during exploration

- `~/dotfiles/nvim/after/queries/python/highlights.scm` (treesitter approach,
  deleted).
