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
`branch = 'master'` (`init.lua:1433`) to stop `:Lazy update` resolving the target
from `remotes/origin/HEAD` and stepping onto it.

That pin is a holding action, not a fix: master's README states **"Neovim 0.10 or
0.11 (Neovim 0.12 is not supported)"** and this machine runs 0.12.4. Highlighting,
parser builds, and the `configs` module all still work, but the version gap has
started to bite in one concrete place, below — and master receives no further
parser updates.

### The `all = false` breakage (2026-08-14)

Opening any markdown file containing a fenced code block with a language
(` ```vim `) produced, once per reparse — so from render-markdown, the
highlighter, and `foldexpr` in turn:

```
vim/treesitter.lua:197: attempt to call method 'range' (a nil value)
  ... get_node_text
  ... nvim-treesitter/query_predicates.lua:141: in function 'handler'
```

`query_predicates.lua:19` registers all six of master's predicates/directives with
`{ force = true, all = false }`. Through 0.11 that asked core for a wrapper handing
the handler one `TSNode` per capture; **0.12 deleted the wrapper** — `add_predicate`
/ `add_directive` now take only `force` — so `all` is silently ignored and handlers
get core's native `table<integer, TSNode[]>`. They index it as a node, hence the
`nil` `:range`. Line 141 is `#set-lang-from-info-string!`, which the plugin's
`queries/markdown/injections.scm` uses in place of the runtime query's plain
`@injection.language` capture. `bash`, `html_tags`, `hcl`, `ruby`, and `php_only`
reach `#downcase!` / `#nth?` the same way.

Fixed in-config rather than by patching the plugin: `nvim/lua/custom/ts_predicate_compat.lua`
wraps `add_predicate`/`add_directive` so an `all = false` caller gets its captures
unwrapped, restoring exactly what core removed. It is installed from the
treesitter spec's `init` (before `query_predicates` registers anything) and no-ops
below 0.12. **Delete it when avenue (2) below lands** — `main` has no such
handlers. Verified: markdown, bash, and html buffers parse clean, and injections
resolve correctly through the repaired directive (```` ```VIM ```` → `vim`,
```` ```sh ```` → `bash`).

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

(2) is the real next step; the reason not to invest much in it is that (3) becoming
attractive would throw it away. It is no longer purely optional, though — the
`all = false` breakage above is the first 0.12 incompatibility to reach a daily
filetype, and it is patched in our config rather than upstream, so expect more of
the same shape as 0.12 sheds further deprecated shims.

## How to re-check this cheaply

```bash
cd /tmp && git clone -q --no-hardlinks ~/dotfiles/nvim nvimcmp && cd nvimcmp
git remote add upstream https://github.com/nvim-lua/kickstart.nvim.git
git fetch -q upstream
git merge-base HEAD upstream/master          # our fork point
git show upstream/master:init.lua | grep -c vim.pack.add
```

Related: [nvim-cterm-highlight-layer-removal.md](../plans/completed/nvim-cterm-highlight-layer-removal.md).
