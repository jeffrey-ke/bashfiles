#!/bin/bash
set -e

DOTFILES="$HOME/dotfiles"
BASHRC="$HOME/.bashrc"

files=(.bash_aliases .functions.sh .bash_prompt .pylintrc .tmux.conf .vimrc .gitconfig)
for f in "${files[@]}"; do
	ln -sf "$DOTFILES/$f" "$HOME/$f"
done
ln -sf "$DOTFILES/lldbinit" "$HOME/.lldbinit"
mkdir -p "$HOME/.config"
ln -sf "$DOTFILES/nvim" "$HOME/.config/nvim"

sources=(.bash_aliases .functions.sh .bash_prompt)
for s in "${sources[@]}"; do
	if ! grep -q "source.*$s" "$BASHRC"; then
		echo "[ -f \"\$HOME/$s\" ] && source \"\$HOME/$s\"" >>"$BASHRC"
	fi
done

if ! grep -q 'machines/.*\.sh' "$BASHRC"; then
	cat >>"$BASHRC" <<'EOF'
MACHINE_CONFIG="$HOME/dotfiles/machines/$(hostname -s).sh"
[ -f "$MACHINE_CONFIG" ] && source "$MACHINE_CONFIG"
EOF
fi
