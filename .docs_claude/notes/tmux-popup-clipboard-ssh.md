# tmux popup clipboard over SSH

## Root cause

`display-popup` does not support OSC 52 passthrough. This is a confirmed tmux
limitation — `allow-passthrough on` and `set-clipboard on` work correctly in
regular panes but are silently non-functional inside popups. The popup's pty
does not forward escape sequences to the outer terminal.

Confirmed by tmux maintainer (nicm) in issue #2921 and by the yazi maintainer
in issue #2308. No fix is planned on the tmux side in the near term.

## Workarounds

### Option 1 — tmux buffer bridge (no config change)

Yazi already writes yanked paths to tmux's clipboard buffer when
`set-clipboard on` is set. After copying in yazi, close the popup and paste
with `prefix ]` in the shell. The path lands on the command line without
needing system clipboard.

### Option 2 — Write-to-file + emit OSC 52 from a regular pane

1. Add a yazi keymap that writes yanked paths to a temp file (e.g.
   `~/.yazi_yank`) via `ya pub`.
2. Bind a new tmux key (fired from a regular pane, not the popup) that reads
   that file and emits an OSC 52 sequence:

   ```sh
   path=$(cat ~/.yazi_yank) && \
   printf '\033]52;c;%s\a' "$(printf '%s' "$path" | base64 -w0)" && \
   rm ~/.yazi_yank
   ```

   Because this runs in a regular pane context, passthrough works and the path
   reaches the SSH client's system clipboard.

### Option 3 — Nested session inside popup

Replace the popup command with a nested tmux session:

```tmux
bind C-y display-popup -E -w 80% -h 80% \
  'tmux new-session yazi \; set status off'
```

Reported to help in some environments (yazi issue #2308). Primarily addresses
image preview issues; clipboard behaviour may vary.

## References

- https://github.com/tmux/tmux/issues/2921
- https://github.com/sxyazi/yazi/issues/2308
- https://github.com/sxyazi/yazi/issues/2123
