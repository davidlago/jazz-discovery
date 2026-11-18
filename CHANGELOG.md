# Changelog

What's new in each release. Add user-visible changes under **Unreleased** as they land; when tagging a release, rename
that heading to the version (for example `## 0.2.0`) and start a new, empty **Unreleased**. The release workflow puts the
section for the tagged version at the top of the GitHub release notes (or **Unreleased**, if there's no section for it).

## Unreleased

## 1.10.0

- **Siri and Shortcuts**: "Play bebop radio on Jazz Discovery", "What happened in jazz today", "Continue my path",
  "Play my next stop", and opening any artist, record or tune.
- **Spotlight**: search the system for "Kind of Blue" or "Body and Soul" and open its page in the app.
- **Next stop**: when a path's track is playing, the player offers the next stop you haven't done; the Continue
  widget has a play button for it.
- **Morning note** (off unless you turn it on, in Settings ▸ Today in Jazz): the day's birthday or session at a time
  you pick. It's scheduled on your device; nothing is sent anywhere.
- **Radio for places and labels**: Play Radio on a city's, club's, studio's or label's page plays what was recorded
  there or on that label, and who played there.
- **The map** groups places that would overlap into one numbered pin; tap it to zoom in.
- The large Today in Jazz widget lists the next days with something when the day has only one event.
- **The Songbook** has all forty of its first list: Manteca, Misty, So What, Giant Steps, Naima, Moanin', Song for My
  Father, Maiden Voyage, Nardis, Stella by Starlight, On Green Dolphin Street and Birdland join, with 45 more versions.
- **25 more artists and 42 more records** (152 and 130 in all): the 1980s, 1990s and 2000s (which had none), soul and
  spiritual jazz, the organ, the first male singers (Johnny Hartman, Kurt Elling, Bobby McFerrin, Leon Thomas), and
  jazz from Norway, Sweden, Poland, Britain, South Africa, Ethiopia, Japan, Brazil and Cuba.
- **Three new paths**: From Hip-Hop Back to Jazz, The Protest Tradition and London Now.
- **Lineages** for the bass (from Jimmy Blanton to Esperanza Spalding) and the guitar.
- **Who played on what** is complete: Bix Beiderbecke's Singin' the Blues and Mongo Santamaría's Watermelon Man! now
  list their bands, session by session.
- **On This Day** covers 258 days, up from 207: release days, milestones like the first jazz record and Ellington's
  first night at the Cotton Club, and the two records above.

## 1.9.0

- **Widgets** on the iPhone (Home Screen, Lock Screen, StandBy) and the Mac (desktop, Notification Center):
  - **Today in Jazz**: the day's calendar page, the record's cover or the artist's portrait, and whose birthday it is
    or what was recorded on this date. Tap it to open that page. Small, medium and large, and on the Lock Screen.
  - **Continue**: the path you're on and its next stop, or the era stamp you're closest to inking. It updates as soon
    as you tick a stop or hear a record.

## 1.8.1

- **Your passport syncs** between your Mac and iPhone through your own iCloud: the records you've heard and saved,
  your era stamps and where you are on each path. There's nothing to set up when you're signed in to iCloud on both;
  the Passport page says whether it's on.

## 1.8.0

- **Today in Jazz** at the top of the home screen: a tear-off calendar page with whose birthday it is and what was
  recorded on this date, round anniversaries first ("Miles Davis was born 100 years ago today"), a picture, and one
  tap to play. On a quiet day it shows the nearest day that isn't.
- **This Week**: the next seven days, one line each.
- **On This Day**: the year at a glance, twelve months with every day that has something marked in its era's colour;
  pick any day (your birthday, say) to see what happened. 320 events on 207 days, from exact birth dates and the
  dated sessions in the personnel data.
- Artist pages show full dates ("May 26, 1926 – September 28, 1991").
- **Share cards**: a poster for a record (on its page) or for today's event, with a link back into the app.
- `jazzdiscovery://today` and `almanac/<mm>-<dd>` links.

## 1.7.0

- **Paths**: journeys with a point of view, a few stops each, every stop with something to listen for. Start Here
  is now a path, and six more join it: *Jazz for People Who Think They Hate Jazz*, *1959*, *Late Night*, *The Latin
  Tinge*, *One Tune, Five Decades* and *The Piano Trio*. Stops can be records, tracks, tunes, glossary terms or places.
- Your place is kept: a stop is done when its record is heard, its track has played through, or you've read it (a
  term, a tune, a place), and you can tick any stop yourself. *Continue* picks up at the next stop; finished paths get
  a stamp on the Passport page. Progress syncs with the rest of your passport.
- A **Paths** row on the home screen, led by the path you're on; Paths in the Mac sidebar under Listen.
  `jazzdiscovery://path/<id>` and `paths` links.

## 1.6.0

- **Lineages**: family trees for the trumpet, the saxophone, the piano, the drums and the voice. Faces placed by when
  each player came of age, lines for who learned from whom, and every line says why (and who said so). Select a face
  to light up its roots and heirs; *Play the Lineage* plays one track per player, in order, and the tree follows.
- Artist pages have a **Lineage** strip: who they came from and who came from them.
- **Glossary**: 35 terms, from *swing* and *the head* to *rhythm changes*, *clave* and *sheets of sound*, each with a
  definition, a paragraph and a recording to hear it in.
- Glossary terms are links wherever the app tells a story: era histories, why each record matters, tune stories.
- **How to Listen**: five steps through *So What*, on the Glossary and, until you've heard your first record, on the
  home screen.
- iPhone: Lineages and Glossary rows on Explore; Mac: in the sidebar. `lineage/<id>`, `lineages`, `term/<id>`,
  `glossary` and `how-to-listen` links.

## 1.5.0

- **Places**: a map of jazz, with 47 cities, neighbourhoods, clubs, studios and festivals as pins in their era's
  colour, and a **time slider** from 1895 to now. Drag it, or press play, and New Orleans lights up, then Chicago and
  Harlem, 52nd Street, the West Coast and, lately, South London. Shortcuts fly to New Orleans, Chicago, Kansas City,
  New York, Los Angeles, Europe and the world.
- **Place pages**: the story of each city and room, a small map with *Open in Maps*, its rooms, who was there, and the
  records made there (from where each Crate record was recorded).
- **Labels**: 14 label pages, Blue Note to Mack Avenue, each with its story, its sound and its look, the people behind
  it, a wall of its covers and its regulars. Labels on album pages are links.
- Era pages link to their places. iPhone: Places and Labels rows on Explore; Mac: Places and Labels in the sidebar.
  `jazzdiscovery://place/<id>`, `map`, `label/<id>` and `labels` links.

## 1.4.0

- **The Songbook**: 28 tunes, from *St. Louis Blues* to *Footprints*, each with its story, who wrote it and when, its
  form, and three to five landmark versions on a timeline, each with a sentence on what to listen for. *Play in Order*
  plays them oldest first.
- Tunes everywhere: a note mark on any track in the Songbook (click it on the Mac; touch and hold on iPhone), a
  Songbook row on artist pages (the tunes they wrote and their versions of others), *Also in the Crate* on tune pages,
  and tunes in search.
- **Songbook Radio**, shuffling versions across the book.
- iPhone: the Eras tab is now **Explore**: the eras as a carousel, then Decades, the Songbook and Connections.
- Mac: Songbook in the sidebar. `jazzdiscovery://tune/<id>`, `songbook` and `tab/explore` links.

## 1.3.0

- **Radio**: stations that keep playing, one per era, decade and instrument, plus **The Long Way** (130 years in order,
  two or three tracks per era) and, once you've heard something, **New to You**. Never the same artist twice in a row
  or the same record twice in five tracks, and each station opens with one of its era's essential tracks.
- **Why this track**: while a station plays, the player says why the track is there (from its record's story, that
  year's turning point or the artist) and links to its record, artist and era.
- **The Blindfold Test**: ten clips with the cover hidden. Which era? Who's playing? What's the lead instrument? Which
  came first? Easy or hard, across every era or just one; the sleeve turns over to show what it was. Your answers add
  up in your passport ("Your ear knows Hard Bop; Swing needs work"). Clips never show on the lock screen.
- *Play Radio* on every era and decade page; a Radio row and a Blindfold Test card on the home screen.
- The first tab is now **Discover** (the Mac's Timeline too); `jazzdiscovery://tab/discover`, `radio` and `blindfold`
  links.
- Every named track and every Crate album's tracklist now comes with the app, so era, artist and album pages show
  their tracks at once. A preview whose link has gone stale is looked up again.

## 1.2.0

- **Passport**: mark the records you've heard and save the ones to come back to (on every album page, and in any
  cover's menu). Records you play through in the app are marked for you once most of their tracks have played in full;
  previews mark a record as sampled. Heard covers get a small stamp, and anything can be unmarked.
- **Stamps**: every era has a passport stamp, inked in its colour as you hear its records, dated when you've heard them
  all. The Passport page (in the Mac's sidebar, and the seal button on iPhone) shows them with where you've been
  decade by decade, the instruments you've heard most, what you've heard lately and what you've saved. Era pages show
  their stamp and how many records you've heard.
- **Three doors** out of every record, at the bottom of its page and in the player when an album ends: the record that
  shares the most players with it, one from the style that came next, and an echo of it playing today, each with a
  sentence saying why, and records you haven't heard first.
- **Continue** on the home screen: the next stop on Start Here and the doors out of the last record you heard.
- The Crate filters by Unheard, Heard and Saved.
- **Import from Last.fm**: mark the Crate records among your most played albums as heard (Passport ▸ Import).
- The passport is ready to sync between your Mac and iPhone through iCloud; sync turns on once iCloud is enabled for
  the app.
- `jazzdiscovery://passport` opens the Passport.

## 1.1.0

- **Personnel**: album pages list who played on the record, set like the credits on an LP's back cover, with when and
  where it was recorded and who produced, arranged and engineered it. Players with a page in the app link to it, and
  on the Mac, pointing at a track dims the players who aren't on it. 86 of the 88 albums so far, each checked by hand
  against the liner notes, Wikipedia or a discography.
- **Sidemen**: 41 more artists, the players all over the records in the Crate: Ron Carter, Paul Chambers, Billy Higgins,
  Tony Williams, Wynton Kelly, Joe Henderson, Johnny Hodges, Jimmy Blanton, Lil Hardin Armstrong and more, including
  the guide's first trombonists, vibraphonists, percussionists, a harpist and a flutist. Their pages show the records
  they play on (*Also Plays On*, with their instrument on each), and so do the pages of everyone already in the guide.
- Artists can be filtered to **Leaders** or **Sidemen**, and search also finds players who don't have a page yet,
  with the records they're on.
- **Connections** now come from the records: two artists are linked when they play on the same album, and the more
  records they share, the thicker the line. Links that aren't on a record (a mentor, a band before the Crate's
  records, an influence, a duo) each say what they were. Select a face, then another in their circle, to see what
  ties them and the records they made together. *Played With* on artist pages lists the closest first.
- **Find a Path** on the Connections map: the shortest chain of records and bonds between any two artists (Scott
  Joplin to Nubya Garcia is nine links), drawn on the map and listed step by step, with *Play the Path*: one track
  from each link, in order. Links like `jazzdiscovery://between/miles-davis/nubya-garcia` open it.
- Mac: `jazzdiscovery://` links open pages in the Mac app too (`jazzdiscovery://artist/miles-davis`, `era/bebop`,
  `album/kind-of-blue`…), as they already did on iPhone.
- *Black Radio* plays the 2012 album; it had been matched to *Black Radio 2* on Apple Music.
- Mac: the faces at the top of the home screen no longer show Miles Davis three times (he leads three eras); each era
  shows a different artist.
- Sonny Rollins (1930–2026) and Cassandra Wilson (1955–2026), who died this year, are shown with their dates.

## 1.0.1

- **Privacy**: the app no longer keeps or sends cookies when it looks things up, and YouTube's player (now its
  "privacy-enhanced" one) forgets everything when you close a video, so YouTube can't tie one search or video to the
  next.
- The video player stays on the video: links in it open in your browser or the YouTube app.
- iPhone: a `jazzdiscovery://decade/…` link with a made-up decade no longer crashes the app, and links can't start
  music by themselves.
- iPhone: your Last.fm connection stays on this iPhone (it isn't copied into backups or onto a new phone), and Settings
  says so if the keychain couldn't save it.
- **Sound quality**: the player shows the quality that's playing (Hi-Res Lossless, Lossless, Dolby Atmos or AAC) and
  where it's going ("Scarlett 2i2 · 96 kHz"), and says when a song comes in a better quality on Apple Music.
- iPhone: full tracks play in the quality set in Settings ▸ Apps ▸ Music ▸ Audio Quality, Hi-Res Lossless included,
  and the app lets go of the audio session its previews used, so it doesn't hold a USB DAC at that rate.
- Mac: Apple Music gives apps on the Mac only its AAC stream (256 kbps, 44.1 kHz), so the output (a USB DAC, say)
  switches to 44.1 kHz while Jazz Discovery plays and goes back to its own rate when you stop or quit, instead of
  the Mac resampling the music. You can turn this off in Settings ▸ Apple Music. For Lossless and Hi-Res Lossless,
  the player's *Open in Music* button names the better quality and takes you to the Music app.

## 1.0.0

- **Jazz Discovery for iPhone**: every section of the Mac app, designed for the phone. Five tabs (Timeline, Eras,
  Artists, Crate and Search), full-bleed era, artist and album pages, a player above the tab bar with a full-screen
  Now Playing, lock screen controls and AirPlay, a Connections map you pinch, pan and tap, and Apple Music and Last.fm
  in Settings.
- Scrobbling counts how far a song actually got, so songs still scrobble when the app was held up in the background
  (or the Mac slept) while they played.
- **Last.fm scrobbling**: add your own Last.fm API key in Settings → Last.fm and connect your account. Full tracks
  you play with Apple Music are scrobbled once half the track (or 4 minutes) has played, and your profile can show
  what's playing now. Scrobbles made offline are kept and sent later. Previews aren't scrobbled.
- Settings now has tabs: **Apple Music** and **Last.fm**.
- **Connections**: hovering a face shows that artist again; before, the card was always Nubya Garcia's.

## 0.1.0

The first release.

- **Timeline**: the River of Jazz, 14 styles from ragtime to today flowing in overlapping channels, with 40 turning
  points to hover; a *Start Here* listening path of 14 records, a daily artist spotlight and a strip of decades.
- **Eras & Styles**: record-sleeve posters for every era, each with its story, sound, places, key artists, essential
  records and tracks, YouTube documentaries and a Wikimedia Commons picture archive.
- **Decades**: the 1890s to the 2020s, with the styles in the air, turning points, records and who was playing.
- **Artists**: 86 players, singers and composers in duotone portraits, filterable by era and instrument, with
  Wikipedia biographies, popular songs on Apple Music, records, live videos and who they played with.
- **The Crate**: 88 essential albums by decade, with playable tracklists and why each one matters.
- **Connections**: a chronological map of who played with whom.
- Full tracks through your Apple Music subscription (MusicKit), 30-second previews otherwise, and **Open in Music**
  everywhere; YouTube videos play in the app.
