#!/usr/bin/env bash
# Prints the ref this branch forked from: the nearest local branch below HEAD that
# is not yet on the upstream (stacked PRs), else the merge-base with the upstream.
# The upstream is $1, else `git config auditing-code-comments.upstream` (set by the
# skill's Setup). Reports which rule fired on stderr.

set -euo pipefail

upstream=${1:-$(git config --get auditing-code-comments.upstream || true)}
if [[ -z $upstream ]]; then
    echo "branch-base: no upstream; pass one or run the skill's Setup" >&2
    exit 1
fi
best=
best_n=
while read -r ref; do
    n=$(git rev-list --count "$ref..HEAD")
    ((n > 0)) || continue
    if [[ -z $best_n ]] || ((n < best_n)); then
        best=$ref
        best_n=$n
    fi
done < <(git for-each-ref --merged HEAD --no-merged "$upstream" --format='%(refname:short)' refs/heads)

if [[ -n $best ]]; then
    echo "branch-base: parent branch $best ($best_n commits below HEAD)" >&2
    echo "$best"
else
    echo "branch-base: merge-base with $upstream" >&2
    git merge-base HEAD "$upstream"
fi
