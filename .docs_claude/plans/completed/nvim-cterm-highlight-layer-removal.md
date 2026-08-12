# Delete nvim's cterm-only highlight layer; let the colorscheme own every group

**Status:** Shipped 2026-08-11 on the `nvim` submodule (`strip-ui-additions` →
`master`, commits `79e633b`, `9176ea8`, `cfbe356`).

## Context

The user asked for an inventory of every visual/TUI change layered on top of
kickstart, intending to revert their additions and keep their removals. Baseline
is upstream kickstart `3338d39` (2025-05-22), the fork point; since then
`init.lua` was +705/−102 plus 9 new files.

Investigating that inventory turned up the real finding: **the entire custom
highlight layer was inert, and actively erasing the colorscheme.** All 16 groups
were declared `ctermfg`/`ctermbg`-only, which `termguicolors = true` ignores.
And `nvim_set_hl` *replaces* a group rather than merging, so each one wiped a
definition seoul256 ships. Dumped from the live config:

```
CursorLine    gui[] cterm[ctermbg=7]           <-- NO GUI COLOR
LineNr        gui[] cterm[ctermfg=14]          <-- NO GUI COLOR
DiffAdd       gui[] cterm[ctermfg=8 ctermbg=2] <-- NO GUI COLOR
WinSeparator  gui[] cterm[ctermfg=10]          <-- NO GUI COLOR
StatusLinePwd gui[] cterm[ctermfg=6]           <-- NO GUI COLOR
```

With the overrides removed, seoul256 defines all of them properly
(`CursorLine bg=#f1f1f1`, `LineNr fg=#999872 bg=#e9e9e9`,
`CursorLineNr fg=#be7572 bold`, `DiffAdd bg=#bcddbd`, `DiffChange bg=#dfdfff`,
`WinSeparator fg=#616161`). So fugitive diffs and `:diffthis` were rendering
uncolored. Only the `bold` flags survived, which is why it read as flat rather
than obviously broken.

This was coherent history, not carelessness. The layer was correct for the
*previous* design — solarized with `termguicolors = false` and
`solarized_termcolors = 16`, deliberately resolving highlights to the terminal's
own palette slots so nvim tracked the terminal theme (the same idea as
`.tmux.conf`'s `fg=terminal,bg=terminal`). Commit `ffbe480` switched to
true-color seoul256 and converted exactly two groups, `TabLineSel` and
`TabLineModified` — its comment states the reason correctly — leaving the other
16 behind.

Five colorschemes in this file's lifetime: tokyonight → gruvbox → `colo vim` →
solarized ANSI-16 → seoul256.

## What was removed from upstream kickstart (kept, per the user's ask)

Only **tokyonight** was deleted outright. gruvbox and vim-colors-solarized were
the user's own additions, added and later dropped. Also removed: `section_fileinfo`
from the statusline, blink.cmp's cmdline completion (native wildmenu instead),
`undofile`, treesitter highlighting for `latex` (VimTeX's conceal needs it off),
and the `lazy-lock.json` line from `.gitignore`. Nothing else from upstream is
gone; the six commented `kickstart.plugins.*` requires are commented upstream too.

## Changes

### 1. Delete the layer (`79e633b`, −248 lines)

Gone: `set_ansi_ui_hl` + its `ColorScheme` autocmd (10 groups), the `StatusLine*`
group definitions, the whole `DraftProse` block (`:ToggleProse`, `<leader>tp`),
and the `vim.on_key` leader flash that reddened `WinSeparator` while a `<leader>`
sequence was pending.

Kept, because they are structure rather than color: the buffer tabline, the
mini.statusline section layout (mode / git / diagnostics / cwd / line:col /
relative path), `laststatus=3`, `:ToggleBackground`. The statusline now colors
only the mode section via mini's own `MiniStatuslineMode*` groups and resets to
`StatusLine` after it.

Rejected alternative: port the 16 groups to gui hex. It re-earns the same bug the
next time the colorscheme changes, and the history says that happens.

Two fixes fell out:

- `<leader>tp` was bound twice. ToggleProse won because it was set *after*
  `lazy.setup()`, so toggleterm's `Terminal (tab)` never fired. Confirmed with
  `verbose nmap`; it now resolves to toggleterm.
- Snacks transparency moved into a `ColorScheme` autocmd. As a bare call it was
  wiped by the first `:ToggleBackground` — the exact trap
  `nvim/.docs_claude/plans/completed/statusline-colors.md` documents.

`custom_foldtext` (~50 lines walking the highlights query to emit `{text, group}`
chunks) became `vim.opt.foldtext = ''`. That is nvim's native equivalent since
**0.10**: "foldtext is disabled, and the line is displayed normally with
highlighting and no line wrapping" (`:help 'foldtext'`). Note the old comment
blamed a missing `vim.treesitter.foldtext` — that function does not exist in
0.12.4 either, so the option was always the right answer. Also moved
`wrap`/`linebreak` up to the options section; they sat *below* the modeline
comment, 2 lines from silently pushing `ts=2` out of the 5-line `modelines`
window.

### 2. Pin nvim-treesitter to `master` (`9176ea8`)

The spec pinned no branch, so lazy resolved the update target from
`remotes/origin/HEAD` (`manage/git.lua:89`). nvim-treesitter's default branch is
now `main`, a ground-up rewrite with no `nvim-treesitter.configs` module. In this
clone `origin/HEAD` → `origin/main` @ `c9f9ed6c` while `origin/master` is
`cf12346a`, which is where we are: **`:Lazy update` would have jumped to the
rewrite** and broken the `main = 'nvim-treesitter.configs'` + `opts` block.

`:Lazy restore` was never the risk. Restore checks out the lockfile's *commit*
(`manage/task/git.lua:359`); the lock's `branch` field is read in exactly one
place, the "already at target, skip" test at `task/git.lua:340`, so a stale
`"branch": "main"` only defeats that skip and causes a redundant checkout to the
commit you already have. Fresh installs are safe for the same reason — the
auto-install path passes the lock explicitly (`core/loader.lua:84`).

This is a **holding action**. master's README says "Neovim 0.10 or 0.11 (Neovim
0.12 is not supported)" and this machine runs 0.12.4. See
[nvim-kickstart-upstream-divergence.md](../../notes/nvim-kickstart-upstream-divergence.md)
for why the two real resolutions are both large.

### 3. `zf`/`zF` no longer throw E490 (`cfbe356`)

`zf` ran `normal! za` unconditionally after trying to jump to the enclosing
function. With no enclosing function the jump is skipped and `za` runs on a line
with no fold → `E490`, surfaced as an E5108 Lua traceback at `keymaps.lua:57`.
Reproduced on any top-level line. `zF` had the same hole at its `zO`.

Both now share a helper that checks `foldlevel` at the cursor and notifies
instead of throwing. The guard is on the *fold*, not on the node being nil: with
the cursor in a class body but outside any method there is no function to jump
to, yet the enclosing class fold is a fine target and `za` should still toggle it.

## Verification

nvim 0.12.4. Every previously-blanked group resolves to seoul256's gui colors;
statusline renders (` N  <cwd>  1:1  file `), tabline renders, folds close with
highlighted text, `<leader>tp` → `Terminal (tab)`, no dangling references to any
deleted group or function, 0 lazy spec errors. `Git.get_branch` and `get_target`
both resolve to `master @ cf12346a` = current checkout, so `:Lazy update` is now
a no-op for treesitter instead of a jump. Fold keys: lines 1/5/11 print "No fold
here" with `v:errmsg` empty; line 26 closes the fold at 25; line 21 closes the
enclosing class at 20.

No `:Lazy` command is needed to pick any of this up — 36 plugins in the spec,
none missing, no clean candidates. Just restart nvim.

## Not done

- Nothing was folded on open and still isn't: `foldlevelstart = 99` opens every
  fold. `foldlevelstart = 2` would open files with methods collapsed. Left alone
  as a preference, not a fix.
- `TabLineModified` is referenced by the tabline function but defined nowhere, so
  `[+]` renders as plain text. Giving it a real gui color is a taste call.
- `E108: No such variable: "s:style"` appears in `:messages` from seoul256's own
  `silent! unlet` (`colors/seoul256.vim:142`). Pre-existing, cosmetic, upstream.
- The treesitter migration and the upstream-divergence question are both open;
  see the note linked above.
