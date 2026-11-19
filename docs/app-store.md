# The apps on the App Store

How Jazz Discovery for iPhone is signed, uploaded to TestFlight and submitted to App Review, and what goes into its
App Store listing. The Mac app joins it on the Mac App Store as the same app (see [The Mac app](#the-mac-app-on-the-mac-app-store)),
and is also released outside the store, signed with Developer ID and notarized, on GitHub. The iPhone app is the `JazzDiscoveryMobile` target of `JazzDiscovery.xcodeproj`; it shares
`Shared/` (data, Apple Music, Last.fm, Wikipedia, YouTube) with the Mac app and has its own views in
`iOS/JazzDiscoveryMobile/`.

| | |
|---|---|
| Bundle ID | `io.github.davidlago.JazzDiscovery` (the Mac app's, so its MusicKit App Service covers both) |
| Team | `2M74C6J5ZY` (`iOS/Signing.xcconfig`; override in `iOS/Local.xcconfig`, which isn't committed) |
| Version | the release tag's (`v0.2.0` uploads 0.2.0); local builds use `MARKETING_VERSION` in `iOS/Version.xcconfig` |
| Requires | iOS 26.1 or later, iPhone only, built with a release (not beta) Xcode 26.1 or later |

## One-time setup

### 1. Apple Developer: the App ID

The App ID `io.github.davidlago.JazzDiscovery` already exists (Xcode registered it for the Mac app) and has the
**MusicKit** App Service, which the iPhone app needs for full tracks. App IDs aren't tied to a platform, so nothing
else is needed. To check: [developer.apple.com ▸ Identifiers](https://developer.apple.com/account/resources/identifiers/list)
▸ the ID ▸ **App Services** ▸ MusicKit is ticked.

### 2. GitHub: the signing secrets for CI

Releases upload from GitHub Actions, as Music Library's do. The `testflight` job in `.github/workflows/ci.yml` signs in
with the App Store Connect API key that already notarizes the Mac app (the `NOTARY_API_KEY`, `NOTARY_API_KEY_ID` and
`NOTARY_API_ISSUER_ID` secrets, an App Manager key). An App Manager key can't use Apple's cloud-managed distribution
certificates, so CI signs with an Apple Distribution certificate of its own, and makes an App Store profile for it
named "io.github.davidlago.JazzDiscovery App Store (CI)" (`scripts/provisioning-profiles.swift`, which replaces it
once it expires or was made for another certificate).

The certificate is already in the login keychain (`security find-identity -v -p codesigning` lists
"Apple Distribution: Dave Lago (2M74C6J5ZY)"; it's the one Music Library's CI uses). Store it for this repository:

```bash
scripts/set-signing-secret.sh "Apple Distribution" APPLE_DISTRIBUTION_CERTIFICATE
```

It exports only that identity (macOS asks for your login password), checks it imports the way CI imports it and sets
`APPLE_DISTRIBUTION_CERTIFICATE_P12` and `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` with `gh`. The certificate lasts a
year: when Apple emails that it's expiring, create a new one (Xcode ▸ Settings ▸ Accounts ▸ the team ▸ Manage
Certificates… ▸ **+** ▸ Apple Distribution) and run the script again, here and in Music Library.

### iCloud and the widgets' app group

The passport syncs between the Mac and iPhone through iCloud key-value storage (`PassportSync`), which needs the
`com.apple.developer.ubiquity-kvstore-identifier` entitlement (`$(TeamIdentifierPrefix)$(CFBundleIdentifier)`). Both
apps share the bundle ID, so they share the store. The widgets (`Widgets/`, the `JazzDiscoveryWidgets` extension, bundle
ID `io.github.davidlago.JazzDiscovery.Widgets`) learn where you are on a path from a small file the app writes to the
app group `group.io.github.davidlago.JazzDiscovery` (`WidgetSnapshot`). Done on 2026-11-18:

1. iCloud is ticked on the App ID `io.github.davidlago.JazzDiscovery` (key-value storage needs no container).
2. The app group is registered, the App ID `io.github.davidlago.JazzDiscovery.Widgets` too, and the group is assigned
   to both App IDs.
3. Developer ID profiles for the Mac ("<bundle ID> Developer ID", valid until 2044) for both bundle IDs, made with the
   API key and stored as the `MAC_PROVISIONING_PROFILE` (the app) and `MAC_WIDGETS_PROVISIONING_PROFILE` (the widgets)
   secrets; the App Store profiles made again for both:

   ```bash
   # The notarizing API key: its file, key ID and issuer ID (App Store Connect ▸ Users and Access ▸ Integrations).
   KEY=~/.appstoreconnect/private_keys/AuthKey_<key ID>.p8 KEY_ID=<key ID> ISSUER=<issuer ID>
   IDS="io.github.davidlago.JazzDiscovery io.github.davidlago.JazzDiscovery.Widgets"
   swift scripts/provisioning-profiles.swift --developer-id --replace "$KEY" "$KEY_ID" "$ISSUER" $IDS
   base64 -i build/profiles/io.github.davidlago.JazzDiscovery.provisionprofile | gh secret set MAC_PROVISIONING_PROFILE
   base64 -i build/profiles/io.github.davidlago.JazzDiscovery.Widgets.provisionprofile | gh secret set MAC_WIDGETS_PROVISIONING_PROFILE
   swift scripts/provisioning-profiles.swift --replace "$KEY" "$KEY_ID" "$ISSUER" $IDS
   ```

   Do this again if the Developer ID certificate is replaced, or after changing either App ID's capabilities (which
   invalidates its profiles).

The repository variable `ICLOUD` (set to `1`) turns it all on for releases:

```bash
gh variable set ICLOUD --body 1
```

A release tag then embeds both profiles in the Mac app (`scripts/build-app.sh` with `PROVISIONING_PROFILE=…` and
`WIDGETS_PROVISIONING_PROFILE=…`, which checks each is a Developer ID profile for its App ID that allows what it needs,
signs the app with `Config/JazzDiscovery-iCloud.entitlements` plus the group, and the widgets with
`Config/JazzDiscoveryWidgets.entitlements` plus the group), and the iPhone upload is signed with
`iOS/JazzDiscoveryMobile.entitlements` and `iOS/JazzDiscoveryWidgets.entitlements` (`scripts/testflight.sh` with
`ICLOUD=1`). To build the Mac app that way on this Mac:

```bash
SIGN_IDENTITY="Developer ID Application: Dave Lago (2M74C6J5ZY)" PROVISIONING_PROFILE=build/profiles/io.github.davidlago.JazzDiscovery.provisionprofile WIDGETS_PROVISIONING_PROFILE=build/profiles/io.github.davidlago.JazzDiscovery.Widgets.provisionprofile scripts/build-app.sh
```

For the iPhone, the three settings in `iOS/Signing.xcconfig`'s comment go in `iOS/Local.xcconfig`. Without any of this
(pull requests, ad-hoc builds, a Personal Team) the apps build as before: the passport stays on the device, and the
widgets show Today in Jazz and, in place of your path, an invitation to Start Here. The app only opens the group when
Info.plist names it (`JazzDiscoveryAppGroup`, filled in by builds signed with it), because macOS asks the user before
an app opens a group it isn't entitled to.

### 3. App Store Connect: the app record

[App Store Connect](https://appstoreconnect.apple.com) ▸ **Apps** ▸ **+** ▸ **New App**:

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | Jazz Discovery (must be unique on the App Store; if it's taken, try "Jazz Discovery: History of Jazz") |
| Primary language | English (U.S.) |
| Bundle ID | io.github.davidlago.JazzDiscovery |
| SKU | jazz-discovery-ios |
| User access | Full access |

App records can't be created with an API key, so this one is done on the website.

Then, once:

1. **Business** (top of App Store Connect): the **Free Apps** agreement is active, and the EU **trader status** is
   declared (not a trader). The Music Library app already did both for this team.
2. The app ▸ **App Information**: subtitle, categories, content rights, age rating (see the listing below).
3. The app ▸ **App Privacy**: the privacy policy URL and the data types below, then **Publish**.
4. The app ▸ **Pricing and Availability**: Free, all countries and regions.

### 4. Optional: a Last.fm API account for the app

As on the Mac, people can scrobble with their own Last.fm API account (Settings ▸ Last.fm, with a Paste button for the
key and secret). To let them just sign in instead, give the app its own:
[create an API account on last.fm](https://www.last.fm/api/account/create) (application name "Jazz Discovery for
iPhone", callback URL empty), then store the key and shared secret as the `LASTFM_API_KEY` and `LASTFM_SHARED_SECRET`
repository secrets, which the `testflight` job builds in:

```bash
gh secret set LASTFM_API_KEY
gh secret set LASTFM_SHARED_SECRET
```

For local builds, put them in `iOS/Local.xcconfig` (never in a committed file):

```
LASTFM_API_KEY = 0123456789abcdef0123456789abcdef
LASTFM_SHARED_SECRET = 0123456789abcdef0123456789abcdef
```

Builds then show **Connect Last.fm** right away, and keep "Use My Own API Account" as an option.

## Each release

### 1. Upload a build

Tag the release as usual (rename **Unreleased** in `CHANGELOG.md` to the version, then push a `vX.Y.Z` tag). Besides
the Mac release, CI uploads the iPhone app to TestFlight as version X.Y.Z, after both apps build: the `testflight`
job archives a Release build for devices, signs it for the App Store and uploads it, with the current UTC time as the
build number.

To check signing without a release, run the workflow by hand: **Actions ▸ CI ▸ Run workflow**, or

```bash
gh workflow run ci.yml -f testflight=export
```

`export` signs an .ipa without uploading it; `upload` uploads it (as `iOS/Version.xcconfig`'s version).

`scripts/testflight.sh` is what the job runs, and works on a Mac too: signed in with Xcode ▸ Settings ▸ Accounts it
signs automatically, or with `ASC_KEY=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 ASC_KEY_ID=… ASC_ISSUER=…`
(add `DISTRIBUTION_CERTIFICATE=1` for an App Manager key, as in CI). `UPLOAD=0` exports
`build/testflight/Jazz Discovery.ipa` without uploading; `VERSION=1.1` overrides the version.

Apple processes the build in 5 to 30 minutes and emails when it's ready. `ITSAppUsesNonExemptEncryption` is `NO` in
`iOS/Info.plist` (the app only uses HTTPS and hashing), so there's no export compliance question per build.

### 2. Test it with TestFlight

**TestFlight** ▸ **Internal Testing** ▸ **+** to make a group, add yourself, and install the build from the
[TestFlight app](https://apps.apple.com/app/testflight/id899247664). Internal testers need no review. Things to check
on a real iPhone, which the simulator can't:

- Settings ▸ Connect Apple Music: the permission prompt, then "Connected · full tracks", and albums play in full.
- Lock the phone while a song plays: it keeps playing, with lock screen controls (previews too).
- Settings ▸ Last.fm ▸ Connect: last.fm's page opens in a sign-in sheet; allow access. The app asks Last.fm every
  2 seconds whether access was allowed, so it connects whether the sheet closes by itself (Last.fm sending it back to
  `jazzdiscovery://lastfm-auth`) or you close it. Then a song played past halfway shows "Scrobbled" in Now Playing and
  appears on your Last.fm profile.

### 3. Submit for review

In App Store Connect, the app ▸ **iOS App** ▸ the version (**+** to add one after the first release):

1. **Screenshots**: App Store Connect takes one iPhone set (iPhone with Dynamic Island, 6.1"/6.3") and uses it for every
   size, so drag in `docs/app-store/iphone-6.3/*` in file order; `iphone-6.9` is for Media Manager if a size ever needs
   its own. The review video goes under App Review Information ▸ Attachment, under 10 MB for a browser upload (ten each, the most App Store Connect takes). They're the
   screens in `docs/app-store/screens/`, framed with a headline: make new screens with `scripts/app-store-screenshots.sh`,
   then `swift scripts/app-store-art.swift` (headlines and colours are at its top). `10-widgets.png` is drawn by the Mac
   app (`--snapshots <dir> --widgets-only`). The product page's **header** (optional, above the screenshots) is
   `docs/app-store/header-3840x1646.png` (or the 5244 × 2950 one), drawn by `swift scripts/app-store-header.swift`.
2. **Promotional text**, **description**, **keywords**, **support URL**, **marketing URL** (below). After the first
   version, only **What's New** is needed (from `CHANGELOG.md`).
3. **Build**: select the one CI uploaded in step 1.
4. **App Review Information**: no sign-in required; the notes below; your contact details.
5. **Version release**: automatically, or manually once approved.
6. **Add for Review**, then **Submit for Review**. Review usually takes a day or two; App Store Connect emails the
   outcome. If it's rejected, the message in the **Resolution Center** says why; reply there or fix and resubmit.

## The Mac app on the Mac App Store

The Mac app (the `JazzDiscovery` target) has the iPhone app's bundle ID, so on App Store Connect it's the same app
record with a second platform, macOS: one product page per platform, one App Information, privacy label, price and age
rating for both, and a **universal purchase** (it's free either way). Its reviews and versions are its own. The
GitHub release carries on as before: the two copies share iCloud and the Last.fm keychain items, so moving from one to
the other keeps the passport.

| | |
|---|---|
| Upload | `scripts/mac-app-store.sh`: an archive (Apple Silicon + Intel, with the widgets), signed with Apple Distribution and Mac App Store profiles, packaged as a .pkg signed with the Mac Installer Distribution certificate |
| Signing | always with iCloud key-value storage and the app group, as the Developer ID release with `ICLOUD=1` |
| Version | the release tag's; the build number is the UTC time, as for the iPhone |
| Requires | macOS 15 or later |

### One-time setup

1. **The Mac Installer Distribution certificate**, which signs the .pkg (the App Store takes Mac apps as installer
   packages). An App Manager API key can make it, so the script does it all: makes a key and a signing request on this
   Mac, asks Apple for the certificate, adds it to the login keychain ("3rd Party Mac Developer Installer: …") and
   stores it as the `MAC_INSTALLER_CERTIFICATE_P12` and `MAC_INSTALLER_CERTIFICATE_PASSWORD` secrets:

   ```bash
   ASC_KEY=~/.appstoreconnect/private_keys/AuthKey_<key ID>.p8 ASC_KEY_ID=<key ID> ASC_ISSUER=<issuer ID> scripts/mac-installer-certificate.sh
   ```

   It lasts a year, like the Apple Distribution certificate: run it again when Apple emails that it's expiring.
2. **The Mac App Store profiles** ("<bundle ID> Mac App Store (CI)", for the app and its widgets) are made by
   `scripts/mac-app-store.sh` the first time it runs with `DISTRIBUTION_CERTIFICATE=1`
   (`scripts/provisioning-profiles.swift --mac-app-store`), and replaced when they expire or the certificate changes.
3. **App Store Connect**: the app ▸ the **+** next to **iOS App** in the sidebar ▸ **macOS**, which adds a **macOS App**
   section with a version in Prepare for Submission (or `POST /v1/appStoreVersions` with `"platform": "MAC_OS"`, which
   the API key can do). Uploads are refused until it exists.
   Steps 1 to 3 were done on 2026-11-19 (the macOS version 1.14.0 was made through the API).
4. Turn the CI job on for release tags:

   ```bash
   gh variable set MAC_APP_STORE --body 1
   ```

To check signing without a release: `gh workflow run ci.yml -f mac_app_store=export` (a signed .pkg, not uploaded),
or `-f mac_app_store=upload` (uploads `iOS/Version.xcconfig`'s version). On this Mac, with both certificates in the
login keychain:

```bash
UPLOAD=0 DISTRIBUTION_CERTIFICATE=1 ASC_KEY=~/.appstoreconnect/private_keys/AuthKey_<key ID>.p8 ASC_KEY_ID=<key ID> ASC_ISSUER=<issuer ID> scripts/mac-app-store.sh
```

leaves `build/mac-app-store/Jazz Discovery.pkg`. To try it as the store would install it, upload and install it with
**TestFlight** on the Mac (internal testers need no review). Quit and delete the GitHub copy in /Applications first:
both have the same bundle ID.

### Each release

With `MAC_APP_STORE` set, a `vX.Y.Z` tag uploads the Mac app too (the `mac-app-store` job, after the Mac build). Then,
in App Store Connect, the app ▸ **macOS App** ▸ the version (**+** to add one after the first release):

1. **Screenshots**: `docs/app-store/mac/*` in file order (2880 × 1800, one of the Mac sizes; ten at most). They're the
   Mac app's window (see below), framed by `swift scripts/app-store-art.swift`.
2. **Promotional text**, **description** and **keywords** (the Mac text below), **support URL**, **marketing URL**,
   **copyright**. After the first version, only **What's New**.
3. **Build**: the one CI uploaded.
4. **App Review Information**: no sign-in; the Mac review notes below; your contact details.
5. **Version release**, then **Add for Review** ▸ **Submit for Review**.

App Information (categories, content rights, age rating), App Privacy and Pricing are shared with the iPhone app and
already done. Adding the macOS platform makes the iPhone app unavailable on Apple silicon Macs, which it already was.

To take the screens again: build the Mac app under a test bundle ID (so it doesn't touch your own copy's keychain
items), open it (its window opens at 1440 × 900 points, 2880 × 1800 pixels on a Retina display), open each page with
its link (`open -g -a "<the .app>" jazzdiscovery://album/kind-of-blue`) and capture the window with
`screencapture -l <window ID> -o -x docs/app-store/screens/mac/<name>.png`, named as in `scripts/app-store-art.swift`'s
`macShots`. (The app's `--snapshots` pages don't do here: an offscreen window draws the sidebar blank.)

```bash
xcodebuild -project JazzDiscovery.xcodeproj -scheme JazzDiscovery -configuration Release -derivedDataPath build/DerivedData-linktest -destination 'platform=macOS' APP_BUNDLE_ID=io.github.davidlago.JazzDiscovery.linktest CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="" -quiet build
```

## The listing

### App information

| Field | Value |
|---|---|
| Name | Jazz Discovery |
| Subtitle (30) | A visual history of jazz |
| Primary category | Music |
| Secondary category | Education |
| Content rights | Contains third-party content: text and photos from Wikipedia and Wikimedia Commons (CC BY-SA, credited in the app), album artwork and previews from Apple Music, YouTube videos in YouTube's own embedded player |
| Age rating | 4+: every question answered None or No. Links open in Safari or the Music and YouTube apps; the app has no web browser of its own |
| Privacy policy URL | https://github.com/davidlago/jazz-discovery/blob/main/docs/privacy.md |
| Support URL | https://github.com/davidlago/jazz-discovery/issues |
| Marketing URL | https://github.com/davidlago/jazz-discovery |
| Copyright | 2026 Dave Lago |
| Price | Free |

### App Privacy

The developer collects nothing. The one thing that leaves the phone about the user is optional and goes to Last.fm, so:

- **Data types**: **Usage Data ▸ Product Interaction** (the songs played, sent to Last.fm when the user connects their
  account). Linked to the user's identity (their Last.fm account): Yes. Used for tracking: No. Purpose: App
  Functionality.
- Everything else: not collected. Wikipedia, iTunes and YouTube requests contain only what's being looked up.

The privacy manifest (`iOS/JazzDiscoveryMobile/PrivacyInfo.xcprivacy`) declares no tracking and the one "required
reason" API the app uses (UserDefaults, CA92.1).

### Version text

This text is for 1.12 (183 artists, 176 records, personnel, Find a Path, Passport, Radio, the Blindfold Test, the
Songbook, Places and Labels, Lineages and the Glossary, Paths, listening guides, Today in Jazz, widgets, Siri). App
Store Connect's limits: description 4,000 characters, promotional text 170, keywords 100, and ten screenshots per
size.

**Promotional text** (170 characters, can change any time without review):

```
183 artists and 176 essential records, from ragtime to today. Follow a recording as it plays with listening guides, and find the path between any two players.
```

**Keywords** (100 characters):

```
jazz,history,bebop,swing,coltrane,miles davis,blue note,albums,artists,timeline,scrobble,last.fm
```

**Description**:

```
Jazz Discovery is a visual guide to 130 years of jazz, from ragtime and the blues to today's new scenes. Follow the music as it flows, splits and comes back together, meet the people who made it, and listen to the records that changed everything.

The River of Jazz
Fourteen styles flow across a timeline like river channels, overlapping where they really did, with forty turning points along the way. Tap a style to dive in.

Eras and decades
Each era has its story, its sound, the places it happened, its key artists and essential records, with tracks to play, performances and a picture archive. Or travel by decade, from the 1890s to the 2020s.

183 artists, 176 records
Leaders and the sidemen all over their records, in Blue Note–style duotone portraits, each with a biography, their records and the people they played with. Every album lists its band like the back of an LP: who played what, and when and where it was recorded. New to jazz? Follow Start Here, one record at a time.

Connections
A map of who played with whom across the century, drawn from the records they share. Find the shortest path between any two artists, from Scott Joplin to Nubya Garcia, and hear one track from each link.

Listening guides
Follow a recording as it plays, from So What to The Girl from Ipanema: its form drawn as a bar (the head, each solo, the way out) and a note on what to hear in each section, moving with the music. Tap a section to jump to it. Guides follow full tracks, with Apple Music.

Paths
Journeys with a point of view, from 1959 to Late Night and The Latin Tinge: a few stops each, every one with something to listen for, and your place kept.

The Songbook
Forty standards and jazz originals, each with its story and the versions that made it matter. Play them in order and hear one song travel through the decades.

Lineages and the glossary
Family trees for eleven instruments, from the trumpet and saxophone to the vibraphone and organ, showing who learned from whom, and a glossary of the words jazz uses, each with a recording to hear it in. How to Listen walks you through one record in five steps.

Places and labels
A map of jazz with a time slider, from New Orleans in 1895 to South London today, with a page for every city, club and studio. And the labels, from Blue Note to ECM, with a wall of their covers.

Radio and the Blindfold Test
Stations for every era, decade, instrument, city and label, that tell you why each track is there. Then test your ears: ten clips, covers hidden.

Today in jazz
Whose birthday it is and what was recorded on this date, with widgets for your Home Screen and Lock Screen and an optional morning note. Ask Siri to "play bebop radio", or find any record in Spotlight.

Your passport
Mark the records you've heard and save the ones to come back to. Every era has a stamp that inks in as you listen, and every record opens three doors to what to hear next. It syncs through your own iCloud and can start from your Last.fm history.

Listen and scrobble
Connect Apple Music to play everything in full; without a subscription you hear 30-second previews. Connect Last.fm and the full tracks you play are added to your profile.

No account, no ads, no tracking. Text and photos from Wikipedia and Wikimedia Commons; artwork and previews from Apple Music.

Also on the Mac: https://github.com/davidlago/jazz-discovery
```

### App Review notes

```
Jazz Discovery is a guide to the history of jazz: eras, decades, artists and essential albums. Its content is an original dataset written for the app, illustrated with Wikipedia and Wikimedia Commons text and photos (credited on each page, CC BY-SA), album artwork and 30-second previews from Apple's iTunes Search API, and YouTube videos that play in YouTube's official embedded player.

No sign-in is needed: every screen works right away.

The attached video shows the app on an iPhone: launching, an era page, full tracks playing with Apple Music, an album page, Connections and the Artists tab.

Apple Music (optional): Settings (gear at the top right of any tab) > Connect Apple Music asks for Apple Music access through MusicKit. With a subscription, songs and albums play in full in the app (ApplicationMusicPlayer); without one, the app plays 30-second previews and "Apple Music" buttons open the album or song in the Music app.

Last.fm (optional): Settings > Last.fm connects the user's own Last.fm account, so the full tracks they play are added to their Last.fm profile ("scrobbling"). Sign-in happens on last.fm's own page in a system sign-in sheet; the app never sees the password. If you don't have a Last.fm account, you can skip this.

Background audio is used only to keep music playing while the phone is locked.

Listening guides (Discover > Listening Guides) follow a recording section by section while it plays in full with Apple Music. Without Apple Music the guide is still readable and says it can't follow a 30-second preview.

Notifications are off unless the user turns on the morning note (Settings > Today in Jazz); it is scheduled on the device, and permission is asked only then. Widgets: Today in Jazz and Continue, for the Home Screen and Lock Screen. Siri and Shortcuts: "Play bebop radio on Jazz Discovery", "What happened in jazz today in Jazz Discovery".

Suggested path: Discover (Today in Jazz at the top, then scroll the River of Jazz sideways and tap a style; the Paths, Listening Guides and Radio rows; the Blindfold Test card), an era page, an artist (Artists tab), an album (Crate tab) with its Personnel, Play, Mark as Heard and Save buttons and its three doors at the bottom, the Explore tab (eras, decades, the Songbook, the Places map with its time slider, Labels, Lineages, the Glossary), the Passport (the seal button at the top right), Artists > Connections (pinch and tap faces, then the path button at the top to find a path between two artists), and Search.
```

### The Mac version

The macOS App version has its own text. **Promotional text** and **keywords**: the same as the iPhone's.

**Description** (the iPhone's, with the Mac's own features in place of the phone's):

```
Jazz Discovery is a visual guide to 130 years of jazz, from ragtime and the blues to today's new scenes. Follow the music as it flows, splits and comes back together, meet the people who made it, and listen to the records that changed everything.

The River of Jazz
Fourteen styles flow across a timeline like river channels, overlapping where they really did, with forty turning points along the way. Click a style to dive in.

Eras and decades
Each era has its story, its sound, the places it happened, its key artists and essential records, with tracks to play, performances and a picture archive. Or travel by decade, from the 1890s to the 2020s.

183 artists, 176 records
Leaders and the sidemen all over their records, in Blue Note–style duotone portraits, each with a biography, their records and the people they played with. Every album lists its band like the back of an LP: who played what, and when and where it was recorded. New to jazz? Follow Start Here, one record at a time.

Connections
A map of who played with whom across the century, drawn from the records they share. Find the shortest path between any two artists, from Scott Joplin to Nubya Garcia, and hear one track from each link.

Listening guides
Follow a recording as it plays, from So What to The Girl from Ipanema: its form drawn as a bar (the head, each solo, the way out) and a note on what to hear in each section, moving with the music. Click a section to jump to it. Guides follow full tracks, with Apple Music.

Paths
Journeys with a point of view, from 1959 to Late Night and The Latin Tinge: a few stops each, every one with something to listen for, and your place kept.

The Songbook
Forty standards and jazz originals, each with its story and the versions that made it matter. Play them in order and hear one song travel through the decades.

Lineages and the glossary
Family trees for eleven instruments, from the trumpet and saxophone to the vibraphone and organ, showing who learned from whom, and a glossary of the words jazz uses, each with a recording to hear it in. How to Listen walks you through one record in five steps.

Places and labels
A map of jazz with a time slider, from New Orleans in 1895 to South London today, with a page for every city, club and studio. And the labels, from Blue Note to ECM, with a wall of their covers.

Radio and the Blindfold Test
Stations for every era, decade, instrument, city and label, that tell you why each track is there. Then test your ears: ten clips, covers hidden.

Made for the Mac
Wide pages with room for the whole story, a sidebar for every section, a Go menu with keyboard shortcuts, and a player in the menu bar that tells you why a station chose each track. Today in Jazz and Continue widgets for your desktop and Notification Center, and Handoff with the iPhone app: the page you're on is ready to open on your other device.

Your passport
Mark the records you've heard and save the ones to come back to. Every era has a stamp that inks in as you listen, and every record opens three doors to what to hear next. It syncs with the iPhone app through your own iCloud and can start from your Last.fm history.

Listen and scrobble
Connect Apple Music to play everything in full; without a subscription you hear 30-second previews. Connect Last.fm with your own API account and the full tracks you play are added to your profile.

No account, no ads, no tracking. Text and photos from Wikipedia and Wikimedia Commons; artwork and previews from Apple Music.
```

**App Review notes**:

```
Jazz Discovery is a guide to the history of jazz: eras, decades, artists and essential albums. Its content is an original dataset written for the app, illustrated with Wikipedia and Wikimedia Commons text and photos (credited on each page, CC BY-SA), album artwork and 30-second previews from Apple's iTunes Search API, and YouTube videos that play in YouTube's official embedded player. This is the Mac version of the iPhone app already on the App Store (same app record, universal purchase).

No sign-in is needed: every page works right away.

Apple Music (optional): click Apple Music at the bottom of the sidebar to connect through MusicKit. With a subscription, songs and albums play in full; without one, the app plays 30-second previews and "Apple Music" buttons open the album or song in the Music app.

Last.fm (optional): Jazz Discovery > Settings > Last.fm connects the user's own Last.fm account with their own Last.fm API key, so the full tracks they play are added to their Last.fm profile ("scrobbling"). Sign-in happens on last.fm's own page in the browser; the app never sees the password. If you don't have a Last.fm account, you can skip this.

Listening guides (Listening Guides in the sidebar) follow a recording section by section while it plays in full with Apple Music. Without Apple Music the guide is still readable and says it can't follow a 30-second preview.

While music plays, a player appears in the menu bar (it can be turned off in Settings > Apple Music). Notifications are off unless the user turns on the morning note (Settings > Today in Jazz); it is scheduled on the Mac, and permission is asked only then. Widgets: Today in Jazz and Continue, for the desktop and Notification Center.

Suggested path: Discover (Today in Jazz at the top, then the River of Jazz: click a style), an era page, an artist (Artists in the sidebar), an album (the Crate) with its Personnel, Play, Mark as Heard and Save buttons and its three doors at the bottom, the Songbook, Places with its time slider, Labels, Lineages, the Glossary, the Passport, Connections (click faces, then find a path between two artists), Radio, the Blindfold Test, and Search (Command-F).
```
