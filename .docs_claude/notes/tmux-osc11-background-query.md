# tmux answers OSC 11 out of the pane's style, so auto-theming apps guess wrong

Why an app that detects light/dark itself — nvim's `&background` detection, Claude Code
with `"theme": "auto"` — picks the *wrong* mode inside tmux, and why the choice of
inactive-pane dim color silently decides it.

## Mechanism

An application asks the terminal for its background with `OSC 11 ; ? ST` and reads the
reply. Inside tmux (3.4 here) the reply does not necessarily come from the terminal:

| pane | its style | reply |
|---|---|---|
| inactive | `window-style 'bg=colour233'` | `ESC]11;rgb:1212/1212/1212 ESC\` — **tmux answers, from the style** |
| inactive | `window-style 'bg=colour252'` | `ESC]11;rgb:d0d0/d0d0/d0d0 ESC\` — same |
| active | `window-active-style 'bg=terminal'` | forwarded to the terminal (no reply at all when the outer terminal is a dumb pty) |

So tmux answers from the pane's own background when the style pins one, and forwards the
query when the style says `bg=terminal`.

## Consequence

`window-style`'s background is not just decoration — it is what every auto-theming app
launched in an **inactive** pane believes the terminal to be. A dark dim color under a
light terminal makes nvim start in `background=dark` and Claude Code render its dark
theme, on a light terminal, with nothing in either app's config to blame. Hence the rule
in `.tmux.conf`: keep the dim on the same side of light/dark as the terminal theme.

An app that queries from the active pane gets the truth, which is why the symptom looks
intermittent — it depends on which pane was focused when the app started.

## The other half: nvim ignores the reply once 'background' is assigned

nvim honors the OSC 11 answer only while `'background'` has never been set. In a pane
answering light:

| nvim invocation | resulting `&background` |
|---|---|
| `nvim --cmd 'set background=dark'` | `dark` — reply ignored for the session |
| `nvim` (option untouched; nvim's own default is `dark`) | `light` — reply applied |

So a single `vim.o.background = 'light'` in a config permanently opts out of detection —
as does `:colorscheme catppuccin-latte`, because catppuccin's compiled chunk assigns
`'background'` whenever it is loaded *with* a flavour name. Plain `:colorscheme
catppuccin` under `flavour = 'auto'` reads the option and leaves it alone, which is the
one path that keeps detection alive (`lua/catppuccin/lib/compiler.lua`,
`colors/catppuccin.lua`).

## Reproducing it

```bash
#!/bin/bash
old=$(stty -g); stty raw -echo min 0 time 15
printf '\033]11;?\033\\'
reply=$(dd bs=1 count=64 2>/dev/null)
stty "$old"; printf '%q\n' "$reply"
```

Run it in an inactive pane (`tmux send-keys -t <other-pane>`), not the one you are
watching — a foreground run makes its own pane active and gets the forwarded answer.

## Not available here

DEC private mode 2031 (theme-change notifications, `CSI ? 2031 h` → `OSC 997`) is the
mechanism that would let apps track a terminal theme flip live instead of querying once
at startup. tmux 3.4 does not pass it through, so under tmux a light/dark flip needs an
explicit signal.
