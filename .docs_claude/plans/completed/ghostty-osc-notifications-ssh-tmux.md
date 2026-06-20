# Ghostty OSC notifications over SSH + tmux (tesu)

Desktop notifications from tesu tmux panes to macOS Ghostty via OSC 777, over SSH.

## Stack

```
MacBook Ghostty  →  SSH  →  tesu (Linux)  →  tmux  →  bash
```

Ghostty is the only component that shows the macOS notification. tesu only emits escape sequences; they travel back over the SSH PTY unchanged.

## What we tried

### Cursor agent shell (did not reach Ghostty)

Running `notify()` from the Cursor agent pane (`TERM=dumb`, session `30` window `agent`) emits bytes, but that shell is not the interactive Ghostty SSH session the user is watching. Not a valid end-to-end test.

### Raw OSC inside tmux (expected failure)

These do **not** work inside tesu tmux — tmux swallows raw OSC before it reaches Ghostty:

```bash
printf '\033]777;notify;Ghostty test;If you see this, the chain works\007'
printf '\033]9;Ghostty OSC 9 test\007'
```

Raw OSC only works outside tmux (directly in a Ghostty shell with no tmux).

### Old `notify()` (stdout + BEL)

Previous implementation:

```bash
printf '\033Ptmux;\033\033]777;notify;%s;%s\007\033\\' "$title" "$body"   # in tmux
printf '\033]777;notify;%s;%s\007' "$title" "$body"                        # no tmux
```

Symptoms:

- Sometimes a terminal **ping** (BEL `\007`) but no macOS banner
- Immediate `notify 'jeff' 'jeff'` often felt like it “didn’t work”

The ping was likely the bell terminator, not a partial notification.

### Delayed notify (worked consistently)

```bash
sleep 3; notify-test
# or
sleep 2; notify 'jeff' 'jeff'
```

Worked when Ghostty was **unfocused** during the sleep (user switched to another app). Same `notify()` code path as immediate invocation — the sleep only provided time to unfocus.

### Immediate notify (intermittent / confusing)

- Failed to show a banner when Ghostty was focused (silent delivery to Notification Centre only)
- Worked after the `notify()` rewrite (pane_tty + ST terminator) when tested from tesu tmux
- Old stdout+BEL version felt broken when focused because BEL was removed and banners were suppressed

### Mac-side checks (already configured)

- Ghostty `desktop-notifications = true`
- System Settings → Notifications → Ghostty enabled

Additional macOS tip: set Ghostty alert style to **Alerts** (not Banners) if banners are still suppressed — Ghostty can request silent delivery and Banners honour that; Alerts may still show.

## Root causes

| Issue | Cause |
|-------|--------|
| Raw `printf` OSC fails in tmux | tmux intercepts OSC 777/9 unless wrapped in DCS passthrough |
| “Ping” without banner | Old `notify()` used `\007` (BEL) as OSC terminator |
| Immediate notify “does nothing” | Ghostty suppresses banners when its window is focused; notification may only appear in Notification Centre |
| Cursor agent tests | Agent shell ≠ user’s Ghostty-attached tmux pane |
| tmux popups | OSC passthrough broken in `display-popup` (same class of issue as OSC 52 — see `notes/tmux-popup-clipboard-ssh.md`) |

## What we changed

**`dotfiles/.functions.sh`** — `notify()` and `notify-test()`:

### `notify()` (current)

- **OSC 777** format: `\033]777;notify;TITLE;BODY` (title/body args: `notify "body" "title"`)
- **Inside tmux:** DCS passthrough written to `#{pane_tty}` (not stdout alone)
- **Terminator:** ST (`\033\\`) instead of BEL — avoids false terminal ping when macOS suppresses the banner
- **Outside tmux:** direct OSC 777 with ST terminator

```bash
notify() {
  local body="$1" title="${2:-Terminal}"
  if [ -n "$TMUX" ]; then
    local pane_tty seq
    pane_tty=$(tmux display-message -p '#{pane_tty}' 2>/dev/null)
    seq=$(printf '\033Ptmux;\033\033]777;notify;%s;%s\033\\\033\\' "$title" "$body")
    if [ -n "$pane_tty" ] && [ -w "$pane_tty" ]; then
      printf '%s' "$seq" >"$pane_tty"
    else
      printf '%s' "$seq"
    fi
  else
    printf '\033]777;notify;%s;%s\033\\' "$title" "$body"
  fi
}
```

Passthrough pattern based on [Ghostty discussion #10387](https://github.com/ghostty-org/ghostty/discussions/10387) (write DCS-wrapped OSC to pane TTY so tmux forwards to the SSH client).

### `notify-test()`

Prints focus/alert-style hints, then calls `notify` with a fixed test message.

## What was already in place (unchanged)

**`dotfiles/.tmux.conf`:**

```tmux
set -gq allow-passthrough on
```

Required for DCS passthrough (tmux ≥ 3.3). tesu runs tmux 3.4.

**`~/.bashrc`** sources `~/.functions.sh` (symlink to `dotfiles/.functions.sh`).

## Usage

```bash
# After editing .functions.sh
source ~/.functions.sh

notify "training finished" "tesu"
notify-test

# Long job — natural unfocus window
long-command; notify "done" "tesu"

# Manual test with time to switch away from Ghostty
sleep 2; notify 'jeff' 'jeff'
```

## Mental model

```
bash notify()  →  DCS passthrough to #{pane_tty}
       ↓
tesu tmux      →  unwraps passthrough (allow-passthrough on)
       ↓
SSH PTY        →  bytes unchanged
       ↓
Ghostty        →  OSC 777 → macOS Notification Center
                 (banner if unfocused; may be silent if focused)
```

## References

- [tmux FAQ — passthrough escape sequence](https://github.com/tmux/tmux/wiki/FAQ#what-is-the-passthrough-escape-sequence-and-how-do-i-use-it)
- [Ghostty #10387 — OSC 777 inside tmux](https://github.com/ghostty-org/ghostty/discussions/10387)
- [Ghostty #10151 — macOS banner suppression when focused](https://github.com/ghostty-org/ghostty/discussions/10151)
- [Ghostty #7902 — notifications over SSH](https://github.com/ghostty-org/ghostty/discussions/7902)
- `dotfiles/.docs_claude/notes/tmux-popup-clipboard-ssh.md` — popup passthrough limitation
