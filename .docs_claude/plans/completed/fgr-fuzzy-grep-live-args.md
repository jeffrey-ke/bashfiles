# `fgr`: standalone live-grep search with inline glob/fuzzy refinement (+ ugrep)

## Goal

A `pydef`-sibling CLI tool for arbitrary text search: live content search
across the whole workspace, live exclusion globs typed mid-session
(`--iglob !*.md`), a freeze-then-fuzzy-narrow step, and a quickfix skim —
all from `fgr [query] [dir]`, no editor open first. Also ship `~/.ugrep` so
the standalone `ug` binary reproduces the same ignore-binary/hidden/gitignore
defaults without remembering four flags by hand.

Motivating case: `rg 'k.?shot'` over the workspace surfaces both real source
(`isaac_datagen/.../store001-optflow-snacks-kshot-*.yaml`) and plan-doc noise
(`.docs_claude/*.md`, which is a *hidden* dir rg skips by default) — the tool
needs to default to searching hidden dirs, then let `*.md` be excluded live
without restarting the search.

## Final solution

- `~/dotfiles/ugrep-config` (new), symlinked as `~/.ugrep`. Config-file
  format is bare `NAME` (or `NAME=VALUE`) per line, no leading dashes (`man
  ugrep` CONFIGURATION section): `ignore-binary`, `ignore-files`, `hidden`,
  `exclude-dir=.git`, `sort`. `ug` (not plain `ugrep`) auto-loads
  `~/.ugrep` from any cwd. Verified `ug -r -Z2 -l kshot isaac_datagen | wc
  -l` still returns 74 (same as the explicit-flags baseline
  `ug -r -I --ignore-files --hidden -g '!.git' -Z2 -l kshot ...`), and that
  plain `ugrep` (long-form command) stays pristine — it doesn't load the
  config.
- `~/dotfiles/bin/telescope_boot.lua` (new): pydef's lazy.nvim clone-if-
  missing + `telescope.setup` (C-j/C-k mappings) + fzf-native
  `load_extension`, extracted verbatim into a `setup{cache_name,
  extra_plugin_specs}` module so each standalone tool gets an isolated
  `stdpath('cache')/<cache_name>/lazy` and only declares its own extra
  plugins.
- `~/dotfiles/bin/pydef.lua` refactored to resolve its own directory
  (`debug.getinfo(1,'S').source`, prepended to `package.path` — `bin/` isn't
  on it by default) and `require('telescope_boot').setup{cache_name =
  'pydef-nvim'}`. Cache name unchanged, so the existing cache is reused
  as-is (no re-bootstrap).
- `~/dotfiles/bin/fgr` (new launcher, mirrors `pydef`) + `~/dotfiles/bin/
  fgr.lua` (new): boots `telescope_boot` with `cache_name = 'fgr-nvim'` and
  the extra plugin `nvim-telescope/telescope-live-grep-args.nvim`. Defines
  `:FGrep [prompt] [dir]`, which opens the `live_grep_args` extension picker
  with `additional_args = { '--hidden', '--glob=!**/.git/**' }` (plus
  `--follow` when the resolved search dir path contains `/alldocs`, since
  that tree is a symlink farm). Mappings: `<C-j>`/`<C-k>` nav (inherited
  from `telescope_boot`'s global defaults, same as pydef); `<C-Space>` →
  telescope core's `actions.to_fuzzy_refine`; `<M-i>` (not `<C-i>` — see
  bugs below) → live-grep-args' `quote_prompt{postfix=' --iglob '}`; `<C-q>`
  is telescope's own default quickfix binding, untouched. A global
  normal-mode `<C-f>` → `telescope.builtin.resume()`, so a quickfix skim can
  reopen the picker where it left off.
- `~/.local/bin/fgr` → `~/dotfiles/bin/fgr` symlink (matches `pydef`'s
  existing symlink pattern).

## What didn't work, and why

### 1. `<C-i>` for the iglob-quoting mapping, as originally planned

The plan's draft mapping was `<C-i>` → `quote_prompt{postfix=' --iglob '}`.
Checked telescope's own vendored `mappings.lua` (already cloned for pydef)
before wiring it up: it documents in a comment that `<C-i>` is the same
keycode as `<Tab>` in terminals, and `<Tab>` is telescope's default
multi-select toggle (`actions.toggle_selection + actions.move_selection_
worse`). Binding `<C-i>` would silently shadow multi-select. Used `<M-i>`
(Alt-i) instead, as the plan's own fallback anticipated.

### 2. `lga_actions.to_fuzzy_refine`, as the plan's first-choice guess

The plan said prefer the live-grep-args extension's own action wrapper if
present, else fall back to telescope core's. Cloned the extension source to
inspect it directly (`nvim-telescope/telescope-live-grep-args.nvim`,
`lua/telescope-live-grep-args/actions/init.lua`): it re-exports only
`quote_prompt`. The README shows `lga_actions.to_fuzzy_refine` in an example
but that name isn't actually defined anywhere in the extension's own
`actions` module (stale doc, or a really old release) — confirmed telescope
core's `actions.to_fuzzy_refine` exists instead (vendored
`telescope.nvim/lua/telescope/actions/init.lua:1480`) and used that.

### 3. Passing multi-token queries straight through argv

First manual verification attempt tried `fgr '"k.?shot" --iglob !*.md'` as
one shell argument, expecting the whole thing to reach the picker prompt.
`:FGrep`'s arg-splitting (`vim.split(cmd_opts.args, '%s+')`, same shape as
pydef's `:PyDef`) treats each whitespace-separated token positionally
(`args[1]` = prompt, `args[2]` = dir) — `--iglob` landed in `args[2]` as a
bogus search dir. Not a bug: `argv[2]` is a directory, not more query text;
extra rg flags are meant to be typed live into the already-open prompt (this
is also what the plan's own verification section describes: launch with a
plain single-token query, *then* type the flags).

## Bugs hit along the way (worth remembering)

- **live-grep-args only splits typed-in flags out of the pattern if the
  prompt's first character is `'`, `"`, or `-`** (its own `auto_quoting`
  rule, `prompt_parser.lua`: `M.parse` returns the *entire* prompt as one
  literal argument otherwise). `fgr`'s `default_text` was originally seeded
  with the bare unquoted CLI term (`k.?shot`), so appending ` --iglob
  !*.md` live — exactly the workflow the plan verifies — would silently
  glue onto the unquoted pattern and search for the literal 27-character
  string, returning zero results instead of dropping `.md` hits. Reproduced
  this directly the first time through. Fix: `:FGrep`'s command handler now
  wraps `args[1]` in double quotes before handing it to the picker as
  `default_text`, so the on-screen prompt starts as `"k.?shot"` — matching
  live-grep-args' own documented usage — and appending flags afterward
  parses correctly.
- **Smart-case + long base64 blobs produce real-but-confusing hits.**
  During `<C-Space>` (`to_fuzzy_refine`) verification, a `sam2/notebooks/*.
  ipynb` file (a huge embedded-PNG base64 blob) showed up in results for a
  query with zero plain-text substring matches. Not a picker bug: telescope's
  inherited `vimgrep_arguments` carries `--smart-case`, and an all-lowercase
  pattern like `k.?shot` becomes case-*insensitive* under smart-case —
  `rg -i` on that file finds a literal `kSHOT` substring inside the base64
  noise. Confirmed genuine (not manager/job leakage) by rerunning the same
  query with `-i` from a shell. Same category of noise the ugrep research
  already flagged for `-Z` fuzzy matching against binary-ish content — here
  it's smart-case regex against base64 text instead.

## Files touched

- `~/dotfiles/ugrep-config` (new)
- `~/.ugrep` (new symlink → `~/dotfiles/ugrep-config`)
- `~/dotfiles/bin/telescope_boot.lua` (new, extracted from pydef.lua)
- `~/dotfiles/bin/pydef.lua` (refactored onto `telescope_boot`, behavior unchanged)
- `~/dotfiles/bin/fgr` (new, executable)
- `~/dotfiles/bin/fgr.lua` (new, executable)
- `~/.local/bin/fgr` (new symlink → `~/dotfiles/bin/fgr`)

## Verification

Driven end-to-end through detached `tmux` sessions (a floating Telescope
picker can't be verified by piping stdout), from
`/home/jeffk/repo/refseg-workspace`:

- Cold bootstrap (`fgr 'k.?shot'` against a fresh `fgr-nvim` cache):
  lazy.nvim clones, `telescope-live-grep-args.nvim` installs alongside the
  already-familiar `telescope.nvim`/`plenary.nvim`/`telescope-fzf-native.
  nvim` trio, picker opens focused on the prompt (`vim.schedule` fix
  carried over from pydef).
- `fgr 'k.?shot'` → 133/133 hits, confirmed both `isaac_datagen/.../
  store001-optflow-snacks-kshot-*.yaml` and hidden `.docs_claude/*.md` /
  `alldocs/PLANS_TOC.md` files present (hidden-dir default works).
- Typed ` --iglob !*.md` live into the (auto-quoted) prompt → 133/133 →
  55/55, all remaining hits `.yaml` (md hits dropped live, no restart).
- `<C-Space>` then typed a refining term → frozen 55-item set correctly
  fuzzy-narrowed (55/55 → 35/55; verified the narrowing is real subsequence
  fuzzy matching, not a pass-through).
- `<C-q>` → quickfix populated (`[Quickfix List] Live Grep (Args) (...)`
  title), `:cn` moved between entries, `<C-f>` reopened the picker with the
  same frozen/refined result set and preview.
- `pydef Grid` regression: opened instantly (no lazy.nvim clone output,
  cache untouched by the `fgr-nvim` bootstrap), 466/7732 filtered results,
  confirming the shared `telescope_boot` extraction didn't change pydef's
  behavior or force a re-bootstrap.
- `ug -r -Z2 -l kshot isaac_datagen | wc -l` → 74, from repo root, via the
  new `~/.ugrep` (matches the explicit-flags baseline exactly).
