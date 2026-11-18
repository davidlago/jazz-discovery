# Changelog

What's new in each release. Add user-visible changes under **Unreleased** as they land; when tagging a release, rename
that heading to the version (for example `## 0.2.0`) and start a new, empty **Unreleased**. The release workflow puts the
section for the tagged version at the top of the GitHub release notes (or **Unreleased**, if there's no section for it).

## Unreleased

- **Sidemen**: 41 more artists, the players all over the records in the Crate: Ron Carter, Paul Chambers, Billy Higgins,
  Tony Williams, Wynton Kelly, Joe Henderson, Johnny Hodges, Jimmy Blanton, Lil Hardin Armstrong and more, including
  the guide's first trombonists, vibraphonists, percussionists, a harpist and a flutist. Their pages show the records
  they play on (*Also Plays On*, with their instrument on each), and so do the pages of everyone already in the guide.
- Artists can be filtered to **Leaders** or **Sidemen**, and search also finds players who don't have a page yet,
  with the records they're on.
- **Personnel**: album pages list who played on the record, set like the credits on an LP's back cover, with when and
  where it was recorded and who produced, arranged and engineered it. Players with a page in the app link to it, and
  on the Mac, pointing at a track dims the players who aren't on it. 86 of the 88 albums so far, each checked by hand
  against the liner notes, Wikipedia or a discography.
- *Black Radio* plays the 2012 album; it had been matched to *Black Radio 2* on Apple Music.
- Sonny Rollins (1930–2026) and Cassandra Wilson (1955–2026), who died this year, are shown with their dates.
- Mac: `jazzdiscovery://` links open pages in the Mac app too (`jazzdiscovery://artist/miles-davis`, `era/bebop`,
  `album/kind-of-blue`…), as they already did on iPhone.

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
