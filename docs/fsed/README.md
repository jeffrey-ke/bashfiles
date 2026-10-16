# fsed — build a `sed -i` edit in fzf

`fsed FILE` walks through three fzf screens, address, search pattern and
replacement, each with a live preview of what sed will do. The finished command is
then prefilled on an editable `$ ` prompt: enter runs it and adds it to history,
ctrl-c drops it.

```bash
fsed learning/behavior/models/model_configs/bfm_model.yaml
#   address>      /comply<tab>,/weig<down><tab><enter>
#   pattern>      \(weight:\) .*<enter>          preview: "1 lines match"
#   replacement>  \1 36.0<enter>                 preview: the diff
# $ sed -i '/comply_with_siren:/,/weight:/ s/\(weight:\) .*/\1 36.0/' learning/...
```

Two pieces:

| Piece | Where | Role |
|---|---|---|
| `fsed-cmd FILE` | `bin/fsed-cmd`, symlinked to `~/.local/bin` by `run.sh` | Runs the three screens and prints one `sed -i '…' FILE` line to stdout. Exits non-zero, printing nothing, on esc or an empty pattern |
| `fsed FILE` | end of `.functions.sh` | Calls `fsed-cmd`, prefills its output with `read -r -e -i`, then `history -s` and `eval` |

The split is forced: a script can't write into its parent shell's history or
prompt, so the history/prompt step has to be a function sourced into the
interactive shell. Everything else lives in the script so it can be tested
without a shell.

## Why it exists

It was built after two sed mistakes in a row on the line above:

- `-in` is GNU sed's `-i` with backup suffix `n` (`-i[SUFFIX]`), not `-i -n`. It
  silently left `bfm_model.yamln` behind. A real `-n` would have been worse: with
  `-n` and no `p`, `-i` writes an empty file.
- `s/\(weight:\) .0/…/` matched nothing, because ` .0` is space, *one* character,
  `0`, and the value was `24.0`. sed gives no sign a substitution didn't match.

Both are "can't see what sed will do" problems. So the design rule is that every
screen's preview is computed **by sed itself** (or grep in the same BRE dialect),
never by a reimplementation, and the tool never adds a backup suffix or `-n` to
the final command.

## Program model

### The sed command it builds

```
sed -i '<ADDR> s/<PAT>/<REP>/' FILE
```

- `ADDR` may be empty (whole file), a line number, `/re/`, or any range sed
  accepts (`A,B`, `A,+N`, `$`, …). The list and preview call `sed -n "ADDR{=;p}"`
  and `sed -n "ADDR="`, so anything sed accepts works, and anything it rejects
  shows sed's own error message as the only list item.
- `s` has no `g` flag, so only the first match on each line is replaced. The
  pattern preview highlights with the same `s` (no `g`) for that reason.
- One trailing `,` on the address is dropped before use (`622,` → `622`).
- A `'` in the script is written as `'\''` when printing; FILE is `printf %q`'d.

### Screen 1: address

The query is split at its **last comma**. The text after it is the *token* being
typed and the text before it is the *prefix* (`${q##*,}`).

| Token looks like | Mode | List | Preview |
|---|---|---|---|
| starts with `/`, closing `/` not yet typed (`^/(.*[^\\])?/$` fails) | word | words matching the regex after `/` | `grep -nF` of the focused word in the file |
| anything else (digits, `/re/`, `$`, `+N`, empty) | line | `N:text` for every line `sed -n "Q{=;p}"` selects | the file from 5 lines above the focused line, addressed lines in green |

- **Words** are maximal runs of non-whitespace (`grep -oE '[^[:space:]]+'`),
  deduplicated in order of first appearance (`awk '!seen[$0]++'`). There's no fuzzy
  ranking. The order is file order, so the first suggestion is the earliest
  occurrence.
- **A range end is suggested from after the range start.** When the query has
  a comma, suggestions come from lines `start+1,$`, where `start` is the first
  line the prefix selects. Without this, `/weig` after `/comply_with_siren:/`
  suggested `decoder_loss_weights:` from hundreds of lines earlier.
- **Tab** in word mode replaces the token with `/<escaped word>/`. In line mode it
  does nothing (re-emits the query).
- **Word matching uses `grep` with no flags**, so it uses the same GNU BRE dialect
  as sed. An incomplete regex (`\(`) makes grep fail, which shows as an empty list.

### Screen 2: search pattern

- List: words from the addressed lines (`sed -n "ADDRp"`) matching the query.
- Tab replaces the whole query with the focused word, escaped.
- Preview: first line is `N lines match` (`sed -n "ADDR{/PAT/p}" | wc -l`), then
  every addressed line numbered, with what `s/PAT/…/` would replace shown in red
  (`sed -n "ADDR{=;s/PAT/<red>&<reset>/;p}"`). An empty query shows the addressed
  lines plain, because `s//…/` would mean "the last regex" and error.
- An empty pattern on enter aborts.

### Screen 3: replacement

- No list. The preview (90% height, top) is
  `diff --color=always -U1 FILE <(sed "SCRIPT" FILE)`, or `(no change)`, or sed's
  error message if the script doesn't parse (checked first with
  `sed -n "SCRIPT" FILE`).

### Escaping

| Text | Treated as |
|---|---|
| A word picked with tab | Literal: `escape_bre` backslashes `] [ \ / . * ^ $` |
| Anything typed | Raw sed BRE / replacement, passed through untouched. A typed `/` must be written `\/`, and `&` / `\1` in the replacement mean what they mean to sed |

## The fzf model it relies on (fzf 0.74.2)

All three screens go through one helper:

```bash
pick() { fzf --disabled --no-sort --layout=reverse --bind "enter:become(printf '%s\n' {q})" "$@"; }
```

- `--disabled`: fzf doesn't filter. The **query is an input field**, and the list
  is whatever the last `reload` produced. This is what lets the query be a sed
  address instead of a fuzzy search.
- `start,change:reload(CMD)+first`: rebuild the list on every keystroke.
  `change` fires on any query change, including one made by `transform-query`,
  which is why tab-completion immediately redraws the list in line mode.
- `tab:transform-query(CMD)`: the command's stdout becomes the new query.
- `enter:become(printf '%s\n' {q})`: fzf replaces itself with the printf, so the
  screen's result is the **query**, not the selected item. fzf 0.74 has no
  `print-query` action, and `accept-or-print-query` would return the focused
  item whenever there is one.
- Placeholders: fzf substitutes `{q}` and `{}` as single-quoted shell words, so
  `$(printf %q "$script_head"){q}/` concatenates into one argument. FILE and the
  address are baked into bind strings with `printf %q`.
- Bind and preview commands run under `$SHELL -c` (bash here). The preview uses
  `<(…)` process substitution, but only inside `fsed-cmd` itself, which is
  `#!/usr/bin/env bash`, so it doesn't depend on `$SHELL`.
- `: |` feeds fzf empty stdin. All content comes from `start:reload`.
- Esc makes fzf exit 130. `set -euo pipefail` turns that into `fsed-cmd` exiting
  130 with no stdout, and `fsed` returns.

### Self-invoking subcommands

fzf can only call out to commands, so `fsed-cmd` calls itself
(`self=$(printf %q "$(realpath "$0")")`) with hidden first arguments:

| Subcommand | Called by | Args |
|---|---|---|
| `__addr-list` | screen 1 reload | FILE Q |
| `__addr-tab` | screen 1 tab | Q ITEM |
| `__addr-preview` | screen 1 preview | FILE Q ITEM |
| `__pat-list` | screen 2 reload | FILE ADDR Q |
| `__pat-tab` | screen 2 tab | ITEM |
| `__pat-preview` | screen 2 preview | FILE ADDR Q |
| `__rep-preview` | screen 3 preview | FILE SCRIPT |

Each one is plain stdin/stdout, so it can be tested without fzf (see Testing).

## OS / tool assumptions

Built and tested on jke-desktop (Ubuntu, Linux 6.8):

| Tool | Version | GNU-isms relied on |
|---|---|---|
| bash | 5.2.21 | `read -e -i` (prefill, bash ≥ 4), `${q:0:N}`, `[[ =~ ]]`, `<(…)`, `history -s` |
| GNU sed | 4.9 | `-i` with no suffix argument; `{=;p}` with no `;` before `}`; `\(`/`\+` BRE extensions; error text on stderr |
| GNU grep | 3.11 (`/usr/bin/grep`) | default BRE matching sed's; `-o`, `-F`, `--color=always` |
| GNU diffutils | 3.10 | `diff --color=always`, `--label` |
| awk | mawk | POSIX-only use; any awk works |
| paste, wc, head, realpath | coreutils | `realpath` for `self` |
| fzf | 0.74.2 | `--disabled`, `start`/`change` events, `reload`, `transform-query`, `become`, `first` |

Inside a Claude Code Bash tool shell, `grep --version` reports **ugrep**. That
shell defines a `grep` *function* that forwards to ugrep. `fsed-cmd` is a
script, so it never sees that function and gets `/usr/bin/grep`. To check
what the script runs, use `bash -c 'command -v grep'`.

**Untested on macOS.** BSD sed takes `-i ''` (a required suffix argument) and wants
`p;}` rather than `p}`, and macOS's bundled bash is 3.2, which has no `read -i`.
The dotfiles do target macOS (`CLAUDE.md`, Installation), so supporting it would
mean `gsed`/brew bash or a `sed` shim. That hasn't been done.

## Known limits

- **A comma inside an address regex breaks the token split.** `/a,b` is split
  at the comma, so the token is `b` (line mode) and sed reports
  `unterminated address regex`. Fixing it needs a real address tokenizer that
  tracks `/…/` and `\/`.
- Only one `s` command with no flags. No `g`, `I`, a different delimiter, or
  multiple commands. The final prompt is editable, so add those there.
- Picking a word gives a whole-token match (`weight:`, `24.0`). To match part of
  a token, type the regex.
- Suggestions in word mode are capped only by the file. A huge file means a long
  reload on every keystroke.
- Addressed-line preview shows up to 200 lines after the focused one.

## Testing

**Subcommands**, no fzf needed:

```bash
F=some.yaml
fsed-cmd __addr-list "$F" '/comply_with_siren:/,/weight:/'    # N:text of the range
fsed-cmd __addr-list "$F" '/comply_with_siren:/,/weig'        # word suggestions after the start
fsed-cmd __addr-tab '/comply_with_siren:/,/weig' 'weight:'    # -> /comply_with_siren:/,/weight:/
fsed-cmd __pat-preview "$F" '622,625' ' .0'                   # "0 lines match" for the original bug
fsed-cmd __rep-preview "$F" '622,625 s/\(weight:\) .*/\1 36.0/'
```

**The TUI**, in a detached tmux session against a *copy* of the file:

```bash
tmux new-session -d -s fsedtest -x 160 -y 45 "cd $DIR && fsed-cmd t.yaml > out.txt; echo EXIT=\$? >> out.txt; sleep 60"
k() { tmux send-keys -t fsedtest "$@"; sleep 0.8; }      # fzf reloads are async; give them time
k -l '/comply_with'; k Tab; k -l ',/weig'; k Down; k Tab; k Enter
k -l '\(weight:\) .*'; k Enter; k -l '\1 36.0'; k Enter
cat "$DIR/out.txt"; tmux kill-session -t fsedtest
```

`tmux capture-pane -pt fsedtest` between steps shows each screen. To test the `fsed`
function (prefill + history) start the session with
`bash --rcfile <(echo 'source ~/.functions.sh; set -o history; cd DIR')`, type
`fsed t.yaml`, and after the final Enter check `history | tail -2`.
