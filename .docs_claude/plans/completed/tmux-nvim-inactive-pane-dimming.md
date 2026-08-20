# Make inactive-pane dimming real, and make it reach nvim

**Status:** Applied 2026-08-18 in the working tree (terminal theme is **light**;
an intermediate dark-flavour pass was reverted) — `.tmux.conf` (sourced into the
live server) and `nvim/init.lua` on the `nvim` submodule.

## Context

Three complaints, one root cause between them:

1. The inactive-pane "dimming" doesn't read as dimming — it looks like a **whitecast**.
2. The nvim pane never dims at all.
3. In nvim the cursor is invisible (white on off-white) and there is no visible
   cursorline, despite `cursorline = true`.

## Root causes

**The dim bleached instead of shading.** `.tmux.conf` had
`window-style 'fg=colour245,bg=colour253'` — `#8a8a8a` text on `#dadada`, 2.5:1. Against
the light Ghostty theme that is a white haze laid over the pane: contrast collapses but
nothing reads as *shaded*, which is what "it's just a whitecast" was describing. The line
arrived in `cdb0c1a` (the pane swap/break commit) and was never revisited.

**`window-style` cannot dim an opaque application.** It recolors only the cells an
application left at default fg/bg. Measured on a scratch tmux server, nvim in an
inactive pane, capturing the bytes tmux sends the client:

| nvim's `Normal` | nvim's own bg forwarded | tmux dim bg (`48;5;253`) | tmux dim fg (`38;5;245`) |
|---|---|---|---|
| opaque catppuccin (`bg=#eff1f5`) | 3× | **0×** | **0×** |
| `guibg=NONE` | 0× | 6× | 31× |

So the user's memory of tmux dimming nvim was correct — it worked while this config was
Solarized in ANSI-16 passthrough with `termguicolors = false` (see
`nvim-cterm-highlight-layer-removal.md`), where nvim left colors to the terminal. The
move to true-color opaque colorschemes silently ended it. No tmux option can recover it;
tmux cannot recolor a cell an application colored explicitly.

**Nothing was setting the cursor color.** Stock `guicursor` names no highlight group in
any mode, and without a group nvim never emits OSC 12 — verified by capturing a whole
nvim startup on a pty: zero `ESC]12;`, only `DECSCUSR` shape changes. Catppuccin's
`Cursor` group (latte: fg `#eff1f5` on bg `#dc8a78` rosewater) was therefore dead code,
and the cursor was drawn in **Ghostty's** cursor color — light, from a dark theme — on
top of latte's `#eff1f5`.

**The cursorline was on but invisible.** Catppuccin's `CursorLine` is a 64% blend of
`surface0` back toward the base: `#e9ebf1` against `Normal`'s `#eff1f5`, i.e. 6/255 per
channel. The spec never called `require('catppuccin').setup{}`, so `custom_highlights` —
the entry point for fixing this — was unreachable.

**And the cursor color was the terminal's.** With no group named in `guicursor`, the
cursor is drawn in Ghostty's own cursor color over whatever nvim paints — under an opaque
latte that is a light cursor on `#eff1f5`, invisible. Naming the group is what moves the
decision into the colorscheme.

## Changes

- `~ set -g window-style` — `.tmux.conf` — `fg=colour245,bg=colour253` →
  `fg=colour242,bg=colour252`. Shades rather than bleaches: `#d0d0d0` is a visibly grayer
  field than `#dadada` and `#6c6c6c` keeps text at ~3.5:1 instead of 2.5:1. It stays a
  *light* gray on purpose — see the OSC 11 constraint below.
- `~ catppuccin spec` — `nvim/init.lua` — adds `require('catppuccin').setup{}` with
  `transparent_background = true`. This is the piece that makes pane dimming reach nvim:
  nvim stops painting its own background, so tmux's `window-style` has cells to fill.
  Floats stay opaque (`float.transparent` defaults false).
- `~ catppuccin spec` — `nvim/init.lua` — **stops assigning `vim.o.background` at all**
  and loads the flavour-agnostic `catppuccin` colorscheme instead of a flavour name, so
  the terminal decides light vs dark. nvim honors the OSC 11 reply only while
  'background' has never been assigned: measured in a pane answering light, a config
  doing `set background=dark` stays dark all session, while the same pane with
  'background' untouched flips to light. `:colorscheme catppuccin-latte` *is* such an
  assignment — its compiled chunk sets 'background' when called with a flavour — but
  plain `catppuccin` under the default `flavour = 'auto'` reads &background and leaves it
  alone (`lib/compiler.lua`'s `if flavour then`). The `OptionSet` handler and
  `:ToggleBackground` are unchanged apart from using the one name.
- `+ custom_highlights` — `nvim/init.lua` — `CursorLine` to an unblended surface
  (`surface1` dark / `surface0` light); `CursorLineNr` bold; `Cursor`/`lCursor`/
  `TermCursor` to `fg = base, bg = text`, the terminal-cursor look (block takes the
  foreground, character under it takes the background) which reads at full contrast in
  both flavours.
- `~ vim.o.guicursor` — `nvim/init.lua` — names `Cursor/lCursor` in every mode so nvim
  actually emits OSC 12. tmux advertises `ccolour` for a Ghostty client, so it reaches
  the outer terminal.

## Verification

- End-to-end, real config, nvim in an inactive pane: `48;5;233` ×6, `38;5;245` ×31, and
  zero leaks of an opaque nvim background. Before the change: 0 and 0.
- `OSC 12` now emitted: `ESC]12;#cdd6f4` ×3, with `OSC 112` on exit restoring the
  terminal's own cursor color.
- With the real config in a pane whose OSC 11 answer is light: `background=light`,
  `colors_name=catppuccin-latte`; flip that pane's style dark and the same config comes
  up `background=dark` / `catppuccin-mocha`. nvim follows the terminal in both
  directions, which it could not do while the flavour was hardcoded.
- Resulting groups under latte: `Normal bg=NONE`, `CursorLine bg=#ccd0da`,
  `CursorLineNr bold`, `Cursor fg=#eff1f5 bg=#4c4f69`. Under mocha (`:ToggleBackground`):
  `CursorLine bg=#45475a`, `Cursor fg=#1e1e2e bg=#cdd6f4`.
- Inactive-pane OSC 11 reply with the final color: `rgb:d0d0/d0d0/d0d0` — still light, so
  auto-theming apps in an inactive pane are told the truth.
- Focus events (the fallback approach, not taken) do work here: `GAINED / LOST /
  GAINED / LOST`, one per pane switch — but only with a client attached, which is why a
  detached-server test of them reports nothing.

## Consequences worth knowing

- **`window-style`'s background doubles as a theme signal.** tmux answers an OSC 11
  background query for an inactive pane out of that style instead of forwarding it to the
  terminal, so the dim color is what nvim's detection and Claude Code's `"theme": "auto"`
  see when they start in an inactive pane. Measured both ways; see
  `.docs_claude/notes/tmux-osc11-background-query.md`. Keep the dim on the same side of
  light/dark as the terminal.
- The dim is **partial inside nvim** by construction: background and default-fg cells
  dim, cells with an explicit syntax foreground stay vivid. Groups that carry their own
  background (`CursorLine`, `Visual`, statusline) likewise don't fade.
- A transparent nvim hands plain-text color to the terminal: buffer text takes Ghostty's
  foreground, while syntax highlighting stays catppuccin's.
- TUIs that paint their own background (yazi, lazygit) remain undimmable for exactly the
  reason nvim was. Claude Code panes dim because they leave the background default.
- `:ToggleBackground` now presumes flipping Ghostty's theme too — which is what its own
  comment always said it was for ("match nvim's light/dark mode to the terminal theme
  after flipping it"), but transparency makes it mandatory rather than cosmetic.
- If Ghostty isn't themed catppuccin-latte, latte's syntax colors sit on a slightly
  different background. Setting Ghostty to the matching flavour makes them line up.
- **tmux still doesn't follow a terminal light/dark flip, by decision.** Every color here
  is literal, tmux cannot detect the terminal's theme, and DEC mode 2031 theme
  notifications don't pass through tmux 3.4. A single switch (auto-detect at attach via an
  OSC 11 query issued *outside* tmux, plus a `prefix`-bound flip that also drives
  `:ToggleBackground` in running nvim servers) was designed and declined 2026-08-18 in
  favor of staying light-only. If that changes, the thing to remember is that flipping the
  styles is not cosmetic: `window-style`'s background is the OSC 11 answer for inactive
  panes, so it has to move with the terminal or auto-theming apps break.

## Rejected alternative

A `FocusLost`/`FocusGained` dim inside nvim — snapshot every highlight group, blend
fg+bg toward the background, switch the UI namespace with `nvim_set_hl_ns`. It dims
*completely* (syntax colors included) and keeps nvim opaque, at ~40 lines plus a
re-snapshot on `ColorScheme`. Passed over in favor of letting tmux own the dim, so that
one mechanism covers every pane instead of nvim reimplementing it.
