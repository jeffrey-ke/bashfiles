# `grab`: fzf picker over visible tmux screen text

## Goal

CTRL-T already gives fzf completion over the filesystem (paths). There's no
equivalent for text that's merely *on screen* — a path in a traceback, a
`--flag=value` in a command's help output, a git hash printed by some other
tool, an identifier buried in a log line. `grab` is a CTRL-G binding that
opens fzf over the current tmux pane's visible content + scrollback, and
inserts the picked text at the cursor.

Three token granularities, switchable without leaving fzf:

- **word** (vim `WORD`, whitespace-delimited) — `foo/bar.py:123:` or
  `--flag=value` stay intact as one candidate. Default/starting mode.
- **line** — each screen line as one candidate, for grabbing a whole error
  message or command.
- **fine** (vim `word`, `[A-Za-z0-9_]+`) — punctuation-split, for pulling
  just `bar.py` or just `123` out of a longer token.

## Design

Split into a portable core tool + thin shell-specific glue, same shape as
`art`/`run` (portable `bin/` script) vs `dsl`/`rls`/etc. (thin wrapper
functions in `.functions.sh`):

- **`~/dotfiles/bin/grab`** (new) — standalone bash script, no readline
  coupling. Captures the pane, runs the fzf picker, prints the chosen text
  to stdout. Symlinked to `~/.local/bin/grab`, same as `art`/`fgr`/`pydef`/
  `commentstrip`.
- **`.bash_tools`** — a `bind -x` block wiring CTRL-G to it. The only
  bash-specific piece.

Requires being inside tmux (`$TMUX` set) — no plain-terminal fallback.

### `bin/grab`

```
grab                       # public entrypoint: capture, pick, print selection
grab --cycle <tmpdir>      # internal only, invoked by fzf's own ctrl-w reload
grab --header <tmpdir>     # internal only, invoked by fzf's own ctrl-w transform-header
```

1. `[ -n "$TMUX" ]` or exit 1 with `grab: not inside tmux` on stderr.
2. `tmpdir=$(mktemp -d)`, `trap 'rm -rf "$tmpdir"' EXIT`.
3. Capture once, up front — not re-captured on mode switches, so the
   candidate set is a stable snapshot of what was on screen when you hit
   CTRL-G:
   `tmux capture-pane -p -S -2000 > "$tmpdir/raw"`
4. `echo word > "$tmpdir/state"` (starting mode).
5. Three tokenizers, all deduped (`awk '!seen[$0]++'`) and **reversed**
   (bottom-of-screen / most-recent lines first, so the most relevant text
   sorts near the top before any fuzzy filtering):
   - `word`: `tac "$tmpdir/raw" | tr -s '[:space:]' '\n'`
   - `line`: `tac "$tmpdir/raw"`
   - `fine`: `tac "$tmpdir/raw" | grep -oE '[A-Za-z0-9_]+'`
   piped through the dedupe `awk`, blank lines dropped.
6. Launch fzf seeded with `word`-mode tokens:
   ```
   fzf --reverse \
       --header "$(grab --header "$tmpdir")" \
       --bind "ctrl-w:reload(grab --cycle \"$tmpdir\")+transform-header(grab --header \"$tmpdir\")" \
       --bind "ctrl-y:execute-silent(printf %s {} | xclip -selection clipboard 2>/dev/null || true)+abort"
   ```
   `Enter` is fzf's default: prints the selected candidate to stdout, grab's
   own stdout is exactly that (nothing else), so `sel=$(grab)` is the
   contract callers use.
7. `--cycle`: reads `$tmpdir/state`, advances word → line → fine → word,
   rewrites it, tokenizes `$tmpdir/raw` per the new mode, prints tokens to
   stdout (this becomes fzf's reloaded candidate list).
8. `--header`: reads `$tmpdir/state` (already advanced by `--cycle`, since
   `reload` runs before `transform-header` in the `+`-chained bind), prints
   `mode: <mode>  (^W cycle mode · ^Y copy)`.

### `.bash_tools` — CTRL-G glue

Same guarded-block idiom already used for `fzf`/`yazi` in this file:

```bash
if command -v grab >/dev/null 2>&1; then
  _grab_insert() {                                            # NEW
    local sel                                                 # NEW
    sel=$(grab) || return                                     # NEW: nonzero exit (Esc, not in tmux) = no-op
    [ -n "$sel" ] || return                                    # NEW
    READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}$sel${READLINE_LINE:$READLINE_POINT}"  # NEW: splice at cursor
    READLINE_POINT=$((READLINE_POINT + ${#sel}))              # NEW: cursor lands after inserted text
  }
  bind -x '"\C-g": _grab_insert'                               # NEW
fi
```

## Error handling / edge cases

- Outside tmux → loud stderr message, nonzero exit, command line untouched.
- Esc / no selection → nonzero exit, command line untouched.
- A mode with zero candidates → empty fzf list, not a crash; `ctrl-w` still
  cycles out of it.
- `xclip` unavailable (plain SSH tty, no X forwarding) → `ctrl-y` silently
  no-ops — identical fallback to the existing `.tmux.conf` copy-mode `y`/
  `Enter` bindings (`xclip ... 2>/dev/null || true`).
- Duplicate tokens (e.g. a word repeated 50× in a log) → deduped; since
  tokens are reversed before dedup, the *most recent* occurrence wins the
  dedup and sorts first.

## Files touched (planned)

- `~/dotfiles/bin/grab` (new, executable)
- `~/.local/bin/grab` (new symlink → `~/dotfiles/bin/grab`)
- `~/dotfiles/.bash_tools` (new guarded block, CTRL-G binding)

## Verification plan

No automated test harness fits an interactive readline widget — manual
smoke test once built:

- CTRL-G in a pane containing a mix of a traceback, a path, and some CLI
  flags: word-mode tokens look right (paths/flags intact).
- `ctrl-w` cycles word → line → fine → word, header text updates each time.
- `Enter` inserts at a **mid-line** cursor position (not just end-of-line)
  and leaves the cursor immediately after the inserted text.
- `ctrl-y` copies the highlighted candidate without inserting; verify with
  `xclip -o`.
- `Esc` cancels cleanly, command line unchanged.
- Running outside tmux errors loudly and does nothing to the command line.
- Scroll the pane's history, confirm an off-screen-scrolled word is still
  reachable (scrollback capture works).
- A word repeated many times on screen appears once in the candidate list.
