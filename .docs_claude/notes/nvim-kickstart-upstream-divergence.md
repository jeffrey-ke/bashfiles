# nvim: our kickstart fork and upstream have diverged past merging

## The short version

`nvim/` is a fork of `nvim-lua/kickstart.nvim` at **`3338d39` (2025-05-22)**, which
is a lazy.nvim-based config. Upstream has since **replaced lazy.nvim with
`vim.pack`**, nvim 0.12's built-in plugin manager. Checked at upstream `626c660`
(2026-08-07): **zero** lazy.nvim references in `init.lua`, **15** `vim.pack.add`
calls, nvim-treesitter pinned `version = 'main'`, and `lazy-lock.json` replaced by
`nvim-pack-lock.json`.

So "pull from upstream" is no longer a merge. Don't reach for it as a fix.

## Why that matters for this repo specifically

Everything custom here is written against lazy's declarative spec:

- all nine files in `nvim/lua/custom/plugins/` use `keys` / `ft` / `event` /
  `enabled` / `opts`
- `myvimtex` is loaded as a lazy **`dir`** plugin whose specs are all `ft = 'tex'`,
  which is what keeps the LaTeX layer out of coding sessions
- `nvim/lazy-lock.json` is tracked deliberately (the `.gitignore` line was removed)

`vim.pack` has no equivalent for any of that. Adopting it means reauthoring the
custom specs and re-deriving the myvimtex arrangement.

## The treesitter corner of the same problem

nvim-treesitter's default branch moved from `master` to `main`, and `main` is a
rewrite with no `nvim-treesitter.configs` module. Our spec now pins
`branch = 'master'` (`init.lua:1235`) to stop `:Lazy update` resolving the target
from `remotes/origin/HEAD` and stepping onto it.

That pin is a holding action, not a fix: master's README states **"Neovim 0.10 or
0.11 (Neovim 0.12 is not supported)"** and this machine runs 0.12.4. It works today
— verified: highlighter attaches, 12 parsers built, `configs` module loads,
captures resolve — but receives no further parser updates.

## Three avenues, ascending cost

1. **Stay pinned on lazy + treesitter master.** Zero work, works today. Diverges
   further every month; no parser updates.
2. **Migrate treesitter to `main`, stay on lazy.** Rewrite one spec block:
   `ensure_installed` → `require('nvim-treesitter').install()`, highlighting → a
   `FileType` autocmd calling `vim.treesitter.start()`. VimTeX's
   `highlight.disable = { 'latex' }` has no equivalent and becomes "don't call
   `vim.treesitter.start()` for tex" — same outcome, different mechanism. The fold
   `foldexpr` and the `:Make`/`gD` paths are unaffected; they use core
   `vim.treesitter`, not the plugin.
3. **Rebase onto upstream's `vim.pack` kickstart.** Resolves everything, costs the
   most: new plugin manager, all custom specs reauthored, myvimtex re-derived.

Nothing is broken, so none of it is urgent. (2) is the real next step; the reason
not to invest much in it is that (3) becoming attractive would throw it away.

## How to re-check this cheaply

```bash
cd /tmp && git clone -q --no-hardlinks ~/dotfiles/nvim nvimcmp && cd nvimcmp
git remote add upstream https://github.com/nvim-lua/kickstart.nvim.git
git fetch -q upstream
git merge-base HEAD upstream/master          # our fork point
git show upstream/master:init.lua | grep -c vim.pack.add
```

Related: [nvim-cterm-highlight-layer-removal.md](../plans/completed/nvim-cterm-highlight-layer-removal.md).
