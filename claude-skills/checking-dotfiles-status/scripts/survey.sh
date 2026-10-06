#!/usr/bin/env bash
# Read-only snapshot of a meta repo and its submodules, for grouping changes into commits.
# Usage: survey.sh [--no-fetch] [repo]   (repo defaults to ~/dotfiles)
# Moves nothing: no checkout, no submodule update. Fetch only updates remote-tracking refs.
set -u
fetch=1
[[ ${1:-} == --no-fetch ]] && { fetch=0; shift; }
repo=${1:-$HOME/dotfiles}
cd "$repo" || exit 1

now=$(date +%s)
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo "$now"; }
age() {   # days since the file was last written; "gone" for deletions
  [[ -e $1 ]] || { echo gone; return; }
  echo "$(( (now - $(mtime "$1")) / 86400 ))d"
}

# One line per dirty path: XY  +add/-del  age  path. Directories (submodules) report no age.
files() {
  local dir=$1
  git -C "$dir" status --porcelain --untracked-files=all | while IFS= read -r line; do
    local xy=${line:0:2} path=${line:3}
    path=${path#*-> }   # rename: keep the new name
    local nums
    if [[ $xy == '??' ]]; then
      nums="+$(wc -l <"$dir/$path" 2>/dev/null | tr -d ' ')/-0"
    else
      nums=$(git -C "$dir" diff HEAD --numstat -- "$path" | awk '{a+=$1; d+=$2} END {printf "+%d/-%d", a, d}')
    fi
    local a=$(age "$dir/$path"); [[ -d $dir/$path ]] && a=-
    printf '  %s  %-10s %5s  %s\n' "$xy" "$nums" "$a" "$path"
  done
}

# "<behind> <ahead>" against the upstream, or a reason there is none.
divergence() {
  git -C "$1" rev-parse -q --verify '@{u}' >/dev/null 2>&1 || { echo "no upstream"; return; }
  git -C "$1" rev-list --left-right --count '@{u}...HEAD' | awk '{print "behind " $1 ", ahead " $2}'
}

if (( fetch )); then
  timeout 30 git fetch --quiet --recurse-submodules=yes 2>/dev/null \
    || echo "!! fetch failed or timed out: remote state below may be stale"
fi

echo "## meta: $repo  [$(git branch --show-current || echo DETACHED)]  $(divergence .)"
echo "   XY  lines      age  path"
files .
incoming=$(git --no-pager log --oneline 'HEAD..@{u}' 2>/dev/null)
[[ -n $incoming ]] && { echo "  incoming meta commits (another machine pushed):"; sed 's/^/    /' <<<"$incoming"; }
unpushed=$(git --no-pager log --oneline '@{u}..HEAD' 2>/dev/null)
[[ -n $unpushed ]] && { echo "  unpushed meta commits:"; sed 's/^/    /' <<<"$unpushed"; }

git config --file .gitmodules --get-regexp '\.path$' | while read -r _ sub; do
  [[ -e $sub/.git ]] || { echo; echo "## $sub  NOT INITIALIZED"; continue; }
  url=$(git config --file .gitmodules "submodule.$sub.url")
  owner=$(sed -E 's#.*[:/]([^/]+)/[^/]+$#\1#' <<<"$url")
  branch=$(git -C "$sub" branch --show-current); branch=${branch:-DETACHED}
  pin=$(git ls-tree HEAD "$sub" | awk '{print $3}')
  echo
  echo "## $sub  [$branch]  owner=$owner  $(divergence "$sub")"
  if [[ $branch == DETACHED ]]; then
    [[ $(git -C "$sub" rev-parse HEAD) == "$pin" ]] && echo "  detached at the pin: fine while clean; switch to a branch before committing"
  fi
  # Commits not yet in the pin, or not yet on the remote, each tagged with what it still needs.
  up=$(git -C "$sub" rev-parse -q --verify '@{u}' 2>/dev/null)
  base=$pin; [[ -n $up ]] && base=$(git -C "$sub" merge-base "$pin" "$up" 2>/dev/null || echo "$pin")
  git -C "$sub" rev-list --format='%h %s' --no-commit-header "$base..HEAD" 2>/dev/null | while read -r h msg; do
    tags=
    git -C "$sub" merge-base --is-ancestor "$h" "$pin" 2>/dev/null || tags+=" unpinned"
    [[ -n $up ]] && ! git -C "$sub" merge-base --is-ancestor "$h" "$up" && tags+=" unpushed"
    [[ -n $tags ]] && printf '    %-18s %s %s\n' "[${tags# }]" "$h" "$msg"
  done
  if [[ -n $up ]] && ! git -C "$sub" merge-base --is-ancestor "$pin" "$up"; then
    echo "  !! the committed pin ${pin:0:7} is not on the remote: push $sub before pushing the meta"
  fi
  if [[ -n $up ]] && [[ $owner != jeffrey-ke ]] && ! git -C "$sub" merge-base --is-ancestor "$up" HEAD; then
    echo "  upstream has moved; third-party, so bump only on purpose"
  fi
  dirty=$(files "$sub")
  if [[ -n $dirty ]]; then echo "  dirty:"; echo "$dirty"; fi
done
exit 0
