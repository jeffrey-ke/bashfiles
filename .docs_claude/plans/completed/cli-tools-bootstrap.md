# CLI tool bootstrap: zoxide + fzf + yazi in new-machine setup

## Context

zoxide's `cd` replacement works on tesu, but its init line is nowhere in the repo — it was hand-added to `~/.bashrc:176` (`eval "$(zoxide init --cmd cd bash)"`), invisible to the dotfiles setup. Similarly, the fzf eval and yazi `y()` wrapper live only in `machines/tesu.sh:33-45`, so no other machine gets them. The user wants zoxide/fzf/yazi to be part of standard new-machine setup: check-and-install the binaries, and wire the shell integration.

Decisions made with the user:
1. **Install method:** user-local, no sudo — everything into `~/.local/bin` (fits the shared-Ubuntu/no-apt constraint, works on clusters, guarantees fzf ≥ 0.48 which `fzf --bash` requires).
2. **Shell integration:** a new repo file `.bash_tools`, symlinked + sourced via run.sh's existing mechanism — not pasted into each `.bashrc` (that copy-drift is exactly how the tesu hand-edit happened).
3. **run.sh** calls the installer automatically at the end (installer is idempotent; network failure warns but doesn't abort).

## Changes

### 1. New file: `~/dotfiles/.bash_tools`

Guarded integration — a no-op wherever a tool is missing. Ensure `~/.local/bin` is on PATH *first* (the installer targets it, and `.bash_tools` may be sourced before `machines/<host>.sh` PATH prepends):

```bash
#!/bin/bash
# Shell integration for CLI tools installed by install-tools.sh.
# Each block is a no-op if the tool isn't installed.

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init --cmd cd bash)"

if command -v fzf >/dev/null 2>&1; then
	eval "$(fzf --bash)"
	export FZF_COMPLETION_TRIGGER='~~'   # moved from tesu's hand-edited ~/.bashrc
fi

if command -v yazi >/dev/null 2>&1; then
	# yazi cwd-on-exit wrapper
	function y() {
		local tmp cwd
		tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
		yazi "$@" --cwd-file="$tmp"
		if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
			builtin cd -- "$cwd"
		fi
		rm -f -- "$tmp"
	}
fi
```

(`--cmd cd` is zoxide's official flag to fully replace `cd` — confirmed against the zoxide README.)

### 2. New file: `~/dotfiles/install-tools.sh`

Idempotent, no sudo, installs to `~/.local/bin`. Skips each tool if `command -v` already finds it. Never exits nonzero for a single tool failure — prints a warning and continues (run.sh has `set -e`).

- **zoxide** — official installer (targets `~/.local/bin`):
  `curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh`
- **fzf** — latest static binary from GitHub releases: query `https://api.github.com/repos/junegunn/fzf/releases/latest`, pick the `linux_${arch}` tarball (`uname -m`: x86_64→amd64, aarch64→arm64), `tar -xz` the `fzf` binary into `~/.local/bin`.
- **yazi** — latest **musl** zip from `https://api.github.com/repos/sxyazi/yazi/releases/latest` (`yazi-x86_64-unknown-linux-musl.zip`; musl avoids glibc-version issues on older cluster machines), extract `yazi` and `ya` into `~/.local/bin`. Requires `unzip` — if absent, use `python3 -m zipfile -e` as fallback.

Structure: one `install_<tool>()` function per tool + a loop; download to a `mktemp -d` workdir, clean up on exit. Print `✓ <tool> already installed (<version>)` / `✓ installed <tool>` / `✗ <tool> install failed` per tool.

### 3. Edit `~/dotfiles/run.sh`

- Add `.bash_tools` to the `files` array (line 7) → gets symlinked.
- Add `.bash_tools` to the `sources` array (line 15) → source line appended to `.bashrc` once (existing `grep -q` guard mechanism).
- At the end: `"$DOTFILES/install-tools.sh" || echo "warning: tool install failed (offline?) — re-run ./install-tools.sh later"`.

### 4. Cleanup (dedup now-redundant copies)

- `machines/tesu.sh`: delete the `y()` wrapper (lines 33–42) and `eval "$(fzf --bash)"` (line 45). Keep `alias fvim` and everything else.
- tesu's `~/.bashrc` (machine-local hand-edits, lines ~176–178): delete the zoxide eval, the `export FZF_COMPLETION_TRIGGER` line (both now in `.bash_tools`), and the duplicate `source ~/.functions.sh` line (run.sh's guarded line already covers it). Running `./run.sh` afterwards also migrates the stale `MACHINE_CONFIG` block to `source-machine.sh` (run.sh:22–26 already handles this).

## Verification

1. `bash -n install-tools.sh .bash_tools run.sh` — syntax check.
2. Run `./run.sh` on tesu. Confirm: `~/.bash_tools` symlink exists; `.bashrc` gained exactly one `source ... .bash_tools` line; `MACHINE_CONFIG` lines gone, `source-machine.sh` line present; installer reported all three tools "already installed" (zoxide/fzf/yazi exist on tesu).
3. Re-run `./run.sh` — fully idempotent, no duplicate lines appended.
4. Fresh interactive shell: `bash -ic 'type cd; type y; command -v zoxide fzf yazi'` — `cd` should be the zoxide function, `y` a function, all three binaries found.
5. Behavior: `cd <partial-dirname>` jumps via zoxide; Ctrl-R gives fzf history; `y`, navigate somewhere in yazi, quit → shell PWD followed.
6. Simulate a bare machine: `PATH=/usr/bin:/bin` with a temp `HOME` won't be practical; instead spot-check installer download logic with one tool renamed out of PATH, or at minimum verify the release-URL resolution commands print valid URLs.
