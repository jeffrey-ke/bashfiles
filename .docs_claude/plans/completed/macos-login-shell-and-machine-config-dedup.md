# Fresh Mac: make `.bashrc` reachable, and stop machine files hoarding shared config

## Context

`bash run.sh` on `jke-laptop` (Apple Silicon, first bootstrap of this repo on it)
reported success and changed nothing about the shell. Every symlink was correct and all
six `source` lines were in `.bashrc`, yet a new Ghostty window had the stock macOS
prompt, `cd` as the builtin, and no `aa`/`fresh`/`y`.

Cause: Ghostty (and Terminal) start the shell through `/usr/bin/login` + `exec -l`, so
it is a **login** shell. Bash reads the first of `.bash_profile` / `.bash_login` /
`.profile` that exists and never reads `.bashrc`; macOS ships none of the three. Ubuntu
does ship a `.profile` that sources `.bashrc`, and desktop terminals there start
non-login shells anyway, which is why `run.sh` only ever patching `.bashrc` had held up
for years. Confirmed by contrast:

```
/bin/bash -lic  → PS1=[\h:\W \u\$ ]   cd is: builtin    aa is: file
/bin/bash  -ic  → cd is: function     aa is: function
```

Two more things surfaced while fixing that. A second `run.sh` run had created
`dotfiles/nvim/nvim -> dotfiles/nvim` and `dotfiles/yazi/yazi -> dotfiles/yazi`, because
`ln -sf` dereferences an existing symlink-to-directory and links *inside* it — so the
installer was not idempotent, and one of the two strays was untracked content inside the
`nvim` submodule. And `machines/jeffpro-3.sh` turned out to hold almost nothing
host-specific: `alias fresh` was hand-copied into **four** machine files, `set -o vi`
into two, and `obgrab` lived there while `alias ot='obgrab tesu'` sat in the shared
`.bash_aliases` — dead on every machine but one.

## Changes

### 1. `run.sh` — patch the login file, don't assume `.bashrc` is reached

After the `.bashrc` block, walk bash's own lookup order and append the bridge line to
whichever file bash will actually read; create a one-line `.bash_profile` only when none
of the three exist. Creating one unconditionally would shadow Ubuntu's `.profile`, which
carries real content. Same `grep -qE` idempotency idiom as the `sources` loop above it.

Verified against two temp `$HOME`s, twice each: a mac-like one (no login files) gains
`.bash_profile` with a single line; an ubuntu-like one whose `.profile` already sources
`.bashrc` is left untouched.

### 2. `run.sh` — `ln -sf` → `ln -sfn` for the two directory links

Only `.config/nvim` and `.config/yazi` need it; every other `ln -sf` in the file targets
a regular file, where the trap doesn't exist. The two existing self-links were deleted.
(`yazi-zoxide-db-integration.md` already documented this hazard for the *first*-run case
— "plain `ln -sf` would've nested inside it instead of replacing it" — and guarded it
with `[ -d ] && [ ! -L ] && rm -rf`, which doesn't help on the second run.)

### 3. `.bash_tools` — `brew shellenv`, above the tool checks

Homebrew on Apple Silicon installs to `/opt/homebrew`, which is not on the default macOS
PATH; its installer only prints the `shellenv` line for you to add. Without it,
`install-tools.sh`'s Darwin branches fail their own `command -v brew` guard, and even
after a successful install every `command -v <tool>` block here no-ops. Guarded on
`[ -x /opt/homebrew/bin/brew ]`, so Linux is unaffected. Note it *prepends*, so brew's
`fd`/`rg` shadow any `~/.local/bin` copies.

### 4. Promote the shared config out of `machines/`

| moved | from | to |
|---|---|---|
| `.aliases`-sourcing `cd` | `jeffpro-3.sh` | `.bash_tools`, inside the `command -v zoxide` block |
| `obgrab` | `jeffpro-3.sh` | `.functions.sh`, destination from `$papers` |
| `set -o vi`, `BASH_SILENCE_DEPRECATION_WARNING` | `jeffpro-3.sh`, `tesu.sh` | `.bash_vars` |
| `alias fresh` | four machine files | `.bash_aliases` |

The `cd` wrapper's placement is forced: `.bashrc` sources `.functions.sh` *before*
`.bash_tools`, and zoxide's `init --cmd cd` defines `cd` — so the intuitive home would
be silently clobbered. That ordering is why it ended up in a machine file (sourced last)
in the first place.

`obgrab` now reads `$papers` from the path registry instead of a hardcoded
`~/repo/Research/Research/papers and figures`, with a message naming `pp` when it's
unregistered; `jeffpro-3.sh` keeps only that registry entry. Its `realpath` call went
away with the hardcoded path — macOS ships BSD realpath, which rejects GNU long options.

Deleted as already-provided elsewhere: `alias z=cd` (zoxide is initialized `--cmd cd`,
so `cd` *is* zoxide and `z` was a second name for it; `cdi` is the interactive picker),
`export EDITOR=nvim` (`.bash_vars:2`), two `~/.local/bin` PATH prepends
(`.bash_tools:5`), `$HOME/bin:/usr/local/bin` (`~/bin` absent; `/usr/local/bin` is
*Intel* Homebrew's prefix, now handled by `brew shellenv`), and tesu's dead
commented-out copy of the `cd` walker.

Net effect: `jke-laptop` needs no `machines/` file at all — one appears only when `pp`
writes a registry block.

## Verification

Login shell (`/bin/bash -lic`), after: `cd` is a function wrapping `__zoxide_z` with the
`_CD_SOURCING` guard, `cdi` exists, `z` does not, `fresh` is the alias, `obgrab` is a
function, vi mode on, `BASH_SILENCE_DEPRECATION_WARNING=1`, `EDITOR=nvim`. Dropping an
`.aliases` in a parent directory and `cd`-ing into a child defines its alias. `_pr_get
papers` reads back the new registry block in `jeffpro-3.sh`. `bash -n` clean across all
touched files.

## Not done

- `run.sh` is mode `100644` in git and always has been, so the `./run.sh` that
  `CLAUDE.md` documents has never worked on any machine — `bash run.sh` masks it.
- `machines/br013.sh` and `machines/r[0-9]+.sh` each run a second
  `eval "$(zoxide init bash)"` on top of `.bash_tools`' `--cmd cd` one, which appends
  `__zoxide_hook` to `PROMPT_COMMAND` twice (every directory recorded twice). Left alone
  because PSC's zoxide version can't be checked from here: if it predates `--cmd`, that
  line is the only thing making zoxide work on those nodes.
- `machines/jeffpro/` (no `.sh`, so `source-machine.sh`'s glob never sees it) still holds
  `obsidian_zsh`, which hardcodes Intel-brew `/usr/local/bin/tmux`.
- `fresh` (re-sourcing `.bashrc`) inflates `PROMPT_COMMAND` every time: `.bash_prompt`
  guards `_vim_tag_post`'s *body* but not the append, and bash-git-prompt's
  `setLastCommandState` duplicates the same way. After two re-sources:
  `setLastCommandState;history -a; setLastCommandState;setGitPrompt;_vim_tag_post;__zoxide_hook;_vim_tag_post;_vim_tag_post`.
  `__zoxide_hook` stays single because zoxide's init checks for itself first — the pattern
  this plan's own `history -a` hook and any fix here should follow.
- ~~`source-machine.sh` runs 8 subprocesses to resolve a host that often matches
  nothing~~ — done 2026-08-11, now zero subprocesses; see
  [macos-shell-startup-latency.md](../../notes/macos-shell-startup-latency.md).
