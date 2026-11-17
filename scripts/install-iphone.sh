#!/usr/bin/env bash
# Builds the iPhone app and installs it on a connected development iPhone, without an Apple ID in Xcode: it signs with
# the Apple Development certificate in the keychain and an installed development profile for the app's bundle ID that
# includes the phone: "Jazz Discovery Development" (developer.apple.com ▸ Profiles ▸ iOS App Development; it expires
# 2027-11-17). Apple Music needs that profile: signed with a wildcard profile (Xcode's "iOS Team Provisioning
# Profile: *"), the app installs but Apple won't give it a MusicKit token, so it falls back to previews.
#
#   scripts/install-iphone.sh            the first connected iPhone
#   DEVICE=<UDID> scripts/install-iphone.sh
#   CONFIGURATION=Debug                  instead of Release
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM=2M74C6J5ZY
BUNDLE_ID=io.github.davidlago.JazzDiscovery
CONFIGURATION="${CONFIGURATION:-Release}"
DEVICE="${DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && /available/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')}"
[[ -n "$DEVICE" ]] || { echo "error: no iPhone connected (or set DEVICE=<UDID>)" >&2; exit 1; }

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Apple Development: .*/\1/p' | head -1)"
[[ -n "$IDENTITY" ]] || { echo "error: no Apple Development certificate in the keychain" >&2; exit 1; }

# A development profile for this team that matches the bundle ID (exactly or by wildcard) and includes the phone.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PROFILE=""; PROFILE_APPID=""
for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
         ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision; do
    [[ -f "$f" ]] || continue
    security cms -D -i "$f" > "$TMP/p.plist" 2> /dev/null || continue
    appid="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$TMP/p.plist" 2> /dev/null)" || continue
    [[ "$appid" == "$TEAM.$BUNDLE_ID" || "$appid" == "$TEAM.*" ]] || continue
    /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$TMP/p.plist" 2> /dev/null | grep -q "$DEVICE" || continue
    expires="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$TMP/p.plist")"
    [[ "$(date -j -f '%a %b %d %T %Z %Y' "$expires" +%s 2> /dev/null || echo 0)" -gt "$(date +%s)" ]] || continue
    PROFILE="$f"; PROFILE_APPID="$appid"
    [[ "$appid" == "$TEAM.$BUNDLE_ID" ]] && break   # prefer the app's own profile over the wildcard
done
[[ -n "$PROFILE" ]] || { echo "error: no development profile for $BUNDLE_ID includes $DEVICE; make one in developer.apple.com ▸ Profiles and double-click it" >&2; exit 1; }
if [[ "$PROFILE_APPID" != "$TEAM.$BUNDLE_ID" ]]; then
    echo "warning: signing with a wildcard profile; Apple Music will only play previews" >&2
fi

xcodebuild -project JazzDiscovery.xcodeproj -scheme JazzDiscoveryMobile -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build -quiet
APP="build/device/Build/Products/$CONFIGURATION-iphoneos/Jazz Discovery.app"

cp "$PROFILE" "$APP/embedded.mobileprovision"
cat > "$TMP/app.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>application-identifier</key><string>$TEAM.$BUNDLE_ID</string>
    <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
    <key>get-task-allow</key><true/>
    <key>keychain-access-groups</key><array><string>$TEAM.$BUNDLE_ID</string></array>
</dict></plist>
PLIST
codesign --force --sign "$IDENTITY" --entitlements "$TMP/app.entitlements" --timestamp=none --generate-entitlement-der "$APP"

xcrun devicectl device install app --device "$DEVICE" "$APP" > /dev/null
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" > /dev/null
echo "Installed and launched Jazz Discovery ($CONFIGURATION) on $DEVICE"
