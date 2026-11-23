#!/bin/zsh
# Builds, signs, notarizes and (optionally) publishes a LightSpot release.
#
#   scripts/release.sh <version>            build everything into build/release-<version>/
#   scripts/release.sh <version> --publish  upload that build as a GitHub release
#
# Before running: set MARKETING_VERSION to <version> and raise CURRENT_PROJECT_VERSION in
# project.yml, write release-notes/<version>.html, and commit. See RELEASING.md.
#
# Runs on the maintainer's Mac: it needs the Developer ID certificate, the PME-Notarize
# notarytool profile and the LightSpot Sparkle key, all in the login keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep in sync with scripts/ExportOptions.plist and RELEASING.md.
SIGN_CERT=C676346A951EA1DC3A58303A578EC657C226DC10 # Developer ID Application (G2)
TEAM=A83U72R947
NOTARY_PROFILE=PME-Notarize
SPARKLE_ACCOUNT=lightspot
REPO=MarinadedDuck/LightSpot

VERSION=${1:?usage: scripts/release.sh <version> [--publish]}
MODE=${2:-build}
[[ $MODE == build || $MODE == --publish ]] || { echo "usage: scripts/release.sh <version> [--publish]" >&2; exit 2; }

OUT=build/release-$VERSION
DMG=$OUT/updates/LightSpot-$VERSION.dmg
APPCAST=$OUT/updates/appcast.xml
DD=build/DerivedData
SPARKLE_BIN=$DD/SourcePackages/artifacts/sparkle/Sparkle/bin

step() { print -P "\n%B==> $*%b" }
die() { print -P "%F{red}error:%f $*" >&2; exit 1 }

# notarize <file>: submit, wait, and show Apple's log if it isn't accepted.
notarize() {
  local result id notary_status
  result=$(xcrun notarytool submit "$1" --keychain-profile $NOTARY_PROFILE --wait --output-format plist)
  id=$(plutil -extract id raw - <<<"$result")
  notary_status=$(plutil -extract status raw - <<<"$result")
  if [[ $notary_status != Accepted ]]; then
    xcrun notarytool log "$id" --keychain-profile $NOTARY_PROFILE >&2 || true
    die "notarization of $1 returned '$notary_status' (submission $id)"
  fi
  echo "Notarized $1 ($id)"
}

leaf_cert_sha1() { # leaf_cert_sha1 <signed path>
  local tmp=$(mktemp -d)
  codesign -d --extract-certificates="$tmp/cert" "$1" 2>/dev/null
  openssl x509 -inform der -in "$tmp/cert0" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g'
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------------------------
if [[ $MODE == --publish ]]; then
  step "Checking build/release-$VERSION"
  [[ -f $DMG && -f $APPCAST && -f $OUT/COMMIT ]] || die "no finished build in $OUT. Run scripts/release.sh $VERSION first."
  xcrun stapler validate -q "$DMG" || die "$DMG isn't stapled"
  [[ $(git rev-parse HEAD) == $(<$OUT/COMMIT) ]] || die "HEAD has moved since this build. Rebuild with scripts/release.sh $VERSION."
  git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote. Create the GitHub repo and push first."
  git fetch -q origin
  [[ $(git rev-parse HEAD) == $(git rev-parse origin/main 2>/dev/null) ]] || die "HEAD isn't pushed to origin/main. Push first."
  gh release view "v$VERSION" --repo $REPO >/dev/null 2>&1 && die "release v$VERSION already exists on GitHub"

  print "\nAbout to publish LightSpot $VERSION to github.com/$REPO as the latest release."
  print "Installed copies with automatic checks on will be offered it within a day."
  read -q "?Publish now? [y/N] " || { print "\nNot published."; exit 1 }
  print

  step "Creating GitHub release v$VERSION"
  gh release create "v$VERSION" "$DMG" "$APPCAST" --repo $REPO \
    --target "$(git rev-parse HEAD)" --latest \
    --title "LightSpot $VERSION" --notes-file "release-notes/$VERSION.html" --generate-notes

  step "Checking the live feed"
  sleep 3
  live=$(curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml") || die "couldn't fetch the published appcast"
  grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" <<<"$live" \
    || die "the latest appcast doesn't list $VERSION yet. Check the release on GitHub."
  print -P "\n%F{green}Published LightSpot $VERSION.%f https://github.com/$REPO/releases/tag/v$VERSION"
  exit 0
fi

# ---------------------------------------------------------------------------------------------
step "Checking the release is ready"
[[ -z $(git status --porcelain) ]] || die "uncommitted changes. Commit them first so the release matches a commit."
grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml || die "project.yml MARKETING_VERSION isn't $VERSION"
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml)
[[ -f release-notes/$VERSION.html ]] || die "missing release-notes/$VERSION.html"
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && die "tag v$VERSION already exists"
command -v xcodegen >/dev/null || die "xcodegen isn't installed (brew install xcodegen)"
grep -q "^LIGHTSPOT_TEAM *= *$TEAM" Config/Signing.local.xcconfig 2>/dev/null \
  || die "Config/Signing.local.xcconfig must set LIGHTSPOT_TEAM = $TEAM (see RELEASING.md)"
security find-identity -v -p codesigning | grep -q $SIGN_CERT || die "Developer ID certificate $SIGN_CERT isn't in the keychain"
[[ $(/usr/libexec/PlistBuddy -c "Print :signingCertificate" scripts/ExportOptions.plist) == $SIGN_CERT ]] \
  || die "scripts/ExportOptions.plist doesn't pin $SIGN_CERT"
xcrun notarytool history --keychain-profile $NOTARY_PROFILE >/dev/null 2>&1 \
  || die "notarytool profile $NOTARY_PROFILE is missing or its password no longer works"
echo "LightSpot $VERSION (build $BUILD) from commit $(git rev-parse --short HEAD)"

step "Generating the project and resolving packages"
xcodegen generate --quiet
xcodebuild -resolvePackageDependencies -project LightSpot.xcodeproj -scheme LightSpot -derivedDataPath $DD -quiet
PUBLIC_KEY=$(sed -n 's/.*SUPublicEDKey: *//p' project.yml)
[[ $("$SPARKLE_BIN/generate_keys" --account $SPARKLE_ACCOUNT -p) == "$PUBLIC_KEY" ]] \
  || die "the '$SPARKLE_ACCOUNT' Sparkle key in the keychain doesn't match SUPublicEDKey in project.yml"

rm -rf $OUT && mkdir -p $OUT/updates

step "Archiving"
xcodebuild archive -project LightSpot.xcodeproj -scheme LightSpot -configuration Release \
  -derivedDataPath $DD -archivePath $OUT/LightSpot.xcarchive -quiet

step "Exporting with Developer ID"
xcodebuild -exportArchive -archivePath $OUT/LightSpot.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath $OUT/export -quiet
APP=$OUT/export/LightSpot.app
codesign --verify --deep --strict "$APP"
[[ $(leaf_cert_sha1 "$APP") == $SIGN_CERT ]] || die "the app wasn't signed with $SIGN_CERT"
[[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist") == $VERSION ]] \
  || die "the exported app isn't version $VERSION"

step "Notarizing the app"
ditto -c -k --keepParent "$APP" $OUT/notarize.zip
notarize $OUT/notarize.zip
xcrun stapler staple -q "$APP"

step "Building the DMG"
DMG_SIGN_IDENTITY=$SIGN_CERT scripts/make-dmg.sh "$APP" "$DMG"
[[ $(leaf_cert_sha1 "$DMG") == $SIGN_CERT ]] || die "the DMG wasn't signed with $SIGN_CERT"

step "Notarizing the DMG"
notarize "$DMG"
xcrun stapler staple -q "$DMG"

step "Checking with Gatekeeper"
spctl -a -vv "$APP" 2>&1 | grep -q "source=Notarized Developer ID" || die "Gatekeeper doesn't accept the app"
spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | grep -q "source=Notarized Developer ID" \
  || die "Gatekeeper doesn't accept the DMG"
echo "App and DMG accepted as Notarized Developer ID"

step "Generating the Sparkle appcast"
scripts/release-notes.sh "$VERSION" "$OUT/updates/LightSpot-$VERSION.html"
appcast_log=$("$SPARKLE_BIN/generate_appcast" --account $SPARKLE_ACCOUNT "$OUT/updates" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --full-release-notes-url "https://github.com/$REPO/releases/tag/v$VERSION" \
  --link "https://github.com/$REPO" 2>&1) || { print -r -- "$appcast_log" >&2; die "generate_appcast failed" }
print -r -- "$appcast_log" | grep -v deprecated || true
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$APPCAST" || die "appcast doesn't list $VERSION"
grep -q "sparkle:edSignature=" "$APPCAST" || die "appcast entry isn't signed"

git rev-parse HEAD > $OUT/COMMIT
print -P "\n%F{green}Built LightSpot $VERSION (build $BUILD).%f"
echo "  DMG:     $DMG"
echo "  Appcast: $APPCAST"
echo "  SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "\nInstall the DMG and try it. When it's good, push and run:  scripts/release.sh $VERSION --publish"
