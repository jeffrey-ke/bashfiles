#!/bin/bash

cur=~/dotfiles
ln -s $cur/.bash_aliases ~/.bash_aliases
ln -s $cur/.functions.sh ~/.functions.sh
ln -s $cur/.pylintrc ~/.pylintrc
ln -s $cur/.tmux.conf ~/.tmux.conf
ln -s $cur/.vimrc ~/.vimrc
ln -s $cur/.bash_vars ~/.bash_vars
ln -s $cur/.setup ~/.setup

echo 'if [[ -f "$HOME/.bash_aliases" ]]; then
  source "$HOME/.bash_aliases"
fi' >> ~/.bashrc
echo 'if [[ -f "$HOME/.functions.sh" ]]; then
  source "$HOME/.functions.sh"
fi' >> ~/.bashrc
echo 'if [[ -f "$HOME/.setup" ]]; then
  source "$HOME/.setup"
fi' >> ~/.bashrc
