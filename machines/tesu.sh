#!/bin/bash

echo "you're in tesu!"

export DATA=/data/user/jeffk
setxkbmap -option caps:escape
set -o vi

export PATH="$HOME/.local/bin:$PATH"
export PATH=$HOME/nvim-linux-x86_64/bin:$PATH
export PATH=$HOME/isaacsim:$PATH
