#!/usr/bin/env bash
#
# Build, notarize, and package Kimer into a distributable DMG.
#
# Prereqs (one-time):
#   - Developer ID Application certificate installed in the login keychain
#   - notarytool keychain profile created via `xcrun notarytool store-credentials`
#
# Env overrides:
#   KIMER_SIGNING_IDENTITY   default: ad-hoc ("-") — for distribution set this to
#                            your Developer ID Application identity
#   KIMER_NOTARY_PROFILE     default: KIMER_NOTARY
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROFILE="${KIMER_NOTARY_PROFILE:-KIMER_NOTARY}"
SIGNING_IDENTITY="${KIMER_SIGNING_IDENTITY:--}"
APP_NAME="Kimer"
APP=".build/${APP_NAME}.app"
DIST_DIR="dist"

if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    echo "ERROR: KIMER_SIGNING_IDENTITY must be set to a real Developer ID for release builds." >&2
    echo "       Example: KIMER_SIGNING_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\" ./scripts/release.sh" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" App/Info.plist)"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.zip"

mkdir -p "${DIST_DIR}"

echo "==> [1/7] build + sign as ${SIGNING_IDENTITY}"
KIMER_SIGNING_IDENTITY="${SIGNING_IDENTITY}" ./scripts/build.sh

echo "==> [2/7] zip .app for notarization"
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP}" "${ZIP_PATH}"

echo "==> [3/7] notarize .app (this may take a few minutes)"
xcrun notarytool submit "${ZIP_PATH}" \
    --keychain-profile "${PROFILE}" \
    --wait

echo "==> [4/7] staple .app"
xcrun stapler staple "${APP}"
spctl -a -vvv "${APP}" | sed 's/^/    /'

echo "==> [5/7] build .dmg"
STAGE_PARENT="$(mktemp -d)"
STAGE="${STAGE_PARENT}/${APP_NAME}"
mkdir -p "${STAGE}"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${STAGE}" \
    -ov -format UDZO \
    "${DMG_PATH}" >/dev/null

echo "==> [6/7] codesign + notarize .dmg"
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "${DMG_PATH}"
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${PROFILE}" \
    --wait

echo "==> [7/7] staple .dmg"
xcrun stapler staple "${DMG_PATH}"
spctl -a -t open --context context:primary-signature -vvv "${DMG_PATH}" | sed 's/^/    /' || true

# Cleanup the intermediate zip; the dmg is the deliverable.
rm -f "${ZIP_PATH}"

echo
echo "==> ✓ released: ${DMG_PATH}"
echo "    Recipient flow: double-click → drag Kimer into Applications → grant Input Monitoring on first launch."
