#!/bin/bash

if [[ $1 = "bash" ]]; then
	filerc=".bashrc"
elif [[ $1 = "zsh" ]]; then
	filerc=".zshrc"
else
	echo "First arg to setup script must be either zsh or bash"
	exit 1
fi
cur=~/dotfiles
ln -s $cur/.bash_aliases ~/.bash_aliases
ln -s $cur/.functions.sh ~/.functions.sh
ln -s $cur/.pylintrc ~/.pylintrc
ln -s $cur/.tmux.conf ~/.tmux.conf
ln -s $cur/.vimrc ~/.vimrc
# ln -s $cur/.bash_vars ~/.bash_vars
ln -s $cur/pyrightconfig.json ~/.config/pyright/pyrightconfig.json
# ln -s $cur/.setup ~/.setup

# Add source lines only if they don't already exist
if ! grep -q 'source "$HOME/.bash_aliases"' ~/$filerc; then
	echo 'if [[ -f "$HOME/.bash_aliases" ]]; then
  source "$HOME/.bash_aliases"
fi' >>~/$filerc
fi

if ! grep -q 'source "$HOME/.functions.sh"' ~/$filerc; then
	echo 'if [[ -f "$HOME/.functions.sh" ]]; then
  source "$HOME/.functions.sh"
fi' >>~/$filerc
fi

# if ! grep -q 'source "$HOME/.setup"' ~/$filerc; then
# 	echo 'if [[ -f "$HOME/.setup" ]]; then
#   source "$HOME/.setup"
# fi' >>~/$filerc
# fi
