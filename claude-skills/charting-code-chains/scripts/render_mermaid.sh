#!/usr/bin/env bash
# Render a .mmd (or .md with mermaid blocks) to PNG using mermaid-cli driven by the
# system Chrome, so no Chromium is downloaded and nothing lands on PATH.
set -euo pipefail

IN="" OUT="" SCALE=3 BG=white
usage() { echo "usage: render_mermaid.sh -i IN.mmd -o OUT.png [-s scale=3] [-b bg=white]" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) IN="${2:-}"; shift 2 ;;
    -o) OUT="${2:-}"; shift 2 ;;
    -s) SCALE="${2:-}"; shift 2 ;;
    -b) BG="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "render_mermaid.sh: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "$IN" && -n "$OUT" ]] || { usage; exit 2; }
[[ -f "$IN" ]] || { echo "render_mermaid.sh: no such input: $IN" >&2; exit 1; }

CHROME=""
for c in "${PUPPETEER_EXECUTABLE_PATH:-}" /usr/bin/google-chrome /usr/bin/chromium \
         /usr/bin/chromium-browser /snap/bin/chromium; do
  [[ -n "$c" && -x "$c" ]] && { CHROME="$c"; break; }
done
[[ -n "$CHROME" ]] || {
  echo "render_mermaid.sh: no Chrome/Chromium found. Install one, or set" >&2
  echo "  PUPPETEER_EXECUTABLE_PATH=/path/to/chrome" >&2
  exit 1
}

CFG="$(mktemp -t puppeteer-XXXXXX.json)"
trap 'rm -f "$CFG"' EXIT
echo '{ "args": ["--no-sandbox", "--disable-setuid-sandbox"] }' > "$CFG"

PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
PUPPETEER_EXECUTABLE_PATH="$CHROME" \
  npx -y @mermaid-js/mermaid-cli@latest \
    -i "$IN" -o "$OUT" -p "$CFG" -b "$BG" -s "$SCALE" 2>&1 | grep -v 'npm notice' || true

[[ -s "$OUT" ]] || { echo "render_mermaid.sh: render produced no output" >&2; exit 1; }
echo "rendered: $OUT"
file -b "$OUT" | sed 's/^/  /'
