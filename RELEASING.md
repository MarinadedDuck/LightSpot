# Releasing LightSpot

Run these steps on the machine that has the **Developer ID Application** certificate and `notarytool` credentials.

## One-time setup

```bash
brew install xcodegen
```

Sign builds with the team instead of locally. Create `Config/Signing.local.xcconfig` (git ignores it):

```
LIGHTSPOT_TEAM = A83U72R947
LIGHTSPOT_SIGN_IDENTITY = Apple Development
```

`scripts/release.sh` checks this file is there. Without it, builds are signed locally, which is the default for contributors.

Notarization uses the team-wide notarytool profile `PME-Notarize` (team A83U72R947, shared with the maintainer's other apps). Check it with `xcrun notarytool history --keychain-profile PME-Notarize`. On a new machine, recreate it with `xcrun notarytool store-credentials PME-Notarize --apple-id <apple-id> --team-id A83U72R947` and an app-specific password from appleid.apple.com.

### Signing certificate

The keychain holds two "Developer ID Application: KEVIN DAVID LUTTMAN (A83U72R947)" certificates with the same name. Releases use the G2 one, SHA-1 `C676346A951EA1DC3A58303A578EC657C226DC10` (valid until 2031). The other is issued by Apple's original Developer ID intermediate, which expires on 1 February 2027. `scripts/ExportOptions.plist` pins the G2 certificate by its hash, and the DMG is signed by hash too, because the shared name is ambiguous to `codesign`. Changing certificates within the team doesn't affect users: macOS ties the Accessibility permission to the team ID, not the certificate.

### Sparkle signing key

Updates are signed with an EdDSA key used only for LightSpot. The private key lives in this Mac's login keychain under the account name `lightspot`, so every Sparkle command below passes `--account lightspot`. The public key is `SUPublicEDKey` in `project.yml`. Sparkle refuses any update that isn't signed with the private key, so only this machine can ship updates to installed copies.

Sparkle's command-line tools come with the package:

```bash
xcodebuild -resolvePackageDependencies -project LightSpot.xcodeproj -scheme LightSpot -derivedDataPath build/DerivedData
SPARKLE_BIN=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
```

- `$SPARKLE_BIN/generate_keys --account lightspot -p` prints the public key in the keychain. It must match `SUPublicEDKey`.
- **Back up the private key** with `$SPARKLE_BIN/generate_keys --account lightspot -x lightspot-sparkle-key`, store the file in a password manager, then delete it. On a new machine, import it with `generate_keys --account lightspot -f lightspot-sparkle-key`.
- If the key is ever lost, you can still switch to a new one in an update signed with the same Developer ID certificate. Sparkle accepts a change to the key or the certificate, but not both in the same update.

## Each release

1. **Bump the version** in `project.yml`: `MARKETING_VERSION` (e.g. `1.0.1`) and `CURRENT_PROJECT_VERSION` (always increase it; Sparkle compares this).
2. **Write the release notes** in `release-notes/<version>.html`: an HTML fragment (no `<html>` or `<body>`) with an `<h3>` heading and a short list, like `release-notes/1.0.0.html`. These appear in the update window and on the GitHub release page.
3. **Commit and push.**
4. **Build:**
   ```bash
   scripts/release.sh <version>
   ```
   This checks everything is in place, then archives, signs, notarizes and staples the app and the DMG, checks them with Gatekeeper, and writes the Sparkle appcast. It stops at the first problem. The results go in `build/release-<version>/`; `updates/` holds the DMG and `appcast.xml`.
5. **Try the DMG** from `build/release-<version>/updates/`.
6. **Publish:**
   ```bash
   scripts/release.sh <version> --publish
   ```
   This checks the build matches the pushed commit, asks for confirmation, creates the GitHub release with the DMG, appcast and notes, then checks that the live feed lists the new version. The release is marked as latest, because the app reads `releases/latest/download/appcast.xml`.

## What release.sh does

If a step fails or you need to run one by hand, these are the commands behind it. The script writes to `build/release-<version>/`; the paths below are the older manual layout.

1. **Generate and archive**
   ```bash
   xcodegen generate
   xcodebuild archive -project LightSpot.xcodeproj -scheme LightSpot -configuration Release \
     -archivePath build/LightSpot.xcarchive
   ```

2. **Export with Developer ID signing**
   ```bash
   xcodebuild -exportArchive -archivePath build/LightSpot.xcarchive \
     -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export
   ```

3. **Notarize and staple the app.** Stapling the app as well as the DMG means the app passes Gatekeeper offline once it is copied out of the DMG.
   ```bash
   ditto -c -k --keepParent build/export/LightSpot.app build/LightSpot-notarize.zip
   xcrun notarytool submit build/LightSpot-notarize.zip --keychain-profile PME-Notarize --wait
   xcrun stapler staple build/export/LightSpot.app
   ```

4. **Build, sign, notarize and staple the DMG**
   ```bash
   DMG_SIGN_IDENTITY=C676346A951EA1DC3A58303A578EC657C226DC10 \
     scripts/make-dmg.sh build/export/LightSpot.app
   xcrun notarytool submit build/LightSpot-<version>.dmg --keychain-profile PME-Notarize --wait
   xcrun stapler staple build/LightSpot-<version>.dmg
   ```

5. **Verify**
   ```bash
   spctl -a -vv build/export/LightSpot.app                       # "source=Notarized Developer ID"
   spctl -a -vv -t open --context context:primary-signature build/LightSpot-<version>.dmg
   ```

6. **Generate the Sparkle appcast.** The notarized DMG is also the update archive. Use a fresh folder for each release so the appcast lists only this version.
   ```bash
   mkdir -p build/updates-<version>
   cp build/LightSpot-<version>.dmg build/updates-<version>/
   scripts/release-notes.sh <version> build/updates-<version>/LightSpot-<version>.html
   $SPARKLE_BIN/generate_appcast --account lightspot build/updates-<version> \
     --download-url-prefix https://github.com/MarinadedDuck/LightSpot/releases/download/v<version>/ \
     --full-release-notes-url https://github.com/MarinadedDuck/LightSpot/releases/tag/v<version> \
     --link https://github.com/MarinadedDuck/LightSpot
   ```
   This signs the DMG with the LightSpot key in your keychain and writes `build/updates-<version>/appcast.xml`. Because `LightSpot-<version>.html` has the same name as the DMG, `generate_appcast` embeds it as the update's notes.

   Sparkle shows only the newest update's notes, so `release-notes.sh` includes every earlier version's notes below the new ones. Someone who skipped a version still sees what changed.

7. **Publish.** The release must be marked as latest: the app reads `releases/latest/download/appcast.xml`. Drafts and pre-releases aren't offered to users.
   ```bash
   gh release create v<version> build/LightSpot-<version>.dmg build/updates-<version>/appcast.xml \
     --title "LightSpot <version>" --notes-file release-notes/<version>.html --generate-notes
   ```

8. **Check the update.** With an older Release build installed, choose **Check for Updates…** from the menu bar icon's right-click menu. Debug builds never check for updates.

## Testing an update locally

To try an update before publishing, serve a test appcast from this Mac and point your installed copy at it:

```bash
# after building and notarizing a higher build into build/test-update/feed (with its notes)
$SPARKLE_BIN/generate_appcast --account lightspot build/test-update/feed --download-url-prefix http://127.0.0.1:8765/
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/test-update/feed
defaults write io.github.marinadedduck.LightSpot SUFeedURL http://127.0.0.1:8765/appcast.xml
```

Then choose **Check for Updates…**. Afterwards, go back to the real feed with `defaults delete io.github.marinadedduck.LightSpot SUFeedURL`.

## Still to do before 1.0

- [ ] Screenshot or GIF for the README.

## Regenerating artwork

- App icon: `LightSpot/AppIcon.icon`. Open it in Icon Composer (Xcode → Open Developer Tool), or edit the SVGs in `Assets/` directly.
- GitHub social preview: `swift Design/render-social-preview.swift` writes `Design/social-preview.png` (1280×640). Upload it in the repo's Settings → General → Social preview. It uses `Design/icon-1024.png`, exported from the compiled `AppIcon.icns`; re-export that if the icon changes.
- DMG background: `swift Design/render-dmg-background.swift`. Icon positions in `scripts/dmg-settings.py` must match the layout in that script.
