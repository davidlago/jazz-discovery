# Jazz Discovery

Native apps for Mac (macOS 15+) and iPhone (iOS 26.1+), in SwiftUI, for exploring jazz: its history, eras, decades, artists and essential records, with Apple Music for listening, YouTube for watching and Last.fm for scrobbling.

## Install

Download the latest `JazzDiscovery-*-macOS.zip` from [Releases](https://github.com/davidlago/jazz-discovery/releases), unzip it and move **Jazz Discovery.app** to Applications. It runs on Apple Silicon and Intel Macs with macOS 15 or later, and it's signed and notarized by Apple.

The iPhone app has every section of the Mac app, laid out for the phone: five tabs (Timeline, Eras, Artists, Crate,
Search), a player above the tab bar with lock screen controls and AirPlay, and a Connections map you pinch and pan.
How it gets to the App Store: [docs/app-store.md](docs/app-store.md).

## What's inside

| Section | What it shows |
|---|---|
| **Timeline** | A "river" of 14 styles from ragtime to today, packed into lanes so overlapping eras run side by side, with milestone markers. It also has a *Start Here* listening path, a daily artist spotlight and a strip of decades. |
| **Eras & Styles** | Poster cards styled like record sleeves. Each era page has a narrative, sonic traits, places, key artists, essential records, playable essential tracks, YouTube documentaries, a picture archive from Wikimedia Commons and the Wikipedia summary. |
| **Decades** | 1890s–2020s, each with the styles in the air, turning points, records released and who was playing. |
| **Artists** | Duotone portrait grid, filterable by era, instrument and leaders or sidemen. Artist pages have a Wikipedia bio, popular songs on Apple Music, their records, the records they play on, live videos and a "Played With" row. |
| **The Crate** | A wall of album covers grouped by decade. Album pages have the personnel (who played what, when and where it was recorded, the producer and engineer), the tracklist (playable), why the album matters, YouTube clips, more by the artist and more from the era. |
| **Connections** | A chronological network: left to right is when each artist came of age, and lines are the records two artists share (thicker for more) or a bond with a note (mentor, influence, duo). Click a face to light up their circle and a second to see what ties them; *Find a Path* draws the shortest chain between any two artists and plays one track from each link. |

## Sources

- **Content**: `Shared/Resources/jazz.json` is a curated dataset with original summaries (eras, artists, albums, milestones).
- **Wikidata** and **MusicBrainz** (both CC0): artists' IDs and exact dates (`ids.json`), and who played on each record,
  when and where (`sessions.json`), drafted by scripts and reviewed by hand.
- **Wikipedia REST API**: artist and era summaries and photos (CC BY-SA / Wikimedia Commons), cached on disk.
- **iTunes Search API**: Apple Music catalog IDs, artwork and 30-second previews. Album lookups are precomputed into `Resources/catalog.json` by `scripts/build-catalog.py`. Live lookups are cached and throttled.
- **YouTube**: videos are found from YouTube's public search page (no API key) and play in the embedded YouTube player.

## Apple Music playback

The app plays music in one of two ways:

1. **Full tracks in the app** through MusicKit (`ApplicationMusicPlayer`) once you connect Apple Music (sidebar → *Apple Music*, or Settings; on iPhone, the gear at the top of any tab).
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

Signing uses team `2M74C6J5ZY` with automatic signing (set in the project). The project uses synchronized folders, so new files are picked up automatically: `Shared/` goes into both apps, `JazzDiscovery/` only into the Mac app, `iOS/JazzDiscoveryMobile/` only into the iPhone app, and `Widgets/` into the widget extension both apps embed. The extension also takes a few of `Shared/`'s files; the rest are listed as exceptions in the project (a new file in `Shared/` joins the widgets too, so it must build in an app extension or be added to those exceptions).

The iPhone app is the `JazzDiscoveryMobile` scheme:

```bash
xcodebuild -project JazzDiscovery.xcodeproj -scheme JazzDiscoveryMobile -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

Its signing settings are in `iOS/Signing.xcconfig` (overrides, such as another team or the app's own Last.fm API key,
go in `iOS/Local.xcconfig`, which isn't committed). `scripts/install-iphone.sh` builds it and installs it on a
connected development iPhone, signed with your development profile (no Apple ID in Xcode needed). Release tags upload it to TestFlight from CI (`scripts/testflight.sh`) and
`scripts/app-store-screenshots.sh` takes the App Store screenshots; see [docs/app-store.md](docs/app-store.md).

### Links

Links like `jazzdiscovery://artist/miles-davis`, `era/bebop`, `album/kind-of-blue`, `decade/1950`, `decades`,
`connections[/<artist>]`, `between/<artist>/<artist>`, `tab/search?q=…`, `now-playing` and `settings` open those screens, in both apps (`open …` on
the Mac, `xcrun simctl openurl <device> …` in the simulator). `Shared/Model/Route.swift` parses them, and only accepts
pages that exist; a link never starts music.

### Tests

```bash
xcodebuild test -project JazzDiscovery.xcodeproj -scheme JazzDiscoveryTests -destination 'platform=macOS'
```

or ⌘U in Xcode with the JazzDiscovery scheme. The tests in `Tests/` cover the shared code (`Shared/`, which the test
bundle compiles itself, with no app to host it, so it needs no signing), and CI runs them on every push.

After you edit `jazz.json`, refresh the generated data. Each script only looks up what it hasn't resolved yet:

```bash
python3 -I scripts/build-catalog.py    # Apple Music album matches → catalog.json
python3 -I scripts/build-ids.py        # Wikidata and MusicBrainz IDs, exact dates → ids.json
python3 -I scripts/build-sessions.py   # personnel, sessions and studios from MusicBrainz → sessions.json
```

`build-sessions.py` writes drafts (`"reviewed": false`) that the app ignores. Each one is checked against the liner
notes, fixed, and marked `"reviewed": true`; `build/sessions-report.md` lists the drafts, what looked off in each, and
the players who don't have a page yet. `validate-data.py` counts how many are reviewed.

### Releases

CI (`.github/workflows/ci.yml`) checks the data, runs the tests and builds the app on every push and pull request. Those builds are ad-hoc signed and attached to the run as an artifact. Pushing a `vX.Y.Z` tag does more:

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
- `--open <jazzdiscovery:// link>` (repeatable) opens links at launch, three seconds apart, for scripted checks of the window. Only here does `jazzdiscovery://play/album/<id>` start the record.

## Layout

```
Shared/                       used by both apps
  Model/                      data types, JazzLibrary (lookups/search), Route (pages and jazzdiscovery:// links), Theme
  Services/                   Wikipedia, ITunes, YouTube, Player (MusicKit + previews), LastFM, HTTP/DiskCache, Platform
  Design/                     remote images, duotone portraits, album covers, FlowLayout, the Connections graph layout
  Resources/jazz.json         curated content
  Resources/catalog.json      precomputed Apple Music album matches
  Resources/ids.json          Wikidata/MusicBrainz IDs and exact dates (build-ids.py)
  Resources/sessions.json     personnel, sessions, studios per album (build-sessions.py, reviewed by hand)
JazzDiscovery/                the Mac app: JazzDiscoveryApp (menus, Settings), Views/, Diagnostics/ (--self-test, --snapshots)
iOS/JazzDiscoveryMobile/      the iPhone app: tabs, pages, player, Connections map, Settings
Widgets/                      the widgets (both platforms): Today in Jazz and Continue; their views are in Shared/Design
iOS/Signing.xcconfig          the iPhone app's team, bundle ID and optional Last.fm API account; Version.xcconfig
Tests/                        unit tests of the shared code (Swift Testing; the JazzDiscoveryTests scheme)
scripts/                      build-app.sh, notarize.sh, validate-data.py, build-catalog.py, build-ids.py,
                              build-sessions.py, make-icon.swift (--ios),
                              import-certificate.sh / set-signing-secret.sh (CI signing), testflight.sh,
                              provisioning-profiles.swift, select-xcode.sh, app-store-screenshots.sh
docs/                         app-store.md (iPhone release guide and listing), privacy.md, app-store/ (screenshots),
                              roadmap/ (the plan for 1.1–1.8)
.github/workflows/ci.yml      test and build both apps on every push; on vX.Y.Z tags, release the Mac app and upload the iPhone app
```
