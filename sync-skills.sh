#!/usr/bin/env bash
# Symlink claude-skills/ into ~/.claude/skills/ and claude-output-styles/
# into ~/.claude/output-styles/ for autodiscovery.
# Skips anything that already exists at the destination.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

link_dirs_into() { # <src-dir-of-dirs> <dest-dir>
    local src_root="$1" dest_dir="$2" item base dest
    mkdir -p "$dest_dir"
    for item in "$src_root"/*/; do
        base="$(basename "$item")"
        dest="$dest_dir/$base"
        if [ -e "$dest" ]; then
            echo "skip: $base (already exists)"
        else
            ln -s "$item" "$dest"
            echo "linked: $base -> $dest"
        fi
    done
}

link_files_into() { # <src-dir-of-files> <dest-dir>
    local src_root="$1" dest_dir="$2" item base dest
    mkdir -p "$dest_dir"
    for item in "$src_root"/*; do
        [ -f "$item" ] || continue
        base="$(basename "$item")"
        dest="$dest_dir/$base"
        if [ -e "$dest" ]; then
            echo "skip: $base (already exists)"
        else
            ln -s "$item" "$dest"
            echo "linked: $base -> $dest"
        fi
    done
}

link_dirs_into "$ROOT/claude-skills" "$HOME/.claude/skills"
link_files_into "$ROOT/claude-output-styles" "$HOME/.claude/output-styles"
