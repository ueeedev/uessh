#!/usr/bin/env bash
# Builds a release uessh.app and packs it into dist/uessh-<version>.dmg.
#
#   tool/build_macos_dmg.sh
#
# Signing, picked automatically:
#   - A "Developer ID Application" certificate in your keychain (or the one
#     named in UESSH_SIGN_IDENTITY): the app and DMG are signed with it,
#     with the hardened runtime, so other Macs can open them.
#   - None: the app keeps Flutter's local ad-hoc signature. It runs on this
#     Mac; on other Macs Gatekeeper blocks it until the user allows it in
#     System Settings > Privacy & Security.
#
# Notarization (needs Developer ID): set UESSH_NOTARY_PROFILE to a keychain
# profile created once with
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team>
# and the DMG is submitted to Apple, waited on, and stapled.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME=uessh
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
APP="build/macos/Build/Products/Release/${APP_NAME}.app"
DIST=dist
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"
ENTITLEMENTS=macos/Runner/Release.entitlements

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

step "Building ${APP_NAME} ${VERSION} (release)"
flutter build macos --release

# --- signing -------------------------------------------------------------
IDENTITY="${UESSH_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)
fi

if [[ -n "$IDENTITY" ]]; then
  step "Signing with: ${IDENTITY}"
  # Inside out: nested frameworks and dylibs first, then the app itself.
  find "$APP/Contents/Frameworks" \( -name '*.framework' -o -name '*.dylib' \) \
    -maxdepth 1 -print0 |
    while IFS= read -r -d '' item; do
      codesign --force --timestamp --options runtime --sign "$IDENTITY" "$item"
    done
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  step "No Developer ID certificate found: keeping the local (ad-hoc) signature"
  echo "The app runs on this Mac. Other Macs will block it until allowed in"
  echo "System Settings > Privacy & Security (see the comment at the top)."
fi

# --- DMG -----------------------------------------------------------------
step "Packing ${DMG}"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"  # drag-to-install target
mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGING" \
  -ov -format UDZO -quiet "$DMG"

if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [[ -n "${UESSH_NOTARY_PROFILE:-}" ]]; then
    step "Notarizing (this can take a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$UESSH_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
  else
    echo "Signed but not notarized: set UESSH_NOTARY_PROFILE to notarize."
  fi
fi

step "Done"
ls -lh "$DMG"
