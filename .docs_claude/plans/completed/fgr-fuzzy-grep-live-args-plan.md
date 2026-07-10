# fgr — fuzzy grep for the workspace, a pydef-sibling tool (+ ugrep)

> Approved plan + tool-research synthesis. The as-built outcome (deviations,
> bugs hit, verification transcript) is in
> [fgr-fuzzy-grep-live-args.md](fgr-fuzzy-grep-live-args.md).

**Decision (user, 2026-07-10):** Telescope tool + ugrep. Tool name: `fgr`
(collision-free; rename = renaming two files + symlink if ever desired).

## Context

`pydef` (dotfiles) proved the pattern: a standalone `nvim --clean -u <tool>.lua` command
that self-bootstraps its own Telescope stack into an isolated cache. The user wants the
same experience for arbitrary text search: live content search, coarse-to-fine
refinement, live exclusion globs (`!*.md`, `!*venv*`), preview, and skimming many hits
in nvim. Motivating query: "k shot data generation in the store usd" — a demo `rg
'k.?shot'` pass found 24 files (10 yaml, 9 md); excluding `*.md` surfaced the real
source (`isaac_datagen/.../store001-optflow-snacks-kshot-*.yaml`,
`segmentation/train_m2f_lwf.py`, `mask2former_lwf_kshot.yaml`).

**Gotcha found during the demo:** `.docs_claude/` is a hidden dir, so default rg
settings silently skip every plan doc. The tool must default `--hidden --glob
'!**/.git/**'` (gitignore still excludes `.venv`).

## Research synthesis (4 parallel web agents, 2026-07-10)

- **No polished standalone rg+fzf wrapper exists.** Everyone adapts fzf's own
  ADVANCED.md `rfv` script (rg-mode ↔ fzf-fuzzy-mode toggle, `become(nvim {1} +{2})`,
  multi-select → `nvim +cw -q`). Its known unsolved gap: editing rg glob flags
  mid-session (fzf issue #3998).
- **ugrep** (apt, actively maintained, v7.8) is the best single binary: `-Q` live TUI
  with `Alt-G` glob editing mid-session, `Z`/`[`/`]` fuzzy (edit-distance) toggle and
  tuning, F2 → `$EDITOR`. It's also the only tool doing TRUE approximate matching of
  the pattern against content (`kshot` ≈ `k_shot`) — fzf-style fuzziness only filters
  already-fetched result lines. Weak spot: nvim handoff (line-jump unconfirmed, no
  quickfix).
- **Best nvim-picker fit: telescope-live-grep-args.nvim** (nvim-telescope org, pure
  Lua, zero marginal cost over pydef's existing vendored stack). Inline flags typed in
  the prompt: `"k.?shot" --iglob !*.md`. Core telescope already ships
  `actions.to_fuzzy_refine` (verified in pydef's vendored copy, actions/init.lua:1480)
  — freeze current results, prompt becomes fuzzy filter — and `<C-q>` → quickfix is a
  default mapping (mappings.lua:169). fzf-lua/snacks/mini.pick are good but add new
  deps or a different bootstrap.
- Ruled out: tre-agrep (superseded, batch-only), semantic-code-search
  (prototype-grade, manual reindex), zoekt/livegrep/hound (index servers — wrong
  shape), television (nice, but no free-form glob editing).

## Approach

1. **ugrep** — installed via apt (5.0.0 at /usr/bin/ug). Verified working recipe:
   `ug -r -I --ignore-files --hidden -g '!.git' -Z2 'kshot' <dir>` → 74 files in
   isaac_datagen incl. the store kshot configs and .docs_claude plans. Gotchas found
   empirically: explicit dir args are searched depth-1 without `-r` (bare `ug PAT`
   recurses cwd via -R); `-I` needed or `-Z` fuzzy-"matches" random bytes in binaries
   (7147 usdz/png false files); `--ignore-files` needed to honor .gitignore (not
   default, unlike rg); `--hidden` needed for .docs_claude; `-Z` is case-sensitive
   and anchors the pattern's first char (use `-i` / leading `.?` to loosen).
   **Ship these as a `dotfiles/ugrep-config` file symlinked to `~/.ugrep`** (plain
   text → portable to macOS, unlike a binary in bin/): `ignore-binary`,
   `ignore-files`, `hidden`, `exclude-dir=.git`, `sort`. `ug` auto-loads it; the
   long-form `ugrep` command stays pristine for scripts.
2. **Build `fgr`** in `~/dotfiles/bin/`:
   - Extract pydef.lua's lazy.nvim/telescope bootstrap into a shared
     `bin/telescope_boot.lua`; `pydef.lua` refactored to require it (behavior
     unchanged — regression-check pydef after). Bootstrap takes the extra plugin
     spec(s) as a parameter so each tool declares only its own additions.
   - New `bin/fgr` (launcher, mirrors bin/pydef: `fgr [query] [dir]`) +
     `bin/fgr.lua`:
     - lazy spec adds `nvim-telescope/telescope-live-grep-args.nvim` (pure Lua, no
       native build beyond the fzf-native `make` pydef already does).
     - Picker: `live_grep_args` with `default_text` from argv, `cwd` from argv;
       default rg args `--hidden --glob '!**/.git/**'` (so `.docs_claude` plans are
       searchable; gitignore still drops `.venv`); auto `--follow` when the target
       dir is under `alldocs/`.
     - Mappings: `<C-Space>` → `to_fuzzy_refine`, `<C-j>/<C-k>` selection nav (match
       pydef), `<C-i>` → live-grep-args `quote_prompt({postfix=" --iglob "})`;
       `<C-q>` quickfix is already a telescope default.
     - After `<C-q>` skim, a normal-mode key (e.g. `<C-f>`) →
       `telescope.builtin.resume()` to reopen the picker where it left off.
   - Symlink `~/.local/bin/fgr` → `~/dotfiles/bin/fgr`.
3. **Docs**: plan doc in `~/dotfiles/.docs_claude/plans/completed/` + entry in
   dotfiles' own PLANS_TOC.md.

## Files

- `~/dotfiles/bin/fgr` (new launcher)
- `~/dotfiles/bin/fgr.lua` (new picker config)
- `~/dotfiles/bin/telescope_boot.lua` (new, extracted from pydef.lua)
- `~/dotfiles/bin/pydef.lua` (refactor onto shared bootstrap)
- `~/.local/bin/fgr` (symlink)
- `~/dotfiles/ugrep-config` (new) + `~/.ugrep` symlink

## Verification

Same tmux-driven end-to-end pydef used:
- Cold bootstrap installs live-grep-args alongside cached plugins; picker opens.
- Type `"k.?shot" --iglob !*.md` → md hits drop live, store kshot yaml configs remain.
- `<C-Space>` then type `store` → fuzzy-narrows frozen set.
- `<C-q>` → quickfix populated; `:cn` skims; `<C-f>` resumes picker.
- Confirm `.docs_claude` plan files DO appear (hidden-dir default works).
- `pydef` still works after the bootstrap extraction.
- After `~/.ugrep` lands: plain `ug -r -Z2 -l kshot isaac_datagen` reproduces the
  74-file result (defaults picked up from config); `-Q` TUI smoke via tmux
  (Alt-G glob edit, `Z` fuzzy toggle).
