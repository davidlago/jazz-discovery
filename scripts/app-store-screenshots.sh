#!/usr/bin/env bash
# Takes the iPhone App Store screenshots in the simulator: docs/app-store/iphone-6.9 (iPhone 18 Pro Max,
# 1320 × 2868) and docs/app-store/iphone-6.3 (iPhone 18 Pro, 1206 × 2622). Each size gets its own simulator, made
# the first time, so the run doesn't disturb your others. The status bar shows 9:41 with full bars, and each screen is
# opened with the app's --open launch argument (a jazzdiscovery:// link; see iOS/JazzDiscoveryMobile/PhoneRouter.swift).
#
#   SIZES="6.3"     only some sizes (default: "6.9 6.3")
#   WAIT=10         seconds to let each screen's pictures load (default: 10)
set -euo pipefail

cd "$(dirname "$0")/.."

SIZES="${SIZES:-6.9 6.3}"
WAIT="${WAIT:-10}"
DERIVED=build/DerivedData-screenshots
APP="$DERIVED/Build/Products/Release-iphonesimulator/Jazz Discovery.app"
BUNDLE=io.github.davidlago.JazzDiscovery

# name|links (space-separated, opened in order)|extra seconds
SHOTS=(
    "01-timeline|jazzdiscovery://tab/discover|0"
    "02-era|jazzdiscovery://era/bebop|0"
    "03-artist|jazzdiscovery://artist/miles-davis|0"
    "04-album|jazzdiscovery://album/kind-of-blue|0"
    "05-connections|jazzdiscovery://between/louis-armstrong/herbie-hancock|4"
    "06-now-playing|jazzdiscovery://play/album/a-love-supreme jazzdiscovery://now-playing|4"
    "07-crate|jazzdiscovery://tab/crate|0"
    "08-eras|jazzdiscovery://tab/eras|0"
    "09-passport|jazzdiscovery://passport|0"
    "10-radio|jazzdiscovery://radio|0"
)

echo "Building for the simulator…"
xcodebuild -project JazzDiscovery.xcodeproj -scheme JazzDiscoveryMobile -configuration Release \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build -quiet

device_for() {
    local model="$1" name="Jazz Discovery screenshots · $1"
    local udid
    udid="$(xcrun simctl list devices available | sed -n "s/^ *$name (\([0-9A-F-]*\)).*/\1/p" | head -1)"
    if [[ -z "$udid" ]]; then udid="$(xcrun simctl create "$name" "$model")"; fi
    echo "$udid"
}

shoot() {  # udid, links…
    local udid="$1"; shift
    # A made-up passport, in memory only, so the stamps and the Continue row have something to show.
    local args=(--demo-passport)
    for l in "$@"; do args+=(--open "$l"); done
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" "${args[@]}" > /dev/null
}

for size in $SIZES; do
    case "$size" in
        6.9) model="iPhone 18 Pro Max" ;;
        6.3) model="iPhone 18 Pro" ;;
        *) echo "error: unknown size $size (6.9 or 6.3)" >&2; exit 1 ;;
    esac
    udid="$(device_for "$model")"
    out="docs/app-store/iphone-$size"
    mkdir -p "$out"
    echo "$model ($udid) → $out"
    xcrun simctl boot "$udid" 2> /dev/null || true
    xcrun simctl bootstatus "$udid" -b > /dev/null
    xcrun simctl ui "$udid" appearance dark
    xcrun simctl install "$udid" "$APP"
    xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

    # A first pass fills the caches, so the second shows every picture.
    for shot in "${SHOTS[@]}"; do
        IFS='|' read -r name links extra <<< "$shot"
        read -r -a urls <<< "$links"
        shoot "$udid" "${urls[@]}"
        sleep $((WAIT / 2 + extra))
    done
    for shot in "${SHOTS[@]}"; do
        IFS='|' read -r name links extra <<< "$shot"
        read -r -a urls <<< "$links"
        shoot "$udid" "${urls[@]}"
        sleep $((WAIT + extra + (${#urls[@]} - 1) * 3))
        xcrun simctl io "$udid" screenshot "$out/$name.png" > /dev/null 2>&1
        echo "  $name.png"
    done
    xcrun simctl terminate "$udid" "$BUNDLE" 2> /dev/null || true
    xcrun simctl status_bar "$udid" clear
done
