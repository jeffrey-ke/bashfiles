# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Installation

```bash
./run.sh   # Creates symlinks from ~/ to ~/dotfiles/ and patches .bashrc
```

The installer is idempotent and self-contained — on a fresh machine `run.sh` alone is
enough. It initializes the submodules (`jeffrey-ke/kickstart.nvim` as `nvim/`,
`jeffrey-ke/commentstrip`), symlinks the configs, patches `.bashrc`, runs
`./sync-skills.sh`, then runs `./install-tools.sh`. Its one prerequisite is a GitHub
SSH key, since the repo and both submodule URLs are `git@github.com:`.

`./install-tools.sh` installs, into `~/.local/bin` without sudo: nvim, fd, rg, uv,
claude, git-lfs, zoxide, fzf, yazi — plus bash-git-prompt, tpm, and vim-plug. Every
entry is something a config file here depends on. Each failure warns and continues, so
an offline machine still gets its symlinks. After it runs, `:PlugInstall` in vim and
`prefix + I` in tmux fetch the actual plugins.

`ugrep` is opt-in — `./install-tools.sh ug` — because Genivia publishes no Linux
binary, so it has to compile (~1–2 min) and lands 7.x where Ubuntu's package is 5.0.
The `ug` alias and the `ugq` function are unavailable until you install it, by that
command or `apt install ugrep`. Passing any tool name as an argument installs only
those tools and skips the plugin managers.

## Repository Structure

**Dotfiles** — classic symlinked configs for bash/zsh, tmux, vim, neovim, git, and Python tooling.

**`machines/`** — hostname-keyed per-machine shell configs, resolved by
`source-machine.sh` (which `run.sh` appends to `.bashrc` once). Each `*.sh` filename is
treated as an anchored regex against `hostname -s`: the first alphabetical regex match
is sourced as a shared base, then `<exact-hostname>.sh` is layered on top so per-host
overrides win. That is why `machines/r[0-9]+.sh` exists — one base for every PSC compute
node, with `r033.sh` / `r191.sh` adding just their own path registries.

To add config for a new machine, create `machines/<hostname>.sh`. No changes to `run.sh`
needed. This is also where the per-machine path registry (`pp` / `pl` / `prm` / `to`,
implemented in `.functions.sh`) writes its marker block, so `$datasets` and friends are
deliberately machine-local and do not transfer.

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
| `nvim/init.lua` | Kickstart.nvim — 1300-line Lua config; read top-to-bottom to understand plugin/keymap layout |

## tmux Conventions

`Ctrl-Space` is the prefix. Pane navigation uses `hjkl`; `HJKL` swaps panes. The `trun` function (in `.functions.sh`) runs a shell function inside a new tmux window so it survives terminal close.

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

## Adding a New Skill

```
claude-skills/<skill-name>/SKILL.md
```

Follow the frontmatter format documented in `claude-skills/create-skill/SKILL.md`. Register the skill in `.claude/settings.local.json` if it needs special permissions.
