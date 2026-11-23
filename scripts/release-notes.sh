#!/bin/zsh
# Builds the Sparkle release notes for one version.
#
#   scripts/release-notes.sh <version> <output.html>
#
# Joins release-notes/<v>.html for every version up to and including <version>, newest first,
# with <hr> between them. Sparkle only shows the newest update's notes, so this way someone who
# skipped versions still sees everything they missed.
#
# Each file is an HTML fragment (no <html> or <body>), so generate_appcast embeds it in the
# appcast and Sparkle styles it for light and dark mode.
#
# Optional env: NOTES_DIR (default release-notes)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release-notes.sh <version> <output.html>}
OUT=${2:?usage: scripts/release-notes.sh <version> <output.html>}
NOTES_DIR=${NOTES_DIR:-release-notes}

if [[ ! -f $NOTES_DIR/$VERSION.html ]]; then
  echo "Missing $NOTES_DIR/$VERSION.html. Write the notes for $VERSION first." >&2
  exit 1
fi

found=false
first=true
: > "$OUT"
for v in $(ls "$NOTES_DIR" | sed -n 's/\.html$//p' | sort -rV); do
  [[ $v == "$VERSION" ]] && found=true
  $found || continue # newer than VERSION
  $first || print "\n<hr>\n" >> "$OUT"
  cat "$NOTES_DIR/$v.html" >> "$OUT"
  first=false
done
echo "Wrote $OUT" >&2
