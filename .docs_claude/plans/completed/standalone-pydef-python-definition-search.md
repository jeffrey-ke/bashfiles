# `pydef`: standalone interactive Python def/class search

## Goal

CLI-reachable, realtime fuzzy search over Python function/class definitions —
fewer keystrokes than opening nvim first, restricted to `*.py` files, and
independent of the user's real nvim config (a `uv run --with`-style ephemeral
tool, not another `~/dotfiles/nvim` feature).

The user already had `:Def [name] [dir]` in `~/dotfiles/nvim/lua/keymaps.lua`
(grep-to-quickfix, jump to first match), but it false-positives on non-Python
files (its glob is an 8-extension *exclude* list, not a `*.py` allowlist) and
isn't reachable without nvim already open.

## Final solution

Two new files, `~/dotfiles/bin/pydef` (launcher) + `~/dotfiles/bin/pydef.lua`
(nvim config), symlinked as `~/.local/bin/pydef -> ~/dotfiles/bin/pydef`
(same pattern as `art`/`run`). Touches nothing under `~/dotfiles/nvim`.

- `pydef.lua` self-bootstraps its own isolated `lazy.nvim` (installs
  `telescope.nvim` + `plenary.nvim` + `telescope-fzf-native.nvim` into
  `stdpath('cache')/pydef-nvim/lazy`, separate from the main config's plugin
  dir) and defines a `:PyDef [name] [dir]` command.
- `pydef` execs `nvim --clean -u pydef.lua -c "PyDef $*"` — `--clean` skips
  the user's real config entirely; the explicit `-u` still loads *this* file
  (confirmed `-u` after `--clean` overrides the "skip config" default).
- The picker is modeled directly on Telescope's own `grep_string` builtin
  (read from the vendored source): one-shot `rg` via `finders.new_oneshot_job`
  restricted to `*.py`, Telescope's prompt does live fuzzy filtering via
  `conf.generic_sorter` (backed by `telescope-fzf-native`, already required).
- Definition pattern: `^\s*(async\s+)?(def|class)\s+\w+\s*[:\(\[]`, with
  `--case-sensitive` — see "Bugs hit along the way".
- `<C-j>`/`<C-k>` mapped to `move_selection_next`/`move_selection_previous`
  (added on request, matches the main config's own telescope mappings).

## What didn't work, and why

### 1. `:PyDef` wired into `~/dotfiles/nvim/keymaps.lua`, jump-to-first-match

First pass reused `:Def`'s exact mechanism (`grep_and_open`: shell `rg
--vimgrep` into the quickfix list, `:cfirst`), just adding a `*.py` glob.

Why dropped: the user wanted a live, interactively-typeable fuzzy filter —
what they'd actually pictured "telescope" doing — not a jump to one match.

### 2. Interactive Telescope picker, still wired into `keymaps.lua`

Second pass built the real interactive picker correctly (same design as what
shipped), but as a command inside the user's actual 800-line, 20+-plugin
config.

Why dropped: the user wants this **independent** of their nvim config's
particulars — asked for a `uv run --with X`-style ephemeral-dependency
analogy for nvim. That analogy is `nvim --clean -u <self-contained-init>`,
which is what shipped.

## Bugs hit along the way (worth remembering)

- **Opening a Telescope picker synchronously from a `-c` startup command
  leaves keyboard focus on the preview window, not the prompt.** Reproduces
  identically against the user's real, already-working config driven the
  same way (`nvim -c "lua require('telescope.builtin').live_grep()"`) — a
  generic Neovim/Telescope startup-timing race (prompt window is normally
  focused last via window-creation order, but that race loses when triggered
  this early), not specific to this picker. Fix: wrap the picker-opening call
  in `vim.schedule(function() ... end)` so it runs on the next event-loop
  tick, after startup settles.
- **A bare `(def|class)\s+` rg pattern matches those words as plain English
  inside docstrings/comments**, not just real Python syntax — e.g. a
  docstring line describing something "in CLASS space" (`vision_core/viz.py`)
  matched because the pattern is unanchored and, worse, `--smart-case`
  (inherited from Telescope's base `vimgrep_arguments`) makes an all-lowercase
  pattern case-*insensitive*, so it matched the uppercase "CLASS" too.
  Anchoring alone isn't enough either — a docstring line like "class methods
  below are used for X" still starts a line with "class ". Fix: require the
  actual definition *shape* — anchored to line-start (after indentation,
  optional `async `), keyword followed by a real identifier then immediately
  `(`, `:`, or `[` (generic class) — plus `--case-sensitive` to override the
  inherited smart-case. Verified against Python's own `ast` parser as ground
  truth across 4 real files: exact match (87/87, 55/55, 10/10, 6/6 def/class
  lines), zero false positives or misses.

## Files touched

- `~/dotfiles/bin/pydef` (new, executable)
- `~/dotfiles/bin/pydef.lua` (new, executable)
- `~/.local/bin/pydef` (new symlink → `~/dotfiles/bin/pydef`)

## Verification

Driven end-to-end through a detached `tmux` session (a floating Telescope
picker can't be verified by piping stdout):
- First run: cold bootstrap (clone + build 3 plugins into the dedicated cache
  dir) completes, picker opens showing only real `.py` def/class lines —
  confirmed zero false positives from sibling `.js`/`.md`/`.lua` decoy files
  in a scratch dir.
- Second run: instant (cache reused), no reinstall.
- Live typing narrows results correctly (2/2 → 1/2 on a query matching one of
  two candidates); `<CR>` jumps to the exact file/line; `<C-j>`/`<C-k>` move
  the selection.
- `pydef Foo` pre-fills the prompt with "Foo" (still editable); `pydef Foo
  <dir>` scopes the search directory.
- Regex fix cross-checked against `ast.parse()` on real `vision_core` source
  files (see "Bugs hit along the way").
- `~/dotfiles/nvim` confirmed untouched (`git status` shows no changes from
  this work).
