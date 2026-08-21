# `rg` over ssh searches stdin, so a remote grep silently finds nothing

Why `ssh host 'cd dir && rg PATTERN'` reports no matches on a file that plainly
contains the pattern, and why the failure is invisible: it exits 1, which is exactly
what "no matches" looks like.

## Mechanism

Given no path argument, ripgrep searches **stdin** rather than the working directory —
but only when stdin is not a TTY. An `ssh host cmd` invocation has no TTY, so rg reads
an empty stream, finds nothing, and exits 1.

Measured against `~/worklog` on jke-desktop, which has one `#reflection` in
`Journal/2026-08-20.md:24`:

| command (all under `ssh jke-desktop '...'`) | result |
|---|---|
| `cd ~/worklog && rg --vimgrep -- '#reflection'` | no output, **exit 1** |
| `cd ~/worklog && rg --vimgrep -- '#reflection' .` | `./Journal/2026-08-20.md:24:34:...`, exit 0 |
| `~/.local/bin/rg --vimgrep -- '#reflection' ~/worklog` | match found — an explicit path, so fine |

The same command run interactively on the host works, because there stdin *is* a TTY and
rg falls back to the directory. That is what makes this so easy to misdiagnose: the fix
you reach for ("run it by hand over there to check") is the one case that behaves.

## Rule

Always pass an explicit path to a remote `rg`, even when it looks redundant:

```bash
ssh host "cd $dir && rg --vimgrep -- $pattern ."   # the '.' is load-bearing
```

`-t`/`--tty` is not a fix here — allocating a pty makes rg read the *pty* instead.

## Adjacent trap: rg is not on PATH at all

Separately, `~/.local/bin` is off PATH for `ssh host cmd`, because Ubuntu's `.bashrc`
early-exits for non-interactive shells before `.bash_tools` runs — the same trap
`bin/sb-up` documents and works around with an absolute path. `rg`, `fd` and `nvim` all
live there.

So a remote grep has two distinct silent-empty modes, and they need different fixes:

| symptom | cause | fix |
|---|---|---|
| exit 1, no output | rg read stdin | explicit path argument |
| `rg: command not found` (swallowed inside nvim) | `~/.local/bin` off PATH | `bash -ic`, or an absolute path |

`bash -ic` fixes the second because `-i` puts `i` in `$-` and `.bashrc`'s guard
(`case $- in *i*`) then lets the file run. This is what `sbj` in `machines/jke-laptop.sh`
uses; hardcoding PATH would work too but duplicates what `.bash_tools` already knows.

Inside nvim the PATH failure is *partly* quiet in a way worth knowing: telescope's
`find_files` falls back from `fd` to `find` and looks perfectly healthy, while
`live_grep` cannot run at all. Check with `:lua print(vim.fn.executable 'rg')`, which
returned `0` in an `ssh -t host 'cd dir && exec nvim'` session and `1` under
`bash -ic`.
