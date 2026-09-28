# .gitconfig's github credential helper is plain `gh`; PSC keeps it here.
export PATH="/ocean/projects/cis260205p/jke2/envs/main/bin:$PATH"

# Re-init zoxide now that the env bin above is on PATH, via .bash_tools' helper --
# a bare `zoxide init bash` here would also define zoxide's default `z`, and this
# file is sourced after .functions.sh, so it would silently clobber z().
_init_zoxide
