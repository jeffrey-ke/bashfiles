# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Installation

```bash
./run.sh   # Creates symlinks from ~/ to ~/dotfiles/ and patches .bashrc
```

The installer is idempotent. After running, manually install vim-plug then run `:PlugInstall` in vim. The nvim config is a git submodule (`jeffrey-ke/kickstart.nvim`).

## Repository Structure

**Dotfiles** — classic symlinked configs for bash/zsh, tmux, vim, neovim, git, and Python tooling.

**`machines/`** — hostname-keyed dictionary of per-machine shell configs. `run.sh` appends this to `.bashrc` once:
```bash
MACHINE_CONFIG="$HOME/dotfiles/machines/$(hostname -s).sh"
[ -f "$MACHINE_CONFIG" ] && source "$MACHINE_CONFIG"
```
To add config for a new machine, create `machines/<hostname>.sh`. No changes to `run.sh` needed.

**`claude-skills/`** — personal skill library for Claude Code. Each skill is a directory with a `SKILL.md` containing YAML frontmatter (`name`, `description`, `argument-hint`) followed by the recipe. Skills encode reusable design patterns, reference implementations, and domain knowledge (robotics, math, refactoring patterns). To create a new skill, use the `create-skill` skill.

## Key Files

| File | Purpose |
|------|---------|
| `.functions.sh` | 400+ line shell utility library: Docker helpers (`db`, `drun`, `dsa` with GPU/X11/USB), git helpers (`gso`, `gig`), rclone/Google Drive wrappers, `aa` for persistent alias creation |
| `.bash_aliases` | Project-specific aliases and shortcuts |
| `.bash_prompt` | Bash/zsh detection, Docker tag in prompt, git prompt, VI-mode indicator |
| `.tmux.conf` | Prefix=Ctrl-Space, vim-style pane nav (hjkl / HJKL to swap), vi copy mode |
| `nvim/init.lua` | Kickstart.nvim — 1300-line Lua config; read top-to-bottom to understand plugin/keymap layout |

## tmux Conventions

`Ctrl-Space` is the prefix. Pane navigation uses `hjkl`; `HJKL` swaps panes. The `trun` function (in `.functions.sh`) runs a shell function inside a new tmux window so it survives terminal close.

## Adding a New Skill

```
claude-skills/<skill-name>/SKILL.md
```

Follow the frontmatter format documented in `claude-skills/create-skill/SKILL.md`. Register the skill in `.claude/settings.local.json` if it needs special permissions.
