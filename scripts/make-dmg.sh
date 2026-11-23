#!/bin/zsh
# Packages an already-built (and ideally signed + notarized) LightSpot.app into a DMG.
#
#   scripts/make-dmg.sh path/to/LightSpot.app [output.dmg]
#
# Optional env:
#   DMG_SIGN_IDENTITY  codesign identity for the DMG: a SHA-1 hash or "Developer ID Application: Name (TEAMID)"
#
# Notarize and staple the resulting DMG afterwards (see RELEASING.md).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=${1:?usage: scripts/make-dmg.sh path/to/LightSpot.app [output.dmg]}
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT=${2:-build/LightSpot-$VERSION.dmg}

# dmgbuild writes the Finder layout directly (no AppleScript / Finder automation needed).
VENV=.build-tools/venv
# Recreate it if it's missing or broken (a venv stops working when the repo folder moves).
if ! $VENV/bin/dmgbuild --help >/dev/null 2>&1; then
  rm -rf $VENV
  python3 -m venv $VENV
  $VENV/bin/pip install --quiet "dmgbuild==1.6.5"
fi

# Rebuild the background if the PNGs are newer than the TIFF.
if [[ ! -f Design/dmg/background.tiff || Design/dmg/background@2x.png -nt Design/dmg/background.tiff ]]; then
  tiffutil -cathidpicheck Design/dmg/background.png Design/dmg/background@2x.png -out Design/dmg/background.tiff
fi

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
$VENV/bin/dmgbuild -s scripts/dmg-settings.py \
  -D app="$APP" -D background="Design/dmg/background.tiff" \
  "LightSpot" "$OUT"

if [[ -n "${DMG_SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$DMG_SIGN_IDENTITY" --timestamp "$OUT"
fi
echo "Created $OUT"
