# Jazz Discovery roadmap: from encyclopedia to companion

*Written 2026-11-17, against `main` at 452078b (Mac 1.0.0 released; the iPhone app built, not yet on the App Store).*

**Status (2026-11-18):** 1.0.1, 1.1 and 1.2 are released (`v1.0.1`, `v1.1.0`, `v1.2.0`); 1.2's iCloud sync waits on
the App ID's iCloud capability (see its file). 1.1 shipped with 86 of the 88 albums'
personnel reviewed: Bix Beiderbecke's *Singin' the Blues* and Mongo Santamaría's *Watermelon Man!* still need a source
for their players. 1.3 (Radio & the Blindfold Test) is released as `v1.3.0`. 1.4 (the Songbook) is released as `v1.4.0`. Next: 1.5, Places & Labels.

Today the app is a beautiful encyclopedia: 14 eras, 86 artists, 88 records and 40 milestones, and every screen is
browse → read → play. This roadmap adds three things it doesn't have:

1. **Relationships**: who played on what, where, for which label, and which tunes they all share.
2. **Listening that teaches**: radio, paths, guides that follow the music, a glossary you can hear.
3. **You**: what you've heard, what's next, and a reason to open the app tomorrow.

It is split into eight releases. Each one is a `vX.Y.0` tag that ships the Mac app and the iPhone app together, the way
releases work today, and each is useful on its own. One file per release:

| Release | Name | What people get | Needs |
|---|---|---|---|
| [1.1](1.1-sessions-and-sidemen.md) | Sessions & Sidemen | Who played on every record; sidemen as people; Connections lines that say why; a path between any two artists | — |
| [1.2](1.2-passport.md) | Passport | Heard / saved, progress per era, stamps, sync between Mac and iPhone, "three doors" out of every record | (1.1 makes the doors better) |
| [1.3](1.3-radio-and-blindfold.md) | Radio & the Blindfold Test | One-tap stations with "why this track"; a guess-who listening game | — (1.2 adds "New to you") |
| [1.4](1.4-songbook.md) | The Songbook | Tunes as pages: one tune, many versions across eras | 1.3 (bundled tracks) |
| [1.5](1.5-places-and-labels.md) | Places & Labels | A map with a time slider, city and venue pages; label pages | 1.1 (where records were made) |
| [1.6](1.6-lineages-and-glossary.md) | Lineages & Glossary | Instrument family trees; jazz terms you can tap and hear | 1.1 (more instruments) |
| [1.7](1.7-paths-and-guides.md) | Paths & Listening Guides | Themed journeys; notes and a form diagram that follow the track as it plays | 1.3, 1.6 |
| [1.8](1.8-on-this-day.md) | On This Day | Birthdays and sessions on today's date; widgets; share cards | 1.1 (session dates) |

[catalog.md](catalog.md) is the ninth thread: growing and balancing the content itself. It runs through every release.

**Order.** 1.1 first because five later releases read its data. After that, 1.2 and 1.3 can swap, and 1.5, 1.6 and 1.8
can go in any order. 1.4 needs 1.3's bundled tracks, and 1.7 needs 1.3 and 1.6.

**Before 1.1.** The **Unreleased** section of `CHANGELOG.md` (privacy, sound quality) and the iPhone app's first App
Store submission are still open. Ship those as 1.0.1 first, so 1.1 is an update to an app that's already in the store,
not part of its first review.

## Principles

These hold for every release. They're what the app already does; the roadmap doesn't change them.

- **No server, no account, no analytics.** Content is curated JSON in the bundle. What the app learns about you stays
  on your devices and in your own iCloud.
- **Everything works without an Apple Music subscription.** Every listening feature has a 30-second-preview form.
  Where a feature really needs full tracks (synced listening guides), it says so and offers *Open in Music*.
- **Facts come from sources, prose is ours.** Dates, personnel, coordinates and composers are drafted by scripts from
  MusicBrainz and Wikidata (both CC0), then reviewed by hand. Summaries, "why it matters" and listening notes are
  original writing. Nothing is shown in the app until it's marked reviewed.
- **New data is additive.** New files and optional fields only, so a release can ship with part of its content and the
  app shows what it has.
- **Shared logic, two UIs.** Models, services and layout maths go in `Shared/`; each app keeps its own views, as now.
- **The look stays.** Ink, cream and brass; condensed display type; era-coloured duotone portraits. Each new section
  gets one visual idea of its own in that language (listed below).

## Where everything lives

### Mac sidebar

| Now | After 1.8 |
|---|---|
| **Explore**: Timeline, Eras & Styles, Decades, Artists, The Crate, Connections | **Discover** (the home page, was Timeline) |
| **Eras**: the 14 eras | **Listen**: Radio, Paths, Blindfold Test |
| | **Explore**: Eras & Styles, Decades, Songbook, Places, Labels, Lineages, Glossary |
| | **People**: Artists, Connections |
| | **Records**: The Crate |
| | **You**: Passport |
| | **Eras**: the 14 eras (unchanged) |

### iPhone tabs

Five tabs, as now. Two are renamed when they outgrow their names:

| Now | After | Changes in |
|---|---|---|
| Timeline | **Discover**: today, continue, radio, the river, paths, Start Here, decades | 1.3 |
| Eras | **Explore**: eras first, then Decades, Songbook, Places, Labels, Lineages, Glossary, Connections as rows with a preview and *See all* | 1.4 |
| Artists | Artists (adds sidemen, the path finder) | 1.1 |
| Crate | Crate (adds All / Saved / Heard; the Passport button) | 1.2 |
| Search | Search (adds tunes, places, labels, terms, paths) | each release |

Passport opens from a stamp button next to the gear, on every tab.

### Discover, when it's all there

Top to bottom: the hero (unchanged) → **Today** (on this day) → **Continue** (your path, your last record's three
doors) → **Radio** (a row of stations) → **The River of Jazz** → **Paths** → **Blindfold Test** → **Travel by Decade**.
Each release adds its row; nothing is rearranged twice.

### One visual idea per section

| Section | Idea |
|---|---|
| Personnel | Back-cover liner credits: expanded small caps, dotted leaders (`JOHN COLTRANE ····· tenor saxophone`) |
| Passport | Rubber stamps in era ink, slightly rotated, one per era, filling in as you listen |
| Radio | Record centre labels: a circle in the station's colour, spinning while it plays |
| Blindfold Test | The cover blurred behind a question mark; the reveal turns the sleeve over |
| Songbook | Lead-sheet cards: faint staff lines, serif italic title, a row of dots (one per version, era-coloured) |
| Places | A dark map with era-coloured pins and a time slider that reuses the River's colours |
| Labels | A wall of covers in catalogue order: the label's design history at a glance |
| Lineages | A family tree of duotone faces, left to right in time |
| Glossary | Dictionary entries: serif headword, one-line definition, a play button |
| Paths | A route with numbered stops (Start Here's numerals, grown up) |
| Listening guides | A form bar: the tune's structure as coloured blocks, with a playhead |
| On This Day | A tear-off calendar page |

## Data

### Files

Each domain gets its own file in `Shared/Resources/`, loaded by `JazzLibrary.load()`. A missing file is an empty
section, not a crash.

| File | Written by | Holds | Since |
|---|---|---|---|
| `jazz.json` | hand | eras, artists, albums, milestones (as now), plus `bonds` (1.1) | 0.1 |
| `catalog.json` | `build-catalog.py` | Apple Music album matches (as now) | 0.1 |
| `sessions.json` | `build-sessions.py`, then reviewed | personnel, recording dates and studios per album | 1.1 |
| `ids.json` | `build-ids.py` | each artist's Wikidata and MusicBrainz IDs, exact birth and death dates | 1.1 |
| `tracks.json` | `build-tracks.py` | Apple Music song matches for every named track | 1.3 |
| `tracklists.json` | `build-catalog.py` | each album's tracks | 1.3 |
| `songbook.json` | hand, checked by `build-songbook.py` | tunes and their versions | 1.4 |
| `places.json`, `labels.json` | hand, coordinates from `build-places.py` | cities, venues, studios; labels | 1.5 |
| `lineages.json`, `glossary.json` | hand | instrument trees; terms and examples | 1.6 |
| `paths.json`, `guides.json` | hand; guide timings from the in-app editor | journeys; timed listening notes | 1.7 |
| `almanac.json` | `build-almanac.py` | every dated event, by month and day | 1.8 |

Everything stays small: all of it together is well under 2 MB of JSON.

### Sources, checked on 2026-11-17

| Need | Source | What I saw |
|---|---|---|
| Personnel, instruments, recording dates, studios, composers | MusicBrainz web service (CC0) | *Kind of Blue*: per-track players with instruments, both session dates (1959-03-02, 1959-04-22), the studio and each tune's composer. Of six more albums sampled, three were complete (*Idle Moments*, *The Epic*, *Black Radio*), one was thin (*Source*: 1 of 9 tracks credited), and for two (*Getz/Gilberto*, *Moanin'*) a plain search picked a later reissue with no credits. So: match on year, try several editions, keep a hand override, and review every album. The server also answered 503 ("busy") to several requests; the script must retry and be resumable. |
| Exact birth and death dates | Wikidata (CC0), looked up by the Wikipedia title already in `jazz.json` | Miles Davis: 1926-05-26 and 1991-09-28, day precision, plus his MusicBrainz ID. |
| Coordinates | Wikidata | Village Vanguard and Minton's Playhouse both have them. |
| Song matches, previews | iTunes Search API (as now) | Already used; ~20 requests a minute, so everything is precomputed at build time. |

MusicBrainz asks scripts to identify themselves and stay at one request a second. The scripts will send a plain
`JazzDiscoveryCatalog/1.0` user agent, like `build-catalog.py` does, with no contact details unless you choose to add one.

### Validation

`scripts/validate-data.py` grows with each file: every ID resolves, every reviewed entry is complete, dates parse,
coordinates are on Earth. CI already runs it on every push. It also prints a count of unreviewed drafts, which is
allowed (they're hidden in the app) but visible.

## Code groundwork

Small pieces that several releases need. Each is built in the first release that uses it.

| Piece | What | First used |
|---|---|---|
| **Unit tests** | The project has no test target; `--self-test` and `--snapshots` are the only checks. Add `JazzDiscoveryTests` (Swift Testing) for `Shared/Model` logic and run it in CI's `build` job. | 1.1 |
| **One `Route`** | The Mac's `Route` and the iPhone's `PhoneRoute` list the same pages twice. Make `Route` (in `Shared/`) the list of pages, and `PhoneRoute` a thin wrapper (`.page(Route)`, plus the phone-only `.decades` and `.connections(focus:)`), so a new page is one case, not two. | 1.1 |
| **One link parser** | `PhoneRouter.handle` parses `jazzdiscovery://` links; the Mac has no URL scheme at all. Move parsing to `Shared/Model/DeepLink.swift` (URL → `Route`), register the scheme in `Config/Info.plist`, and keep the rule that a link can only show a page, never start music. Widgets (1.8) need this on both platforms. | 1.1 |
| **Optional data files** | `JazzLibrary.load()` reads the extra files; decoding uses defaults for missing fields. | 1.1 |
| **`PlayContext`** | Every `player.play…` call says why it's playing (`.album(id)`, `.era(id)`, `.station(id)`, `.tune(id)`, `.path(id, step)`), so the passport and "why this track" know what you're hearing. | 1.2 |
| **Listening log** | The player already measures real listening time for Last.fm. The same measure, independent of Last.fm, tells the passport when a track counts. | 1.2 |
| **Start at, stop at** | Play a track from a time, optionally to a time (glossary examples, guide sections). | 1.6 |
| **Passport sync** | iCloud key-value storage; see 1.2 for the signing work on the Mac. | 1.2 |
| **Widget target** | A WidgetKit extension for both platforms, an app group, profiles for a second bundle ID. | 1.8 |

## How each release gets done

Every release file has the same shape: what people get, data, shared code, Mac, iPhone, tests, work packages, risks,
and a done checklist. A **work package** is one reviewable change, roughly one sitting together, in an order where the
app still builds and runs after each. Packages marked ★ are the smallest set that makes the release worth shipping; the
rest can slip to a point release.

Who does what:

- **Claude**: code, scripts, first drafts of all data and prose, tests, screenshots for review.
- **Scripts + sources**: every date, credit, coordinate and composer.
- **You**: taste (which records, which tunes, which paths), reading the prose, anything that needs ears (guide timings,
  whether a blindfold round is fair), Apple's developer portal, and App Store submission.

The done checklist, common to all:

1. `python3 -I scripts/validate-data.py` passes.
2. Unit tests pass; both apps build in CI.
3. Mac `--snapshots` and the iPhone screenshot script cover the new screens, and you've looked at them.
4. `--self-test` passes from the sandboxed Mac app.
5. Works with Apple Music connected, and with previews only.
6. VoiceOver reads the new screens; Reduce Motion is respected; iPhone text scales.
7. `CHANGELOG.md`, the README's section table, `docs/privacy.md` (if what the app stores or sends changed) and
   `docs/app-store.md` (listing text, screenshots) are updated.
8. Tag `vX.Y.0`: CI publishes the Mac release and uploads the iPhone build to TestFlight; you submit it for review.

## Decisions for you

None of these block 1.1.

| # | Decision | My recommendation | Needed by |
|---|---|---|---|
| 1 | The game's name. "Blindfold Test" is the name of DownBeat magazine's long-running column. | Call it **Needle Drop** in the app (the music-school term for the same exercise) unless you're comfortable with the homage. | 1.3 |
| 2 | Passport sync needs the iCloud capability turned on for the app's bundle ID, in Apple's developer portal. | Do it; it's the same kind of one-time step as MusicKit. Without it the passport still works, on one device. | 1.2 |
| 3 | New eras. Nothing covers European/ECM jazz or the acid-jazz and hip-hop years. | Add two eras when the catalogue has enough records for them; the River already packs lanes automatically. | catalog |
| 4 | A daily "On this day" notification. | Off by default, scheduled on the device, one switch in Settings. | 1.8 |
| 5 | "Near you" for venues would need your location. | Skip it. *Open in Maps* does the job and the privacy policy stays one sentence. | 1.5 |
| 6 | How far the catalogue grows. | About 150 artists and 200 records by 1.8; see [catalog.md](catalog.md). | ongoing |

## Not planned

Accounts or a backend; social features; tour dates and tickets; Spotify or other services; lyrics; an AI chat. An iPad
layout, CarPlay and Apple TV are natural later steps once the content is this deep, and nothing here makes them harder.
