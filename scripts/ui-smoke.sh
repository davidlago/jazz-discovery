#!/usr/bin/env bash
# Opens the iPhone app's pages one by one in a simulator of its own and fails if the app crashes or a page comes up
# blank: the kind of break the unit tests can't see (1.12.2's crash on tapping the morning note was one). CI runs it on
# every push; locally it uses its own simulator, so it doesn't disturb the others.
#
# Each page is opened with the app's --open launch argument (a jazzdiscovery:// link), with a made-up passport in
# memory (--demo-passport). Every page is opened at the default text size, then a few at a large accessibility size,
# where pages with type that doesn't fit are most likely to break. Screenshots go to build/ui-smoke/.
#
#   APP=<path to .app>   skip the build and test this simulator build
#   WAIT=5               seconds to give each page (default: 5)
#   KEEP=1               leave the simulator booted afterwards
set -euo pipefail

cd "$(dirname "$0")/.."

WAIT="${WAIT:-5}"
BUNDLE=io.github.davidlago.JazzDiscovery
OUT=build/ui-smoke
DEVICE_NAME="Jazz Discovery UI smoke"

if [[ -z "${APP:-}" ]]; then
    echo "Building for the simulator…"
    xcodebuild -project JazzDiscovery.xcodeproj -scheme JazzDiscoveryMobile -configuration Release \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData-smoke CODE_SIGNING_ALLOWED=NO \
        build -quiet
    APP="build/DerivedData-smoke/Build/Products/Release-iphonesimulator/Jazz Discovery.app"
fi

# Every kind of page, and the ones that broke before.
LINKS=(
    tab/discover tab/explore tab/artists tab/crate "tab/search?q=blue"
    era/roots era/bebop era/contemporary decades decade/1890 decade/1950 decade/2020
    artist/miles-davis artist/scott-joplin album/kind-of-blue
    connections connections/john-coltrane between/louis-armstrong/herbie-hancock
    songbook tune/body-and-soul map place/village-vanguard labels label/blue-note
    lineages lineage/saxophone glossary term/rhythm-changes
    paths path/nineteen-fifty-nine guides guide/so-what
    today almanac/05-26 passport radio blindfold settings
)
# At a large text size: the pages with the most display type.
LARGE_LINKS=(tab/discover tab/explore era/bebop album/kind-of-blue tune/body-and-soul path/nineteen-fifty-nine today passport)

# The simulator: made the first time, from the newest iPhone this Xcode has.
udid="$(xcrun simctl list devices available | sed -n "s/^ *$DEVICE_NAME (\([0-9A-F-]*\)).*/\1/p" | head -1)"
if [[ -z "$udid" ]]; then
    model="$(xcrun simctl list devicetypes | sed -n 's/^\(iPhone [0-9][0-9]* Pro\) (.*/\1/p' | sort -V | tail -1)"
    [[ -n "$model" ]] || model="$(xcrun simctl list devicetypes | sed -n 's/^\(iPhone[^(]*\) (.*/\1/p' | tail -1 | sed 's/ *$//')"
    echo "Making a simulator ($model)…"
    udid="$(xcrun simctl create "$DEVICE_NAME" "$model")"
fi
echo "Simulator $udid"
xcrun simctl boot "$udid" 2> /dev/null || true
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl install "$udid" "$APP"
rm -rf "$OUT"; mkdir -p "$OUT"
swiftc -O scripts/screen-check.swift -o build/screen-check

failures=()
check() {  # size label, link
    local size="$1" link="$2"
    local name; name="$size-$(tr '/?=' '---' <<< "$link")"
    local launched pid
    if ! launched="$(xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" \
            --demo-passport --today 2026-05-26 --open "jazzdiscovery://$link" 2>&1)"; then
        failures+=("$link ($size): didn't launch: $launched"); return
    fi
    pid="${launched##*: }"
    sleep "$WAIT"
    # Simulator apps are processes on this Mac: a crash leaves no process.
    if ! kill -0 "$pid" 2> /dev/null; then
        failures+=("$link ($size): the app quit (crashed?)"); return
    fi
    xcrun simctl io "$udid" screenshot "$OUT/$name.png" > /dev/null 2>&1
    if ! build/screen-check "$OUT/$name.png"; then
        failures+=("$link ($size): blank page")
    fi
    echo "  ok  $link"
}

xcrun simctl ui "$udid" appearance dark
xcrun simctl ui "$udid" content_size large
echo "Default text size:"
for l in "${LINKS[@]}"; do check default "$l"; done

xcrun simctl ui "$udid" content_size accessibility-extra-large
echo "Large text (Accessibility XL):"
for l in "${LARGE_LINKS[@]}"; do check large "$l"; done
xcrun simctl ui "$udid" content_size large

xcrun simctl terminate "$udid" "$BUNDLE" 2> /dev/null || true
[[ -n "${KEEP:-}" ]] || xcrun simctl shutdown "$udid" 2> /dev/null || true

if (( ${#failures[@]} )); then
    echo "UI smoke check failed:" >&2
    printf '  %s\n' "${failures[@]}" >&2
    echo "Screenshots: $OUT" >&2
    exit 1
fi
echo "All $(( ${#LINKS[@]} + ${#LARGE_LINKS[@]} )) pages opened. Screenshots: $OUT"
