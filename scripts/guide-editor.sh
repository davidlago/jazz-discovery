#!/usr/bin/env bash
# Builds Jazz Discovery signed with your Developer ID (so Apple Music plays full tracks, which timing needs) and opens
# it with the listening guide editor (JazzDiscovery/Views/GuideEditor.swift).
#
#   scripts/guide-editor.sh          build, then open
#   scripts/guide-editor.sh --open   open the last build again
#
# It's the real app (same bundle ID, passport and settings as the one in Applications), so the installed copy is quit
# first. Times you take are kept in the app's container and applied whenever the editor is on; Copy JSON in the
# editor puts the whole guides.json on the clipboard, for Shared/Resources/guides.json.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Jazz Discovery.app"
if [[ "${1:-}" != "--open" ]]; then
    identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -1)}"
    [[ -n "$identity" ]] || { echo "error: no Developer ID Application certificate in your keychain" >&2; exit 1; }
    profiles=build/profiles
    [[ -f "$profiles/io.github.davidlago.JazzDiscovery.provisionprofile" ]] \
        || { echo "error: $profiles has no Developer ID profile (scripts/provisioning-profiles.swift --developer-id)" >&2; exit 1; }
    version="$(sed -n 's/^MARKETING_VERSION *= *//p' iOS/Version.xcconfig)"
    SIGN_IDENTITY="$identity" VERSION="$version" \
        PROVISIONING_PROFILE="$profiles/io.github.davidlago.JazzDiscovery.provisionprofile" \
        WIDGETS_PROVISIONING_PROFILE="$profiles/io.github.davidlago.JazzDiscovery.Widgets.provisionprofile" \
        scripts/build-app.sh
fi
[[ -d "$APP" ]] || { echo "error: $APP isn't built yet" >&2; exit 1; }

osascript -e 'tell application id "io.github.davidlago.JazzDiscovery" to quit' 2> /dev/null || true
sleep 1
open -n "$APP" --args -guideEditor YES
echo "Opened $APP with the guide editor."
