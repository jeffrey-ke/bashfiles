#!/usr/bin/env python3
"""Reads a unified diff on stdin and prints each added comment line as `path:line: text`.

Detection is per file extension and line-based: whole-line and trailing comments,
plus Python docstring openers. Lint pragmas are not comments and are skipped.
"""

import re
import sys
from pathlib import PurePath

HASH_SUFFIXES = {".py", ".pyi", ".bzl", ".sh", ".bash", ".yaml", ".yml", ".toml", ".cfg"}
HASH_NAMES = {"BUILD", "BUILD.bazel", "WORKSPACE", "MODULE.bazel"}
SLASH_SUFFIXES = {".c", ".cc", ".cpp", ".h", ".hpp", ".cu", ".cuh", ".proto", ".go", ".rs", ".java", ".js", ".ts", ".tsx"}

HASH_COMMENT = re.compile(r"^\s*#|\s#\s")
SLASH_COMMENT = re.compile(r"^\s*(//|/\*|\*)|\s//\s|/\*")
DOCSTRING = re.compile(r"""^\s*[rRbBuU]?("{3}|'{3})""")
PRAGMA = re.compile(r"^#!|type:\s*ignore|noqa|pylint:|pyright:|fmt:\s*(on|off|skip)|NOLINT|IWYU pragma|clang-format|-\*- coding")

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def comment_pattern(path: str) -> re.Pattern[str] | None:
    p = PurePath(path)
    if p.suffix in HASH_SUFFIXES or p.name in HASH_NAMES:
        return HASH_COMMENT
    if p.suffix in SLASH_SUFFIXES:
        return SLASH_COMMENT
    return None


def main() -> None:
    path, pattern, line_no = "", None, 0
    for raw in sys.stdin:
        line = raw.rstrip("\n")
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else ""
            pattern = comment_pattern(path)
        elif m := HUNK.match(line):
            line_no = int(m.group(1))
        elif line.startswith("+"):
            text = line[1:]
            is_docstring = path.endswith((".py", ".pyi")) and DOCSTRING.match(text)
            if pattern and (pattern.search(text) or is_docstring) and not PRAGMA.search(text):
                print(f"{path}:{line_no}: {text.strip()}")
            line_no += 1
        elif line.startswith(" "):
            line_no += 1


if __name__ == "__main__":
    main()
