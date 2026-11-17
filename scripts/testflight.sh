#!/usr/bin/env bash
# Archives the iPhone app and uploads it to App Store Connect for TestFlight (and, from there, App Review).
# Needs a paid Apple Developer Program team (iOS/Signing.xcconfig, or DEVELOPMENT_TEAM in iOS/Local.xcconfig) and the
# app's record in App Store Connect (docs/app-store.md). Releases upload from CI (the `testflight` job in
# .github/workflows/ci.yml), which signs with DISTRIBUTION_CERTIFICATE=1. On a Mac, signing is automatic: Xcode creates
# the App Store profile as needed and signs with your Apple Distribution certificate (or a cloud-managed one), using
# the account in Xcode ▸ Settings ▸ Accounts, or an App Store Connect API key.
#
#   VERSION=1.1          version (default: MARKETING_VERSION in iOS/Version.xcconfig)
#   BUILD=202611171530   build number (default: the current UTC time, so every upload gets a new, higher one)
#   UPLOAD=0             export build/testflight/Jazz Discovery.ipa instead of uploading it
#   DEVELOPMENT_TEAM=…   another team
#   ASC_KEY=path/to/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER=…
#                        sign in with an App Store Connect API key instead of the account in Xcode
#   DISTRIBUTION_CERTIFICATE=1
#                        sign manually with the Apple Distribution certificate in the keychain and an App Store profile
#                        made for it with the API key (scripts/provisioning-profiles.swift); for CI, where there's no
#                        development certificate and an App Manager API key can't use cloud signing
#   LASTFM_API_KEY=… LASTFM_SHARED_SECRET=…
#                        build in the app's own Last.fm API account (see iOS/Signing.xcconfig)
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
ARCHIVE=build/JazzDiscoveryMobile.xcarchive
EXPORT=build/testflight

SETTINGS=(CURRENT_PROJECT_VERSION="$BUILD")
if [[ -n "${VERSION:-}" ]]; then SETTINGS+=(MARKETING_VERSION="$VERSION"); fi
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then SETTINGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"); fi
if [[ -n "${LASTFM_API_KEY:-}" && -n "${LASTFM_SHARED_SECRET:-}" ]]; then
    SETTINGS+=(LASTFM_API_KEY="$LASTFM_API_KEY" LASTFM_SHARED_SECRET="$LASTFM_SHARED_SECRET")
fi

AUTH=()
if [[ -n "${ASC_KEY:-}" ]]; then
    ASC_KEY="$(cd "$(dirname "$ASC_KEY")" && pwd)/$(basename "$ASC_KEY")"
    AUTH=(-authenticationKeyPath "$ASC_KEY"
          -authenticationKeyID "${ASC_KEY_ID:?set ASC_KEY_ID}" -authenticationKeyIssuerID "${ASC_ISSUER:?set ASC_ISSUER}")
fi

# The App Store refuses builds from a beta Xcode.
if xcodebuild -version | grep -qi beta || [[ "$(xcode-select -p)" == *[Bb]eta* ]]; then
    echo "error: $(xcode-select -p) is a beta Xcode; App Store Connect only accepts builds from a release Xcode" >&2
    exit 1
fi

python3 -I scripts/validate-data.py

PROFILES=()   # bundle ID, profile name, … for manual signing
if [[ "${DISTRIBUTION_CERTIFICATE:-0}" == "1" ]]; then
    [[ -n "${ASC_KEY:-}" ]] || { echo "error: DISTRIBUTION_CERTIFICATE=1 needs ASC_KEY, ASC_KEY_ID and ASC_ISSUER" >&2; exit 1; }
    # Manual signing with an App Store profile for that certificate (scripts/provisioning-profiles.swift names it
    # "<bundle ID> App Store (CI)"): automatic signing can't be told to use it, and the profiles Xcode manages for
    # cloud signing don't include it.
    BUNDLE_ID="$(xcodebuild -project JazzDiscovery.xcodeproj -target JazzDiscoveryMobile -configuration Release \
        -showBuildSettings -json "${SETTINGS[@]}" 2> /dev/null | plutil -extract 0.buildSettings.PRODUCT_BUNDLE_IDENTIFIER raw -)" \
        || { echo "error: couldn't read the iPhone app's bundle ID" >&2; exit 1; }
    swift scripts/provisioning-profiles.swift "$ASC_KEY" "$ASC_KEY_ID" "$ASC_ISSUER" "$BUNDLE_ID"
    PROFILES+=("$BUNDLE_ID" "$BUNDLE_ID App Store (CI)")
    SETTINGS+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution"
               PROVISIONING_PROFILE_SPECIFIER='$(PRODUCT_BUNDLE_IDENTIFIER) App Store (CI)')
fi

rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild -project JazzDiscovery.xcodeproj -scheme JazzDiscoveryMobile -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
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
$(if [[ ${#PROFILES[@]} -gt 0 ]]; then
    echo "    <key>signingStyle</key><string>manual</string>"
    echo "    <key>signingCertificate</key><string>Apple Distribution</string>"
    echo "    <key>provisioningProfiles</key><dict>"
    for ((i = 0; i < ${#PROFILES[@]}; i += 2)); do echo "        <key>${PROFILES[i]}</key><string>${PROFILES[i+1]}</string>"; done
    echo "    </dict>"
else
    echo "    <key>signingStyle</key><string>automatic</string>"
fi)
$([[ -n "${DEVELOPMENT_TEAM:-}" ]] && echo "    <key>teamID</key><string>$DEVELOPMENT_TEAM</string>")
    <key>manageAppVersionAndBuildNumber</key><false/>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$OPTIONS" \
    -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist")"
if [[ "${UPLOAD:-1}" == "1" ]]; then
    echo "Uploaded Jazz Discovery $VERSION ($BUILD). It shows up in App Store Connect ▸ TestFlight once Apple has processed it."
else
    echo "Exported $EXPORT/Jazz Discovery.ipa ($VERSION, $BUILD)"
fi
