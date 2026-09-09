---
name: annotating-code-in-nvim
description: nvim keymaps for line annotations (haunt.nvim) and region highlights (vim-highlighter). Use to annotate, note, or highlight code.
---

# Annotating and Highlighting Code in nvim

Two plugins, both storing state **outside** the source file so nothing reaches git.
Configured in `nvim/lua/custom/plugins/haunt.lua` and `nvim/lua/custom/plugins/highlighter.lua`.

- **haunt.nvim** — a text note on a line, rendered as faint end-of-line ghost text.
- **vim-highlighter** — a highlighter-pen wash over an arbitrary region.

Both ride the text, because both are extmarks: haunt's note is one with
`right_gravity = true`, a wash is one with `end_row`/`end_col`. Inserting above,
below, or inside a marked span moves it.

## Annotations — `<leader>n`

| Task | Keys | Command |
|---|---|---|
| Add a note to this line | `<leader>nn` | `:HauntAnnotate` |
| Add without the prompt | — | `:HauntAnnotate the retry loop lives here` |
| Edit this line's note | `<leader>ne` | `:HauntAnnotate` (prefills old text) |
| Delete this line's note | `<leader>nd` | `:HauntDelete` |
| Delete all notes in this file | `<leader>nc` | `:HauntClear` |
| Delete all notes, every file | `<leader>nC` | `:HauntClearAll` |
| Hide without deleting | `<leader>nt` / `<leader>nT` (all) | `:HauntToggle` |
| Next / previous note | `<leader>nj` / `<leader>nk` | `:HauntNext` / `:HauntPrev` |
| Picker over all notes | `<leader>nl` | `:HauntList` (`d` delete, `a` edit) |
| Notes to quickfix | `<leader>nq` | `:HauntQf` / `:HauntQfAll` |
| Reload after an external branch switch | — | `:HauntReload` |

The prompt is a `vim.fn.input` reading ` Annotation: `. Line-scoped only — there
are no range annotations.

## Highlight a region *and* annotate it — `<leader>na`

One stroke for both, over the same span (`nvim/lua/custom/annot.lua`). The note
lands on the region's first line.

| Task | Keys |
|---|---|
| Region + note | `<leader>na{motion}` — `<leader>na4j`, `<leader>naap`, `<leader>nai{` |
| Just this line | `<leader>na_` |
| From a visual selection | Select, then `<leader>na` |
| From a `:` range | `:12,15HiNote 3` (color is a one-off override) |

`<leader>na` is an **operator**, so it takes a motion the way `d` does. The count
belongs to the motion, as in `4dj` — `<leader>na4j` marks the cursor line plus 4
below.

The pair is **all or nothing**: abandoning the prompt with `<C-c>`, `<Esc>`, or a
bare `<Enter>` removes the wash too and puts the cursor back. For a wash with no
note, use `t<CR>` instead.

### Removing one

The wash and the note are two independent marks, so one keystroke made them and
two remove them. Put the cursor on the region's **first line**, where both are
reachable:

| To remove | Press |
|---|---|
| The note | `<leader>nd` |
| The wash | `f<BS>` (cursor anywhere inside it) |
| Both | `<leader>nd` then `f<BS>` |
| Every wash in the window | `f<C-L>` |
| Every note in the file | `<leader>nc` |

To reword a note, `<leader>ne` (prompt returns prefilled). To recolor a region,
`f<BS>` the wash, set the pen, mark it again.

## Color — one global pen

Nothing picks a color on its own. `vim.g.annot_color` (default 1) is the pen, and
every highlight uses it: the operator above, and a bare `t<CR>`.

| Task | Keys |
|---|---|
| Set the pen to 1-9 | `<leader>n1` … `<leader>n9` |
| Show the palette as swatches | `<leader>np` |
| Set a color above 9 | `23<leader>np`, or `:HiPen 23` |

Pin a default in your config with `vim.g.annot_color = 7`. The pen is session
state otherwise. Out-of-range values are rejected and leave the pen alone; the
number of colors available depends on the terminal (14 in a 16-color one, more
with truecolor).

## Region highlights alone — `t<CR>`

`t<CR>` is positional (the exact span selected). `f<CR>` is the *other* feature —
pattern highlighting, which colors every occurrence of a word.

| Task | Keys |
|---|---|
| Highlight a region | Select with `v`/`V`/motion, then `t<CR>` |
| Highlight this line | `t<CR>` in normal mode |
| Pick a color | Set the pen (`<leader>n3`); `t<CR>` ignores counts |
| Erase one highlight | Cursor inside it, `f<BS>` (works on a selection too) |
| Erase all in the window | `f<C-L>` |
| Jump between highlights | `:Hi {` / `:Hi }` (any color), `:Hi [` / `:Hi ]` (same color) |
| Highlight every occurrence of a word | `f<CR>` on the word |
| Save this file's highlights | automatic — `<leader>Hs` to force |
| Load by hand | `<leader>Hl` (automatic on `BufWinEnter`) |

Multiline selections become positional automatically. `f<CR> f<BS> f<Tab> t<CR>`
all have visual-mode variants; `f<C-L>` is normal mode only. Plain `f{char}` and
`t{char}` motions are unaffected.

## Storage

- Annotations: `~/.local/share/nvim/haunt/<project-hash>.json`, project-relative
  paths, one file **per git branch**. Saved on every change.
- Highlights: `~/.local/share/nvim/highlighter/<slugified-path>.hl`.

## Traps

- **Both kinds now persist themselves.** Highlights autosave on add and on
  delete (the mutating keys `t<CR>`/`f<BS>`/`f<C-L>` are this config's wrappers,
  which write through), plus `BufWinLeave`, `BufWritePost` and `VimLeavePre`.
- **Deleting the last highlight deletes the store**, including the `.hl.o`
  backup vim-highlighter renames the old file to on every save — otherwise a
  copy of the just-deleted highlights would survive on disk.
- **Pruning is gated on `b:hi_load_ok`.** An empty buffer only means "no
  highlights" if a load actually ran for it; without that flag autosave leaves
  the store alone rather than discarding it.
- **Empty input cancels, it does not delete.** Clearing the text in the annotation
  prompt leaves the old note intact. Use `<leader>nd`. (For `<leader>na`, an empty
  prompt aborts the whole gesture instead — see above.)
- **Rollback deletes extmarks by identity, not position.** `custom/annot.lua`
  snapshots vim-highlighter's `HiColor` namespace before highlighting and removes
  only marks that appeared, so aborting over an existing wash never eats it.
  Deleting the extmark is sufficient cleanup because the plugin's save routine
  enumerates live marks rather than keeping a side table.
- **Never use bare `:Hi save` / `:Hi load`.** They share one `_.hl`, and a saved
  positional highlight stores only `line,col` with no file path — stock load
  replays one file's coordinates into whatever buffer is current. The
  `<leader>Hs`/`<leader>Hl` wrappers key the file per buffer path; use them.
- **Neither re-anchors after an external edit.** Only `{file, line, note}` is
  persisted, so a `git pull` or a formatter run while nvim is closed brings marks
  back on stale line numbers. Drift is exact only while the buffer is open.
- **Never pass color `0`/nil through to `highlighter#Command`.** Its optional
  second argument overrides the color, but falling back to `0` makes it read
  `v:count` instead — a line count of 4 would silently mean color 4. The wrapper
  in `custom/annot.lua` always passes an explicit color for this reason.
- **`t<CR>` is this config's mapping, not the plugin's.** `vim.g.HiSetSL = ''`
  suppresses vim-highlighter's own version so the pen applies. `f<CR>` is left
  as-is on purpose: an explicit color argument disables its toggle-off, which
  vim-highlighter only honors when no color was given.
- **`HiColor*` groups are defined lazily**, inside vim-highlighter's `s:Load()`
  on first command. Anything counting them before that sees zero.
- `<leader>h` is *not* the annotation prefix (it is window-left and gitsigns'
  hunk group); upstream haunt docs suggest it, this config uses `<leader>n`.
