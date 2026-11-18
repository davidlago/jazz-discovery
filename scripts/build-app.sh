#!/usr/bin/env bash
# Builds "build/Jazz Discovery.app" (Release, Apple Silicon + Intel), ad-hoc signed unless SIGN_IDENTITY is set.
#
#   VERSION=0.1.0   version shown in Finder and About (default: 0.0.0-dev)
#   BUILD=42        build number (default: 1)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#                   sign with this certificate (hardened runtime and a secure timestamp, which notarization needs:
#                   scripts/notarize.sh) instead of ad hoc. The team comes from the identity's name.
#   PROVISIONING_PROFILE=path/to/JazzDiscovery.provisionprofile
#                   a Developer ID profile for io.github.davidlago.JazzDiscovery with iCloud (docs/app-store.md,
#                   scripts/provisioning-profiles.swift --developer-id), embedded in the app, which is then signed with
#                   Config/JazzDiscovery-iCloud.entitlements so the passport syncs (PassportSync). Needs SIGN_IDENTITY.
#                   Without a profile the app has no iCloud: the passport stays on this Mac.
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
           OTHER_CODE_SIGN_FLAGS="--timestamp"
           CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)  # no get-task-allow: notarization refuses it
else
    args+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="")
fi

# iCloud is a restricted entitlement: a Developer ID app may only have it with an embedded profile that allows it.
ICLOUD=""
if [[ -n "${PROVISIONING_PROFILE:-}" ]]; then
    fail() { echo "error: $1" >&2; exit 1; }
    [[ -n "${SIGN_IDENTITY:-}" ]] || fail "PROVISIONING_PROFILE needs SIGN_IDENTITY (an ad-hoc signature can't use a profile)"
    mkdir -p build
    PROFILE_PLIST="$(mktemp build/profile.XXXXXX)"
    trap 'rm -f "$PROFILE_PLIST"' EXIT
    security cms -D -i "$PROVISIONING_PROFILE" > "$PROFILE_PLIST" 2> /dev/null \
        || fail "can't read the provisioning profile $PROVISIONING_PROFILE"
    field() { /usr/libexec/PlistBuddy -c "Print :$1" "$PROFILE_PLIST" 2> /dev/null || true; }
    BUNDLE_ID="$(xcodebuild -project JazzDiscovery.xcodeproj -target JazzDiscovery -configuration Release \
        -showBuildSettings -json 2> /dev/null | plutil -extract 0.buildSettings.PRODUCT_BUNDLE_IDENTIFIER raw -)"
    [[ "$(field Entitlements:com.apple.developer.team-identifier)" == "$team" ]] \
        || fail "the profile is for team $(field Entitlements:com.apple.developer.team-identifier), not $team"
    [[ "$(field Entitlements:com.apple.application-identifier)" == "$team.$BUNDLE_ID" ]] \
        || fail "the profile is for $(field Entitlements:com.apple.application-identifier), not $team.$BUNDLE_ID"
    [[ "$(field Platform:0)" == OSX ]] || fail "the profile isn't a macOS one (make a Developer ID profile)"
    [[ "$(field ProvisionsAllDevices)" == true ]] || fail "the profile isn't a Developer ID one"
    [[ -n "$(field Entitlements:com.apple.developer.ubiquity-kvstore-identifier)" ]] \
        || fail "the profile doesn't allow iCloud key-value storage; turn on iCloud for $BUNDLE_ID and make the profile again"
    # Xcode takes the profile by UUID from its profiles folder, embeds it as Contents/embedded.provisionprofile and
    # checks it (expiry, certificate, entitlements).
    uuid="$(field UUID)"
    for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
        mkdir -p "$dir" && cp "$PROVISIONING_PROFILE" "$dir/$uuid.provisionprofile"
    done
    args+=(CODE_SIGN_ENTITLEMENTS=Config/JazzDiscovery-iCloud.entitlements)
    ICLOUD=" with iCloud ($(field Name))"
fi
# No profile, no iCloud: Developer ID apps need none otherwise.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then args+=(PROVISIONING_PROFILE_SPECIFIER="${uuid:-}"); fi

echo "Building Jazz Discovery $VERSION ($BUILD)${ICLOUD}…"
xcodebuild "${args[@]}" -quiet clean build

rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/Jazz Discovery.app" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ -n "$ICLOUD" ]]; then
    [[ -f "$APP/Contents/embedded.provisionprofile" ]] || { echo "error: the profile wasn't embedded" >&2; exit 1; }
    codesign -d --entitlements - --xml "$APP" 2> /dev/null | grep -q ubiquity-kvstore-identifier \
        || { echo "error: the app isn't signed with iCloud key-value storage" >&2; exit 1; }
fi
lipo -archs "$APP/Contents/MacOS/Jazz Discovery"
echo "Built $APP${ICLOUD}"
