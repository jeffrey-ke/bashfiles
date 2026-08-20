#!/bin/bash
set -e

DOTFILES="$HOME/dotfiles"
BASHRC="$HOME/.bashrc"

# nvim/ and commentstrip/ are submodules; without this the ~/.config/nvim symlink
# points at an empty directory and nvim starts with no config at all. Non-fatal:
# the URLs are SSH, so a machine without a GitHub key gets a warning, not an abort.
git -C "$DOTFILES" submodule update --init --recursive ||
	echo "warning: submodule init failed (missing SSH key or offline?) — nvim config and commentstrip are unavailable until you re-run it"

# Same name in the repo and in $HOME (modulo the leading dot already present).
files=(.bash_aliases .functions.sh .bash_prompt .bash_tools .bash_vars .pylintrc .tmux.conf .vimrc .gitconfig .visidatarc)
for f in "${files[@]}"; do
	ln -sf "$DOTFILES/$f" "$HOME/$f"
done

# Different name in the repo than in $HOME.
ln -sf "$DOTFILES/ugrep-config" "$HOME/.ugrep"
ln -sf "$DOTFILES/gitignore_global" "$HOME/.gitignore_global"
ln -sf "$DOTFILES/pyrightconfig.json" "$HOME/pyrightconfig.json"

# -n on both: these two links point at directories, and plain `ln -sf` dereferences an
# existing symlink-to-directory and drops the new link *inside* it — a second run would
# create dotfiles/nvim/nvim -> dotfiles/nvim (untracked content inside the submodule).
mkdir -p "$HOME/.config"
ln -sfn "$DOTFILES/nvim" "$HOME/.config/nvim"

[ -d "$HOME/.config/yazi" ] && [ ! -L "$HOME/.config/yazi" ] && rm -rf "$HOME/.config/yazi"
ln -sfn "$DOTFILES/yazi" "$HOME/.config/yazi"

mkdir -p "$HOME/.local/bin"
for f in "$DOTFILES"/bin/*; do
	[ -f "$f" ] && [ -x "$f" ] || continue
	case "$(basename "$f")" in *.*) continue ;; esac
	ln -sf "$f" "$HOME/.local/bin/$(basename "$f")"
done

[ -f "$BASHRC" ] || touch "$BASHRC"

sources=(.bash_aliases .functions.sh .bash_prompt .bash_tools .bash_vars)
for s in "${sources[@]}"; do
	line="[ -f \"\$HOME/$s\" ] && source \"\$HOME/$s\""
	# Second grep catches a pre-existing block in any form — both our own appended
	# line and Ubuntu's stock `. ~/.bash_aliases`, which the old `source.*` pattern
	# missed and therefore double-sourced.
	grep -qF "$line" "$BASHRC" && continue
	grep -qE "^[^#]*(source|\.)[[:space:]]+[^#]*$s" "$BASHRC" && continue
	echo "$line" >>"$BASHRC"
done

# A login shell reads the first of .bash_profile/.bash_login/.profile that exists and
# never reads .bashrc — so on macOS, where none of the three ship, everything appended
# above is dead code (Ghostty/Terminal go through `login`, which starts a login shell).
# Ubuntu's stock .profile already sources .bashrc, and creating a .bash_profile there
# would shadow it, so patch the file bash actually reads instead of always making one.
profile=""
for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
	[ -f "$f" ] && profile="$f" && break
done
if [ -z "$profile" ]; then
	profile="$HOME/.bash_profile"
	touch "$profile"
fi
grep -qE "^[^#]*(source|\.)[[:space:]]+[^#]*\.bashrc" "$profile" ||
	echo '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"' >>"$profile"

# Migrate the old inline machine-config block (exact-hostname only) if present.
sed -i.bak '/MACHINE_CONFIG/d' "$BASHRC" && rm -f "$BASHRC.bak"
# Anchored at a non-comment `source`, like the loop above: a bare substring grep also
# matches a *comment* that merely names the file — e.g. one left behind to record that
# some hand-written block moved into machines/ — and then silently never appends the
# line, leaving the machine config unsourced with nothing to show why.
if ! grep -qE "^[^#]*(source|\.)[[:space:]]+[^#]*source-machine\.sh" "$BASHRC"; then
	echo '[ -f "$HOME/dotfiles/source-machine.sh" ] && source "$HOME/dotfiles/source-machine.sh"' >>"$BASHRC"
fi

"$DOTFILES/sync-skills.sh" || echo "warning: skill sync failed — re-run ./sync-skills.sh later"
"$DOTFILES/install-tools.sh" || echo "warning: tool install failed (offline?) — re-run ./install-tools.sh later"
