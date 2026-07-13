# `grab`/dotfiles: cross-platform install/bootstrap

## Goal

Sub-project 3 of 4 in
[grab-macos-support-roadmap.md](../../notes/grab-macos-support-roadmap.md)
(macOS cross-platform support for `grab`). Three bundled issues that block
`grab` (and the other `bin/` tools) from landing on a fresh Mac at all,
independent of `grab`'s own code:

1. `~/.local/bin/grab`'s symlink is manual/undocumented — nothing in
   `run.sh` or `install-tools.sh` creates it (same for `art`/`fgr`/
   `pydef`/`commentstrip`).
2. `install-tools.sh`'s `install_fzf`/`install_yazi` hardcode Linux-only
   GitHub release asset patterns. On Apple Silicon this fails honestly
   (arch mismatch); on Intel Mac it's worse — `x86_64` still maps
   correctly, downloads the **Linux** binary, `command -v fzf` succeeds,
   the script reports "✓ installed" — but the binary can't execute.
3. `run.sh:26` — `sed -i '/MACHINE_CONFIG/d' "$BASHRC"` is GNU-only syntax
   (BSD/macOS `sed -i` requires an explicit suffix argument). This is what
   actually crashes `run.sh` outright on a Mac (`set -e` at the top), before
   it ever reaches `install-tools.sh`.

## Design

### 1. `run.sh` — symlink `bin/`'s user commands

Add a loop, using the same `ln -sf` idiom the file already uses for
`nvim`/`yazi`, restricted to `bin/`'s **extensionless executable** files —
confirmed this filter matches exactly the current manually-symlinked set
(`art`, `commentstrip`, `fgr`, `grab`, `pydef`, `run`), correctly excluding
`fgr.lua`/`pydef.lua` (executable, but implementation details invoked by
their sibling launcher via the script's own directory, not meant to be run
by name) and `registry.py`/`telescope_boot.lua` (not executable, not
user-facing):

```bash
mkdir -p "$HOME/.local/bin"
for f in "$DOTFILES"/bin/*; do
	[ -f "$f" ] && [ -x "$f" ] || continue
	case "$(basename "$f")" in *.*) continue ;; esac
	ln -sf "$f" "$HOME/.local/bin/$(basename "$f")"
done
```

**Ordering note (found during self-review):** `install-tools.sh`, called
at the very end of `run.sh`, is the only place that currently does
`mkdir -p "$HOME/.local/bin"` — but this new loop runs earlier in
`run.sh`, alongside the other symlink loops, so it must create the
directory itself rather than relying on that later call.

### 2. `run.sh` — portable `sed -i`

```bash
sed -i.bak '/MACHINE_CONFIG/d' "$BASHRC" && rm -f "$BASHRC.bak"
```
`-i.bak` (suffix attached directly, no space) is accepted identically by
GNU and BSD sed — no `uname`/OS branching needed, same portable-by-
construction approach as the `tac`→`rev_lines` fix in sub-project 1.

### 3. `install-tools.sh` — Homebrew on Darwin instead of GitHub-release URLs

Considered and rejected: replicating the Linux GitHub-release-download
approach with Darwin-specific asset URL patterns (`darwin_amd64`/
`darwin_arm64` for fzf, `x86_64-apple-darwin`/`aarch64-apple-darwin` for
yazi — note yazi's Apple-Silicon asset name, `aarch64`, doesn't match
macOS's own `uname -m` output, `arm64`, requiring an explicit,
non-obvious mapping). This works but is strictly more code, more
fragile (exactly the asset-naming traps just found), and duplicates
platform-detection Homebrew already does correctly. The existing script's
own header — "no sudo, idempotent" — motivates the direct-download
approach on Linux (useful on shared/restricted machines with no package
manager), but that constraint doesn't hold on a personal Mac, where
Homebrew is already the standard tool (and this repo already has a
precedent: `.bash_prompt` has an existing "Mac: brew install
bash-git-prompt" hint).

Chosen instead: branch on `uname -s = Darwin` and shell out to Homebrew:

```bash
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
```
`install_zoxide` is unchanged — its installer (`ajeetdsouza/zoxide`'s
official `install.sh`) already handles macOS correctly.

### 4. `install-tools.sh` — verify the binary actually runs

The install loop's success check currently only tests `command -v
"$tool"` (present on `PATH`), which is exactly what let the Intel-Mac
false-success bug through — a non-executable Linux binary is still
"present." Change the check to also invoke the tool:

```bash
for tool in zoxide fzf yazi; do
	if command -v "$tool" >/dev/null 2>&1 && "$tool" --version >/dev/null 2>&1; then
		echo "✓ $tool already installed ($("$tool" --version 2>/dev/null | head -1))"
	elif "install_$tool" >/dev/null 2>&1 && command -v "$tool" >/dev/null 2>&1 && "$tool" --version >/dev/null 2>&1; then
		echo "✓ installed $tool -> $BIN"
	else
		echo "✗ $tool install failed — re-run ./install-tools.sh later" >&2
	fi
done
```
This closes the false-success failure mode generally (any future
platform/arch mismatch, not just this one), not just for Darwin.

## Files touched

- `~/dotfiles/run.sh` — symlink loop (item 1), portable `sed -i` (item 2)
- `~/dotfiles/install-tools.sh` — Darwin brew branches (item 3),
  binary-runs verification (item 4)

## Verification plan

- On this Linux machine: `bash -n run.sh` and `bash -n install-tools.sh`
  (syntax check) — both fixes touch bash-3.2-safe/POSIX-portable syntax,
  no new bashisms introduced.
- Re-run `run.sh` on this machine (Linux/tesu): symlink loop creates/
  updates `~/.local/bin/{art,commentstrip,fgr,grab,pydef,run}` correctly
  (matches the already-manually-created symlinks, `ln -sf` is idempotent);
  `sed -i.bak` migration still removes any `MACHINE_CONFIG` line and
  cleans up its own `.bak` file; `install-tools.sh` still installs/
  verifies zoxide/fzf/yazi exactly as before (Darwin branch untaken on
  Linux, so this exercises the "existing Linux path unchanged" claim).
- `grep -c 'sed -i ' run.sh` after the fix shows the corrected `-i.bak`
  form, not the old bare `-i`.
- macOS verification (Darwin branches, brew install, bin/ symlink loop on
  a real Mac) is out of scope for this sub-project in this session — no
  Mac available — same open-item pattern as sub-project 1. Note this in
  the roadmap, don't move the plan to `completed/` until it's actually
  run on `jeffpro`.
