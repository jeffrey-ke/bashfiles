#!/bin/bash

# Everything else this file used to hold moved into the shared configs, because none
# of it was host-specific: the .aliases-sourcing `cd` -> .bash_tools (next to zoxide's
# init, which defines the cd it wraps), `obgrab` -> .functions.sh, `set -o vi` and
# BASH_SILENCE_DEPRECATION_WARNING -> .bash_vars, `alias fresh` -> .bash_aliases.
# Dropped outright: `alias z=cd` (zoxide is initialized with --cmd cd, so cd already
# *is* zoxide and z was a second name for it; `cdi` is the interactive picker),
# `export EDITOR=nvim` (.bash_vars:2), the ~/.local/bin PATH prepend (.bash_tools:5),
# and /usr/local/bin (Intel Homebrew's prefix — .bash_tools now runs `brew shellenv`,
# which gets the prefix right on both architectures).

# >>> path registry >>>
export papers='/Users/jke/repo/Research/Research/papers and figures'
# <<< path registry <<<
