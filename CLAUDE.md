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

**`claude-output-styles/`** — personal output styles for Claude Code. Each style is a single `.md` file with YAML frontmatter (`name`, `description`, `keep-coding-instructions`) followed by the prose instructions. `./sync-skills.sh` symlinks both `claude-skills/*` into `~/.claude/skills/` and `claude-output-styles/*.md` into `~/.claude/output-styles/` for autodiscovery (run it manually after adding a new skill or style — it's not called from `run.sh`).

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
