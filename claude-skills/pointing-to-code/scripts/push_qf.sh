#!/usr/bin/env bash
# Push code pointers into a live nvim session as a quickfix list, then jump to the first.
#
# The payload travels through a temp file that nvim reads with json_decode, so no part of
# it is ever interpolated into a vimscript string. That sidesteps the quoting hazards of
# building setqflist() arguments on the command line.
set -euo pipefail

SOCKET=""
TITLE="claude: code pointers"
JUMP=1
COPEN=0

usage() {
  cat <<'EOF'
usage: push_qf.sh --socket SOCK [--title T] [--no-jump] [--copen] < items.json

items.json is a JSON array of quickfix entries:
  [{"filename": "/abs/path/a.cc", "lnum": 31, "col": 3, "text": "why this line matters"}]

  filename  required, must be absolute (it is resolved against nvim's cwd otherwise)
  lnum      required
  col, text optional

options:
  --socket   nvim RPC socket, e.g. /run/user/1000/nvim.12345.0   (required)
  --title    quickfix list title shown in :copen
  --no-jump  set the list but leave the cursor where it is
  --copen    also open the quickfix window (changes the window layout)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --socket) SOCKET="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --no-jump) JUMP=0; shift ;;
    --copen) COPEN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "push_qf.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$SOCKET" ]] || { echo "push_qf.sh: --socket is required" >&2; exit 2; }
[[ -S "$SOCKET" ]] || { echo "push_qf.sh: not a socket: $SOCKET" >&2; exit 1; }

WHAT=$(mktemp "${TMPDIR:-/tmp}/claude-qf-XXXXXX.json")
trap 'rm -f "$WHAT"' EXIT

items=$(cat)
[[ -n "${items//[[:space:]]/}" ]] || { echo "push_qf.sh: no entries on stdin" >&2; exit 2; }

esc_title=${TITLE//\\/\\\\}
esc_title=${esc_title//\"/\\\"}
printf '{"title":"%s","items":%s}' "$esc_title" "$items" > "$WHAT"

# --remote-expr is a blocking rpcrequest: a modal prompt in the target session
# (hit-enter, a confirm dialog) would otherwise hang this script forever.
remote_expr() {
  timeout 10 nvim --server "$SOCKET" --remote-expr "$1"
}

if ! remote_expr 'setqflist([], "r", json_decode(join(readfile("'"$WHAT"'"), "\n")))' > /dev/null; then
  echo "push_qf.sh: setqflist failed (session busy, or malformed entries)" >&2
  exit 1
fi

size=$(remote_expr 'getqflist({"size": 1}).size')
echo "pushed $size entr$([[ "$size" == 1 ]] && echo y || echo ies) to $SOCKET"

if (( JUMP )); then
  # execute() rather than --remote-send: it jumps without forcing normal mode, so it
  # does not yank the user out of insert if they are mid-typing.
  cmd=$( (( COPEN )) && echo 'botright copen | cfirst' || echo 'cfirst' )
  if ! remote_expr "execute(\"$cmd\")" > /dev/null; then
    echo "push_qf.sh: list is set but the jump failed" >&2
    exit 1
  fi
  echo "cursor now at: $(remote_expr 'expand("%:p") . ":" . line(".") . ":" . col(".")')"
fi
