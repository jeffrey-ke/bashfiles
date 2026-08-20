# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Installation

```bash
./run.sh   # Creates symlinks from ~/ to ~/dotfiles/ and patches .bashrc
```

`run.sh` also makes sure a login shell reaches `.bashrc`, since bash reads only the
first of `.bash_profile`/`.bash_login`/`.profile` and never `.bashrc` itself. Ubuntu's
stock `.profile` already does this; macOS ships none of the three, so a fresh Mac gets
a one-line `~/.bash_profile` stub — without it every `source` line `run.sh` appends is
dead code, because Ghostty and Terminal both start the shell via `login`. Where a login
file already exists it is patched, never replaced (creating `.bash_profile` on Ubuntu
would shadow `.profile`).

The installer is idempotent and self-contained — on a fresh machine `run.sh` alone is
enough. It initializes the submodules (`jeffrey-ke/kickstart.nvim` as `nvim/`,
`jeffrey-ke/commentstrip`), symlinks the configs, patches `.bashrc`, runs
`./sync-skills.sh`, then runs `./install-tools.sh`. Its one prerequisite is a GitHub
SSH key, since the repo and both submodule URLs are `git@github.com:`.

`./install-tools.sh` installs, into `~/.local/bin` without sudo: nvim, fd, rg, uv,
claude, git-lfs, zoxide, fzf, yazi — plus bash-git-prompt, tpm, and vim-plug. Every
entry is something a config file here depends on. `tmux` is in the list too but has no
no-sudo Linux route (upstream ships source only), so there it needs `apt`; macOS gets it
from brew like the rest. Each failure warns and continues, so
an offline machine still gets its symlinks. After it runs, `:PlugInstall` in vim and
`prefix + I` in tmux fetch the actual plugins.

On macOS that list instead comes from **Homebrew** — everything except zoxide, uv, and
claude, whose own installers are cross-platform — so brew is a second prerequisite
there, and `install-tools.sh` reports `✗` for six of nine tools without it. Homebrew
alone isn't sufficient: `/opt/homebrew/bin` is not on the default macOS PATH, which is
why `.bash_tools` evals `brew shellenv` before its `command -v` checks.

`ugrep` is opt-in — `./install-tools.sh ug` — because Genivia publishes no Linux
binary, so it has to compile (~1–2 min) and lands 7.x where Ubuntu's package is 5.0.
The `ug` alias and the `ugq` function are unavailable until you install it, by that
command or `apt install ugrep`. Passing any tool name as an argument installs only
those tools and skips the plugin managers.

## Repository Structure

**Dotfiles** — classic symlinked configs for bash/zsh, tmux, vim, neovim, git, and Python tooling.

**`machines/`** — hostname-keyed per-machine shell configs, resolved by
`source-machine.sh` (which `run.sh` appends to `.bashrc` once). Each `*.sh` filename is
treated as an anchored regex against the short hostname (`${HOSTNAME%%.*}`, resolved
without spawning a subprocess): the first alphabetical regex match
is sourced as a shared base, then `<exact-hostname>.sh` is layered on top so per-host
overrides win. That is why `machines/r[0-9]+.sh` exists — one base for every PSC compute
node, with `r033.sh` / `r191.sh` adding just their own path registries.

To add config for a new machine, create `machines/<hostname>.sh`. No changes to `run.sh`
needed. This is also where the per-machine path registry (`pp` / `pl` / `prm` / `to`,
implemented in `.functions.sh`) writes its marker block, so `$datasets` and friends are
deliberately machine-local and do not transfer.

It is also where a *foreign* installer's `.bashrc` additions go. `jke-desktop.sh` is the
worked example: the Nuro work machine runs `Nuro/misc/scripts/swe_setup/swe_setup.sh`,
which appends fnm/Node, `~/bin` (nuro-cli `n`), and `~/.local/bin` PATH blocks to
`~/.bashrc`. Moving them into the machine file makes them version-controlled and lets
them be guarded (swe_setup's `eval "$(fnm env)"` is unguarded and errors once the
install goes missing). Re-running the foreign installer is then a no-op, because its
re-append guards are all PATH tests — `command -v fnm`, `":$PATH:" == *":$HOME/bin:"*`
— and PATH is exported into the installer even though it never reads `.bashrc` itself.
The two installers otherwise compose: `run.sh`'s `.bashrc` appends are guarded,
`install-tools.sh` skips tools already on PATH (so apt's git-lfs and swe_setup's claude
stand), `sync-skills.sh` skips existing destinations, and swe_setup's only git change is
`include.path` in `Nuro/.git/config`, which the `~/.gitconfig` symlink cannot disturb.
What does need a manual step per work repo is identity: `.gitconfig` carries a personal
`user.email`, so a work clone wants `git config --local user.email <work address>`.

**`claude-skills/`** — personal skill library for Claude Code. Each skill is a directory with a `SKILL.md` containing YAML frontmatter (`name`, `description`, `argument-hint`) followed by the recipe. Skills encode reusable design patterns, reference implementations, and domain knowledge (robotics, math, refactoring patterns). To create a new skill, use the `create-skill` skill.

**`claude-output-styles/`** — personal output styles for Claude Code. Each style is a single `.md` file with YAML frontmatter (`name`, `description`, `keep-coding-instructions`) followed by the prose instructions. `./sync-skills.sh` symlinks both `claude-skills/*` into `~/.claude/skills/` and `claude-output-styles/*.md` into `~/.claude/output-styles/` for autodiscovery. `run.sh` calls it; run it manually after adding a new skill or style.

## Key Files

| File | Purpose |
|------|---------|
| `.functions.sh` | 400+ line shell utility library: Docker helpers (`db`, `drun`, `dsa` with GPU/X11/USB), git helpers (`gso`, `gig`), rclone/Google Drive wrappers, `aa` for persistent alias creation |
| `.bash_aliases` | Project-specific aliases and shortcuts |
| `.bash_prompt` | The only place bash-git-prompt is sourced (three fallback locations), plus the `(VIM)` tag marking a shell spawned from inside vim/nvim |
| `.bash_vars` | `EDITOR`/`GIT_EDITOR`, and `HISTCONTROL=ignoredups` overriding Ubuntu's stock `ignoreboth` |
| `.bash_tools` | Shell integration for the installed tools: PATH, zoxide `cd`, the custom fzf Ctrl-T directory-hopping widget, `grab`'s Ctrl-G, yazi's `y` wrapper |
| `.tmux.conf` | Prefix=Ctrl-Space, vim-style pane nav (hjkl / HJKL to swap), vi copy mode |
| `.visidatarc` | Two layers. (1) Clipboard transport: the syscopy commands go to `tmux load-buffer -w -` inside tmux (tmux then emits OSC 52 to the attached client) or `bin/osc52-copy` outside it, because the stock `xclip` default writes the *remote* X clipboard and a headless ssh login has neither xclip nor `$DISPLAY`. (2) A vim layer: `y` cell / `yy` row / `Y` row (a `beforeExecHooks` state machine, since a bound key can never also act as a prefix — `mainloop.py:242` before `:248`); `:` command line taking literal text (not `exec-longname`, whose Enter takes the top *fuzzy* match), with `addcol-split` relocated to `g:`; `vim-`-namespaced verbs `:vs :sp :only :e (Tab-completes paths) :E :ls :b :bn `:bp :bd :q :qa :w` — namespaced because `getCommand` chases keystroke aliases first, so a longname `e` is unreachable behind the `e` key; a real side-by-side split via a `vd.setWindows` override (upstream is stacked-only); `Ctrl+W` as a window prefix (`hjklw` swap, `v`/`s` split, `c`/`o` close, `x` exchange); `Ctrl+D`/`Ctrl+U` half-page. Every displaced binding is deliberate: `Sheet` is `TableSheet` (`sheets.py:1092`) and `addCommand` overwrites the stock slot *silently*. The keybind manual, the testing rig, and 12 traps are in `.docs_claude/plans/completed/visidata-clipboard-and-vim-keybindings.md` |
| `nvim/init.lua` | Kickstart.nvim fork — ~1350-line Lua config; read top-to-bottom to understand plugin/keymap layout. Forked from upstream at `3338d39` (2025-05-22); upstream has since dropped lazy.nvim for `vim.pack`, so it can no longer be merged — see the divergence note below |

## tmux Conventions

`Ctrl-Space` is the prefix. Pane navigation uses `hjkl`; `HJKL` swaps panes. The `trun` function (in `.functions.sh`) runs a shell function inside a new tmux window so it survives terminal close.

Inactive panes are dimmed by `window-style` (`.tmux.conf`), which recolors only the
cells an application left at default fg/bg — so it reaches nvim **only** because
catppuccin runs with `transparent_background = true` in `nvim/init.lua`. Making nvim's
colorscheme opaque silently disables pane dimming for nvim; TUIs that paint their own
background (yazi, lazygit) can't be dimmed at all. See the plan doc for the measurements.
That dim color is also load-bearing beyond looks: tmux answers an OSC 11 background query
for an inactive pane out of `window-style` instead of forwarding it, so it must stay on
the same side of light/dark as the terminal theme or every auto-theming app (nvim,
Claude Code's `"theme": "auto"`) started in an inactive pane picks the wrong mode.

`prefix + X` forks the Claude Code conversation running in the current pane into a
sibling pane (`prefix + C-x` into a new window), via `tmux-fork-claude.sh`. It resolves
pane → session ID by looking up `~/.claude/sessions/<pid>.json`, then delegates to the
`fork-conversation-pane` skill's `fork-pane.sh`, so it is the same fork the skill
performs with none of the model round trip. See the note below for the traps.

## Plans

[`.docs_claude/PLANS_TOC.md`](.docs_claude/PLANS_TOC.md) is the topic-organized index of
plan docs under `.docs_claude/plans/{active,completed}/` (plus one legacy entry at
top-level `plans/completed/`, predating that convention). Two views: a **chronological
index** (most recent first) and **topic sections**, each plan carrying a prose abstract +
a "Key changes" list.

**To find a plan, search `.docs_claude/PLANS_TOC.md` FIRST** — "which plan did X" / "when
did Y land" questions are answered by the chronological index + topic abstracts, before
grepping plan bodies or the codebase.

### Maintaining `.docs_claude/PLANS_TOC.md`

When a plan is added, copied, moved, renamed, or deleted:

1. Find it: `find . -path '*/.docs_claude/plans/*' -name '*.md'` (new plans go here; don't
   add new ones to the legacy top-level `plans/completed/`).
2. Read its title + summary to judge purpose and which area it touches.
3. Add an entry — a `###` link, a code-location line, a 2-4 sentence prose abstract, then
   a **"Key changes"** list — under every matching topic. A plan MUST appear under at
   least one topic; it MAY appear under several. If it fits no existing topic, add a new
   `## Topic` section.
4. On move/rename/delete, update or remove the existing entry/entries.
5. Also add it to the **Chronological index** — date = git creation date
   (`git log --diff-filter=A --follow --format=%as -- <path> | tail -1`; an uncommitted
   plan uses today's date). Re-sort most-recent first.

## Notes

`.docs_claude/notes/` holds findings that aren't a plan for a change — root causes,
upstream limitations, and environment behavior that would otherwise be re-derived from
scratch. They are deliberately **not** in `PLANS_TOC.md` (that indexes plans only), so
check this directory directly before re-investigating a "why is X slow / broken" question:

| Note | Answers |
|------|---------|
| `macos-shell-startup-latency.md` | Why new terminal tabs take seconds on a Mac with an exec-authorizing security agent, and why it is not the sourced files |
| `tmux-popup-clipboard-ssh.md` | Why OSC 52 copy doesn't work inside `display-popup` |
| `grab-macos-support-roadmap.md` | The four macOS sub-projects for `grab`/dotfiles and what's still open |
| `nvim-kickstart-upstream-divergence.md` | Why `nvim/` can't be merged from upstream kickstart any more, why nvim-treesitter is pinned to `master`, and the three ways out |
| `tmux-osc11-background-query.md` | Why nvim / Claude Code pick the wrong light/dark mode inside tmux: tmux answers OSC 11 from the pane's own `window-style` background rather than forwarding to the terminal |
| `claude-session-tmux-pane-lookup.md` | How a tmux pane resolves to the Claude session running in it (`~/.claude/sessions/<pid>.json`), and the four traps: `sdk-cli` one-shots, no `TMUX_PANE` under `run-shell`, `read` exiting 1 on the missing trailing newline, no `/proc` on macOS |

## Adding a New Skill

```
claude-skills/<skill-name>/SKILL.md
```

Follow the frontmatter format documented in `claude-skills/create-skill/SKILL.md`. Register the skill in `.claude/settings.local.json` if it needs special permissions.
