# `grep2qf`: bare `grep -n` output → nvim quickfix format

## Goal

`grep -n pattern file` only prints `line:text` when searching a single file —
the filename is omitted, so the output isn't directly usable as an nvim
quickfix list (`file:line:text`, vim's default `errorformat`). Wanted a filter
that patches that back in from the pipe, for `grep -n ... | filter | nvim -q
/dev/stdin`.

## Final solution

`~/dotfiles/bin/grep2qf`, symlinked `~/.local/bin/grep2qf -> ~/dotfiles/bin/grep2qf`
(same pattern as `art`/`fgr`/`grab`):

```bash
#!/usr/bin/env bash
filename="$1"
warned=0

while IFS= read -r line; do
    if [[ "$line" =~ ^[^:]+:[0-9]+: ]]; then
        printf '%s\n' "$line"
    elif [[ "$line" =~ ^[0-9]+: ]]; then
        if [[ -n "$filename" ]]; then
            printf '%s:%s\n' "$filename" "$line"
        elif [[ "$warned" -eq 0 ]]; then
            echo "grep2qf: bare 'line:text' input needs a filename argument, skipping (or just add -H to your grep)" >&2
            warned=1
        fi
    fi
done
```

Lines already shaped `file:line:text` (multi-file or `-r` grep) pass through
unchanged. Bare `line:text` lines get `$1` prepended. Anything else — blank
lines, shell-prompt junk if the input is a pasted terminal transcript rather
than a live pipe — is silently dropped.

```
grep -n pattern file.py | grep2qf file.py | nvim -q /dev/stdin
grep -rn pattern src/   | grep2qf         | nvim -q /dev/stdin
```

## grep/rg already have (most of) this built in

Investigated after the fact, prompted by "does rg/grep already do this?":

- **ripgrep**: `--vimgrep` is a real, dedicated flag — `file:line:col:text`,
  one row per match (splits a line with multiple matches into separate
  entries with correct columns). Purpose-built for `set grepprg=rg\ --vimgrep`.
- **grep**: no flag *named* for vim, but `-H`/`--with-filename` forces the
  filename even for a single file (grep only auto-adds it for 2+ files
  otherwise). `grep -Hn pattern file` alone already produces `file:line:text`,
  which vim's default errorformat (`%f:%l:%m`) parses with zero conversion.

Net effect: for live piping, `grep -Hn ... | nvim -q /dev/stdin` or `rg
--vimgrep ... | nvim -q /dev/stdin` needs no helper at all. `grep2qf`'s
filename-argument branch is a fallback for grep invocations that already
happened without `-H` (e.g. output copied from a scrollback/chat) — its
warning message now says so.

Tangential finding: in the sandboxed Bash tool used to build this, `grep` is
actually a shell function that execs `ugrep` (`ARGV0=ugrep`) with gitignore-
aware flags — a Claude Code shim, not the user's real login-shell `grep`.
`grep --version` there reports `ugrep 7.5.0`.

## Files touched

- `~/dotfiles/bin/grep2qf` (new, executable)
- `~/.local/bin/grep2qf` (new symlink → `~/dotfiles/bin/grep2qf`)

## Verification

- Single-file `grep -n` + `grep2qf <file>`: correct `file:line:text` rows for
  all 11 matches on a real file.
- Multi-file `grep -rn` + `grep2qf` (no arg): passthrough unchanged.
- Junk lines (blank, non-matching prose) dropped; bare `line:text` with no
  filename arg warns to stderr and drops rather than emitting a bad row.
- Loaded real output through `nvim --headless -q /dev/stdin`, inspected
  `getqflist()`: 11 valid entries, correct `lnum`/`text`/`bufnr` for each.
