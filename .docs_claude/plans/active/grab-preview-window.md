# `grab`: preview window showing the captured terminal screen

## Goal

`grab` (CTRL-G fzf picker over visible tmux screen text — see
[grab-screen-word-completion.md](../completed/grab-screen-word-completion.md))
currently shows only the tokenized candidate list, with no way to see where a
token came from. Add an fzf preview window that shows the full captured
terminal screen (the same raw `tmux capture-pane` snapshot every tokenization
mode is built from) as context while picking.

## Design

One change to `bin/grab`'s `main()`, in the existing fzf invocation:

```
emit_mode word "$tmpdir/raw" | fzf --reverse --header-lines=1 \
    --preview 'cat "$tmpdir/raw"' \
    --preview-window=down,60% \
    --bind "ctrl-w:reload(grab --cycle \"$tmpdir\")" \
    --bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
```

- **Content:** the full captured scrollback (`$tmpdir/raw`, already written once per invocation and shared by all three tokenization modes) — not a truncated tail. Static: the preview does not scroll/highlight to match the currently-selected candidate; it always shows the same view, letting fzf's own preview-window scrolling (mouse/keys) be the user's control.
- **Layout:** below the candidate list, `--preview-window=down,60%`, not a side split. Proven in a real tmux session before writing this doc: fzf runs full-screen (no `--height` set), so a `down` preview gets close to the terminal's actual width — matching the width `tmux capture-pane` originally captured at, so lines render with minimal reflow. A `right,50%` split would halve the effective width and cause more wrapping of exactly the wide content (multi-column `ls`, long log lines, wide prompts) this feature exists to show faithfully.
- **No interaction with mode-cycling or copy:** `ctrl-w` (cycle tokenization mode) and `ctrl-y` (copy) are untouched — neither reads or writes the preview. The preview command is set once at fzf launch and isn't part of the `reload`d candidate stream, so cycling modes doesn't affect it.
- **No ANSI handling needed:** `tmux capture-pane -p` (no `-e`) already captures plain text, so `cat` is sufficient — no `--ansi` flag or color stripping required.

## Files touched

- `~/dotfiles/bin/grab` (modify `main()`'s fzf invocation only — 2 new flags)

## Verification plan

- CTRL-G in a pane with varied content (wide `ls` output, a `tail -f` log,
  some prompt lines): preview below the candidate list shows the full
  captured screen, full width, matching what was actually on screen (spot
  check: multi-column `ls` alignment isn't broken by wrapping).
- Moving the fzf selection up/down does not change the preview content
  (static, confirmed by design).
- `ctrl-w` still cycles tokenization mode correctly; preview content
  unchanged across mode switches.
- `ctrl-y` still copies and aborts correctly; preview unaffected.
- `Enter` still inserts the correct selection at the cursor (regression
  check against the original CTRL-G behavior).
