#!/usr/bin/env bash
# Symlink claude-skills/ into ~/.claude/skills/ for autodiscovery.
# Skips any skill that already exists at the destination.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)/claude-skills"
DEST_DIR="$HOME/.claude/skills"

mkdir -p "$DEST_DIR"

for skill_dir in "$SRC_DIR"/*/; do
    skill="$(basename "$skill_dir")"
    dest="$DEST_DIR/$skill"

    if [ -e "$dest" ]; then
        echo "skip: $skill (already exists)"
    else
        ln -s "$skill_dir" "$dest"
        echo "linked: $skill -> $dest"
    fi
done
