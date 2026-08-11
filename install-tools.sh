#!/bin/bash
# Install the CLI tools the shell config assumes, into ~/.local/bin — no sudo, idempotent.
# Always exits 0 so run.sh's `set -e` survives an offline machine;
# per-tool failures print a warning instead.
#
# On macOS everything except zoxide/uv/claude (whose own installers are cross-platform)
# delegates to Homebrew instead, landing in /opt/homebrew: the no-sudo direct-download
# route exists for shared/restricted Linux boxes with no package manager, a constraint
# that doesn't apply to a personal Mac, and the release-asset naming differs per
# publisher for the same CPU (fd/ripgrep say aarch64, git-lfs says arm64 and ships a
# zip) — platform detection Homebrew already does correctly. `brew shellenv` in
# .bash_tools is what puts the results on PATH.
#
# Anything referenced by .bash_aliases / .functions.sh / .bash_tools / nvim belongs
# here, otherwise a fresh clone silently loses the feature that depends on it:
#   nvim     the editor itself (efunc, envim, laa, ugq, fvim, bin/fgr, bin/pydef)
#   fd       fh, fvim, nvim telescope find_files
#   rg       the `rg` alias, nvim telescope live_grep
#   uv       shebang of bin/art, bin/run, bin/commentstrip; the `ur` alias
#   claude   haiku / opus / sonn / fab
#   git-lfs  .gitconfig sets filter.lfs.required, so LFS repos hard-fail without it
#   tmux     .tmux.conf, every tmux-*.sh, `trun`; tpm below is only its plugin manager
# plus three plugin managers whose absence half-breaks a config: bash-git-prompt
# (.bash_prompt), tpm (.tmux.conf), vim-plug (.vimrc).
#
# Usage:
#   ./install-tools.sh          the default set above, plus the plugin managers
#   ./install-tools.sh <tool>…  only the named tools (the only way to get `ug`)

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:$PATH" ;; esac

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

latest_asset_url() { # <owner/repo> <asset-pattern>
	# The pattern is anchored to the end of the URL: every caller's pattern ends at the
	# file extension, and several projects publish a checksum sibling (ripgrep ships
	# <asset>.tar.gz.sha256) that an unanchored pattern matches just as well. Without
	# the anchor the right one is picked only because the API happens to list the
	# archive before its .sha256.
	curl -sSfL "https://api.github.com/repos/$1/releases/latest" |
		grep -o '"browser_download_url": *"[^"]*"' |
		grep -o 'https://[^"]*' |
		grep -m1 "$2\$"
}

# Fetch a release tarball and install one named binary out of it, wherever it sits.
fetch_tar_bin() { # <owner/repo> <asset-pattern> <binary-name>
	local url found
	url="$(latest_asset_url "$1" "$2")" || return 1
	[ -n "$url" ] || return 1
	curl -sSfL "$url" -o "$WORKDIR/$3.tar.gz" || return 1
	rm -rf "${WORKDIR:?}/x" && mkdir -p "$WORKDIR/x"
	tar -xzf "$WORKDIR/$3.tar.gz" -C "$WORKDIR/x" || return 1
	found="$(find "$WORKDIR/x" -type f -name "$3" | head -1)"
	[ -n "$found" ] || return 1
	install -m 755 "$found" "$BIN/$3"
}

# Rust-style target triple for the running machine (musl where publishers ship it).
# Linux-only by construction — the Darwin branches above return before reaching it.
# Callers must check its status explicitly: it is used inside a command substitution,
# where a bare `$(rust_target)` throws the failure away and leaves an empty triple,
# degrading the caller's asset pattern to a bare extension that matches whichever
# archive the release happens to list first.
rust_target() {
	case "$(uname -m)" in
		x86_64) echo "x86_64-unknown-linux-musl" ;;
		aarch64) echo "aarch64-unknown-linux-gnu" ;;
		*) return 1 ;;
	esac
}

install_zoxide() {
	curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
}

install_fzf() {
	if [ "$(uname -s)" = "Darwin" ]; then
		command -v brew >/dev/null 2>&1 || return 1
		brew install fzf
		return
	fi
	local arch url
	case "$(uname -m)" in
		x86_64) arch=amd64 ;;
		aarch64) arch=arm64 ;;
		*) return 1 ;;
	esac
	url="$(latest_asset_url junegunn/fzf "linux_${arch}\.tar\.gz")" || return 1
	curl -sSfL "$url" -o "$WORKDIR/fzf.tar.gz" || return 1
	tar -xzf "$WORKDIR/fzf.tar.gz" -C "$BIN" fzf
}

install_yazi() {
	if [ "$(uname -s)" = "Darwin" ]; then
		command -v brew >/dev/null 2>&1 || return 1
		brew install yazi
		return
	fi
	# musl build: static, no glibc-version headaches on older machines
	local arch url bin
	case "$(uname -m)" in
		x86_64 | aarch64) arch="$(uname -m)" ;;
		*) return 1 ;;
	esac
	url="$(latest_asset_url sxyazi/yazi "${arch}-unknown-linux-musl\.zip")" || return 1
	curl -sSfL "$url" -o "$WORKDIR/yazi.zip" || return 1
	if command -v unzip >/dev/null 2>&1; then
		unzip -q -o "$WORKDIR/yazi.zip" -d "$WORKDIR/yazi" || return 1
	else
		python3 -m zipfile -e "$WORKDIR/yazi.zip" "$WORKDIR/yazi" || return 1
	fi
	for tool in yazi ya; do
		bin="$(find "$WORKDIR/yazi" -maxdepth 2 -name "$tool" -type f | head -1)"
		[ -n "$bin" ] && install -m 755 "$bin" "$BIN/$tool"
	done
	[ -x "$BIN/yazi" ]
}

# Unpacked as a tree (nvim needs its runtime/ next to the binary), then symlinked.
install_nvim() {
	if [ "$(uname -s)" = "Darwin" ]; then
		command -v brew >/dev/null 2>&1 || return 1
		brew install neovim
		return
	fi
	local arch url
	case "$(uname -m)" in
		x86_64) arch=x86_64 ;;
		aarch64) arch=arm64 ;;
		*) return 1 ;;
	esac
	url="$(latest_asset_url neovim/neovim "nvim-linux-${arch}\.tar\.gz")" || return 1
	[ -n "$url" ] || return 1
	curl -sSfL "$url" -o "$WORKDIR/nvim.tar.gz" || return 1
	rm -rf "$HOME/.local/nvim" && mkdir -p "$HOME/.local/nvim"
	tar -xzf "$WORKDIR/nvim.tar.gz" -C "$HOME/.local/nvim" --strip-components=1 || return 1
	ln -sf "$HOME/.local/nvim/bin/nvim" "$BIN/nvim"
}

install_fd() {
	if [ "$(uname -s)" = "Darwin" ]; then
		command -v brew >/dev/null 2>&1 || return 1
		brew install fd
		return
	fi
	local target
	target="$(rust_target)" || return 1
	fetch_tar_bin sharkdp/fd "$target\.tar\.gz" fd
}

install_rg() {
	if [ "$(uname -s)" = "Darwin" ]; then
		command -v brew >/dev/null 2>&1 || return 1
		# Formula name differs from the binary the dispatch loop verifies (`rg`).
		brew install ripgrep
		return
	fi
	local target
	target="$(rust_target)" || return 1
	fetch_tar_bin BurntSushi/ripgrep "$target\.tar\.gz" rg
}

# Opt-in only (`./install-tools.sh ug`). Genivia publishes no Linux binary — the
# latest release ships a Windows zip and nothing else — so the choice is compiling
# from source or `sudo apt install ugrep`. This compiles, which takes ~1–2 min and
# lands a newer major version than Ubuntu's package (7.x vs 5.0), so `ugq`'s -Q TUI
# behavior is worth a check afterward. Left out of the default set for both reasons.
install_ug() {
	command -v gcc >/dev/null 2>&1 || return 1
	git clone --depth 1 https://github.com/Genivia/ugrep "$WORKDIR/ugrep" || return 1
	(cd "$WORKDIR/ugrep" && ./build.sh --prefix="$HOME/.local" && make install)
}

install_uv() {
	curl -LsSf https://astral.sh/uv/install.sh | sh
}

install_claude() {
	curl -fsSL https://claude.ai/install.sh | bash
}

# The one tool with no no-sudo Linux route: tmux/tmux publishes source tarballs only,
# and building it wants libevent + ncurses headers. Ubuntu ships it preinstalled or a
# `sudo apt install tmux` away, so the loop's first gate covers Linux in practice and
# the note after the loop covers the rest. macOS ships no tmux at all — the gap that
# left `tpm` cloned and `.tmux.conf` symlinked next to a `tmux: command not found`.
install_tmux() {
	if [ "$(uname -s)" = "Darwin" ]; then
		command -v brew >/dev/null 2>&1 || return 1
		brew install tmux
		return
	fi
	return 1
}

install_git_lfs() {
	if [ "$(uname -s)" = "Darwin" ]; then
		command -v brew >/dev/null 2>&1 || return 1
		brew install git-lfs
		return
	fi
	local arch
	case "$(uname -m)" in
		x86_64) arch=amd64 ;;
		aarch64) arch=arm64 ;;
		*) return 1 ;;
	esac
	# No `git lfs install`: .gitconfig already carries the filter block, and running
	# it would rewrite the symlinked, git-tracked .gitconfig.
	fetch_tar_bin git-lfs/git-lfs "linux-${arch}-v.*\.tar\.gz" git-lfs
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	# No arguments: the default set. Arguments: exactly those tools, and skip the
	# plugin managers — that path exists to install one thing (usually `ug`).
	if [ "$#" -gt 0 ]; then
		tools=("$@")
	else
		tools=(zoxide fzf yazi nvim fd rg uv claude git-lfs tmux)
	fi

	# Run the tool to prove it actually executes — the check that catches a
	# wrong-platform binary, which `command -v` alone reports as present. The flag isn't
	# universal: tmux only understands -V and exits non-zero on --version, which read as
	# "install failed" for a tmux that was sitting right there on PATH.
	tool_version() {
		case "$1" in
			tmux) "$1" -V ;;
			*) "$1" --version ;;
		esac
	}

	for tool in "${tools[@]}"; do
		if ! declare -F "install_${tool//-/_}" >/dev/null; then
			echo "✗ no installer for '$tool'" >&2
			continue
		fi
		if command -v "$tool" >/dev/null 2>&1 && tool_version "$tool" >/dev/null 2>&1; then
			echo "✓ $tool already installed ($(tool_version "$tool" 2>/dev/null | head -1))"
		elif "install_${tool//-/_}" >/dev/null 2>&1 && command -v "$tool" >/dev/null 2>&1 && tool_version "$tool" >/dev/null 2>&1; then
			echo "✓ installed $tool -> $(command -v "$tool")"
		else
			echo "✗ $tool install failed — re-run ./install-tools.sh later" >&2
		fi
	done

	if [ "$#" -gt 0 ]; then
		exit 0
	fi

	command -v ug >/dev/null 2>&1 ||
		echo "· ug not installed (opt-in: ./install-tools.sh ug builds it from source, or apt install ugrep)"

	# The generic per-tool failure line says "re-run later", which is wrong for tmux on
	# Linux — re-running can't help without a package manager.
	command -v tmux >/dev/null 2>&1 ||
		echo "· tmux needs a package manager: brew install tmux, or sudo apt install tmux"

	# Plugin managers: each is a plain git clone / file drop into a fixed location
	# that the matching config already looks for.
	clone_once() { # <label> <repo-url> <dest>
		if [ -d "$3" ]; then
			echo "✓ $1 already installed"
		elif git clone --depth 1 "$2" "$3" >/dev/null 2>&1; then
			echo "✓ installed $1 -> $3"
		else
			echo "✗ $1 install failed — re-run ./install-tools.sh later" >&2
		fi
	}
	clone_once bash-git-prompt https://github.com/magicmonty/bash-git-prompt.git "$HOME/.bash-git-prompt"
	clone_once tpm https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"

	if [ -f "$HOME/.vim/autoload/plug.vim" ]; then
		echo "✓ vim-plug already installed"
	elif curl -sSfL --create-dirs -o "$HOME/.vim/autoload/plug.vim" \
		https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim; then
		echo "✓ installed vim-plug (run :PlugInstall in vim)"
	else
		echo "✗ vim-plug install failed — re-run ./install-tools.sh later" >&2
	fi

	if command -v ya >/dev/null 2>&1 && [ -f "$HOME/.config/yazi/package.toml" ]; then
		ya pkg install >/dev/null 2>&1 && echo "✓ yazi plugins installed" || echo "✗ yazi plugin install failed — re-run 'ya pkg install' later" >&2
	fi

	exit 0
fi
