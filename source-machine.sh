# Resolve this host's machine config. Each *.sh filename in machines/ is treated
# as an anchored regex matched against `hostname -s`. The first (alphabetical)
# regex match is sourced as a shared base, then the exact-hostname file (if any)
# is sourced on top so per-host overrides — e.g. the path registry — win without
# shadowing the shared regex config.
_host=$(hostname -s)
_mdir="$HOME/dotfiles/machines"
for _f in "$_mdir"/*.sh; do
	[ -e "$_f" ] || continue
	_name=$(basename "$_f" .sh)
	# Skip the exact-host file here; it is layered on last.
	[ "$_name" = "$_host" ] && continue
	if [[ $_host =~ ^$_name$ ]]; then
		source "$_f"
		break
	fi
done
[ -f "$_mdir/$_host.sh" ] && source "$_mdir/$_host.sh"
unset _host _mdir _f _name
