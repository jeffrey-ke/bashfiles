#!/bin/bash
set -e

DOTFILES="$HOME/dotfiles"
BASHRC="$HOME/.bashrc"

files=(.bash_aliases .functions.sh .bash_prompt .bash_tools .pylintrc .tmux.conf .vimrc .gitconfig)
for f in "${files[@]}"; do
	ln -sf "$DOTFILES/$f" "$HOME/$f"
done
ln -sf "$DOTFILES/lldbinit" "$HOME/.lldbinit"
mkdir -p "$HOME/.config"
ln -sf "$DOTFILES/nvim" "$HOME/.config/nvim"

[ -d "$HOME/.config/yazi" ] && [ ! -L "$HOME/.config/yazi" ] && rm -rf "$HOME/.config/yazi"
ln -sf "$DOTFILES/yazi" "$HOME/.config/yazi"

sources=(.bash_aliases .functions.sh .bash_prompt .bash_tools)
for s in "${sources[@]}"; do
	if ! grep -q "source.*$s" "$BASHRC"; then
		echo "[ -f \"\$HOME/$s\" ] && source \"\$HOME/$s\"" >>"$BASHRC"
	fi
done

# Migrate the old inline machine-config block (exact-hostname only) if present.
sed -i '/MACHINE_CONFIG/d' "$BASHRC"
if ! grep -q 'source-machine.sh' "$BASHRC"; then
	echo '[ -f "$HOME/dotfiles/source-machine.sh" ] && source "$HOME/dotfiles/source-machine.sh"' >>"$BASHRC"
fi

"$DOTFILES/install-tools.sh" || echo "warning: tool install failed (offline?) — re-run ./install-tools.sh later"
