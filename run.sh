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
files=(.bash_aliases .functions.sh .bash_prompt .bash_tools .bash_vars .pylintrc .tmux.conf .vimrc .gitconfig)
for f in "${files[@]}"; do
	ln -sf "$DOTFILES/$f" "$HOME/$f"
done

# Different name in the repo than in $HOME.
ln -sf "$DOTFILES/ugrep-config" "$HOME/.ugrep"
ln -sf "$DOTFILES/gitignore_global" "$HOME/.gitignore_global"
ln -sf "$DOTFILES/pyrightconfig.json" "$HOME/pyrightconfig.json"

mkdir -p "$HOME/.config"
ln -sf "$DOTFILES/nvim" "$HOME/.config/nvim"

[ -d "$HOME/.config/yazi" ] && [ ! -L "$HOME/.config/yazi" ] && rm -rf "$HOME/.config/yazi"
ln -sf "$DOTFILES/yazi" "$HOME/.config/yazi"

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

# Migrate the old inline machine-config block (exact-hostname only) if present.
sed -i.bak '/MACHINE_CONFIG/d' "$BASHRC" && rm -f "$BASHRC.bak"
if ! grep -q 'source-machine.sh' "$BASHRC"; then
	echo '[ -f "$HOME/dotfiles/source-machine.sh" ] && source "$HOME/dotfiles/source-machine.sh"' >>"$BASHRC"
fi

"$DOTFILES/sync-skills.sh" || echo "warning: skill sync failed — re-run ./sync-skills.sh later"
"$DOTFILES/install-tools.sh" || echo "warning: tool install failed (offline?) — re-run ./install-tools.sh later"
