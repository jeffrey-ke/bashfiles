# Fix: unreadable grey code blocks in render-markdown under Solarized ANSI-16

**Status:** Shipped 2026-07-12 — `nvim/lua/custom/plugins/markdown.lua` now passes
`code.disable_background = true`. Verified headlessly that render-markdown's `setup`
accepts the option and it resolves to `true` for all languages (label/border config
unchanged); the final light↔dark visual confirmation is a live-UI step.

## Context

The recent plan **"Neovim ANSI-16 Solarized passthrough"**
(`~/.claude/plans/plan-to-modify-my-rippling-summit.md`, 2026-07-08) switched the
colorscheme from `tokyonight-storm` to `altercation/vim-colors-solarized` running in
**ANSI-16 passthrough mode** (`termguicolors = false`, `solarized_termcolors = 16`).
Every highlight now resolves to a terminal ANSI slot (0–15) from the terminal's Solarized
palette instead of a truecolor hex value.

`MeanderingProgrammer/render-markdown.nvim` (v8.12.0, installed but not in the stale
`lazy-lock.json`) runs on **100% defaults** — its spec is literally
`return { 'MeanderingProgrammer/render-markdown.nvim' }`
(`lua/custom/plugins/markdown.lua`). Fenced ```` ```python ```` blocks therefore render as
"hard-to-read grey blocks."

## Root cause (confirmed from source)

- render-markdown's default code-block fill is `code.highlight = 'RenderMarkdownCode'`
  (`settings.lua:527`), and `RenderMarkdownCode` **links to `ColorColumn`**
  (`core/colors.lua:27`). It re-establishes this link on **every `ColorScheme` event**
  (`core/colors.lua:84`) — so overriding `RenderMarkdownCode` directly is fragile.
- `vim-colors-solarized` sets `ColorColumn` to **base02**
  (`colors/solarized.vim:672`), which in 16-color mode is ANSI slot **0** in dark mode /
  slot **7** in light mode (the light/dark swap at `solarized.vim:379-395`).
- Slots 0/7 (base02/base2) are Solarized's *canonical subtle-highlight* tone — only **one
  step** off the actual background (base03/base3). That low contrast is Solarized by
  design, and it is what makes the block "hard to read."
- **ANSI-16 has no better option.** The Solarized 16-slot palette exposes only two
  background tones per mode; render-markdown already uses the alternate one. You cannot get
  a distinct *and* readable grey block in cterm-only mode — the choice is "subtle fill" or
  "no fill." A readable *tinted* block would require a truecolor bg, which contradicts the
  passthrough design.

## Recommended fix

Remove the code-block background so code renders on the normal terminal background (where
Solarized's syntax colors have their designed contrast), while keeping the language
label + border so blocks stay visually identifiable. render-markdown exposes
`code.disable_background` (`settings.lua:481`, `boolean | string[]`) exactly for this —
its default is `{ 'diff' }`; we widen it to all languages.

This matches the plan's own philosophy (it *dropped* several 256-cube background overrides
like `WildMenu`/`Pmenu` to "let Solarized's native highlighting cover them"). It is a plugin
`opts` change, so it survives colorscheme reloads with no highlight-override bookkeeping.

**Chosen look:** drop the block fill, keep the language label + border, and leave inline
`` `code` `` with its subtle tint (`disable_background = true` — not `style = 'language'`,
which would also disable inline-code rendering).

## The edit

**File:** `lua/custom/plugins/markdown.lua` (was a bare one-line spec).

```lua
return {
  'MeanderingProgrammer/render-markdown.nvim',
  opts = {
    code = {
      -- ANSI-16 Solarized has no readable "block" tone: RenderMarkdownCode links to
      -- ColorColumn = base02, only one step off the background. Render fenced blocks on
      -- the normal bg instead (full syntax contrast); keep the language label + border so
      -- blocks stay identifiable. Default was { 'diff' }; widen to all languages.
      disable_background = true,
    },
  },
}
```

Notes:
- lazy.nvim auto-runs `require('render-markdown').setup(opts)` when `opts` is present — no
  `config` function needed.
- No highlight override and no touch to `set_ansi_ui_hl()` / `ColorColumn` is required; the
  fill is removed at the plugin level, so it holds across `:ToggleBackground` in both light
  and dark automatically.
- Inline code is untouched (keeps `RenderMarkdownCodeInline` → `ColorColumn` tint), which is
  the intended behavior here.

## Verification

1. Reload nvim (or `:Lazy reload render-markdown.nvim`) and open any markdown file
   containing a ```` ```python ```` fenced block (e.g. one of the plan docs, or a scratch
   `test.md`).
2. Confirm the code body now sits on the **normal terminal background** with no grey fill,
   while the `python` language label and the block border are still shown, and Python
   syntax colors read clearly.
3. Confirm inline `` `code` `` still shows its subtle tint (unchanged).
4. Run `:ToggleBackground` (or `<leader>tb`) to flip light↔dark and confirm code blocks
   stay fill-free and readable in both modes.
5. Sanity: `stylua --check lua/custom/plugins/markdown.lua` (repo style: 160 cols, 2-space).

Headless check performed at ship time (mirrors the exact opts lazy passes): `setup_ok = true`,
`disable_background = true`, `style = "full"`, `highlight = "RenderMarkdownCode"` — option
accepted and applied, label/border retained.
