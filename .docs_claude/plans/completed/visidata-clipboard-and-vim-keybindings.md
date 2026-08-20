# VisiData: clipboard that reaches the laptop, and a vim keybinding layer

**Status:** Applied 2026-08-19 in the working tree — `.visidatarc` (new, symlinked by
`run.sh`), `bin/osc52-copy` (new). `vd` itself is the alias at `.bash_aliases:81`,
`uv run --with visidata vd`, so there is no pinned install to patch; everything lives in
the rc. VisiData **3.4**.

## Context

Two complaints, addressed in one file.

1. **Copying a cell inside `vd` never reached the laptop.** Working over ssh into the
   desktop, inside tmux. tmux copy-mode yanks and nvim yanks *do* arrive, so the
   transport exists; VisiData wasn't using it.
2. **The keybindings aren't vim.** Wanted `y` for a cell, `yy` for a row, `:vs` for a
   split, and an answer to "how do I open another file in a buffer".

## Part 1 — Why the clipboard was broken

VisiData's system-clipboard commands shell out to `options.clipboard_copy_cmd` with the
payload on stdin (`clipboard.py:73-83`, `:99-117`). The Linux default is
`xclip -selection clipboard -filter` (`clipboard.py:32`). Two independent problems:

- Over ssh that writes the **remote desktop's** X clipboard, which nobody is looking at.
- On this box there is no `xclip`, no `xsel`, no `wl-copy`, and no `$DISPLAY` at all, so
  the call died on `FileNotFoundError` — the syscopy commands were inert, not merely
  misdirected.

And the key being pressed was `gy`/`zy`, which are the **internal** clipboard
(`vd.memory`, `clipboard.py:193-214`) and never shell out at all. Only the capital-Y
family (`Y`/`gY`/`zY`/`gzY`) touches the system clipboard.

**Fix.** Inside tmux, `tmux load-buffer -w -`: tmux fills its own buffer and emits the
OSC 52 to its attached client, which is the same path `set -s set-clipboard on`
(`.tmux.conf:82`) already gives copy mode and nvim's OSC 52 provider. Because *tmux*
writes the escape, nothing has to survive DCS passthrough and no subprocess writes to
`/dev/tty` underneath a curses app. Outside tmux, `bin/osc52-copy` emits the sequence
itself (base64 + `\033]52;c;…\a` to `/dev/tty`, with DCS wrapping if `$TMUX` is set).

Paste reads back out of the tmux buffer (`tmux show-buffer`), because terminals allow an
app to *write* the clipboard over OSC 52 but essentially never to read it. cmd-V into an
editable cell is unaffected — that is ordinary keyboard input, not a clipboard read.

## Part 2 — The keybinding manual

### Yank (all of these hit the system clipboard *and* the internal one, so `p`/`P`/`zp` still work)

| key | does | replaced |
|---|---|---|
| `y` | copy **cell** | `copy-row` (internal only) — superseded by `yy` |
| `yy` | copy **row** as one csv line | — (new idiom) |
| `Y` | copy row, same as `yy`, no prompt | `syscopy-row`, which prompted for a filetype |
| `gy` | copy **selected rows**, one csv line each | `copy-selected` (internal only) |
| `gzy` | copy **cursor column over selected rows**, one bare value per line | `copy-cells` (internal only) |
| `zy` | **untouched, stock** — internal-only cell copy | — |

Rows are serialized by `rowAsLine` (a `csv.writer` with `lineterminator=''` over
`visibleCols`, using `getFullDisplayValue`), **not** by `syscopyCells(filetype='csv')`.
The upstream saver prepends the column-name header and terminates CRLF, so a one-row
copy pasted as two lines: `name,role,city,score\r\ngrace,admiral,…`.

`yyy` = cell, row, cell. Any other command in between resets the chain, so `y j y` is
two cell copies.

### The `:` command line

`:` opens a vim-style prompt over command longnames, Tab-completing.

| verb | maps to |
|---|---|
| `:vs` `:vsplit` | side-by-side split (see below) |
| `:sp` `:split` | stacked split (upstream's native geometry) |
| `:only` | close the split |
| `:e` | open a file, **Tab-completing the path** — pushes a new sheet |
| `:E` `:Ex` | browse the current directory as a DirSheet (`open-dir-current`, unbound upstream) |
| `:ls` | `sheets-all` — every sheet this session |
| `:b` | `jump-sheet` — by name, Tab-completes |
| `:bn` `:bp` | cycle `vd.allSheets` (no upstream equivalent existed) |
| `:bd` | `quit-sheet-free` |
| `:q` `:qa` `:w` | quit sheet / quit all / save |

Any built-in longname also works (`:addcol-split`, `:save-cmdlog`, …).

**`:` replaced `addcol-split`** (add column split by regex, `features/regex.py:138`),
which moved to **`g:`** — `g:`/`z:`/`gz:` were unbound registry-wide.

### Path completion in `:e`

Measured, not assumed — driven through the rig:

| typed | Tab gives |
|---|---|
| `oth` | `other.csv` |
| `p`, then Tab again, again | cycles `people.csv` → `probe1.py` → `probe2.py` |
| `xd` | `xdg/` — directories come back with the trailing slash |
| `~/dotf` | `/home/jke/dotfiles/` — `~` expands |
| `/etc/hostn` | `/etc/hostname` — absolute paths work |
| `xdg/` then Tab | **re-cycles `xdg` rather than descending.** Type the next character first: `v` → Tab → `xdg/visidata/` |

Empty input + Tab lists the cwd, dotfiles excluded until you type the leading dot.

`o` is deliberately left stock: its two-field prompt is the only way to force a filetype
on a file whose extension lies, and that same second field is why it cannot complete.

### Windows

| key | does | replaced |
|---|---|---|
| `Ctrl+W` | **prefix** (see below) | nothing, was free registry-wide |
| `^Wh` `^Wj` `^Wk` `^Wl` `^Ww` | go to the other pane (`splitwin-swap`) | — |
| `^Wv` / `^Ws` | vertical / stacked split | — |
| `^Wc` / `^Wo` | close the split | — |
| `^Wx` | exchange panes (`splitwin-swap-pane`) | — |
| `Tab` | still `splitwin-swap`, stock | — |

All four directions mean "the other pane" because VisiData has exactly two, ever. `^W^W`
cannot work: the mainloop rejects a repeated prefix with `duplicate prefix`.

### Movement

| key | does | replaced |
|---|---|---|
| `Ctrl+D` | half-page down | **`save-cmdlog`** (still reachable as `:save-cmdlog`) |
| `Ctrl+U` | half-page up | nothing, was free |

Everything else was already vim-like and is left stock: `gg`/`G`, `gh`/`gl`,
`Ctrl+F`/`Ctrl+B`, `/`, `?`, `x`, `d`, `u`, `p`/`P`. Left alone deliberately:
`H`/`J`/`K`/`L` are `slide-left/down/up/right` (move a row or column one position),
which has no vim analogue and is worth more than vim's `H`/`M`/`L`.

### Sheets are buffers — the vim translation

VisiData has **two** lists, which is the thing to internalize: `vd.sheets` is a *stack*
(`q` pops) and `vd.allSheets` is append-only, everything opened this session. `Alt+1`…
`Alt+0` (`jump-sheet-1..10`, `movement.py:139`) index into the latter.

| vim | VisiData | caveat |
|---|---|---|
| `:e file` | `:e` (completes) or `o` (stock) | `:e` Tab-completes; `o` cannot, but is the only way to force a filetype |
| `:b N` | `Alt+N` | positional in `allSheets`; every `q` renumbers; `vd a b c` numbers them in *reverse* CLI order, so `Alt+1` is the last file named |
| `:b name` | `:b` | exact match only |
| `:bn`/`:bp` | `:bn`/`:bp` | added here; upstream `g>`/`g<` only walk a parent IndexSheet and *replace* rather than stack |
| `:ls` | `:ls` / `gS` (all) or `S` (stack) | two lists, not one |
| `:bd` | `Q` / `:bd` | `q` is **not** `:bd` — a popped sheet stays in `allSheets`, recoverable via `gU`, `Alt+N`, `:b` |
| `:qa` | `gq` | |
| `Ctrl-^` | `Ctrl+^` (`jump-prev`) | "second on the stack", not a remembered alternate |
| `:e!` | `Ctrl+R` | |
| `:bufdo` | none | |

Pin a shortcut number by editing the `shortcut` cell on the `:ls` sheet.

## Implementation notes

**`yy` is a state machine, not a prefix.** A key that is bound can *never* also act as a
prefix: `mainloop.py:242` looks up `vd.bindkeys` before `mainloop.py:248` consults
`vd.allPrefixes`. So making `y` a prefix would make bare `y` unreachable — verified by a
subagent driving a pty: with `y` both a prefix and bound, `y y` fired the bare command
twice and the `yy` binding never ran; with `y` a pure prefix, `y j` printed
`no command for "yj"` and *ate* the `j`. Instead `y` records `(sheet, rowidx, colidx)`
and a second `y` on that same cell upgrades to the row. `vd.beforeExecHooks`
(`basesheet.py:6`, called at `:214` for **every** command) clears it.

`vd.cmdlog` would not work as the "previous command" oracle: movement commands declare
`replay=False` and never land in it, so `y j y` and `y y` are indistinguishable there.

**`Ctrl+W` as a prefix** required *not* binding it directly, for the same
mainloop-ordering reason. `vd.allPrefixes` is a plain list (`vdobj.py:28`) an rc can
append to.

**The `vim-` namespace is load-bearing.** `getCommand` (`settings.py:429-435`) chases
keystroke→longname aliases *before* consulting longnames, so a longname literally called
`e` is unreachable behind the `e` key. Every vim verb is registered as `vim-<x>` and
`vimCmdline` tries `vim-<typed>` first, falling back to the literal text.

**Path completion is `:e`'s own.** Upstream's `_completeFilename` is private, doesn't
expand `~`, and returns directories with no trailing `/`, so you can't walk down a tree.
`_completePath` in the rc expands `~`, appends `/` to directories, and hides dotfiles
until you type the dot. Measured behavior: Tab completes, and repeated Tab **cycles**
matches (`p` → `people.csv` → `probe1.py` → `probe2.py`); after a directory completes to
`xdg/`, another Tab re-cycles that same segment rather than descending — type the next
character first (`xdg/` → `v` → Tab → `xdg/visidata/`). That is how VisiData's completion
works generally, not something specific here.

**`:` uses `vd.input`, not `exec-longname`.** `Space`/`exec-longname`'s Enter accepts the
top **fuzzy** match rather than the text typed, and `sp` ties five ways there
(`sp`/`splitwin-close`/`splitwin-half`/`splitwin-input`/`split-col`), broken only by a
stable sort over registry order — `:sp` could have fired `splitwin-close`.

**The vertical split is a monkeypatch, and the only thing here that is.** Upstream has no
vertical split at all: `disp_splitwin_pct` is a *height* percent (`splitwin.py:3`) and
`setWindows` hands both panes `x=0` and the full width (`mainloop.py:101-103`). But each
pane is an independent curses subwindow, sheets self-size from `_scr.getmaxyx()`
(`basesheet.py:59-66`), and status bars plus mouse hit-testing are scr-relative — so
re-deriving the two subwindows as left/right is sufficient. The rc wraps `vd.setWindows`
behind a new `disp_vsplit` option. **If a VisiData upgrade changes `setWindows`, delete
that block and `:vs` degrades to a stacked split.**

`splitPane` only *moves* a sheet across when a sheet is under this one
(`splitwin.py:11`), so `:vs` with a single sheet open sets the geometry and still shows
one pane — same as upstream `Z`.

## How this was tested

Three channels, because a curses app can't be asserted on directly.

**1. Headless introspection** — for anything that is registry state rather than
behavior. This is also how to check for clobbering before adding a binding:

```bash
cd /tmp && uv run --quiet --with visidata python -c "
from visidata import vd
vd.loadConfigFile('/home/jke/.visidatarc')
print(list(vd.statuses) or 'clean')          # rc exceptions surface here
print(vd.bindkeys._get('y', obj='TableSheet'))
"
```
`vd.commands` and `vd.bindkeys` are `SettingsMgr` dicts (`settings.py:14`) keyed
`longname → {objname: Command}` and `keystroke → {objname: longname}`. A full dump of all
701 stock bindings is one loop over `.iterall()`.

**2. A tmux rig that drives a real `vd`** — for anything that only exists on screen.
Detached on purpose: `load-buffer -w` only emits OSC 52 to clients attached to the target
session, so a detached rig writes the tmux buffer without touching the real clipboard of
whoever is attached. `show-buffer` is then the read-back channel for what `vd` copied.

```bash
#!/usr/bin/env bash
# usage: vdrig.sh start [rcfile] | keys <keys>... | screen | buf | stop
set -uo pipefail
S=vdrig
SC="$(cd "$(dirname "$0")" && pwd)"
pause() { timeout "$1" tail -f /dev/null 2>/dev/null; }   # `sleep` is unavailable here

case "${1:?}" in
start)
	tmux kill-session -t $S 2>/dev/null
	tmux new-session -d -s $S -x 120 -y 30 -c "$SC"
	rc="${2:-}"
	cmd="uv run --quiet --with visidata vd $SC/people.csv"
	# --config is parsed too late to pick the rc (see traps); XDG is the only
	# honoured override, and it *replaces* ~/.visidatarc rather than layering
	[ -n "$rc" ] && { cp "$rc" "$SC/xdg/visidata/config.py"; cmd="XDG_CONFIG_HOME=$SC/xdg $cmd"; }
	tmux send-keys -t $S "$cmd" Enter
	for _ in $(seq 40); do
		tmux capture-pane -pt $S | grep -q 'barbara' && exit 0   # a known cell
		pause 0.5
	done
	echo "TIMEOUT waiting for vd to draw:"; tmux capture-pane -pt $S | tail -5; exit 1
	;;
keys)  shift; tmux send-keys -t $S "$@"; pause 0.6 ;;
screen) tmux capture-pane -pt $S ;;
buf)   tmux show-buffer 2>/dev/null ;;
stop)  tmux kill-session -t $S 2>/dev/null ;;
esac
```

Used as `./vdrig.sh keys j l` then `./vdrig.sh keys zy` then `./vdrig.sh buf`. The status
line is the assertion surface for "which command ran": it renders `keystroke  longname`
at the bottom right, so `screen | tail -1` confirms dispatch even when the command has no
visible effect. Candidate rcs set `clipboard_copy_cmd` to
`tmux load-buffer -b vdrigtest -w -`, a **named** buffer, so tests never disturb the real
default buffer.

**3. Fanned-out subagents** for source archaeology — the 701-binding dump, the keystroke
dispatch/prefix/hook internals, the splitwin model, and the sheets-as-buffers model. Two
of the four independently pty-drove `vd` to check their own claims, and one of them
converged on the same `beforeExecHooks` design for `yy` from the opposite direction.

## Traps found along the way

Ordered by how much time each would cost someone re-deriving it.

1. **`vd --config FILE` is silently ignored.** `loadConfigAndPlugins()` reads
   `vd.options.config` (`settings.py:530`) but CLI globals are only pushed into options
   *after* that call (`main.py:417` then `:419`), and `config` isn't declared `cli_only`
   (`main.py:25`). To test an alternate rc, point `XDG_CONFIG_HOME` at a dir containing
   `visidata/config.py` — `vd.config_file` honors it (`settings.py:462-468`) and it
   *replaces* `~/.visidatarc` rather than layering.
2. **`addCommand` steals a keybinding silently.** It calls module-level `vd.bindkey`
   (`settings.py:396`), which never warns. Only `BaseSheet.bindkey` warns — and its check
   inspects the *un-prettified* string and only the exact class, so
   `Sheet.bindkey('Y', …)` checks `bindkeys['Y']` (absent), warns nothing, then writes
   `bindkeys['Shift+Y']` over `syscopy-row`.
3. **`Sheet` IS `TableSheet`** (`sheets.py:1092`), and `objname` keys by class *name*, so
   `Sheet.addCommand` replaces the stock TableSheet slot in place. There is no
   Sheet-vs-TableSheet layering to exploit. A CSV opens as
   `CsvSheet → SequenceSheet → TableSheet → BaseSheet` with **zero** bindings on the
   first two.
4. **Uppercase keystrokes are stored prettified.** `Y` is `Shift+Y`, `zY` is
   `zShift+Y`, `^O` is `Ctrl+O` (`keys.py:113-127`). `vd.bindkeys._get('Y')` returns
   `None`.
5. **A csv-typed copy includes the header row and uses CRLF** — measured, not assumed:
   `name,role,city,score\r\ngrace,admiral,new-york,88\r\n` for a *one-row* copy. There is
   no `save_header` option to turn it off.
6. **`getCommand` prefers keystrokes over longnames** (`settings.py:429`). This made
   `:e` run `edit-cell` and type the filename into the cell. Caught by the rig, not by
   inspection.
7. **`exec-longname`'s Enter takes the top fuzzy match**, not your text
   (`cmdpalette.py:183`).
8. **A bound key can never act as a prefix** (`mainloop.py:242` before `:248`), and a
   prefix + unbound key eats the second keystroke with a non-modal
   `no command for "…"`.
9. **Upstream's `o` prompt cannot Tab-complete paths — and it is not the completer's
   fault.** `_completeFilename` exists and works (`_open.py:44-62`), but `inputPath`
   builds a two-field form (path + `as filetype:`) via `inputMultiple`, which rebinds Tab
   to next-field (`_input.py:521-525`), and `editline` checks those bindings *before* the
   completion handler. Single-field prompts (`jump to sheet:`) complete fine. Worked
   around by giving `:e` its own single-field `vd.input` — see `vimOpen`.
10. **An unbound keystroke does not break the `y`-`y` chain**, because it never reaches
    `execCommand`. `y` `Esc` `y` still yields a row copy. Unfixable without patching the
    mainloop; harmless in practice.
11. **`DirSheet` keeps its own `y`** (`shell.py:289`, a more specific class), so the vim
    yank does not apply in the directory browser.
12. **Rig gotchas.** `sleep` is unavailable in this environment — use
    `timeout N tail -f /dev/null`. In a split, both panes render a status line on the
    same bottom row, so `tail -1 | cut` reads the *left* pane and can attribute a command
    to the wrong sheet; grep the whole row for the longname instead. And a wedged prompt
    (e.g. a bogus filetype `csvtsv`) leaves `vd` in `processing…` forever — restart the
    rig rather than trying to escape it.

## Rejected alternatives

- **`y` as a prefix** for a true `yy`: kills bare `y`, per trap 8.
- **Time-based double-tap** (`time.monotonic()` in the command, or the curses timeout):
  makes correctness depend on typing speed, and the timeout branch has no extension point
  — after 10 idle ticks `get_curses_timeout()` returns `-1` and blocks
  (`mainloop.py:300-303`).
- **`Y` for the row and no `yy`**: cheapest, and vim's `Y` *is* yank-line, so `Y` was
  bound that way too — but it doesn't deliver the asked-for `yy`.
- **`import visidata.experimental.vimcompat`** for the half-page keys: upstream ships it
  (13 lines: `go`→`go-home`, `Ctrl+D`/`Ctrl+U`→half-page) but it takes `Ctrl+D` from
  `save-cmdlog` invisibly. The two `bindkey`s are written out explicitly instead, so the
  displacement is visible in the file.
- **`pct`-only splits with no monkeypatch**, pointing `:vs` at the stacked split:
  preserves muscle memory but not geometry. Kept as the documented fallback.
