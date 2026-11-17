# Jazz Discovery

A native macOS app (SwiftUI, macOS 15+) for exploring jazz: its history, eras, decades, artists and essential records, with Apple Music for listening and YouTube for watching.

## Install

Download the latest `JazzDiscovery-*-macOS.zip` from [Releases](https://github.com/davidlago/jazz-discovery/releases), unzip it and move **Jazz Discovery.app** to Applications. It runs on Apple Silicon and Intel Macs with macOS 15 or later, and it's signed and notarized by Apple.

## What's inside

| Section | What it shows |
|---|---|
| **Timeline** | A "river" of 14 styles from ragtime to today, packed into lanes so overlapping eras run side by side, with milestone markers. It also has a *Start Here* listening path, a daily artist spotlight and a strip of decades. |
| **Eras & Styles** | Poster cards styled like record sleeves. Each era page has a narrative, sonic traits, places, key artists, essential records, playable essential tracks, YouTube documentaries, a picture archive from Wikimedia Commons and the Wikipedia summary. |
| **Decades** | 1890s–2020s, each with the styles in the air, turning points, records released and who was playing. |
| **Artists** | Duotone portrait grid, filterable by era and instrument. Artist pages have a Wikipedia bio, popular songs on Apple Music, records, live videos and a "Played With" row. |
| **The Crate** | A wall of album covers grouped by decade. Album pages have the tracklist (playable), why the album matters, YouTube clips, more by the artist and more from the era. |
| **Connections** | A chronological network: left to right is when each artist came of age, and lines are collaborations. Hover or click a face to light up their circle; double-click to open the artist. |

## Sources

- **Content**: `JazzDiscovery/Resources/jazz.json` is a curated dataset with original summaries (eras, artists, albums, milestones).
- **Wikipedia REST API**: artist and era summaries and photos (CC BY-SA / Wikimedia Commons), cached on disk.
- **iTunes Search API**: Apple Music catalog IDs, artwork and 30-second previews. Album lookups are precomputed into `Resources/catalog.json` by `scripts/build-catalog.py`. Live lookups are cached and throttled.
- **YouTube**: videos are found from YouTube's public search page (no API key) and play in the embedded YouTube player.

## Apple Music playback

The app plays music in one of two ways:

1. **Full tracks in the app** through MusicKit (`ApplicationMusicPlayer`) once you connect Apple Music (sidebar → *Apple Music*, or Settings).
2. **Fallback**: 30-second previews in the app, plus *Open in Music* buttons that jump to the album or track in Music.app, where your subscription plays it in full.

Full-track playback needs the **MusicKit App Service** turned on for the app's bundle ID. Apple only allows this from the developer portal. It's a one-time step:

1. Go to [developer.apple.com → Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list).
2. Open `io.github.davidlago.JazzDiscovery` (Xcode registered it the first time it built with automatic signing; if it isn't there, create an App ID with that bundle ID).
3. Open the **App Services** tab, check **MusicKit**, and save.
4. Relaunch the app and click *Connect Apple Music*.

If the service isn't enabled yet, the sidebar shows "Not enabled · previews" and everything else keeps working.

## Last.fm scrobbling

Scrobbling uses your own Last.fm API account:

1. [Create a free API account on last.fm](https://www.last.fm/api/account/create). The callback URL can stay empty.
2. In Jazz Discovery, open Settings (⌘,) → **Last.fm** and paste the API key and shared secret. Both are stored in
   your keychain.
3. Click **Connect…**. Your browser opens on last.fm. Allow access there, and the app picks up the connection on its
   own.

From then on:

- Full tracks played with Apple Music are scrobbled once half the track, or 4 minutes, has played (Last.fm's rule).
  Songs under 30 seconds and 30-second previews aren't scrobbled.
- Your profile shows what's playing now. You can turn this off in Settings.
- A small mark in the player shows when a track has been scrobbled.
- Scrobbles that can't be sent (offline, Last.fm down) are saved and sent later. **Send Now** in Settings retries
  right away.

## Build & run

```bash
open JazzDiscovery.xcodeproj   # then ⌘R
```

or from the command line:

```bash
xcodebuild -project JazzDiscovery.xcodeproj -scheme JazzDiscovery -configuration Release \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates build
open "build/DerivedData/Build/Products/Release/Jazz Discovery.app"
```

Signing uses team `2M74C6J5ZY` with automatic signing (set in the project). The project uses a synchronized folder, so new files in `JazzDiscovery/` are picked up automatically.

After you edit `jazz.json`, refresh the album catalog. The script only looks up albums it hasn't resolved yet:

```bash
python3 -I scripts/build-catalog.py
```

### Releases

CI (`.github/workflows/ci.yml`) checks the data and builds the app on every push and pull request. Those builds are ad-hoc signed and attached to the run as an artifact. Pushing a `vX.Y.Z` tag does more:

1. Builds a universal app signed with the Developer ID certificate.
2. Notarizes and staples it.
3. Publishes a GitHub release with the zip and its SHA-256. The notes come from that version's `CHANGELOG.md` section.

To cut a release:

1. Rename **Unreleased** in `CHANGELOG.md` to the new version.
2. Commit.
3. Run `git tag vX.Y.Z && git push origin main vX.Y.Z`.

The workflow needs these repository secrets:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12`, `DEVELOPER_ID_CERTIFICATE_PASSWORD` | the Developer ID Application certificate and its key as a base64 .p12, and the .p12's password |
| `NOTARY_API_KEY`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID` | an App Store Connect API key (`.p8` contents), its Key ID and the Issuer ID |

Set them with:

```bash
scripts/set-signing-secret.sh "Developer ID Application" DEVELOPER_ID_CERTIFICATE
gh secret set NOTARY_API_KEY < ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
gh secret set NOTARY_API_KEY_ID --body XXXXXXXXXX
gh secret set NOTARY_API_ISSUER_ID --body xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

To sign and notarize locally, run `SIGN_IDENTITY="Developer ID Application: …" VERSION=0.1.0 scripts/build-app.sh`, then `NOTARY_KEY=… NOTARY_KEY_ID=… NOTARY_ISSUER=… scripts/notarize.sh`. `python3 -I scripts/validate-data.py` checks `jazz.json` and `catalog.json`.

### Diagnostics

- `"Jazz Discovery.app/Contents/MacOS/Jazz Discovery" --self-test` checks every source from inside the sandboxed app and prints a report: Wikipedia pages and images, album matches, previews, YouTube results, whether the Last.fm API key from Settings works, and whether the MusicKit developer token works.
- `--snapshots <dir>` renders each section offscreen and saves PNGs. Use an unsandboxed build for this, because a sandboxed app can only write inside its container.

## Layout

```
JazzDiscovery/
  JazzDiscoveryApp.swift      app, menus, Settings scene
  Model/                      data types, JazzLibrary (lookups/search), Router, Theme
  Services/                   Wikipedia, ITunes, YouTube, Player (MusicKit + previews), HTTP/DiskCache
  Views/                      Home/Timeline, Eras, Decades, Artists, Albums (Crate), Connections, players
  Resources/jazz.json         curated content
  Resources/catalog.json      precomputed Apple Music album matches
scripts/                      build-app.sh, notarize.sh, validate-data.py, build-catalog.py, make-icon.swift,
                              import-certificate.sh / set-signing-secret.sh (CI signing)
.github/workflows/ci.yml      build on every push; sign, notarize and release on vX.Y.Z tags
```
