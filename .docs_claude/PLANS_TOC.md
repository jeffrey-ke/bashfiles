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
5. Shell: Tooling & Bootstrap · 6. Shell: Git Helpers

---

## Chronological index

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

### [render-markdown-code-block-background.md](plans/completed/render-markdown-code-block-background.md)
`~/dotfiles/nvim/lua/custom/plugins/markdown.lua` · 2026-07-12
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
`~/dotfiles/nvim/init.lua` · 2026-05-18
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
