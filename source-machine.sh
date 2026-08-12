# Resolve this host's machine config. Each *.sh filename in machines/ is treated
# as an anchored regex matched against the short hostname. The first (alphabetical)
# regex match is sourced as a shared base, then the exact-hostname file (if any)
# is sourced on top so per-host overrides — e.g. the path registry — win without
# shadowing the shared regex config.
#
# Runs no subprocesses. bash already holds the hostname in $HOSTNAME, and stripping a
# directory and a suffix is parameter expansion — `hostname -s` plus one `basename` per
# machine file was 8 forks+execs per interactive shell, which is the one part of the
# startup path that buys nothing. Matters on a machine that authorizes every exec; see
# .docs_claude/notes/macos-shell-startup-latency.md.
_host=${HOSTNAME:-$(hostname)}
# %%.* is what `hostname -s` does: r033.ib.bridges2.psc.edu -> r033. The $( ) above is
# only reached if HOSTNAME is unset, which bash never leaves it.
_host=${_host%%.*}
_mdir="$HOME/dotfiles/machines"
for _f in "$_mdir"/*.sh; do
	[ -e "$_f" ] || continue
	# `basename "$_f" .sh` — safe as expansions because every $_f comes from the *.sh
	# glob, so it always has a / and always ends in .sh.
	_name=${_f##*/}
	_name=${_name%.sh}
	# Skip the exact-host file here; it is layered on last.
	[ "$_name" = "$_host" ] && continue
	if [[ $_host =~ ^$_name$ ]]; then
		source "$_f"
		break
	fi
done
[ -f "$_mdir/$_host.sh" ] && source "$_mdir/$_host.sh"
unset _host _mdir _f _name
