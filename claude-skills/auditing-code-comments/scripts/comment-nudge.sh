#!/usr/bin/env bash
# Pre-commit hook: lists comment lines added in the staged diff. Never blocks the commit.

skill_dir=$(dirname "$(readlink -f "$0")")
added=$(git diff --cached -U0 --no-color | "$skill_dir/added-comments.py")
if [[ -n $added ]]; then
    {
        echo "comment-nudge: this commit adds $(wc -l <<<"$added") comment line(s):"
        head -n 20 <<<"$added" | sed 's/^/  /'
        echo "  Earned? Review the branch with /auditing-code-comments."
    } >&2
fi
exit 0
