---
name: tmux
description: Reference for tmux's data model, command system, quoting rules, and configuration patterns. Use when writing or debugging tmux config, bind-key commands, run-shell scripts, or format strings.
argument-hint: [optional: describe what you're configuring or debugging]
---

# tmux — Program and Data Model

## Object Hierarchy

tmux is a client-server terminal multiplexer. The server owns all state; clients attach to view and interact with it.

```
server (one per socket, usually one per user)
  └── session (named group of windows)
        └── window (a tab within a session, has a layout)
              └── pane (a single terminal instance)
```

- **Server** — The persistent process. Survives client disconnection. Owns all sessions, windows, panes. Started implicitly by `tmux new-session` or explicitly with `tmux start-server`.
- **Session** — A named collection of windows. Each client is attached to exactly one session. Sessions persist until explicitly killed or the last window closes.
- **Window** — A tab within a session. Has a layout (how its panes are arranged) and a name. Windows are numbered per-session (the index can have gaps).
- **Pane** — A single pseudo-terminal. Runs one shell or process. Panes are numbered per-window starting at 0.

### Target Syntax

Most commands accept a target to identify a session, window, or pane:

```
-t session_name           # target a session
-t session:window         # target a window (by index or name)
-t session:window.pane    # target a specific pane
-t :window                # window in current session
-t :.pane                 # pane in current window
-t !                      # last active window
-t +                      # next window
-t -                      # previous window
```

Special tokens: `$` = current session, `@` = current window, `%` prefix = pane ID (global).

## Command System

tmux commands can be run from:
1. **Shell** — `tmux command args...`
2. **Config file** — one command per line in `.tmux.conf`
3. **Command prompt** — `prefix :` then type a command
4. **Key bindings** — `bind-key` associates a key with one or more commands

### Command Sequencing

Commands in a binding are separated by `\;` (escaped semicolon):

```
bind-key x kill-pane \; display-message "pane killed"
```

Without the backslash, the shell or tmux parser treats `;` as a line terminator.

### Blocking vs Background

- `run-shell "cmd"` — blocks the command queue until the shell command finishes
- `run-shell -b "cmd"` — runs in background, queue continues immediately
- `command-prompt` and `confirm-before` — block by default (since tmux 3.2+)

When chaining with `\;`, a blocking command delays subsequent commands. Use `-b` when the result isn't needed before the next command runs.

## Quoting and Format Expansion

This is the single most error-prone area of tmux configuration. There are three quoting styles, each with different expansion rules:

### Double Quotes `"..."`

- tmux **expands** format variables: `#I`, `#W`, `#S`, `#{...}`
- tmux **expands** environment variables: `$HOME`
- Backslash escapes work: `\"`, `\\`, `\;`, `\$`

### Single Quotes `'...'`

- Documented as "literal" but **`run-shell` still expands format variables inside single-quoted arguments**
- Safe from shell interpretation but NOT safe from tmux format expansion in `run-shell`

### Braces `{...}`

- Text inside is taken literally without replacements
- Supports line continuation (can span multiple lines)
- Designed for passing groups of tmux or shell commands as arguments (e.g., to `if-shell`)
- Note: historically had bugs with `run-shell` (issue #2841, fixed in ~3.3)

### The Critical Rule for `run-shell`

**`run-shell` always expands tmux format variables in its argument, regardless of quoting style.** To pass a literal `#X` through to the shell, you must double the hash:

```
# WRONG — tmux expands #I and #W before the shell sees them
run-shell 'tmux list-windows -F "#I:#W"'

# RIGHT — ## produces literal # after tmux expansion
run-shell 'tmux list-windows -F "##I:##W"'
```

This applies to all format sequences: `##I` (window index), `##W` (window name), `##S` (session name), `##{...}` (conditional formats), etc.

### Format Strings

Formats are tmux's variable/expression system. They appear wherever tmux expands strings (status line, `display-message`, `list-windows -F`, `if-shell` conditions, etc.).

```
#S                  — session name
#I                  — window index
#W                  — window name
#P                  — pane index
#T                  — pane title
#{pane_current_path} — long-form variable
#{?condition,true,false} — conditional
#{==:#{a},#{b}}     — comparison
#(shell-command)    — output of shell command (cached, re-run periodically)
```

The `#()` form runs a shell command and substitutes its stdout. It's cached and re-evaluated periodically (useful in status-line formats). It does NOT run on every keystroke.

## Key Binding Model

```
bind-key [-n] [-T table] key command [args...]
```

- **Prefix table** (default) — key is pressed after the prefix key (e.g., `C-Space`)
- **Root table** (`-n` or `-T root`) — key fires without prefix (use carefully)
- **Copy-mode tables** (`-T copy-mode-vi`, `-T copy-mode`) — active during copy mode

Key names: `C-x` (ctrl), `M-x` (alt/meta), `S-x` (shift for special keys), `F1`-`F12`, `Up`/`Down`/`Left`/`Right`, `Enter`, `Space`, `BSpace`, `Tab`, `DC` (delete), `IC` (insert), `NPage`/`PPage` (page down/up).

## Configuration Patterns

### Dynamic Prompts with Window/Session Lists

The proven pattern for showing a dynamic list in a `command-prompt`:

```
# Build window list in shell, pass to command-prompt
bind-key X run-shell 'wins=$(tmux list-windows -F "##I:##W" \
  | tr "\n" "|" | sed "s/|$//; s/|/ | /g"); \
  tmux command-prompt -p "[$wins] Prompt:" "some-command \"%%\""'
```

Key points:
- `##I:##W` — double hash to survive `run-shell` format expansion
- `tr` + `sed` for joining — `paste -sd " | "` does NOT produce ` | ` separators (it cycles through ` `, `|`, ` ` as individual delimiter characters)
- `%%` — `command-prompt`'s placeholder, replaced with user input
- `\"%%\"` — escaped quotes so tmux passes `"user_input"` to the command

### Dynamic Menus

For selection (rather than free-text input), `display-menu` is often better:

```
# Build a menu from session list
bind-key S run-shell 'tmux list-sessions -F "##S" \
  | awk '\''BEGIN{ORS=" "}{print $1, NR, "\"switch-client -t " $1 "\""}'\'' \
  | xargs tmux display-menu -T "Switch session"'
```

`display-menu` takes triplets: `name key command`. The user navigates with arrows or presses the shortcut key.

### Environment and Options

```
# Server options
set -g option value          # -g = global (server-wide)
set -s option value          # -s = server option

# Session options
set option value             # current session

# Window options
set -w option value          # current window
set -wg option value         # global window default

# User options (arbitrary key-value storage)
set -g @myvar "hello"        # set
display-message "#{@myvar}"  # read in format string
```

User options (prefixed with `@`) are useful for communication between `run-shell` scripts and format strings: set the value in a shell command, read it in a format expansion.

### Conditional Execution

```
# if-shell runs a shell command; branches on exit code
if-shell "command -v fzf" {
  bind-key f run-shell "fzf-tmux"
} {
  bind-key f choose-tree
}

# Format conditionals (inline, for status line etc.)
#{?window_zoomed_flag,ZOOMED,}
```

## Common Pitfalls

1. **`#` eaten by `run-shell`** — Always use `##` for literal `#` in `run-shell` arguments. This is the most common tmux scripting bug.

2. **`paste -sd " | "` doesn't join with ` | `** — It cycles through space, pipe, space as separate delimiters. Use `tr "\n" "|" | sed "s/|$//; s/|/ | /g"` instead.

3. **`\;` vs `;`** — In config files, `\;` separates commands in a binding. A bare `;` ends the line. In shell (`tmux bind ...`), you often need `\\;` because the shell eats one backslash.

4. **`run-shell -b` with interactive commands** — Background `run-shell` works with `command-prompt` and `display-menu` because those are tmux commands that register their own input handlers.

5. **Format expansion timing** — Formats in `bind-key` arguments are expanded when the key is pressed, not when the config is loaded. But `run-shell` arguments are expanded once at execution time, then passed to the shell.

6. **Nested tmux commands** — When `run-shell` calls `tmux command-prompt`, the inner tmux command connects to the same server as a client command. Format expansion in the inner command is independent of the outer `run-shell` expansion.