#!/bin/bash

echo "you're in tesu!"

export DATA=/data/user/jeffk
setxkbmap -option caps:escape
set -o vi

export PATH="$HOME/.local/bin:$PATH"
export PATH=$HOME/nvim-linux-x86_64/bin:$PATH
export PATH=$HOME/isaacsim:$PATH

function cd() {
	__zoxide_z "$@" || return $?
	[[ -n "$_CD_SOURCING" ]] && return 0
	local _CD_SOURCING=1
	local accumulator="" remaining="${PWD#/}"
	while [[ -n "$remaining" ]]; do
		if [[ "$remaining" == */* ]]; then
			accumulator+="/${remaining%%/*}"
			remaining="${remaining#*/}"
		else
			accumulator+="/$remaining"
			remaining=""
		fi
		if [[ -f "$accumulator/.aliases" ]]; then
			echo "Sourcing $accumulator/.aliases:"
			cat "$accumulator/.aliases"
			source "$accumulator/.aliases"
		fi
	done
	return 0
}
alias z=cd
