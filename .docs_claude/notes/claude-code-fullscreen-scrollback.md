# tmux copy mode cannot see a Claude Code conversation

Why `prefix [` / `/` / any tmux copy-mode search finds only the *visible* frame of a
Claude Code pane, and where the conversation actually lives. Investigated 2026-08-31 on
Claude Code 2.1.252, tmux 3.4.

## Measurement

```
$ tmux display-message -p -t %107 'alt_on=#{alternate_on} hist=#{history_size}/#{history_limit}'
alt_on=1 hist=0/2000
```

`history_size=0` on **every** Claude pane. tmux holds no scrollback for them at all.

## Mechanism

Claude Code's *fullscreen renderer* (a research preview, on by default since 2.1.239 —
or for accounts whose first use was on/after 2026-05-06) draws to the **alternate screen
buffer**, like vim or htop, and scrolls *inside the app*. Only currently-visible messages
are in its render tree, which is what keeps its memory flat in long conversations.

Consequently the conversation is never written to the terminal's grid, so it never enters
tmux's history. Scrolling up in Claude Code repaints the same visible frame; the earlier
turns you see were never in tmux's scrollback to begin with. Upstream states this plainly:
"Your terminal's `Cmd+f` and tmux search don't see the conversation because it lives in
the alternate screen buffer, not the native scrollback."

This is the root cause of a whole family of symptoms that look like separate bugs: copy
mode opening on an empty or stale buffer, PgUp/PgDn being swallowed, `capture-pane -S -`
returning only one screen, and — the one that started this — a copy-mode search for the
user-prompt marker `❯` matching only the chevrons currently on screen.

## The fix is upstream, not in tmux

Claude Code already implements per-exchange navigation, on the real transcript rather
than on rendered text. `Ctrl+o` enters transcript mode, then:

| key | action |
|---|---|
| `{` / `}` | **previous / next prompt** — one exchange at a time |
| `/`, then `n` / `N` | search, next/previous match |
| `j` `k`, `g` `G`, `Ctrl+u` `Ctrl+d`, `Ctrl+b` `Ctrl+f` | less-style motion |
| `[` | write the whole conversation into the terminal's **native scrollback**, tool output expanded — after this, tmux copy mode and `capture-pane` do see it, until `Esc`/`q` returns to fullscreen |
| `v` | write the conversation to a temp file and open `$VISUAL`/`$EDITOR` |
| `Ctrl+o`, `Esc`, `q` | back to the prompt |

`{` / `}` reach the start of the session even across repeated compactions — Claude Code
keeps every earlier message in the fullscreen scrollback even though the model continues
from the compaction summary.

## Do NOT solve this with a tmux binding

A `bind-key ... copy-mode \; send-keys -X search-backward '^❯'` was written, measured
working on a scratch server (the `^` anchor matters — a bare `❯` also matches assistant
prose and captured shell output), and then **reverted**: on the alternate screen it can
only ever find the chevrons in the current frame, because that is all tmux has. The
binding was not wrong, its input was empty.

Two costs made keeping a dead binding worse than nothing: `C-j` in `copy-mode-vi`
displaces the stock `copy-pipe-and-cancel`, and making the walk stop at the oldest prompt
instead of wrapping to the newest requires `set -g wrap-search off`, which is global and
also changes plain `/` searches.

## Escape hatches, if native scrollback is worth more than fullscreen

| variable | effect |
|---|---|
| `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` | force the classic renderer regardless of the saved `tui` setting; conversation goes to real tmux scrollback, so `/`, copy mode and the `xclip` binds work as usual. Costs flicker, memory that grows with the conversation, and in-app mouse |
| `CLAUDE_CODE_DISABLE_MOUSE=1` | keep fullscreen + flat memory, opt out of mouse capture so native click-drag selection works. Does **not** restore scrollback |
| `CLAUDE_CODE_NO_FLICKER=1` / `=0` | force fullscreen / classic at startup |
| `/tui fullscreen`, `/tui default`, `/tui` | switch renderer mid-session (relaunches, conversation intact) or print the active one |

`set -g mouse on` in `.tmux.conf` is already required for wheel scrolling to reach Claude
Code inside tmux, and is already set here.

## Related

- `claude-session-tmux-pane-lookup.md` — resolving a pane to the Claude session in it
- Upstream docs: <https://code.claude.com/docs/en/fullscreen>
