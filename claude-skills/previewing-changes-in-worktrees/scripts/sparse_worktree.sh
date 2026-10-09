# Draft a change in a throwaway git worktree that holds only the files it touches, review it
# as a side-by-side diff, then merge it into the checkout it came from. Source this file.
#
#   sparse_worktree <name> <files...>      worktree of the current working tree, <files> only
#   sparse_worktree_add <name> <files...>  bring more files in
#   worktree_patch <name>                  its diff against that state -> <root>/<name>.patch
#   worktree_diff <name> [pane]            git difftool -t nvimdiff, file by file, in a tmux pane
#   worktree_apply <name>                  3-way merge each changed file into the source checkout
#   worktree_remove <name>
#
# Paths are repo-relative. Nothing writes the source checkout's index, stash or config: the
# base is a `git stash create` commit, files outside <files> are skip-worktree entries rather
# than a `git sparse-checkout` (which turns on extensions.worktreeConfig in the shared config),
# and worktree_apply writes working-tree files with `git merge-file`.

SPARSE_WORKTREE_ROOT=${SPARSE_WORKTREE_ROOT:-/tmp/sparse_worktrees}

_worktree_dir() { echo "$SPARSE_WORKTREE_ROOT/$1"; }
_worktree_meta() { echo "$(git -C "$(_worktree_dir "$1")" rev-parse --absolute-git-dir)/$2"; }
_worktree_base() { cat "$(_worktree_meta "$1" worktree-base)"; }
_worktree_source() { cat "$(_worktree_meta "$1" worktree-source)"; }

sparse_worktree() {
	local name=$1 w src base
	shift
	w=$(_worktree_dir "$name")
	src=$(git rev-parse --show-toplevel) || return
	# A commit of the working tree's tracked files, uncommitted edits included; empty when clean.
	base=$(git stash create) && base=${base:-$(git rev-parse HEAD)} || return
	git -c core.hooksPath=/dev/null worktree add -q --detach --no-checkout "$w" "$base" || return
	echo "$base" >"$(_worktree_meta "$name" worktree-base)"
	echo "$src" >"$(_worktree_meta "$name" worktree-source)"
	git -C "$w" read-tree "$base"
	# Every entry absent from disk, so status and `add -A` see only the files brought in.
	git -C "$w" ls-files -z | git -C "$w" update-index -z --skip-worktree --stdin
	sparse_worktree_add "$name" "$@" && echo "$w"
}

sparse_worktree_add() {
	local name=$1 w src f
	shift
	w=$(_worktree_dir "$name")
	src=$(_worktree_source "$name")
	for f in "$@"; do
		if git -C "$w" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
			git -C "$w" update-index --no-skip-worktree -- "$f" &&
				git -C "$w" checkout -- "$f"
		elif [[ -e $src/$f ]]; then # untracked: stash create skipped it
			mkdir -p "$w/$(dirname "$f")" && cp "$src/$f" "$w/$f" &&
				_worktree_add_to_base "$name" "$f"
		fi # else a file the draft will create
	done
}

# Folds an untracked file into the base, so the patch shows the draft's edits to it rather than
# the whole file as new. A throwaway index keeps draft edits staged in the worktree's out of it.
_worktree_add_to_base() {
	local name=$1 f=$2 w base index blob tree mode=100644
	w=$(_worktree_dir "$name")
	base=$(_worktree_base "$name")
	index=$(mktemp -u)
	[[ -x $w/$f ]] && mode=100755
	blob=$(git -C "$w" hash-object -w -- "$f")
	tree=$(GIT_INDEX_FILE=$index git -C "$w" read-tree "$base" &&
		GIT_INDEX_FILE=$index git -C "$w" update-index --add --cacheinfo "$mode,$blob,$f" &&
		GIT_INDEX_FILE=$index git -C "$w" write-tree)
	rm -f "$index"
	git -C "$w" commit-tree "$tree" -p "$base" -m "base + untracked $f" \
		>"$(_worktree_meta "$name" worktree-base)"
	git -C "$w" add -- "$f"
}

worktree_patch() {
	local w patch
	w=$(_worktree_dir "$1")
	patch="$w.patch"
	git -C "$w" add -A && git -C "$w" diff --cached "$(_worktree_base "$1")" >"$patch" &&
		echo "$patch"
}

worktree_diff() {
	local name=$1 pane=${2:-} w base
	w=$(_worktree_dir "$name")
	base=$(_worktree_base "$name")
	git -C "$w" add -A || return
	git -C "$w" diff --cached --quiet "$base" && { echo "no changes in $w" >&2; return 1; }
	# One nvimdiff per file, base on the left: :qa moves to the next file, :cq stops.
	local cmd="cd '$w' && git difftool -y --trust-exit-code -t nvimdiff --cached $base"
	# The pane closes once difftool finishes, so a pane id from an earlier call may be gone.
	if [[ -n $pane ]] && tmux display-message -t "$pane" -p '' 2>/dev/null; then
		tmux respawn-pane -k -t "$pane" "$cmd" && echo "$pane"
	else
		tmux split-window -v -l 60% -P -F '#{pane_id}' "$cmd"
	fi
}

worktree_apply() {
	local name=$1 w src base f status tmp conflicts=0
	w=$(_worktree_dir "$name")
	src=$(_worktree_source "$name")
	base=$(_worktree_base "$name")
	git -C "$w" add -A || return
	tmp=$(mktemp)
	while IFS=$'\t' read -r status f; do
		case $status in
		A) mkdir -p "$src/$(dirname "$f")" && cp "$w/$f" "$src/$f" ;;
		D) rm -f "$src/$f" ;;
		*)
			# current = the source checkout now, which may have moved on since the base.
			git -C "$w" show "$base:$f" >"$tmp"
			git merge-file -L current -L base -L draft "$src/$f" "$tmp" "$w/$f" ||
				{ echo "conflict: $f" >&2; conflicts=$((conflicts + 1)); }
			;;
		esac
	done < <(git -C "$w" diff --cached --name-status "$base")
	rm -f "$tmp"
	((conflicts == 0))
}

worktree_remove() {
	local w
	w=$(_worktree_dir "$1")
	git -C "$(_worktree_source "$1")" worktree remove --force "$w" && rm -f "$w.patch"
}
