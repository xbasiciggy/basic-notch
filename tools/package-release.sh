#!/bin/bash
# Local: tools/package-release.sh
# Public: SIGN_IDENTITY='Developer ID Application: Name (TEAM)' NOTARY_PROFILE=profile tools/package-release.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION=1.1.0
IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == '-' ]]; then OUT="$ROOT/dist/preview"; else OUT="$ROOT/dist/release"; fi
if [[ "$IDENTITY" != '-' && -z "${NOTARY_PROFILE:-}" ]]; then
    echo 'Set NOTARY_PROFILE to a configured notarytool Keychain profile for public releases.' >&2
    exit 1
fi
mkdir -p "$OUT" "$ROOT/.build"
xcodebuild -project BasicNotch.xcodeproj -scheme BasicNotch -configuration Release \
    -derivedDataPath "$ROOT/.build" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO build
STAGE="$(mktemp -d "$ROOT/.build/release.XXXXXX")"
APP="$STAGE/BasicNotch.app"
ditto "$ROOT/.build/Build/Products/Release/BasicNotch.app" "$APP"
if [[ "$IDENTITY" == '-' ]]; then
    /usr/libexec/PlistBuddy -c 'Set :BasicNotchLocalPreview true' "$APP/Contents/Info.plist"
    codesign --force --sign - --options runtime --entitlements Config/Release.entitlements "$APP"
else
    /usr/libexec/PlistBuddy -c 'Set :BasicNotchLocalPreview false' "$APP/Contents/Info.plist"
    codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements Config/Release.entitlements "$APP"
    ditto -c -k --keepParent "$APP" "$STAGE/notarize.zip"
    xcrun notarytool submit "$STAGE/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
ARCH_LIST="$(lipo -archs "$APP/Contents/MacOS/BasicNotch")"
[[ " $ARCH_LIST " == *" arm64 "* && " $ARCH_LIST " == *" x86_64 "* ]]
DMGROOT="$STAGE/disk"
mkdir -p "$DMGROOT"
ditto "$APP" "$DMGROOT/BasicNotch.app"
ln -s /Applications "$DMGROOT/Applications"
if [[ "$IDENTITY" == '-' ]]; then
    echo 'LOCAL PREVIEW — NOT APPLE NOTARIZED' > "$DMGROOT/READ ME FIRST.txt"
    echo 'macOS may show a security warning. Only install a copy from a source you trust.' >> "$DMGROOT/READ ME FIRST.txt"
    echo 'This notice does not replace Apple signing or notarization.' >> "$DMGROOT/READ ME FIRST.txt"
    echo '' >> "$DMGROOT/READ ME FIRST.txt"
else
    echo 'DEVELOPER ID SIGNED — APPLE NOTARIZATION COMPLETED' > "$DMGROOT/READ ME FIRST.txt"
fi
cat Docs/USER-GUIDE.md >> "$DMGROOT/READ ME FIRST.txt"
ditto "$ROOT/BasicNotch/Resources/Lightroom.bundle/BasicNotchExport.lrplugin" "$DMGROOT/BasicNotchExport.lrplugin"
cp Docs/LIGHTROOM-SETUP.md "$DMGROOT/LIGHTROOM-SETUP.txt"
ditto -c -k --keepParent "$DMGROOT/BasicNotchExport.lrplugin" "$OUT/BasicNotch-Lightroom-Plugin-$VERSION.zip"
cp Docs/LIGHTROOM-SETUP.md "$OUT/LIGHTROOM-SETUP.md"
hdiutil create -volname BasicNotch -srcfolder "$DMGROOT" -format UDZO -ov "$OUT/BasicNotch-$VERSION.dmg"
if [[ "$IDENTITY" != '-' ]]; then
    codesign --sign "$IDENTITY" --timestamp "$OUT/BasicNotch-$VERSION.dmg"
    xcrun notarytool submit "$OUT/BasicNotch-$VERSION.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUT/BasicNotch-$VERSION.dmg"
    xcrun stapler validate "$OUT/BasicNotch-$VERSION.dmg"
    spctl --assess --type execute --verbose=2 "$APP"
fi
ditto "$APP" "$OUT/BasicNotch.app"
ditto -c -k --keepParent "$APP" "$OUT/BasicNotch-$VERSION.zip"
cp Docs/USER-GUIDE.md "$OUT/USER-GUIDE.md"
(cd "$OUT" && shasum -a 256 "BasicNotch-$VERSION.dmg" "BasicNotch-$VERSION.zip" "BasicNotch-Lightroom-Plugin-$VERSION.zip") > "$OUT/SHA256SUMS.txt"
echo "Packaged in $OUT (signing identity: $IDENTITY)"
