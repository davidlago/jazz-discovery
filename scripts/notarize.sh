#!/usr/bin/env bash
# Notarizes "build/Jazz Discovery.app" (built by scripts/build-app.sh with a "Developer ID Application" SIGN_IDENTITY)
# and staples the ticket to it, so it opens without Gatekeeper warnings, even offline.
#
# Credentials, either:
#   NOTARY_PROFILE=jazz-discovery   a keychain profile saved once with
#                                   xcrun notarytool store-credentials jazz-discovery --key … --key-id … --issuer …
#   NOTARY_KEY=path/to/AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER=…   an App Store Connect API key (CI)
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Jazz Discovery.app"
[[ -d "$APP" ]] || { echo "error: $APP is missing; build it with scripts/build-app.sh" >&2; exit 1; }

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
else
    echo "error: set NOTARY_PROFILE, or NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER" >&2
    exit 1
fi

if [[ "$(codesign -dv --verbose=2 "$APP" 2>&1)" != *$'\nAuthority=Developer ID Application'* ]]; then
    echo "error: $APP isn't signed with a Developer ID Application certificate (SIGN_IDENTITY)" >&2
    exit 1
fi

# Runs a command up to three times, waiting 10 s and then 30 s in between (NOTARIZE_RETRY_DELAYS overrides the
# waits): stapling and checking the ticket ask Apple's servers again, and a dropped connection shouldn't fail a release.
retry() {
    local delays=(${NOTARIZE_RETRY_DELAYS-10 30}) attempt=0 status
    while true; do
        "$@" && return 0 || status=$?
        (( attempt < ${#delays[@]} )) || return "$status"
        echo "warning: '$*' failed (status $status); trying again in ${delays[attempt]} s…" >&2
        sleep "${delays[attempt]}"
        attempt=$((attempt + 1))
    done
}

ZIP_DIR="$(mktemp -d)"
trap 'rm -rf "$ZIP_DIR"' EXIT
ZIP="$ZIP_DIR/JazzDiscovery.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple's notary service (usually a few minutes)…"
OUT="$(xcrun notarytool submit "$ZIP" "${AUTH[@]}" --wait --output-format json)" || true
ID="$(printf '%s' "$OUT" | plutil -extract id raw - 2>/dev/null || true)"
STATUS="$(printf '%s' "$OUT" | plutil -extract status raw - 2>/dev/null || true)"
if [[ "$STATUS" != "Accepted" ]]; then
    echo "error: notarization ${STATUS:-failed}: $OUT" >&2
    if [[ -n "$ID" ]]; then xcrun notarytool log "$ID" "${AUTH[@]}" >&2 || true; fi
    exit 1
fi

retry xcrun stapler staple "$APP"
retry xcrun stapler validate "$APP"
retry spctl --assess --type execute --verbose=2 "$APP"
echo "Notarized $APP ($ID)"
