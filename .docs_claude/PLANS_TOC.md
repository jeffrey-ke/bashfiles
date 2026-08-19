# Plans Table of Contents

Topic-organized + chronological index of plan docs in this repo (currently all under
`.docs_claude/plans/{active,completed}/`; one legacy entry predates that convention and
still lives at top-level `plans/completed/`). Two views: a **chronological index**
(most recent first) and **topic sections**, each plan carrying a prose abstract + a
"Key changes" list of the salient files/functions it created(+)/modified(~)/deleted(-).

## Maintaining this file

When a plan is added, copied, moved, renamed, or deleted:

1. Find it: `find . -path '*/.docs_claude/plans/*' -name '*.md'` (new plans go here;
   `plans/completed/*.md` at the repo root is legacy, don't add new ones there).
2. Read its title + summary to judge purpose and which area it touches.
3. Add an entry — a `###` link, a code-location line, a 2-4 sentence prose **abstract**,
   then a **"Key changes"** list — under every matching topic. A plan MUST appear under
   at least one topic; it MAY appear under several. If it fits no existing topic, add a
   new `## Topic` section.
4. On move/rename/delete, update or remove the existing entry/entries.
5. Also add it to the **Chronological index**, most-recent first — date = git creation
   date: `git log --diff-filter=A --follow --format=%as -- <path> | tail -1` (an
   uncommitted plan uses today's date).

### Topics

1. Nvim: Editing, Git & Highlighting · 2. Nvim: Standalone Search Tools ·
3. Tmux: Popups & Notifications · 4. Shell: Navigation & Machine Config ·
5. Shell: Tooling & Bootstrap · 6. Shell: Git Helpers ·
7. Claude Code Integration

---

## Chronological index

- **2026-08-19** — [dir-aliases-every-nav-entry-point.md](plans/completed/dir-aliases-every-nav-entry-point.md) `.bash_tools`
- **2026-08-18** — [tmux-prefix-x-fork-claude-conversation.md](plans/completed/tmux-prefix-x-fork-claude-conversation.md) `.tmux.conf`, `tmux-fork-claude.sh`, `claude-skills/fork-conversation-pane/`
- **2026-08-11** — [nvim-cterm-highlight-layer-removal.md](plans/completed/nvim-cterm-highlight-layer-removal.md) `nvim/init.lua`, `nvim/lua/keymaps.lua`
- **2026-08-11** — [macos-login-shell-and-machine-config-dedup.md](plans/completed/macos-login-shell-and-machine-config-dedup.md) `run.sh`, `.bash_tools`, `machines/`
- **2026-07-15** — [fzf-ctrl-t-directory-navigation.md](plans/completed/fzf-ctrl-t-directory-navigation.md) `.bash_tools`
- **2026-07-15** — [fvim-alias-function-collision-fix.md](plans/completed/fvim-alias-function-collision-fix.md) `machines/tesu.sh`
- **2026-07-15** — [grep2qf-grep-to-quickfix.md](plans/completed/grep2qf-grep-to-quickfix.md) `bin/grep2qf`
- **2026-07-13** — [grab-macos-install-bootstrap.md](plans/completed/grab-macos-install-bootstrap.md) `run.sh`, `install-tools.sh`
- **2026-07-13** — [grab-preview-follow-match.md](plans/completed/grab-preview-follow-match.md) `bin/grab`
- **2026-07-13** — [grab-preview-follow-scroll.md](plans/completed/grab-preview-follow-scroll.md) `bin/grab`
- **2026-07-13** — [grab-preview-window.md](plans/completed/grab-preview-window.md) `bin/grab`
- **2026-07-13** — [grab-screen-word-completion.md](plans/completed/grab-screen-word-completion.md) `bin/grab`, `.bash_tools`
- **2026-07-12** — [render-markdown-code-block-background.md](plans/completed/render-markdown-code-block-background.md) `nvim/lua/custom/plugins/markdown.lua`
- **2026-07-12** — [ugq-query-tui-quickfix.md](plans/completed/ugq-query-tui-quickfix.md) `.functions.sh`
- **2026-07-12** — [fgc-fuzzy-git-commit-search.md](plans/completed/fgc-fuzzy-git-commit-search.md) `.functions.sh`
- **2026-07-11** — [tmux-prefix-e-claude-explain.md](plans/completed/tmux-prefix-e-claude-explain.md) `.tmux.conf`, `tmux-claude-explain.sh`
- **2026-07-10** — [yazi-zoxide-db-integration.md](plans/completed/yazi-zoxide-db-integration.md) `yazi/`, `run.sh`
- **2026-07-10** — [fgr-fuzzy-grep-live-args.md](plans/completed/fgr-fuzzy-grep-live-args.md) `bin/`
- **2026-07-10** — [fgr-fuzzy-grep-live-args-plan.md](plans/completed/fgr-fuzzy-grep-live-args-plan.md) `bin/`
- **2026-07-09** — [standalone-pydef-python-definition-search.md](plans/completed/standalone-pydef-python-definition-search.md) `bin/`
- **2026-07-07** — [cli-tools-bootstrap.md](plans/completed/cli-tools-bootstrap.md) `shell tooling`
- **2026-06-25** — [2026-06-25-regex-hostname-shadowing-fix.md](../plans/completed/2026-06-25-regex-hostname-shadowing-fix.md) `source-machine.sh`
- **2026-06-20** — [ghostty-osc-notifications-ssh-tmux.md](plans/completed/ghostty-osc-notifications-ssh-tmux.md) `.functions.sh`
- **2026-06-17** — [machine-specific-path-registry.md](plans/completed/machine-specific-path-registry.md) `.functions.sh`
- **2026-06-15** — [stage-commit-partial-hunk-fix.md](plans/completed/stage-commit-partial-hunk-fix.md) `nvim/lua/custom`
- **2026-05-18** — [draft-prose-highlighting.md](plans/completed/draft-prose-highlighting.md) `nvim/init.lua`
- **2026-05-17** — [tmux-popup-window.md](plans/completed/tmux-popup-window.md) `.tmux.conf`

---

## 1. Nvim: Editing, Git & Highlighting

### [nvim-cterm-highlight-layer-removal.md](plans/completed/nvim-cterm-highlight-layer-removal.md)
`~/dotfiles/nvim/init.lua`, `nvim/lua/keymaps.lua` · 2026-08-11
> An inventory of every visual/TUI change layered on kickstart (fork point `3338d39`,
> 2025-05-22) turned up that the whole custom highlight layer was inert *and* destructive:
> all 16 groups were declared `ctermfg`/`ctermbg`-only, which `termguicolors = true`
> ignores, and since `nvim_set_hl` replaces rather than merges, each one erased a
> definition seoul256 ships — fugitive diffs and `:diffthis` were rendering uncolored.
> The layer was correct for the *previous* design (solarized in ANSI-16 passthrough with
> `termguicolors = false`); `ffbe480` flipped to true-color seoul256 and converted only
> `TabLineSel`/`TabLineModified`. Deleting it is cheaper and more durable than porting 16
> groups to hex, given five colorschemes in this file's lifetime. Structure was kept
> (buffer tabline, statusline section layout, `laststatus=3`, `:ToggleBackground`); only
> color was dropped. Also pins nvim-treesitter to `branch = 'master'`, since its default
> branch is now the `main` rewrite and `:Lazy update` would have stepped onto it.
>
> **Key changes:**
> - `- set_ansi_ui_hl() + ColorScheme autocmd` — `~/dotfiles/nvim/init.lua` — 10 cterm-only UI groups
> - `- StatusLine{File,Git,Loc,Pwd,NC}` — `~/dotfiles/nvim/init.lua` — statusline now colors only the mode section
> - `- DraftProse block` — `~/dotfiles/nvim/init.lua` — `:ToggleProse`, `<leader>tp`; frees `<leader>tp` for toggleterm, which it had shadowed
> - `- leader WinSeparator flash` — `~/dotfiles/nvim/init.lua` — `vim.on_key` namespace `leader-winsep-flash`
> - `- custom_foldtext()` — `~/dotfiles/nvim/init.lua` — ~50 lines → `vim.opt.foldtext = ''`, native since nvim 0.10
> - `~ set_snacks_transparent()` — `~/dotfiles/nvim/init.lua` — moved into a `ColorScheme` autocmd so `:ToggleBackground` can't wipe it
> - `+ set_tabline_modified()` — `~/dotfiles/nvim/init.lua` — `[+]` badge was referenced but undefined; now inverts each cell's own fg/bg (`TabLineModified` / `TabLineSelModified`) so it reads on both the grey and teal cells with no hardcoded color
> - `~ nvim-treesitter spec` — `~/dotfiles/nvim/init.lua` — `branch = 'master'`; holding action, see the divergence note
> - `~ fold_at_enclosing_function()` — `~/dotfiles/nvim/lua/keymaps.lua` — `zf`/`zF` guard `foldlevel` instead of throwing `E490`

### [render-markdown-code-block-background.md](plans/completed/render-markdown-code-block-background.md)
`~/dotfiles/nvim/lua/custom/plugins/markdown.lua` · 2026-07-12 · **premise superseded 2026-08-11** (fix still ships)
> Fenced code blocks rendered as hard-to-read grey boxes after the Solarized ANSI-16
> passthrough switch. Root cause: render-markdown links its code fill `RenderMarkdownCode`
> → `ColorColumn` → Solarized `base02`, which in cterm-only mode is just the canonical
> subtle-highlight tone one step off the background — and ANSI-16 exposes no
> higher-contrast "block" slot, so a distinct *and* readable tinted block is impossible
> without truecolor. Fix drops the fill entirely (`code.disable_background = true`) so code
> sits on the normal background with full syntax contrast, keeping the language label +
> border; inline `` `code` `` keeps its tint. Matches the passthrough plan's "let Solarized
> cover it" philosophy; a plugin `opts` change, so it survives colorscheme reloads with no
> highlight bookkeeping.
>
> **Key changes:**
> - `~ lua/custom/plugins/markdown.lua` — `~/dotfiles/nvim/` — bare spec gains `opts = { code = { disable_background = true } }` (default was `{ 'diff' }`)

### [draft-prose-highlighting.md](plans/completed/draft-prose-highlighting.md)
`~/dotfiles/nvim/init.lua` · 2026-05-18 · **SUPERSEDED 2026-08-11 — feature deleted**; the four failed-approach investigations and the Vim-regex/`matchadd` gotchas are still the value here
> Backtick-delimited draft-prose regions get a background-only tint via `matchadd`, so
> free-form design notes iterated on inline with real code don't blend in. Landed after
> three other approaches failed (LSP diagnostic override, treesitter `ERROR`-node query,
> Lua extmark walk) — treesitter parses optimistically and recovers past the draft text,
> so no `ERROR`/`MISSING` node ever covers it.
>
> **Key changes:**
> - `~ DraftProse highlight + matchadd autocmd` — `~/dotfiles/nvim/init.lua`
> - `- after/queries/python/highlights.scm` — treesitter approach, deleted during exploration

### [stage-commit-partial-hunk-fix.md](plans/completed/stage-commit-partial-hunk-fix.md)
`~/dotfiles/nvim/lua/custom/stage_commit.lua` · 2026-06-15
> Fixes `:St!` (partial-hunk stage+commit) silently committing the *whole file* instead
> of just the staged hunk. Root cause: `git commit -- <path>` doesn't filter what gets
> committed — it auto-stages the working-tree version of `<path>` first, overwriting
> gitsigns' partial staging.
>
> **Key changes:**
> - `~ on_write()` — `~/dotfiles/nvim/lua/custom/stage_commit.lua` — drops `-- <restrict_path>` from the `git commit` args

## 2. Nvim: Standalone Search Tools

### [standalone-pydef-python-definition-search.md](plans/completed/standalone-pydef-python-definition-search.md)
`~/dotfiles/bin/` · 2026-07-09
> `pydef`: a CLI-reachable, realtime fuzzy search over Python function/class
> definitions, restricted to `*.py` files, fully independent of the user's real nvim
> config — `nvim --clean -u pydef.lua` self-bootstraps its own isolated Telescope
> install (a `uv run --with`-style ephemeral tool). The picker mirrors Telescope's own
> `grep_string` builtin (one-shot rg + live fuzzy sorter). Two earlier designs were
> rejected (quickfix jump-to-first-match; wiring into the user's real `keymaps.lua`)
> before landing on the standalone shape. Found and fixed two bugs during verification:
> a generic Telescope startup-timing focus race (fixed with `vim.schedule`), and a
> definition-pattern false-positive on docstring/comment prose (fixed by requiring real
> definition syntax, cross-checked against Python's own `ast` parser).
>
> **Key changes:**
> - `+ bin/pydef` — launcher: `nvim --clean -u pydef.lua -c "PyDef $*"`
> - `+ bin/pydef.lua` — self-bootstrapping lazy.nvim + Telescope `:PyDef` picker

### [fgr-fuzzy-grep-live-args.md](plans/completed/fgr-fuzzy-grep-live-args.md)
`~/dotfiles/bin/` · 2026-07-10
> `fgr`: a pydef-sibling standalone live-grep tool — `nvim --clean -u fgr.lua` opens a
> `telescope-live-grep-args.nvim` picker with `--hidden` on by default, live-typed
> exclusion globs (`"pattern" --iglob !*.md`), a freeze-then-fuzzy-narrow step
> (`<C-Space>`), and quickfix skim/resume (`<C-q>` / `<C-f>`). pydef's lazy.nvim +
> Telescope bootstrap was extracted into a shared `telescope_boot.lua` module (per-tool
> isolated cache dir) so both tools reuse it without pydef's own cache ever
> re-bootstrapping. Also ships `~/.ugrep` so the standalone `ug` binary gets the same
> ignore-binary/hidden/gitignore defaults without remembering flags. Two mapping
> choices from the plan draft turned out wrong once checked against the installed
> source — `<C-i>` collides with `<Tab>` (same terminal keycode; rebound to `<M-i>`),
> and `telescope-live-grep-args`'s own `actions` module doesn't re-export
> `to_fuzzy_refine` despite its README (used telescope core's instead) — and a genuine
> auto-quoting gap where live-grep-args only splits typed flags out of an unquoted
> prompt, fixed by auto-quoting the seeded search term.
>
> **Key changes:**
> - `+ ugrep-config` (`~/.ugrep` symlink) — `ignore-binary`, `ignore-files`, `hidden`, `exclude-dir=.git`, `sort`
> - `+ bin/telescope_boot.lua` — `setup{cache_name, extra_plugin_specs}`, extracted from pydef.lua
> - `~ bin/pydef.lua` — refactored onto `telescope_boot`, behavior unchanged
> - `+ bin/fgr` — launcher: `nvim --clean -u fgr.lua -c "FGrep $*"`
> - `+ bin/fgr.lua` — `:FGrep` live-grep-args picker + `<C-f>` resume mapping

### [fgr-fuzzy-grep-live-args-plan.md](plans/completed/fgr-fuzzy-grep-live-args-plan.md)
`~/dotfiles/bin/` · 2026-07-10
> The approved plan behind `fgr`, kept for its tool-research synthesis: four parallel
> web agents compared interactive grep TUIs (ugrep -Q/-Z, television, broot), fzf+rg
> harness patterns (no polished standalone wrapper exists; everyone adapts fzf's
> ADVANCED.md rfv script), nvim pickers (telescope-live-grep-args vs fzf-lua vs
> snacks vs mini.pick), and approximate matching (only ugrep -Z fuzzy-matches the
> pattern against content; fzf-style fuzziness merely filters fetched result lines).
> Also records the empirically-found ugrep gotchas: dir args searched depth-1 without
> `-r`, `-I` needed to stop `-Z` matching random binary bytes, `--ignore-files` not
> default, `-Z` case-sensitive with the first char anchored. Outcome doc:
> [fgr-fuzzy-grep-live-args.md](plans/completed/fgr-fuzzy-grep-live-args.md).
>
> **Key changes:** same file set as the outcome doc above (plan, not code).

### [ugq-query-tui-quickfix.md](plans/completed/ugq-query-tui-quickfix.md)
`.functions.sh` · 2026-07-12
> `ugq`: the `ug -Q -Z` alias's live TUI (type pattern, live fuzzy results) wrapped so
> lines picked in ugrep's native selection mode (`Enter` → toggle lines / `A` all →
> `Ctrl-Q`) land in an nvim quickfix list with accurate line:col jumps — closing the
> alias's one gap, CTRL-Y only ever opening the *file* (ugrep's `--view` is never given
> a line number). Bare `ugq` drops straight into the TUI like bare `ug`. Built on
> facts verified in ugrep v5.0.0's source: the TUI draws on `/dev/tty`
> (screen.cpp:272) so `$(...)` cleanly captures just the Ctrl-Q selection output; with
> `-Q` a seeded pattern needs `-e`; `-H --no-heading --no-initial-tab` forces rows to
> `file:line:col:text` (nvim's default errorformat); and `-Q` forces `--color=always`
> even into a pipe, so a shell-side sed strips the SGR codes. Two earlier fzf-based
> iterations were discarded (no live TUI, broken preview — see the doc's
> what-didn't-work section); raw-pty scripting of `-Q` fails on ugrep's
> cursor-position probe, so verification is tmux-driven.
>
> **Key changes:**
> - `~ .functions.sh` — `ugq()` rewritten: `ug -Q -Z -n -k -H --no-heading --no-initial-tab [-e PAT]` → sed SGR-strip → `nvim -q <(...) -c cwindow`
> - no-selection fallback: quitting a *seeded* `ugq PAT` without selecting batch re-runs PAT and quickfixes ALL matches (live-typed patterns aren't recoverable — TUI history is in-memory only)

### [grep2qf-grep-to-quickfix.md](plans/completed/grep2qf-grep-to-quickfix.md)
`~/dotfiles/bin/grep2qf` · 2026-07-15
> `grep2qf`: filter that patches the filename back into bare `grep -n` output
> (omitted when searching a single file) so it becomes `file:line:text`,
> nvim's default quickfix errorformat, for `grep -n ... | grep2qf <file> |
> nvim -q /dev/stdin`. Lines already shaped `file:line:text` (multi-file/`-r`
> grep) pass through unchanged; junk (blank lines, non-matching prose) is
> dropped. Investigated afterward whether grep/rg already do this: ripgrep's
> `--vimgrep` is a dedicated `file:line:col:text` mode built for exactly this;
> plain `grep -Hn` also already forces the filename on a single file with zero
> conversion needed — so `grep2qf`'s filename-argument fallback is mainly for
> grep output that already happened without `-H` (e.g. pasted from a
> scrollback), and its warning message says so.
>
> **Key changes:**
> - `+ bin/grep2qf` — bare-`line:text` → `file:line:text` filter
> - `+ ~/.local/bin/grep2qf` (symlink)

## 3. Tmux: Popups & Notifications

### [tmux-popup-window.md](plans/completed/tmux-popup-window.md)
`~/dotfiles/.tmux.conf` · 2026-05-17
> `prefix P` toggle: prompts for a window and opens it in a floating tmux popup (a
> grouped session sharing the main session's window list); pressing `prefix P` again
> inside the popup closes it, via an `if -F` check on the transient `_popup_*` session
> name.
>
> **Key changes:**
> - `~ bind-key P` — `~/dotfiles/.tmux.conf`
> - `+ tmux-popup-window.sh` — popup session create/attach/cleanup

### [ghostty-osc-notifications-ssh-tmux.md](plans/completed/ghostty-osc-notifications-ssh-tmux.md)
`~/dotfiles/.functions.sh` · 2026-06-20
> Gets macOS desktop notifications working from tesu tmux panes through SSH to Ghostty.
> Root causes: tmux swallows raw OSC unless DCS-passthrough-wrapped and written to the
> pane TTY, and the old `notify()` used a BEL terminator which produced a bell "ping"
> with no banner whenever Ghostty was focused and suppressing banners.
>
> **Key changes:**
> - `~ notify()` — `~/dotfiles/.functions.sh` — DCS passthrough via `#{pane_tty}`, ST terminator instead of BEL
> - `~ notify-test()` — `~/dotfiles/.functions.sh`

### [tmux-prefix-e-claude-explain.md](plans/completed/tmux-prefix-e-claude-explain.md)
`~/dotfiles/.tmux.conf`, `~/dotfiles/tmux-claude-explain.sh` · 2026-07-11
> `prefix E` opens a headless-Claude popup that diagnoses the focused pane's most
> recent failed command as a bash/OS mechanism lesson, then offers `[f]` to drop a
> suggested fix onto that pane's prompt via `send-keys -l` (never auto-run), using a
> read-only `claude -p` (Read/Grep/Glob + safe Bash only, `find -delete`/`-exec`
> explicitly disallowed). **Shipped code diverged from this plan:** the `CCEXPLAIN`
> `PROMPT_COMMAND` marker and its `run.sh`/`.bashrc` wiring (§1 here) were dropped in
> favor of a "diagnose the most recent command" prompt over the full 2000-line
> scrollback, and the binding hops through `run-shell` because tmux 3.4 doesn't
> format-expand `display-popup`'s shell-command (3.5 does). Later extended so the
> agent is handed nearby project context.
>
> **Key changes:**
> - `+ tmux-claude-explain.sh` — capture pane scrollback → `claude -p` read-only diagnosis → `[f]` places fix via `send-keys -l`
> - `~ bind-key E` — `~/dotfiles/.tmux.conf` — overrides tmux's default spread-panes-evenly; `run-shell -b` wrapper for tmux 3.4 format-expansion
> - `~ tmux-claude-explain.sh` (later) — walk-up notes `CLAUDE.md`/`.docs_claude` + immediate-child `CLAUDE.md` to the agent; `--add-dir` grants Read on parents
> - _planned, not shipped:_ `CCEXPLAIN` `PROMPT_COMMAND` marker in `run.sh`/`.bashrc`

## 4. Shell: Navigation & Machine Config

### [dir-aliases-every-nav-entry-point.md](plans/completed/dir-aliases-every-nav-entry-point.md)
`~/dotfiles/.bash_tools` · 2026-08-19
> The per-directory `.aliases` mechanism only ever wrapped `cd`, so every other way this
> config lands in a new directory silently skipped it: `cdi` (zoxide's fzf picker — its
> `zoxide init` sibling, never redefined, so still stock) and `y` (the yazi cwd-on-exit
> wrapper, whose `builtin cd` is verbatim from upstream's snippet rather than a deliberate
> opt-out). Hoisted the path-walking loop into `_source_path_aliases` and called it from
> all three. The helper sits at top level, not in the zoxide block, because `y` needs it
> on a machine with yazi but no zoxide. The `_CD_SOURCING` re-entrancy guard survives the
> move on `local`'s dynamic scoping — the `source` now happens inside the helper, so a
> sourced file's own `cd` still sees the caller's flag — which is the one thing here that
> could have broken quietly, hence a dedicated fixture test. Surfaced by writing the
> mechanism's first real consumer, an `rf`/`rf_dry` wrapper over a long `bazel run` in the
> Nuro monorepo; that also pinned down that any test of this must be interactive, since
> non-interactive bash never loads `.bashrc` and so has `cd` as a plain builtin.
>
> **Key changes:**
> - `+ _source_path_aliases()` — `~/dotfiles/.bash_tools` — the walk loop, extracted from `cd` to top level so it is reachable without zoxide
> - `~ cd()` — `~/dotfiles/.bash_tools` — reduced to `__zoxide_z "$@" || return $?; _source_path_aliases`
> - `+ cdi()` — `~/dotfiles/.bash_tools` — same shape over `__zoxide_zi`, overriding the stock definition from `zoxide init`
> - `~ y()` — `~/dotfiles/.bash_tools` — `builtin cd -- "$cwd"` → `builtin cd -- "$cwd" && _source_path_aliases`

### [fzf-ctrl-t-directory-navigation.md](plans/completed/fzf-ctrl-t-directory-navigation.md)
`~/dotfiles/.bash_tools` · 2026-07-15
> Adds yazi-style in-picker navigation to fzf's Ctrl-T file finder: Ctrl-H up a
> directory, Ctrl-L descend into the highlighted directory, Ctrl-D jump back to the
> origin — all via fzf 0.70's `become` action (execve-replaces the fzf process after
> `cd`, so hops are real cwd changes and compose across repeated presses). Also rebases
> every inserted selection onto the origin directory regardless of how far the picker
> wandered, using a temp-file side channel since the `become` chain runs in a subshell
> and can't otherwise report its final cwd back out. Shows the current directory as a
> live `--header` on every relaunch. Found and worked around two real fzf 0.70 quirks:
> `transform` actions silently stop firing on any process reached via `become`
> (`execute-silent`/`become` itself are unaffected) — Ctrl-L moved the directory check
> inside the target function instead of gating with `transform` first; and fzf's own
> `__fzf_select__` builds its own options and knows nothing about custom ones, so the
> initial Ctrl-T launch had to be rerouted through the same relaunch function as every
> hop for the header to appear from the first press.
>
> **Key changes:**
> - `~ .bash_tools` — `_fzf_ctrl_t_relaunch`/`_fzf_ctrl_t_up`/`_fzf_ctrl_t_down`/`_fzf_ctrl_t_origin`, `FZF_CTRL_T_OPTS` binds, `_fzf_ctrl_t_widget` (replaces the default Ctrl-T binding) with `realpath --relative-to` rebasing

### [fvim-alias-function-collision-fix.md](plans/completed/fvim-alias-function-collision-fix.md)
`~/dotfiles/machines/tesu.sh` · 2026-07-15
> Fixes `fvim` being defined twice (alias in `machines/tesu.sh`, function in
> `.functions.sh`) — bash resolves aliases before functions, so the alias silently won
> on every fresh shell (the function was dead code), and re-sourcing `.bashrc` in an
> already-running shell hit a `syntax error near unexpected token '('` trying to
> redefine the function over the still-active alias. Found incidentally while testing
> fzf-ctrl-t-directory-navigation.md above.
>
> **Key changes:**
> - `~ machines/tesu.sh` — removed the shadowing `alias fvim`

### [machine-specific-path-registry.md](plans/completed/machine-specific-path-registry.md)
`~/dotfiles/.functions.sh` · 2026-06-17
> Adds a `pp`/`pl`/`prm`/`to` named long-path registry — plain shell variables (which
> expand anywhere on a line, unlike aliases) backed by a marker block written into
> `machines/<hostname>.sh`, so the registry is per-machine and version-controlled for
> free via the existing per-machine sourcing mechanism.
>
> **Key changes:**
> - `~ pp(), pl(), prm(), to(), _pr_*` — `~/dotfiles/.functions.sh`
> - `~ machines/tesu.sh` — lazily gains a `# >>> path registry >>>` marker block on first `pp` call

### [2026-06-25-regex-hostname-shadowing-fix.md](../plans/completed/2026-06-25-regex-hostname-shadowing-fix.md)
`~/dotfiles/source-machine.sh` · 2026-06-25
> Fixes shared regex-hostname config (`machines/r[0-9]+.sh`) silently failing to load on
> `r###` hosts once an exact-match file existed — `pp`/the path-registry (see above)
> writes to `machines/$(hostname -s).sh`, an exact filename that was short-circuiting
> the regex branch entirely. Made exact and regex config additive instead of
> either/or: source the regex match as a shared base, then layer the exact file on top.
>
> **Key changes:**
> - `~ source-machine.sh` — additive exact+regex sourcing instead of exact-wins-and-stops

## 5. Shell: Tooling & Bootstrap

### [macos-login-shell-and-machine-config-dedup.md](plans/completed/macos-login-shell-and-machine-config-dedup.md)
`~/dotfiles/run.sh`, `~/dotfiles/.bash_tools`, `~/dotfiles/machines/` · 2026-08-11
> First bootstrap on `jke-laptop` reported success and changed nothing about the shell:
> Ghostty starts bash through `login` as a *login* shell, which reads
> `.bash_profile`/`.bash_login`/`.profile` and never `.bashrc` — and macOS ships none of
> the three, so every `source` line `run.sh` appends was dead code. Ubuntu's stock
> `.profile` had been covering for that. Fixing it also exposed a non-idempotent `ln -sf`
> that self-links the repo into itself on the second run, and that `machines/jeffpro-3.sh`
> was holding four pieces of config no machine file needed to own.
>
> **Key changes:**
> - `~ run.sh` — appends the `.bashrc` bridge to whichever login file bash reads,
>   creating a one-line `.bash_profile` only when none exist (making one on Ubuntu would
>   shadow its `.profile`)
> - `~ run.sh` — `ln -sfn` for the `.config/nvim` and `.config/yazi` links; `ln -sf`
>   dereferences an existing symlink-to-directory and nests inside it
> - `~ .bash_tools` — guarded `brew shellenv` above the `command -v` checks
>   (`/opt/homebrew/bin` isn't on the default macOS PATH)
> - `~ .bash_tools` — the `.aliases`-sourcing `cd`, moved next to zoxide's init because
>   `.functions.sh` is sourced *before* it and would be clobbered
> - `~ .functions.sh` — `obgrab`, destination via the `$papers` registry entry instead of
>   a hardcoded path; `alias ot` in the shared `.bash_aliases` had been dead everywhere else
> - `~ .bash_vars`, `~ .bash_aliases` — `set -o vi` + `BASH_SILENCE_DEPRECATION_WARNING`,
>   and `alias fresh` (hand-copied into four machine files)
> - `~ machines/{jeffpro-3,tesu,br013,r[0-9]+}.sh` — shared config removed; `alias z=cd`,
>   duplicate `EDITOR`, two `~/.local/bin` prepends and a dead `cd` copy deleted

### [grab-macos-install-bootstrap.md](plans/completed/grab-macos-install-bootstrap.md)
`~/dotfiles/run.sh`, `~/dotfiles/install-tools.sh` · 2026-07-13
> Sub-project 3 of the macOS support roadmap: the three things that stopped a fresh Mac
> from bootstrapping at all — `bin/`'s user commands never being symlinked, GNU-only
> `sed -i` aborting `run.sh` under `set -e`, and `install-tools.sh`'s Linux-only release
> assets. Darwin branches shell out to Homebrew rather than adding per-publisher asset
> patterns, since the publishers disagree about the same CPU (fd/ripgrep say `aarch64`,
> git-lfs says `arm64` and ships a zip). Written without a Mac to test on and held in
> `active/` for that reason; verified end-to-end on `jke-laptop` 2026-08-11, which also
> extended the Darwin branch to the three tools the original pass left behind.
>
> **Key changes:**
> - `~ run.sh` — symlinks `bin/`'s extensionless executables; portable `sed -i.bak`
> - `~ install-tools.sh` — Darwin brew branches for fzf/yazi/nvim, then fd/rg/git-lfs;
>   dispatch loop now requires `"$tool" --version` to succeed, not just `command -v`
> - `~ install-tools.sh` — `latest_asset_url` pattern anchored with `$` (ripgrep's
>   `.tar.gz.sha256` sibling matched the unanchored form); `rust_target`'s failure now
>   propagates instead of degrading the asset pattern to a bare extension
> - Verified on macOS: all six `bin/` symlinks land, `sed -i.bak` survives BSD sed,
>   `brew install` path works for all six brew-delegated tools

### [cli-tools-bootstrap.md](plans/completed/cli-tools-bootstrap.md)
`~/dotfiles/install-tools.sh` · 2026-07-07
> Makes zoxide/fzf/yazi part of standard new-machine setup instead of living only as
> hand-edits on `tesu`. Idempotent, no-sudo installer to `~/.local/bin`, plus a new
> guarded `.bash_tools` integration file (no-op per tool if not installed), wired into
> `run.sh`'s existing symlink/source machinery.
>
> **Key changes:**
> - `+ .bash_tools` — guarded zoxide/fzf/yazi shell integration
> - `+ install-tools.sh` — idempotent no-sudo installer (zoxide official script, fzf/yazi GitHub release binaries)
> - `~ run.sh` — symlinks + sources `.bash_tools`, calls the installer at the end
> - `~ machines/tesu.sh` — now-redundant hand-added `y()`/`fzf --bash` removed

### [yazi-zoxide-db-integration.md](plans/completed/yazi-zoxide-db-integration.md)
`~/dotfiles/yazi/`, `~/dotfiles/run.sh` · 2026-07-10
> Brings `~/.config/yazi` under dotfiles tracking (previously untracked, unlike nvim) and
> enables yazi's built-in zoxide plugin `update_db` option, so directories browsed in
> yazi get written into the same zoxide database the shell's `z`/`zi` use — verified
> against yazi's plugin source and confirmed end-to-end via a scripted tmux session.
>
> **Key changes:**
> - `+ yazi/yazi.toml`, `+ yazi/keymap.toml` — moved verbatim from `~/.config/yazi/`
> - `+ yazi/init.lua` — `require("zoxide"):setup { update_db = true }`
> - `~ run.sh` — guarded symlink (`~/.config/yazi` was a real directory, not a symlink;
>   plain `ln -sf` would've nested inside it instead of replacing it)

### [grab-screen-word-completion.md](plans/completed/grab-screen-word-completion.md)
`~/dotfiles/bin/`, `.bash_tools` · 2026-07-13
> `grab`: a CTRL-G fzf picker over the current tmux pane's visible text +
> scrollback, complementing fzf's own CTRL-T (filesystem paths). Three
> switchable tokenizations — `word` (vim WORD, whitespace-delimited, keeps
> `foo/bar.py:123:`/`--flag=value` intact), `line` (whole screen lines), and
> `fine` (vim word, punctuation-split) — cycled in-fzf via `ctrl-w`, with
> `ctrl-y` to copy instead of insert. Portable `bin/grab` (capture → tokenize
> → fzf, symlinked to `~/.local/bin/grab` like `art`/`fgr`/`pydef`) plus a
> thin `.bash_tools` `bind -x` glue block, matching the `art`/`run` (library)
> vs `dsl`/`rls` (thin wrapper) split. Built via
> subagent-driven-development (4 tasks, task-reviewed, final whole-branch
> review: ready to merge); every mechanism — including the trickiest part,
> fzf's `ctrl-w` mode-cycling — was proven against real detached tmux
> sessions before being written into the plan, catching two real bugs before
> a single line shipped: chained `reload(...)+transform-header(...)` fzf
> actions run *concurrently* not sequentially (fixed by folding the mode
> line into `reload`'s own stdout with `--header-lines=1`, atomic, no race),
> and a `tmpdir` declared `local` inside `main()` went out of scope before
> its own `EXIT` trap fired, corrupting the exit code under `set -u` even on
> a successful selection (fixed by making it a plain script-scoped var).
> Two more bugs surfaced during task review and were fixed with the user's
> sign-off: a top-level `set -euo pipefail` was leaking `errexit` into any
> shell that `source`s `bin/grab` for testing (moved inside the
> run-as-script guard), and `bind -x` with no `-m` only registers into
> the keymap active at call time — this machine's `set -o vi` (sourced
> later in `~/.bashrc`) orphaned an emacs-only binding, fixed by also
> binding `vi-insert`/`vi-command` (and a `bind` flag-order gotcha — `-m
> KEYMAP` must precede `-x` — caught while proving that fix live).
>
> **Key changes:**
> - `+ bin/grab` — `tokenize_word`/`tokenize_line`/`tokenize_fine`/`tokenize_mode` (dedup+reverse), `next_mode`/`header_line`/`emit_mode`/`cmd_cycle` (mode state machine), `main()` (tmux capture + fzf wiring), `--cycle` CLI dispatch
> - `~ .bash_tools` — `_grab_insert()` + `bind -x`/`bind -m vi-insert -x`/`bind -m vi-command -x` on CTRL-G
> - `+ ~/.local/bin/grab` (symlink, machine-local install state, not tracked)

### [grab-preview-window.md](plans/completed/grab-preview-window.md)
`~/dotfiles/bin/grab` · 2026-07-13
> Adds an fzf preview window to `grab` (see grab-screen-word-completion.md
> above), showing the full captured terminal screen below the candidate
> list — static (not synced to the selected candidate), full raw scrollback
> (not a truncated tail). Chose `--preview-window=down,60%` over a
> `right,50%` side split after proving in a real tmux session that fzf runs
> full-screen by default, so a below-split preview keeps close to the
> pane's actual captured width and minimizes text reflow (multi-column `ls`
> output, long log lines, wide prompts render faithfully instead of
> wrapping). The whole-branch review caught a real quoting bug in the plan
> doc's own illustrative Design snippet (single-quoted, would have broken
> at runtime since `$tmpdir` isn't exported and fzf's preview subshell
> can't see it) — the actual Implementation Plan step and shipped code
> already had the correct double-quoted form.
>
> **Key changes:**
> - `~ bin/grab` — `main()`'s fzf invocation gains `--preview "cat \"$tmpdir/raw\""` and `--preview-window=down,60%`

### [grab-preview-follow-scroll.md](plans/completed/grab-preview-follow-scroll.md)
`~/dotfiles/bin/grab` · 2026-07-13
> One-flag follow-up to grab-preview-window.md: `--preview-window=down,60%`
> → `down,60%,follow`, so the preview starts scrolled to the bottom (most
> recent captured lines) instead of the top, and re-anchors to the bottom
> instead of the top on every re-render. Verified directly via tmux that
> fzf has no mechanism to preserve an arbitrary manually-scrolled position
> across a re-render (triggered whenever the highlighted candidate changes
> — typing that reorders the top match, or arrow navigation): the only
> choice is a fixed re-anchor point, "always top" (default) or "always
> bottom" (`follow`). User confirmed always-bottom, with manual scroll-up
> to peek still working until the next re-render, was the wanted tradeoff.
>
> **Key changes:**
> - `~ bin/grab` — `main()`'s `--preview-window` value gains `,follow`

### [grab-preview-follow-match.md](plans/completed/grab-preview-follow-match.md)
`~/dotfiles/bin/grab` · 2026-07-13
> Supersedes grab-preview-follow-scroll.md's `,follow`-to-bottom behavior:
> the preview now jumps to and shows context around wherever the
> highlighted candidate's text actually appears in the captured screen,
> found via a word-boundary fixed-string search (`grep -nFw`) at render
> time rather than tracking position structurally in the tokenizers (a
> position-tagged alternative was designed and proven working, then
> rejected as more invasive). Went through a mid-brainstorm design
> revision: the context window was originally sized to exactly fill the
> preview pane (`$FZF_PREVIEW_LINES`-derived), but the user wanted margin
> against an imprecise match, so it's now a plain symmetric constant
> (`PREVIEW_CONTEXT_LINES=25`, same pattern as `SCROLLBACK_LINES`),
> accepting that the match may need an initial scroll to center rather
> than always being at the very top of the pane. The final whole-branch
> review caught a real bug the task-level tests missed: the no-match
> fallback was dead under the file's own `set -euo pipefail` (a `grep`
> miss's nonzero exit, propagated by `pipefail`, aborted before reaching
> the fallback branch) — masked because the unit tests `source` the file
> and never trigger the run-as-script guard where `set -e` actually
> lives. Fixed with `|| true`, verified directly against the real binary.
>
> **Key changes:**
> - `~ bin/grab` — adds `PREVIEW_CONTEXT_LINES=25` and `cmd_preview_context()` (word-boundary search + symmetric context window + no-match fallback), wires it into the CLI dispatch as `--preview-context` and into `main()`'s `--preview`/`--preview-window` (drops `,follow`)

### [grep2qf-grep-to-quickfix.md](plans/completed/grep2qf-grep-to-quickfix.md)
`~/dotfiles/bin/grep2qf` · 2026-07-15
> `grep2qf`: filter that patches the filename back into bare `grep -n` output
> (omitted when searching a single file) so it becomes `file:line:text`,
> nvim's default quickfix errorformat, for `grep -n ... | grep2qf <file> |
> nvim -q /dev/stdin`. Lines already shaped `file:line:text` (multi-file/`-r`
> grep) pass through unchanged; junk (blank lines, non-matching prose) is
> dropped. Investigated afterward whether grep/rg already do this: ripgrep's
> `--vimgrep` is a dedicated `file:line:col:text` mode built for exactly this;
> plain `grep -Hn` also already forces the filename on a single file with zero
> conversion needed — so `grep2qf`'s filename-argument fallback is mainly for
> grep output that already happened without `-H` (e.g. pasted from a
> scrollback), and its warning message says so.
>
> **Key changes:**
> - `+ bin/grep2qf` — bare-`line:text` → `file:line:text` filter
> - `+ ~/.local/bin/grep2qf` (symlink)

## 6. Shell: Git Helpers

### [fgc-fuzzy-git-commit-search.md](plans/completed/fgc-fuzzy-git-commit-search.md)
`~/dotfiles/.functions.sh` · 2026-07-12
> `fgc`: a fuzzy git-commit-search function applying the same two-stage pattern as
> `fgr` to git history instead of files — exact/regex prefilter on the high-entropy
> corpus (diff content, via git's `-G` pickaxe), then fzf fuzzy-narrowing on the small,
> human-authored candidate list (the oneline commit summaries), not the reverse.
> Measured why the reverse order fails: fuzzy-matching raw diff lines directly produced
> 1,100 false-positive hits for a 6-character query against only 2 real commits, in just
> one submodule's history. Enter prints the selected hash to stdout for piping.
>
> **Key changes:**
> - `+ fgc()` — `~/dotfiles/.functions.sh`, appended after `gpu2()`

## 7. Claude Code Integration

### [tmux-prefix-x-fork-claude-conversation.md](plans/completed/tmux-prefix-x-fork-claude-conversation.md)
`~/dotfiles/.tmux.conf`, `~/dotfiles/tmux-fork-claude.sh`, `~/dotfiles/claude-skills/fork-conversation-pane/` · 2026-08-18
> `prefix X` forks the Claude Code conversation running in the current pane into a
> sibling pane (`prefix C-x` into a new window), turning the `fork-conversation-pane`
> skill into a key binding so the fork costs no model round trip. The enabling discovery
> is that Claude Code already publishes the mapping in `~/.claude/sessions/<pid>.json`
> (`sessionId` plus `"tmux":"<sess>:@<win>.%<pane>"`), so pane → conversation is a pure
> lookup — no pane renaming (Claude overwrites the title anyway) and no `SessionStart`
> hook. The resolver delegates to the skill's `fork-pane.sh` so the guards can't drift.
> A first cut produced an unnamed fork that didn't know it was one; reading the 2.1.235
> bundle showed in-app `/branch` adds `--name "<parent> ⑂ …"` and an
> `--append-system-prompt` worktree-collision notice, both now reproduced, while its
> job-registry lineage stays out of reach for an interactive pane.
>
> **Key changes:**
> - `+ tmux-fork-claude.sh` — pane → session via `~/.claude/sessions/<pid>.json`, filtered to `entrypoint:"cli"`, pid verified against `procStart`, `--resolve` for debugging
> - `~ bind-key X` / `bind-key C-x` — `.tmux.conf` — both previously unbound; `#{pane_id}` passed as an argument because `run-shell` sets no `TMUX_PANE`
> - `~ fork-pane.sh` — `--name`/`--append-system-prompt` parity with `/branch`, new `-n`/`-A`
> - `+ .docs_claude/notes/claude-session-tmux-pane-lookup.md` — the lookup and its traps (`sdk-cli` one-shots stealing the pane, `read` exiting 1 on the missing trailing newline — fatal under `set -e`, no `/proc` on macOS)
