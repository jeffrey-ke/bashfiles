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

---

# `grab`/dotfiles install-bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `run.sh` symlink `bin/`'s user commands and survive on BSD sed; make `install-tools.sh` install fzf/yazi via Homebrew on Darwin and verify installed binaries actually run.

**Architecture:** Two independent tasks, one per file. Task 1 edits `run.sh` (symlink loop + portable `sed -i`). Task 2 edits `install-tools.sh` (Darwin branches in `install_fzf`/`install_yazi` + a stronger success check in the main install loop).

**Tech Stack:** bash, POSIX sed (`-i.bak` suffix form), `uname -s`/`uname -m` platform detection, Homebrew (Darwin only).

## Global Constraints

- No macOS hardware available in this session — every mechanism must be proven via mock/fixture tests on this Linux machine (fake `uname`/`brew`, fixture directories), not asserted. Real macOS/Homebrew behavior remains an explicitly open item; do not claim it as verified.
- The symlink loop must match exactly `art`, `commentstrip`, `fgr`, `grab`, `pydef`, `run` — no more, no less (extensionless executable files in `bin/`).
- `install_zoxide` and the existing Linux paths in `install_fzf`/`install_yazi` must be byte-for-byte unchanged — this is an additive Darwin branch, not a rewrite.
- The `sed -i` fix must use the `-i.bak` suffix form (no OS detection) — same portable-by-construction approach as sub-project 1's `rev_lines()`.

---

### Task 1: `run.sh` — symlink `bin/` + portable `sed -i`

**Files:**
- Modify: `~/dotfiles/run.sh:13-16` (insert the new symlink loop after the existing `yazi` config symlink block)
- Modify: `~/dotfiles/run.sh:26` (the `sed -i` migration line)

**Interfaces:** None — `run.sh` is a standalone bootstrap script, no functions consumed by or exposed to Task 2.

- [ ] **Step 1: Write the failing test — bin/ symlink loop**

```bash
mkdir -p /tmp/grab-tests
cat > /tmp/grab-tests/test_bin_symlinks.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

WORK=$(mktemp -d)
mkdir -p "$WORK/bin" "$WORK/fakehome"
touch "$WORK/bin/art" "$WORK/bin/commentstrip" "$WORK/bin/fgr" "$WORK/bin/grab" "$WORK/bin/pydef" "$WORK/bin/run"
touch "$WORK/bin/fgr.lua" "$WORK/bin/pydef.lua" "$WORK/bin/telescope_boot.lua" "$WORK/bin/registry.py"
chmod +x "$WORK/bin/art" "$WORK/bin/commentstrip" "$WORK/bin/fgr" "$WORK/bin/grab" "$WORK/bin/pydef" "$WORK/bin/run" "$WORK/bin/fgr.lua" "$WORK/bin/pydef.lua"
mkdir -p "$WORK/bin/__pycache__"

DOTFILES="$WORK" HOME="$WORK/fakehome" bash "$1"

fail=0
got=$(ls "$WORK/fakehome/.local/bin/" 2>/dev/null | sort)
want=$'art\ncommentstrip\nfgr\ngrab\npydef\nrun'
if [ "$got" = "$want" ]; then
	echo "PASS: bin/ symlink loop creates exactly the right set"
else
	echo "FAIL: bin/ symlink loop"
	echo "--- got ---"; echo "$got"
	echo "--- want ---"; echo "$want"
	fail=1
fi

rm -rf "$WORK"
exit $fail
EOF
chmod +x /tmp/grab-tests/test_bin_symlinks.sh
```

This test runs a standalone snippet file (Step 3 extracts just the new
loop into its own file so it can be tested in isolation without running
all of `run.sh`, which touches real `$HOME` files like `.bashrc`).

- [ ] **Step 2: Run test to verify it fails**

```bash
cat > /tmp/grab-tests/binloop_snippet.sh <<'EOF'
mkdir -p "$HOME/.local/bin"
EOF
bash /tmp/grab-tests/test_bin_symlinks.sh /tmp/grab-tests/binloop_snippet.sh
```
Expected: FAIL — `got` is empty (nothing symlinked yet), `want` lists the 6 tools.

- [ ] **Step 3: Write the implementation**

In `~/dotfiles/run.sh`, after line 16 (`ln -sf "$DOTFILES/yazi" "$HOME/.config/yazi"`), insert:

```bash

mkdir -p "$HOME/.local/bin"
for f in "$DOTFILES"/bin/*; do
	[ -f "$f" ] && [ -x "$f" ] || continue
	case "$(basename "$f")" in *.*) continue ;; esac
	ln -sf "$f" "$HOME/.local/bin/$(basename "$f")"
done
```

Also update the standalone test snippet to match:
```bash
cat > /tmp/grab-tests/binloop_snippet.sh <<'EOF'
mkdir -p "$HOME/.local/bin"
for f in "$DOTFILES"/bin/*; do
	[ -f "$f" ] && [ -x "$f" ] || continue
	case "$(basename "$f")" in *.*) continue ;; esac
	ln -sf "$f" "$HOME/.local/bin/$(basename "$f")"
done
EOF
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash /tmp/grab-tests/test_bin_symlinks.sh /tmp/grab-tests/binloop_snippet.sh
```
Expected: `PASS: bin/ symlink loop creates exactly the right set`
(Verified in planning — this exact fixture/snippet pair, run during
brainstorming, produced exactly this result.)

- [ ] **Step 5: Write the failing test — portable `sed -i`**

```bash
cat > /tmp/grab-tests/test_sed_portable.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

WORK=$(mktemp -d)
cat > "$WORK/bashrc_test" <<'RCEOF'
# some existing content
export PATH="/usr/bin:$PATH"
# MACHINE_CONFIG block start
[ "$(hostname)" = "oldmachine" ] && export SOME_VAR=1
# MACHINE_CONFIG block end
source ~/.bash_aliases
RCEOF

BASHRC="$WORK/bashrc_test"
bash "$1" "$BASHRC"

fail=0
if grep -q MACHINE_CONFIG "$BASHRC"; then
	echo "FAIL: MACHINE_CONFIG line(s) still present"
	fail=1
else
	echo "PASS: MACHINE_CONFIG line(s) removed"
fi
if [ -f "$BASHRC.bak" ]; then
	echo "FAIL: leftover .bak file"
	fail=1
else
	echo "PASS: no leftover .bak file"
fi

rm -rf "$WORK"
exit $fail
EOF
chmod +x /tmp/grab-tests/test_sed_portable.sh

cat > /tmp/grab-tests/sed_snippet.sh <<'EOF'
sed -i '/MACHINE_CONFIG/d' "$1"
EOF
```

- [ ] **Step 6: Run test to verify it fails**

```bash
bash /tmp/grab-tests/test_sed_portable.sh /tmp/grab-tests/sed_snippet.sh
```
Expected: this actually PASSes on this machine's GNU sed (the bug is BSD-sed-specific and can't be reproduced on Linux) — GNU `sed -i` with no suffix already works, so this "RED" step is really confirming the *old* behavior is fine on GNU, setting up a clean before/after rather than a true failure. Note this explicitly rather than forcing an artificial failure: the portability bug only manifests on BSD sed, which isn't available to test against directly (see Global Constraints).

- [ ] **Step 7: Write the implementation**

In `~/dotfiles/run.sh`, replace line 26:
```bash
sed -i '/MACHINE_CONFIG/d' "$BASHRC"
```
with:
```bash
sed -i.bak '/MACHINE_CONFIG/d' "$BASHRC" && rm -f "$BASHRC.bak"
```

Update the test snippet:
```bash
cat > /tmp/grab-tests/sed_snippet.sh <<'EOF'
sed -i.bak '/MACHINE_CONFIG/d' "$1" && rm -f "$1.bak"
EOF
```

- [ ] **Step 8: Run test to verify it passes**

```bash
bash /tmp/grab-tests/test_sed_portable.sh /tmp/grab-tests/sed_snippet.sh
```
Expected:
```
PASS: MACHINE_CONFIG line(s) removed
PASS: no leftover .bak file
```
(Verified in planning — this exact fixture, run during brainstorming,
produced exactly this result on this machine's GNU sed. BSD sed behavior
is not verified — see Global Constraints.)

- [ ] **Step 9: Syntax-check the real file and commit**

```bash
bash -n ~/dotfiles/run.sh
cd ~/dotfiles
git add run.sh
git commit -m "run.sh: symlink bin/'s user commands, fix sed -i portability"
```
Expected: `bash -n` prints nothing (valid syntax).

---

### Task 2: `install-tools.sh` — Darwin brew branches + binary-runs check

**Files:**
- Modify: `~/dotfiles/install-tools.sh:24-34` (`install_fzf`)
- Modify: `~/dotfiles/install-tools.sh:36-55` (`install_yazi`)
- Modify: `~/dotfiles/install-tools.sh:57-65` (the install loop's success check)

**Interfaces:** None — `install_fzf`/`install_yazi` keep their existing no-argument, return-code-only contract; the install loop keeps calling them the same way.

- [ ] **Step 1: Write the failing test — Darwin branch control flow**

```bash
cat > /tmp/grab-tests/test_darwin_branch.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$1"

rm -f /tmp/grab-tests/brew_calls.log
uname() { [ "$1" = "-s" ] && echo "Darwin"; }
brew() { echo "MOCK BREW CALLED WITH: $*" >> /tmp/grab-tests/brew_calls.log; }
export -f uname brew

install_fzf >/dev/null 2>&1
install_yazi >/dev/null 2>&1

fail=0
got=$(cat /tmp/grab-tests/brew_calls.log 2>/dev/null)
want=$'MOCK BREW CALLED WITH: install fzf\nMOCK BREW CALLED WITH: install yazi'
if [ "$got" = "$want" ]; then
	echo "PASS: Darwin branch dispatches to brew install for both tools"
else
	echo "FAIL: Darwin branch"
	echo "--- got ---"; echo "$got"
	echo "--- want ---"; echo "$want"
	fail=1
fi

rm -f /tmp/grab-tests/brew_calls.log
exit $fail
EOF
chmod +x /tmp/grab-tests/test_darwin_branch.sh
```

Note: this sources `install-tools.sh` itself, which means its top-level
code (the `for tool in zoxide fzf yazi; do ... done` loop and the final
`exit 0`) would also run on `source`. To make the functions sourceable in
isolation for testing, Step 3 wraps that top-level execution in the same
`if [ "${BASH_SOURCE[0]}" = "$0" ]; then ... fi` guard `bin/grab` already
uses (see `grab-screen-word-completion.md` Task 1) — this is a new,
small structural change beyond the spec's literal diff, needed to make
this test possible; call it out in the self-review below.

- [ ] **Step 2: Run test to verify it fails**

```bash
bash /tmp/grab-tests/test_darwin_branch.sh ~/dotfiles/install-tools.sh
```
Expected: FAIL — no Darwin branch exists yet, so `install_fzf`/
`install_yazi` fall into their Linux `case "$(uname -m)"` logic instead
(and since `uname` is mocked to only understand `-s`, `uname -m` returns
nothing, hitting the `*) return 1 ;;` case) — `brew_calls.log` stays
empty, `got` is empty, not matching `want`.

- [ ] **Step 3: Write the implementation**

In `~/dotfiles/install-tools.sh`, replace `install_fzf` and `install_yazi`:
```bash
install_fzf() {
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
with:
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

And wrap the file's top-level execution (everything from the `for tool in
zoxide fzf yazi; do` loop through the final `exit 0`) in a run-as-script
guard, so the functions above can be `source`d for testing without
triggering a real install run — replace:
```bash
for tool in zoxide fzf yazi; do
	if command -v "$tool" >/dev/null 2>&1; then
		echo "✓ $tool already installed ($("$tool" --version 2>/dev/null | head -1))"
	elif "install_$tool" >/dev/null 2>&1 && command -v "$tool" >/dev/null 2>&1; then
		echo "✓ installed $tool -> $BIN"
	else
		echo "✗ $tool install failed — re-run ./install-tools.sh later" >&2
	fi
done

if command -v ya >/dev/null 2>&1 && [ -f "$HOME/.config/yazi/package.toml" ]; then
	ya pkg install >/dev/null 2>&1 && echo "✓ yazi plugins installed" || echo "✗ yazi plugin install failed — re-run 'ya pkg install' later" >&2
fi

exit 0
```
with:
```bash
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
```
(This also folds in the binary-runs check from the spec's item 4 — note
`&& "$tool" --version >/dev/null 2>&1` added to both branches of the
`if`/`elif`.)

**Guard verified in planning**, applying this exact transformation to a
scratch copy of the real file:

```bash
bash -c "source /path/to/modified/install-tools.sh; type install_fzf"
```
→ sources cleanly, no install ran, `install_fzf` is defined (confirms
sourcing is now safe for testing).

```bash
bash /path/to/modified/install-tools.sh
```
→ `✓ zoxide already installed (zoxide 0.9.9)`, `✓ fzf already installed
(0.70 (conda-forge))`, `✓ yazi already installed (Yazi 26.5.6 ...)`, `✓
yazi plugins installed` — direct execution behaves identically to the
unmodified file, including the new `--version` check passing for all
three already-installed tools.

- [ ] **Step 4: Run test to verify it passes**

```bash
bash /tmp/grab-tests/test_darwin_branch.sh ~/dotfiles/install-tools.sh
```
Expected: `PASS: Darwin branch dispatches to brew install for both tools`
(Verified in planning — this exact mocked `uname`/`brew` test, run during
brainstorming, produced exactly this result.)

- [ ] **Step 5: Write and run the Linux-path-unaffected test**

```bash
cat > /tmp/grab-tests/test_linux_path.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$1"

got=$(uname -s)
if [ "$got" = "Linux" ]; then
	echo "PASS: real uname -s on this machine is Linux (Darwin branch untaken by construction)"
else
	echo "SKIP: not running on Linux, can't confirm this specific claim here ($got)"
fi
EOF
chmod +x /tmp/grab-tests/test_linux_path.sh
bash /tmp/grab-tests/test_linux_path.sh ~/dotfiles/install-tools.sh
```
Expected: `PASS: real uname -s on this machine is Linux (Darwin branch
untaken by construction)` — confirms the existing Linux download path in
`install_fzf`/`install_yazi` is exactly what still runs on this machine,
unchanged.

- [ ] **Step 6: Write and run the binary-runs-check test**

```bash
cat > /tmp/grab-tests/test_binary_runs_check.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

WORK=$(mktemp -d)
mkdir -p "$WORK/bin"
cat > "$WORK/bin/faketool" <<'TOOLEOF'
#!/bin/nonexistent-interpreter-xyz
echo "should never print"
TOOLEOF
chmod +x "$WORK/bin/faketool"
export PATH="$WORK/bin:$PATH"

fail=0
if command -v faketool >/dev/null 2>&1 && faketool --version >/dev/null 2>&1; then
	echo "FAIL: new check reports success for a broken binary"
	fail=1
else
	echo "PASS: new check correctly rejects a broken-but-PATH-present binary"
fi

if command -v fzf >/dev/null 2>&1 && fzf --version >/dev/null 2>&1; then
	echo "PASS: new check still succeeds for a genuinely working tool (fzf)"
else
	echo "FAIL: new check rejects a genuinely working tool"
	fail=1
fi

rm -rf "$WORK"
exit $fail
EOF
chmod +x /tmp/grab-tests/test_binary_runs_check.sh
bash /tmp/grab-tests/test_binary_runs_check.sh
```
Expected:
```
PASS: new check correctly rejects a broken-but-PATH-present binary
PASS: new check still succeeds for a genuinely working tool (fzf)
```
(Verified in planning — this exact test, run during brainstorming,
produced exactly this result. This proves the *pattern* used in Step 3's
`&& "$tool" --version >/dev/null 2>&1` addition; it doesn't re-source the
real file since the real loop is now guarded behind `BASH_SOURCE`, per
Step 3.)

- [ ] **Step 7: Syntax-check the real file and commit**

```bash
bash -n ~/dotfiles/install-tools.sh
cd ~/dotfiles
git add install-tools.sh
git commit -m "install-tools.sh: install fzf/yazi via brew on Darwin, verify binaries run"
```
Expected: `bash -n` prints nothing (valid syntax).

- [ ] **Step 8: Regression-check the real Linux install path still works**

```bash
bash ~/dotfiles/install-tools.sh
```
Expected: `✓ zoxide already installed (...)`, `✓ fzf already installed
(...)`, `✓ yazi already installed (...)` — all three tools are already
installed on this machine, so this exercises the "already installed, and
the new `--version` check still passes" branch, confirming Step 3's
`BASH_SOURCE` guard didn't break the file's normal direct-execution
behavior.

---

## Self-Review

**Spec coverage:** bin/ symlink loop (Task 1, matches spec item 1 exactly,
verified via fixture) ✓. Portable `sed -i` (Task 1, matches spec item 2,
verified on GNU sed, BSD sed explicitly noted as unverifiable here) ✓.
Darwin brew branches (Task 2, matches spec item 3, verified via mocked
`uname`/`brew` control flow) ✓. Binary-runs check (Task 2, matches spec
item 4, verified via a broken-binary fixture) ✓. Every spec item has a
task and a verification step; macOS live verification is explicitly
called out as out-of-scope everywhere it applies, not silently dropped.

**Deviation from the spec's literal diff, flagged:** Task 2 Step 3 wraps
`install-tools.sh`'s top-level execution in a `BASH_SOURCE` guard — this
wasn't in the spec's original code snippets, but is necessary to make the
Darwin-branch control-flow test (Step 1) possible at all (sourcing the
file for testing would otherwise immediately run a real install attempt).
This mirrors the exact pattern already established in `bin/grab` (see
`grab-screen-word-completion.md` Task 1) for the same reason. Not a scope
change to the spec's actual behavior — `install-tools.sh` run directly
(`bash install-tools.sh` or `./install-tools.sh`) behaves identically
before and after, only sourcing behavior changes (from "immediately runs"
to "just defines functions").

**Placeholder scan:** none — every step has literal code, literal
commands, and literal expected output, all verified during brainstorming.

**Type/name consistency:** `install_fzf`/`install_yazi` keep their
existing no-argument, return-code-only signature throughout; the install
loop's `"install_$tool"` dynamic dispatch (unchanged) still resolves to
these same names.
