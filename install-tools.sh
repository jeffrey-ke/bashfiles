#!/bin/bash
# Install zoxide, fzf, and yazi into ~/.local/bin — no sudo, idempotent.
# Always exits 0 so run.sh's `set -e` survives an offline machine;
# per-tool failures print a warning instead.

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:$PATH" ;; esac

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

latest_asset_url() { # <owner/repo> <asset-pattern>
	curl -sSfL "https://api.github.com/repos/$1/releases/latest" |
		grep -o '"browser_download_url": *"[^"]*"' |
		grep -o 'https://[^"]*' |
		grep -m1 "$2"
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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	for tool in zoxide fzf yazi; do
		if command -v "$tool" >/dev/null 2>&1 && "$tool" --version >/dev/null 2>&1; then
			echo "✓ $tool already installed ($("$tool" --version 2>/dev/null | head -1))"
		elif "install_$tool" >/dev/null 2>&1 && command -v "$tool" >/dev/null 2>&1 && "$tool" --version >/dev/null 2>&1; then
			echo "✓ installed $tool -> $BIN"
		else
			echo "✗ $tool install failed — re-run ./install-tools.sh later" >&2
		fi
	done

	if command -v ya >/dev/null 2>&1 && [ -f "$HOME/.config/yazi/package.toml" ]; then
		ya pkg install >/dev/null 2>&1 && echo "✓ yazi plugins installed" || echo "✗ yazi plugin install failed — re-run 'ya pkg install' later" >&2
	fi

	exit 0
fi
