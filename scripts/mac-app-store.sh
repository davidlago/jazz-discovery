#!/usr/bin/env bash
# Archives the Mac app (Apple Silicon + Intel, with its widgets) and uploads it to App Store Connect for the Mac App
# Store, the way scripts/testflight.sh uploads the iPhone app. Both are the same app record (one bundle ID), so the
# upload shows up under the app's macOS platform, in TestFlight and for App Review (docs/app-store.md). Releases upload
# from CI (the `mac-app-store` job in .github/workflows/ci.yml), which signs with DISTRIBUTION_CERTIFICATE=1.
#
# The Mac App Store build is always signed with iCloud key-value storage and the app group (the App IDs have both), so
# the passport syncs and the widgets follow your path, as in the Developer ID release.
#
#   VERSION=1.1          version (default: MARKETING_VERSION in iOS/Version.xcconfig)
#   BUILD=202611171530   build number (default: the current UTC time, so every upload gets a new, higher one)
#   UPLOAD=0             export build/mac-app-store/Jazz Discovery.pkg instead of uploading it
#   DEVELOPMENT_TEAM=…   another team (default: iOS/Signing.xcconfig's)
#   ASC_KEY=path/to/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER=…
#                        sign in with an App Store Connect API key instead of the account in Xcode
#   DISTRIBUTION_CERTIFICATE=1
#                        sign manually with the Apple Distribution and "3rd Party Mac Developer Installer" certificates
#                        in the keychain (scripts/mac-installer-certificate.sh makes the second), and Mac App Store
#                        profiles made for the first with the API key (scripts/provisioning-profiles.swift
#                        --mac-app-store); for CI, where an App Manager API key can't use cloud signing
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "error: $1" >&2; exit 1; }
config_value() { sed -n "s/^ *$1 *= *\\([^ ]*\\).*/\\1/p" "$2" | head -1; }

BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
VERSION="${VERSION:-$(config_value MARKETING_VERSION iOS/Version.xcconfig)}"
[[ -n "$VERSION" ]] || fail "no VERSION, and no MARKETING_VERSION in iOS/Version.xcconfig"
TEAM="${DEVELOPMENT_TEAM:-$(config_value DEVELOPMENT_TEAM iOS/Signing.xcconfig)}"
[[ -n "$TEAM" ]] || fail "no DEVELOPMENT_TEAM"
ARCHIVE=build/JazzDiscovery-MacAppStore.xcarchive
EXPORT=build/mac-app-store
SIGNING=build/mac-app-store-signing

setting() {
    xcodebuild -project JazzDiscovery.xcodeproj -target "$1" -configuration Release -sdk macosx -showBuildSettings -json \
        2> /dev/null | plutil -extract "0.buildSettings.$2" raw - || fail "couldn't read $1's $2"
}
APP_ID="$(setting JazzDiscovery PRODUCT_BUNDLE_IDENTIFIER)"
WIDGETS_ID="$(setting JazzDiscoveryWidgets PRODUCT_BUNDLE_IDENTIFIER)"
GROUP="$(setting JazzDiscovery APP_GROUP_IDENTIFIER)"

# The entitlements: the app's with iCloud, and both with the app group (as scripts/build-app.sh signs the Developer ID
# release).
rm -rf "$SIGNING" && mkdir -p "$SIGNING"
cp Config/JazzDiscovery-iCloud.entitlements "$SIGNING/JazzDiscovery.entitlements"
cp Config/JazzDiscoveryWidgets.entitlements "$SIGNING/JazzDiscoveryWidgets.entitlements"
for file in JazzDiscovery JazzDiscoveryWidgets; do
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" \
        -c "Add :com.apple.security.application-groups:0 string $GROUP" "$SIGNING/$file.entitlements" > /dev/null
done

SETTINGS=(
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" DEVELOPMENT_TEAM="$TEAM"
    MAC_APP_ENTITLEMENTS="$SIGNING/JazzDiscovery.entitlements" MAC_WIDGET_ENTITLEMENTS="$SIGNING/JazzDiscoveryWidgets.entitlements"
    APP_GROUP_IN_USE="$GROUP"
)

AUTH=()
if [[ -n "${ASC_KEY:-}" ]]; then
    ASC_KEY="$(cd "$(dirname "$ASC_KEY")" && pwd)/$(basename "$ASC_KEY")"
    AUTH=(-authenticationKeyPath "$ASC_KEY"
          -authenticationKeyID "${ASC_KEY_ID:?set ASC_KEY_ID}" -authenticationKeyIssuerID "${ASC_ISSUER:?set ASC_ISSUER}")
fi

# The App Store refuses builds from a beta Xcode.
if xcodebuild -version | grep -qi beta || [[ "$(xcode-select -p)" == *[Bb]eta* ]]; then
    fail "$(xcode-select -p) is a beta Xcode; App Store Connect only accepts builds from a release Xcode"
fi

python3 -I scripts/validate-data.py

MANUAL=0
if [[ "${DISTRIBUTION_CERTIFICATE:-0}" == "1" ]]; then
    [[ -n "${ASC_KEY:-}" ]] || fail "DISTRIBUTION_CERTIFICATE=1 needs ASC_KEY, ASC_KEY_ID and ASC_ISSUER"
    security find-identity -v | grep -q '"3rd Party Mac Developer Installer: ' \
        || fail "no \"3rd Party Mac Developer Installer\" certificate in the keychain (scripts/mac-installer-certificate.sh)"
    swift scripts/provisioning-profiles.swift --mac-app-store "$ASC_KEY" "$ASC_KEY_ID" "$ASC_ISSUER" "$APP_ID" "$WIDGETS_ID"
    SETTINGS+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution"
               MAC_APP_PROFILE="$APP_ID Mac App Store (CI)" MAC_WIDGET_PROFILE="$WIDGETS_ID Mac App Store (CI)")
    MANUAL=1
fi

echo "Archiving Jazz Discovery $VERSION ($BUILD) for the Mac App Store…"
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild -project JazzDiscovery.xcodeproj -scheme JazzDiscovery -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
    "${SETTINGS[@]}" archive -quiet

OPTIONS_DIR="$(mktemp -d)"
trap 'rm -rf "$OPTIONS_DIR"' EXIT
OPTIONS="$OPTIONS_DIR/ExportOptions.plist"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$([[ "${UPLOAD:-1}" == "1" ]] && echo upload || echo export)</string>
    <key>teamID</key><string>$TEAM</string>
$(if [[ "$MANUAL" == 1 ]]; then
    echo "    <key>signingStyle</key><string>manual</string>"
    echo "    <key>signingCertificate</key><string>Apple Distribution</string>"
    echo "    <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer</string>"
    echo "    <key>provisioningProfiles</key><dict>"
    echo "        <key>$APP_ID</key><string>$APP_ID Mac App Store (CI)</string>"
    echo "        <key>$WIDGETS_ID</key><string>$WIDGETS_ID Mac App Store (CI)</string>"
    echo "    </dict>"
else
    echo "    <key>signingStyle</key><string>automatic</string>"
fi)
    <key>manageAppVersionAndBuildNumber</key><false/>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$OPTIONS" \
    -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

if [[ "${UPLOAD:-1}" == "1" ]]; then
    echo "Uploaded Jazz Discovery $VERSION ($BUILD) for the Mac. It shows up in App Store Connect ▸ TestFlight ▸ macOS once Apple has processed it."
else
    PKG="$EXPORT/Jazz Discovery.pkg"
    [[ -f "$PKG" ]] || fail "the export made no $PKG"
    pkgutil --check-signature "$PKG"
    echo "Exported $PKG ($VERSION, $BUILD)"
fi
