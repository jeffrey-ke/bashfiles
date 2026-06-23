# Resolve this host's machine config. Each *.sh filename in machines/ is treated
# as an anchored regex matched against `hostname -s`. An exact-hostname file
# wins; otherwise the first (alphabetical) regex match is sourced.
_host=$(hostname -s)
_mdir="$HOME/dotfiles/machines"
if [ -f "$_mdir/$_host.sh" ]; then
	source "$_mdir/$_host.sh"
else
	for _f in "$_mdir"/*.sh; do
		[ -e "$_f" ] || continue
		_name=$(basename "$_f" .sh)
		if [[ $_host =~ ^$_name$ ]]; then
			source "$_f"
			break
		fi
	done
fi
unset _host _mdir _f _name
