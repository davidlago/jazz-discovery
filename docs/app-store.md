# The iPhone app on the App Store

How Jazz Discovery for iPhone is signed, uploaded to TestFlight and submitted to App Review, and what goes into its
App Store listing. The iPhone app is the `JazzDiscoveryMobile` target of `JazzDiscovery.xcodeproj`; it shares
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

1. **Screenshots** (Media Manager): drag in `docs/app-store/iphone-6.9/*` for the 6.9-inch display and
   `docs/app-store/iphone-6.3/*` for 6.3-inch, in file order. Make new ones with `scripts/app-store-screenshots.sh`.
2. **Promotional text**, **description**, **keywords**, **support URL**, **marketing URL** (below). After the first
   version, only **What's New** is needed (from `CHANGELOG.md`).
3. **Build**: select the one CI uploaded in step 1.
4. **App Review Information**: no sign-in required; the notes below; your contact details.
5. **Version release**: automatically, or manually once approved.
6. **Add for Review**, then **Submit for Review**. Review usually takes a day or two; App Store Connect emails the
   outcome. If it's rejected, the message in the **Resolution Center** says why; reply there or fix and resubmit.

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

This text is for 1.1 (127 artists, personnel, Find a Path). If 1.0.1 is submitted on its own first, say "86 artists"
and leave out the *Who played on what* paragraph and the path-finding sentence.

**Promotional text** (170 characters, can change any time without review):

```
127 artists and 88 essential records, from ragtime to today, with who played on every one. Find the path between any two players, and listen as you go.
```

**Keywords** (100 characters):

```
jazz,history,bebop,swing,coltrane,miles davis,blue note,albums,artists,timeline,scrobble,last.fm
```

**Description**:

```
Jazz Discovery is a visual guide to 130 years of jazz, from ragtime and the blues to the new jazz renaissance. Follow the music as it flows, splits and comes back together, meet the people who made it, and listen to the records that changed everything.

The River of Jazz
Fourteen styles flow across a timeline like river channels, overlapping where they really did, with forty turning points along the way. Tap a style to dive in, or a dot to read what happened that year.

Eras and decades
Each era has its story, its sound, the places it happened, its key artists and essential records, tracks to play, documentaries and performances, and a picture archive. Or travel by decade, from the 1890s to the 2020s: the styles in the air, the turning points, the records and who was playing.

127 artists
Leaders and the sidemen all over their records, in Blue Note–style duotone portraits, filterable by era and instrument, each with a biography, their most popular songs, their records, the records they play on, live videos and the people they played with.

The Crate
88 essential albums, by decade, with why each one matters, its tracklist and the tracks to start with. New to jazz? Follow the Start Here path, one record at a time.

Who played on what
Every album lists its band like the back of an LP: who played what, who sat out which track, when and where it was recorded, and who produced it, checked against the liner notes and discographies.

Connections
A map of who played with whom across the whole century, drawn from the records they share: tap a face to light up their circle, and another to see what ties them. Find the shortest path between any two artists, from Scott Joplin to Nubya Garcia, and play one track from each link.

Listen and watch
Connect Apple Music to play every song and album in full; without a subscription you hear 30-second previews, and everything opens in the Music app with one tap. Playback continues on the lock screen and works with AirPlay. Videos play right in the app.

Scrobble to Last.fm
Connect your Last.fm account and the full tracks you play are added to your profile, even when you're offline: they're sent when you're back.

No account, no ads, no tracking. Text and photos from Wikipedia and Wikimedia Commons; artwork and previews from Apple Music.

Also on the Mac: https://github.com/davidlago/jazz-discovery
```

### App Review notes

```
Jazz Discovery is a guide to the history of jazz: eras, decades, artists and essential albums. Its content is an original dataset written for the app, illustrated with Wikipedia and Wikimedia Commons text and photos (credited on each page, CC BY-SA), album artwork and 30-second previews from Apple's iTunes Search API, and YouTube videos that play in YouTube's official embedded player.

No sign-in is needed: every screen works right away.

Apple Music (optional): Settings (gear at the top right of any tab) > Connect Apple Music asks for Apple Music access through MusicKit. With a subscription, songs and albums play in full in the app (ApplicationMusicPlayer); without one, the app plays 30-second previews and "Apple Music" buttons open the album or song in the Music app.

Last.fm (optional): Settings > Last.fm connects the user's own Last.fm account, so the full tracks they play are added to their Last.fm profile ("scrobbling"). Sign-in happens on last.fm's own page in a system sign-in sheet; the app never sees the password. If you don't have a Last.fm account, you can skip this.

Background audio is used only to keep music playing while the phone is locked.

Suggested path: Timeline (scroll the River of Jazz sideways and tap a style), an era page, an artist (Artists tab), an album (Crate tab) with its Personnel and Play button, Artists > Connections (pinch and tap faces, then the path button at the top to find a path between two artists), and Search.
```
