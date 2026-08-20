#!/usr/bin/env bash
# Persist code pointers to disk as a reloadable quickfix file plus a JSON sidecar.
#
# Two files, because they answer to different readers:
#   <name>.quickfix       plain "path:lnum:col: text", what :cfile parses
#   <name>.quickfix.json  title, provenance, and setqflist-ready items
#
# The .quickfix file carries no frontmatter on purpose. :cfile parses with 'errorformat',
# and any line that matches no pattern is kept as a valid=0 entry -- so a YAML header would
# show up as clutter in :copen. All metadata therefore lives in the sidecar.
set -euo pipefail

SOCKET=""
NAME="pointers"
TITLE=""
DESCRIPTION=""
OUTDIR=""
VERIFY=1
GITIGNORE=1

usage() {
  cat <<'EOF'
usage: save_qf.sh (--socket SOCK | --items FILE | < items.json) [options]

Sources, pick one:
  --socket SOCK   read the live quickfix list back out of nvim and save that. Preferred:
                  it saves what is actually in the editor, with bufnr resolved to paths.
  --items FILE    a JSON array of {filename, lnum, col, text}
  (stdin)         the same JSON array, same shape push_qf.sh accepts

options:
  --name N        basename for the pair, default "pointers" -> N.quickfix, N.quickfix.json
  --title T       quickfix title. Taken from the live list when --socket is used.
  --description D one line of prose stored in the sidecar
  --outdir DIR    default <git toplevel>/code-pointers, else ./code-pointers. Created if absent.
  --no-verify     skip the headless :cfile check
  --no-gitignore  do not touch .git/info/exclude

Writes both files, then reloads the .quickfix in a throwaway headless nvim and fails if any
entry comes back invalid.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --socket) SOCKET="${2:-}"; shift 2 ;;
    --items) ITEMS_FILE="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --description) DESCRIPTION="${2:-}"; shift 2 ;;
    --outdir) OUTDIR="${2:-}"; shift 2 ;;
    --no-verify) VERIFY=0; shift ;;
    --no-gitignore) GITIGNORE=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "save_qf.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$NAME" == */* ]] && { echo "save_qf.sh: --name must be a basename, not a path" >&2; exit 2; }

# ---- collect items -----------------------------------------------------------------
if [[ -n "$SOCKET" ]]; then
  [[ -S "$SOCKET" ]] || { echo "save_qf.sh: not a socket: $SOCKET" >&2; exit 1; }
  # bufname() resolves each entry's buffer to an absolute path; the live list stores
  # bufnr, which means nothing once written to disk.
  ITEMS=$(timeout 10 nvim --server "$SOCKET" --remote-expr \
    'json_encode(map(getqflist(), "{'"'"'filename'"'"': fnamemodify(bufname(v:val.bufnr), '"'"':p'"'"'), '"'"'lnum'"'"': v:val.lnum, '"'"'col'"'"': v:val.col, '"'"'text'"'"': v:val.text}"))') \
    || { echo "save_qf.sh: could not read the quickfix list (session busy?)" >&2; exit 1; }
  if [[ -z "$TITLE" ]]; then
    TITLE=$(timeout 10 nvim --server "$SOCKET" --remote-expr 'getqflist({"title": 1}).title' || true)
  fi
elif [[ -n "${ITEMS_FILE:-}" ]]; then
  [[ -r "$ITEMS_FILE" ]] || { echo "save_qf.sh: cannot read $ITEMS_FILE" >&2; exit 1; }
  ITEMS=$(cat "$ITEMS_FILE")
else
  ITEMS=$(cat)
fi
[[ -n "${ITEMS//[[:space:]]/}" ]] || { echo "save_qf.sh: no entries to save" >&2; exit 2; }
[[ -n "$TITLE" ]] || TITLE="claude: code pointers"

# ---- locate and create the output directory ----------------------------------------
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
[[ -n "$OUTDIR" ]] || OUTDIR="${TOPLEVEL:-$PWD}/code-pointers"
mkdir -p "$OUTDIR"

# Keep the folder out of git without adding a tracked file: .git/info/exclude is
# per-clone and produces no diff. --git-common-dir so this lands in the main .git
# when run from a linked worktree.
if (( GITIGNORE )) && [[ -n "$TOPLEVEL" ]]; then
  GITDIR=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
  REL="${OUTDIR#"$TOPLEVEL"/}"
  if [[ -n "$GITDIR" && "$REL" != "$OUTDIR" ]]; then
    EXCLUDE="$GITDIR/info/exclude"
    mkdir -p "$(dirname "$EXCLUDE")"
    if ! grep -qxF "/$REL/" "$EXCLUDE" 2>/dev/null; then
      printf '/%s/\n' "$REL" >> "$EXCLUDE"
      echo "ignored /$REL/ via $EXCLUDE"
    fi
  fi
fi

QF="$OUTDIR/$NAME.quickfix"
JSON="$QF.json"
EXISTED=0; [[ -e "$QF" ]] && EXISTED=1

# ---- write both files from one source of truth --------------------------------------
# 12-hour clock, spelled-out date. %-I and %-d drop the zero padding.
SAVED_HUMAN=$(date '+%A, %B %-d, %Y at %-I:%M:%S %p %Z')
SAVED_ISO=$(date '+%Y-%m-%dT%H:%M:%S%z')
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")
if [[ -n "$TOPLEVEL" ]] && [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  TREE_STATE="dirty"
else
  TREE_STATE=$([[ -n "$COMMIT" ]] && echo clean || echo "not-a-git-repo")
fi

ITEMS="$ITEMS" QF="$QF" JSON="$JSON" \
TITLE="$TITLE" DESCRIPTION="$DESCRIPTION" \
SAVED_HUMAN="$SAVED_HUMAN" SAVED_ISO="$SAVED_ISO" \
COMMIT="$COMMIT" TREE_STATE="$TREE_STATE" \
python3 - <<'PY'
import json, os, sys

items = json.loads(os.environ['ITEMS'])
if not isinstance(items, list) or not items:
    sys.exit('save_qf.sh: expected a non-empty JSON array of entries')

clean = []
for i, entry in enumerate(items):
    path = entry.get('filename', '')
    lnum = entry.get('lnum', 0)
    if not path or not os.path.isabs(path):
        sys.exit(f'save_qf.sh: entry {i} has no absolute filename: {entry!r}')
    if not isinstance(lnum, int) or lnum < 1:
        sys.exit(f'save_qf.sh: entry {i} has a bad lnum: {entry!r}')
    clean.append({
        'filename': path,
        'lnum': lnum,
        'col': entry.get('col') or 1,
        # Newlines and colons in text would confuse errorformat on reload.
        'text': ' '.join(str(entry.get('text', '')).split()),
    })

with open(os.environ['QF'], 'w') as f:
    for e in clean:
        f.write(f"{e['filename']}:{e['lnum']}:{e['col']}: {e['text']}\n")

meta = {
    'title': os.environ['TITLE'],
    'saved': os.environ['SAVED_HUMAN'],
    'saved_iso': os.environ['SAVED_ISO'],
    'commit': os.environ['COMMIT'],
    'tree_state': os.environ['TREE_STATE'],
    'note': ('lnum values are pinned to the commit above; re-verify after rebasing or editing.'
             if os.environ['COMMIT'] else
             'no commit recorded, so lnum values are pinned to nothing; re-verify before trusting.'),
    'items': clean,
}
if os.environ.get('DESCRIPTION'):
    meta['description'] = os.environ['DESCRIPTION']
# 'items' last so the metadata reads first in an editor.
meta = {k: meta[k] for k in [*(k for k in meta if k != 'items'), 'items']}

with open(os.environ['JSON'], 'w') as f:
    json.dump(meta, f, indent=2)
    f.write('\n')
PY

COUNT=$(wc -l < "$QF" | tr -d ' ')

# ---- verify the file reloads ---------------------------------------------------------
# -u NONE so the check does not depend on the user's errorformat.
if (( VERIFY )) && command -v nvim > /dev/null; then
  VALID=$(timeout 30 nvim --headless -u NONE \
    -c "cfile $QF" \
    -c 'echo len(filter(getqflist(), "v:val.valid"))' \
    -c 'qa!' 2>&1 | tail -1 | tr -dc '0-9')
  if [[ "$VALID" != "$COUNT" ]]; then
    echo "save_qf.sh: wrote $COUNT entries but only ${VALID:-0} reload as valid: $QF" >&2
    exit 1
  fi
  echo "verified: $VALID/$COUNT entries reload via :cfile"
fi

echo "saved $COUNT pointer$([[ "$COUNT" == 1 ]] || echo s)$([[ $EXISTED == 1 ]] && echo ' (replaced)')"
echo "  $QF"
echo "  $JSON"
echo
echo "reload with either:"
echo "  :cfile $QF"
echo "  :call setqflist([], ' ', json_decode(join(readfile('$JSON'))))"
