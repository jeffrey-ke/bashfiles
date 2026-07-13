# `grab`: preview window starts at the bottom and stays there

## Goal

`grab`'s preview window (see
[grab-preview-window.md](../completed/grab-preview-window.md)) currently
starts scrolled to the top of the captured screen and jumps back to the top
on every re-render (typing that reorders the top match, or arrow
navigation) — the opposite of useful, since the most relevant context is
usually the most recent (bottom) lines. Make it start at the bottom, and
re-anchor to the bottom instead of the top on every re-render, while still
letting the user manually scroll up to peek.

## Design

One flag value change to `bin/grab`'s existing `main()` fzf invocation:

```
--preview-window=down,60%        # before
--preview-window=down,60%,follow # after
```

fzf's `follow` preview-window flag ("automatically scroll to the bottom...
similarly to how tail -f works") does exactly this. Verified directly
against a real tmux session before writing this doc, against both a
synthetic fixture and the actual `bin/grab` binary:

- **Starts at the bottom.** A fresh `grab` invocation opens with the preview
  already scrolled to the last lines of the capture, not line 1.
- **Manual scroll-up still works.** `shift-up`/`shift-down` (fzf's default
  preview-scroll keys) move the preview freely while the query/selection
  is unchanged — confirmed by scrolling up 30 lines and observing the
  preview stay there.
- **Re-anchors to the bottom (not the top) on re-render.** This is a hard
  fzf constraint, not a design choice: any re-render of the preview
  (triggered whenever the highlighted candidate changes — via typing that
  reorders the top match, or via arrow navigation) resets scroll to a fixed
  point. Without `follow` that point is line 1 (confirmed: scrolling up 30
  lines then pressing Down twice snapped back to line 1). With `follow`
  that point is the bottom instead (confirmed: same sequence snapped back
  to the last lines, not line 1). There is no fzf mechanism found that
  preserves an arbitrary manually-scrolled position across a re-render —
  the choice is "always top" vs. "always bottom" on re-render, and the
  user confirmed "always bottom" is the wanted behavior.

## Files touched

- `~/dotfiles/bin/grab` (one flag value change, `main()`'s fzf invocation)

## Verification plan

- CTRL-G in a pane with enough content to scroll: preview opens already
  scrolled to the bottom (most recent lines), not the top.
- Manually scroll the preview up (shift-up): moves freely, content visible
  matches what was actually on screen at that point.
- Type a query character that changes the top-ranked candidate: preview
  re-anchors to the bottom (not the top, and not wherever it was manually
  scrolled to — this is the known, accepted limitation).
- `ctrl-w` mode cycling and `ctrl-y` copy still work unaffected (regression
  check — this task doesn't touch either binding).
