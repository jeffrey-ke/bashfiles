#!/bin/bash
# jke-desktop — Nuro work machine (Ubuntu 24.04, ~/repo/Nuro).
#
# Holds the shell state that Nuro/misc/scripts/swe_setup/swe_setup.sh appends to
# ~/.bashrc, moved here so it is version-controlled and survives a .bashrc reset.
# Re-running swe_setup.sh adds nothing back: each block it writes is guarded by a
# `command -v` / PATH-contains check, and PATH is exported, so those checks see what
# this file set even though the script is non-interactive and never reads .bashrc.
#
# Everything else swe_setup installs is system-wide (bazel, kubectl, docker,
# google-cloud-sdk, git-lfs — all under /usr) and needs no shell config. The one
# non-PATH thing it writes is the Nuro repo's `include.path` -> Nuro/.gitconfig,
# which lives in .git/config, so symlinking ~/.gitconfig doesn't disturb it.
#
# Deliberately not carried over from what swe_setup wrote:
#   export PATH="$PATH:$HOME/.local/bin"   (for claude) — .bash_tools:5 prepends it

# nuro-cli (`n`), installed by Nuro/tools/cli/install.sh. Prepended, as it writes it.
[ -d "$HOME/bin" ] && PATH="$HOME/bin:$PATH"

# Node via fnm. `fnm env` exports the per-shell multishell dir that node/npm/yarn
# actually resolve through, so it has to be eval'd in every shell rather than baked
# into PATH once. Guarded, unlike swe_setup's bare eval, which errors out on any
# shell started after the install goes missing.
if [ -x "$HOME/.local/share/fnm/fnm" ]; then
	export PATH="$PATH:$HOME/.local/share/fnm"
	eval "$("$HOME/.local/share/fnm/fnm" env --shell bash)"
fi

# Not sourced here on purpose:
#   Nuro/misc/scripts/swe_setup/cuda_env.sh — sets TF_CUDA_COMPUTE_CAPABILITIES off
#     `nvidia-smi -L` and puts /usr/local/cuda/bin on PATH. Only bazel --config=cuda
#     builds want it, and it shells out to nvidia-smi on every shell start, so
#     `source` it in the shell that needs it.
