#!/usr/bin/env bash
# Builds "build/Jazz Discovery.app" (Release, Apple Silicon + Intel, with its widgets), ad-hoc signed unless
# SIGN_IDENTITY is set.
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
#   WIDGETS_PROVISIONING_PROFILE=path/to/JazzDiscovery.Widgets.provisionprofile
#                   the widgets' Developer ID profile (io.github.davidlago.JazzDiscovery.Widgets), with
#                   PROVISIONING_PROFILE: both are then signed with the app group, through which the app tells the
#                   widgets where you are on a path. Without it the widgets show only what needs no passport.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
BUILD="${BUILD:-1}"
APP="build/Jazz Discovery.app"
WIDGETS="$APP/Contents/PlugIns/JazzDiscoveryWidgets.appex"
DERIVED=build/DerivedData
fail() { echo "error: $1" >&2; exit 1; }

args=(
    -project JazzDiscovery.xcodeproj -scheme JazzDiscovery -configuration Release
    -derivedDataPath "$DERIVED" -destination "generic/platform=macOS"
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD"
)
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    team="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<< "$SIGN_IDENTITY")"
    [[ -n "$team" ]] || fail "no team ID in \"$SIGN_IDENTITY\""
    args+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$team"
           OTHER_CODE_SIGN_FLAGS="--timestamp"
           CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)  # no get-task-allow: notarization refuses it
else
    args+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="")
fi

setting() {
    xcodebuild -project JazzDiscovery.xcodeproj -target "$1" -configuration Release -sdk macosx -showBuildSettings -json \
        2> /dev/null | plutil -extract "0.buildSettings.$2" raw -
}

# Reads a Developer ID profile into $SIGNING/<name>.plist, checks it's for this team and bundle ID, and installs it
# where Xcode looks for profiles. Prints its UUID.
SIGNING=build/signing
check_profile() {   # <path> <bundle ID> <name>
    local plist="$SIGNING/$3.plist"
    security cms -D -i "$1" > "$plist" 2> /dev/null || fail "can't read the provisioning profile $1"
    field() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2> /dev/null || true; }
    [[ "$(field Entitlements:com.apple.developer.team-identifier)" == "$team" ]] \
        || fail "$1 is for team $(field Entitlements:com.apple.developer.team-identifier), not $team"
    [[ "$(field Entitlements:com.apple.application-identifier)" == "$team.$2" ]] \
        || fail "$1 is for $(field Entitlements:com.apple.application-identifier), not $team.$2"
    [[ "$(field Platform:0)" == OSX ]] || fail "$1 isn't a macOS profile (make a Developer ID one)"
    [[ "$(field ProvisionsAllDevices)" == true ]] || fail "$1 isn't a Developer ID profile"
    local uuid; uuid="$(field UUID)"
    # Xcode takes a profile by UUID from its profiles folder, embeds it as embedded.provisionprofile and checks it
    # (expiry, certificate, entitlements).
    for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
        mkdir -p "$dir" && cp "$1" "$dir/$uuid.provisionprofile"
    done
    echo "$uuid"
}
allows() {   # <name> <entitlement> [value]: whether that profile allows the entitlement (with that value)
    local v
    v="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:$2" "$SIGNING/$1.plist" 2> /dev/null)" || return 1
    [[ -z "${3:-}" ]] || sed 's/^ *//' <<< "$v" | grep -qxF -e "$3" -e '*'
}

# iCloud and the app group are restricted entitlements: a Developer ID app may only have them with an embedded profile
# that allows them.
EXTRAS=""
if [[ -n "${PROVISIONING_PROFILE:-}" ]]; then
    [[ -n "${SIGN_IDENTITY:-}" ]] || fail "PROVISIONING_PROFILE needs SIGN_IDENTITY (an ad-hoc signature can't use a profile)"
    rm -rf "$SIGNING" && mkdir -p "$SIGNING"
    BUNDLE_ID="$(setting JazzDiscovery PRODUCT_BUNDLE_IDENTIFIER)"
    app_uuid="$(check_profile "$PROVISIONING_PROFILE" "$BUNDLE_ID" app)"
    allows app com.apple.developer.ubiquity-kvstore-identifier \
        || fail "the profile doesn't allow iCloud key-value storage; turn on iCloud for $BUNDLE_ID and make the profile again"
    cp Config/JazzDiscovery-iCloud.entitlements "$SIGNING/JazzDiscovery.entitlements"
    args+=(MAC_APP_PROFILE="$app_uuid" MAC_APP_ENTITLEMENTS="$SIGNING/JazzDiscovery.entitlements")
    EXTRAS="iCloud"

    if [[ -n "${WIDGETS_PROVISIONING_PROFILE:-}" ]]; then
        WIDGETS_ID="$(setting JazzDiscoveryWidgets PRODUCT_BUNDLE_IDENTIFIER)"
        GROUP="$(setting JazzDiscovery APP_GROUP_IDENTIFIER)"
        widgets_uuid="$(check_profile "$WIDGETS_PROVISIONING_PROFILE" "$WIDGETS_ID" widgets)"
        for name in app widgets; do
            allows "$name" com.apple.security.application-groups "$GROUP" \
                || fail "the $name profile doesn't allow the app group $GROUP; assign it to the App ID and make the profile again"
        done
        cp Config/JazzDiscoveryWidgets.entitlements "$SIGNING/JazzDiscoveryWidgets.entitlements"
        for file in JazzDiscovery JazzDiscoveryWidgets; do
            /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" \
                -c "Add :com.apple.security.application-groups:0 string $GROUP" "$SIGNING/$file.entitlements" > /dev/null
        done
        args+=(MAC_WIDGET_PROFILE="$widgets_uuid" MAC_WIDGET_ENTITLEMENTS="$SIGNING/JazzDiscoveryWidgets.entitlements"
               APP_GROUP_IN_USE="$GROUP")
        EXTRAS+=" and the app group"
    fi
fi

echo "Building Jazz Discovery $VERSION ($BUILD)${EXTRAS:+ with $EXTRAS}…"
xcodebuild "${args[@]}" -quiet clean build

rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/Jazz Discovery.app" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
[[ -d "$WIDGETS" ]] || fail "the widgets weren't embedded"
entitled() { codesign -d --entitlements - --xml "$1" 2> /dev/null | grep -q "$2"; }
if [[ -n "$EXTRAS" ]]; then
    [[ -f "$APP/Contents/embedded.provisionprofile" ]] || fail "the app's profile wasn't embedded"
    entitled "$APP" ubiquity-kvstore-identifier || fail "the app isn't signed with iCloud key-value storage"
fi
if [[ -n "${WIDGETS_PROVISIONING_PROFILE:-}" ]]; then
    [[ -f "$WIDGETS/Contents/embedded.provisionprofile" ]] || fail "the widgets' profile wasn't embedded"
    for bundle in "$APP" "$WIDGETS"; do
        entitled "$bundle" "$GROUP" || fail "$(basename "$bundle") isn't signed with the app group"
    done
fi
lipo -archs "$APP/Contents/MacOS/Jazz Discovery"
echo "Built $APP${EXTRAS:+ with $EXTRAS}"
