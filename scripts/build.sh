#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP_NAME="Kimer"
APP=".build/${APP_NAME}.app"

# Defaults to ad-hoc signing so anyone can build locally without a Developer ID.
# Override with `KIMER_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build.sh`
SIGNING_IDENTITY="${KIMER_SIGNING_IDENTITY:--}"
ENTITLEMENTS="App/Kimer.entitlements"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH=".build/${CONFIG}/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "ERROR: built binary not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> packaging ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${APP_NAME}"
cp App/Info.plist "${APP}/Contents/Info.plist"
if [[ -d Resources ]]; then
    find Resources -mindepth 1 -maxdepth 1 -exec cp -R {} "${APP}/Contents/Resources/" \; 2>/dev/null || true
fi
if [[ -f App/AppIcon.icns ]]; then
    cp App/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
fi

echo "==> codesign as ${SIGNING_IDENTITY}"
# Hardened Runtime (--options runtime) and a secure timestamp are required for
# Apple notarization. The empty entitlements file is intentional — we don't
# need any sandbox/exception flags; including the file just makes the cert
# requirement deterministic across builds.
SIGN_ARGS=(
    --force
    --options runtime
    --entitlements "${ENTITLEMENTS}"
    --sign "${SIGNING_IDENTITY}"
)
if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
    SIGN_ARGS+=(--timestamp)
fi
codesign "${SIGN_ARGS[@]}" "${APP}"

echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "${APP}" 2>&1 | sed 's/^/    /'

echo "==> built ${APP}"
