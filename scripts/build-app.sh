#!/usr/bin/env bash
# Builds "build/Jazz Discovery.app" (Release, Apple Silicon + Intel), ad-hoc signed unless SIGN_IDENTITY is set.
#
#   VERSION=0.1.0   version shown in Finder and About (default: 0.0.0-dev)
#   BUILD=42        build number (default: 1)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#                   sign with this certificate (hardened runtime and a secure timestamp, which notarization needs:
#                   scripts/notarize.sh) instead of ad hoc. The team comes from the identity's name.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
BUILD="${BUILD:-1}"
APP="build/Jazz Discovery.app"
DERIVED=build/DerivedData

args=(
    -project JazzDiscovery.xcodeproj -scheme JazzDiscovery -configuration Release
    -derivedDataPath "$DERIVED" -destination "generic/platform=macOS"
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD"
)
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    team="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<< "$SIGN_IDENTITY")"
    [[ -n "$team" ]] || { echo "error: no team ID in \"$SIGN_IDENTITY\"" >&2; exit 1; }
    args+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$team"
           PROVISIONING_PROFILE_SPECIFIER="" OTHER_CODE_SIGN_FLAGS="--timestamp"
           CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)  # no get-task-allow: notarization refuses it
else
    args+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="")
fi

echo "Building Jazz Discovery $VERSION ($BUILD)…"
xcodebuild "${args[@]}" -quiet clean build

rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/Jazz Discovery.app" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/Jazz Discovery"
echo "Built $APP"
