#!/bin/bash

export PATH="$HOME/bin:/usr/local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
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

function obgrab() {
	local host="$1"
	local remote_path="$2"
	local name="${3:-$(basename "$remote_path")}"
	local dest_dir
	dest_dir="$(realpath "$HOME/repo/Research/Research/papers and figures")"
	scp -r "$host:$remote_path" "$dest_dir/$name"
}

alias z=cd
alias fresh="source ~/.zshrc"
export EDITOR="nvim"
set -o vi
