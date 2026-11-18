# The catalogue: more, and better balanced

Every feature in the roadmap is only as good as the data under it. A radio station with eight tracks repeats; a
lineage with three bassists isn't one; a calendar with 170 dates is empty half the year. This thread grows the content
alongside the features. It isn't a release of its own: each release takes a batch.

## Where it stands (2026-11-18, after the second batch)

183 artists and 176 records. The second batch (31 artists, 46 records) meets every floor in this file: each decade
from the 1920s has at least 10 records (the 1920s 11, 1930s 11, 1940s 10, 2020s 17), each era at least 6 artists and 8
records, and trombone, clarinet, vibraphone and organ each have a lineage tree (6–8 players). Two records' personnel
stay unreviewed (The Movement Revisited, Dear Love: no per-track credits, two unconfirmed names). Research for the
batch was done by agents with a source for every fact, kept outside the repo; `scripts/coverage.py` prints the shape.

## Where it stood (2026-11-18, after the first batch)

152 artists and 130 records (was 86 and 88 when this was written; 127 after 1.1's sidemen). The first batch (25 artists,
42 records) filled the 1980s–2010s (each now 10 or more records), soul jazz, spiritual jazz, the organ, the first male
singers, and Europe/ECM, South Africa, Ethiopia, Japan, Brazil and Cuba after the 1960s. Still under the floors: the
1920s–40s and 2020s, roots (3 artists, 3 records), and the New Orleans, swing, bebop, cool and Latin eras' records.

Two hand fixes in tracks.json that a `build-tracks.py` run would undo, since it re-searches tracks with no Crate album:
Ornette Coleman's "Turnaround" (keep the 1959 original, not the 2005 Sound Grammar version) and Wayne Shorter's
"Nefertiti" (left unresolved rather than matched to Herbie Hancock's 2007 version). Check them after any rerun.

## Where it stood (2026-11-17)

| | Count | Notes |
|---|---|---|
| Eras | 14 | 1895 to now |
| Artists | 86 | 21 living |
| Records | 88 | all matched on Apple Music |
| Milestones | 40 | |
| Named tracks | 455 | 98 era essentials, plus album highlights and artists' signature tracks, without duplicates |

Where it's lopsided:

- **By decade.** 48 of the 88 records are from the 1950s and 1960s.

  | 1920s | 1930s | 1940s | 1950s | 1960s | 1970s | 1980s | 1990s | 2000s | 2010s | 2020s |
  |---|---|---|---|---|---|---|---|---|---|---|
  | 5 | 4 | 4 | 24 | 24 | 10 | 2 | 4 | 0 | 9 | 2 |

  (No record in the Crate is dated 2000–2009.)
- **By instrument.** Saxophone 21, piano 19, trumpet 14, vocals 8, bandleader 6, guitar 5, drums 5, composer 3,
  bass 3, clarinet 1, organ 1. No trombone, vibraphone, flute, violin or harp; no percussionist listed as one.
- **By era.** Roots, soul jazz and spiritual jazz are the main era of three artists each; contemporary, of eleven.
- **By place.** Outside the United States: Brazil and Cuba through the Latin era, Django Reinhardt's Paris, and
  London through two artists. The three ECM records are all led by Americans. Nothing from European jazz as a scene
  of its own, or from South Africa, Japan or Ethiopia, each of which has a real jazz history.
- **By voice.** All eight artists listed as vocalists are women, and only three women are listed as instrumentalists
  (Alice Coltrane, Esperanza Spalding, Nubya Garcia). No man is listed as a vocalist, though Louis Armstrong and Chet
  Baker both sang.

## Targets

By 1.8: about **150 artists** and **200 records**. Not a bigger encyclopedia for its own sake; these numbers are what
the features need.

| Feature | Needs |
|---|---|
| Radio (1.3) | At least 12 resolved tracks per station; 20 is comfortable. Every era, decade and instrument family. |
| Blindfold Test (1.3) | Four plausible wrong answers per question: at least five artists per era and per instrument family. |
| Songbook (1.4) | Versions across eras, including recent ones and at least one singer per song with words. |
| Lineages (1.6) | Six to twelve players per instrument tree, with no generation missing. |
| On This Day (1.8) | 450+ dated events for most days to have one. |

Floors to reach: every decade from the 1920s on has at least 10 records; every era has at least 6 artists and 8
records; every instrument family with a lineage has at least 6 players.

## What to add, and when

Who exactly is your call; these are the gaps and the kind of names that fill them. The lists are prompts, not a canon.

### With 1.1: the people already on the records

The sessions data names them. Rhythm sections first, since they tie the graph together and fix the instrument gaps:
bassists and drummers who appear on many of the existing records, and the first trombonists and vibraphonists.
About 40 people, chosen by how often they appear. No new records needed; they come with the ones already here.

### With 1.3: fill the thin stations

- **The 1980s, 1990s and 2000s**: about 25 records. The eighties beyond the young lions; the nineties' piano trios
  and big-label signings; the 2000s, which are empty.
- **Soul jazz and spiritual jazz**: three or four artists and five or six records each. The organ tradition has one
  player today.
- **Roots**: the era has three artists; a few more blues and ragtime figures make its station more than a loop.

### With 1.4: singers and the standards players

The Songbook needs voices. Male vocalists (none is listed as one), vocal groups, and the instrumentalists known for
standards more than for originals. About 10 artists, 12 records.

### With 1.5: the rest of the map

About 20 artists and 25 records from outside the American mainstream: European jazz and the ECM label's world;
British jazz before the current wave; South African jazz in exile and at home; Japan; Ethiopia; more of Cuba and
Brazil beyond the 1960s. This is also where the two **new eras** in the roadmap's decision table would come in, if
the records justify them:

- *European & ECM* (about 1969 on), which today has three ECM records and no era of its own.
- *Acid jazz & hip-hop* (about 1988–2000), the bridge the "From Hip-Hop Back to Jazz" path needs.

A new era costs a summary, traits, places, key artists and records, essential tracks, a colour that reads next to its
neighbours on the River, and `leadsTo` links (1.2). The River packs lanes by itself.

### With 1.6: complete the trees

Whoever each lineage is missing once it's drawn: usually an early figure (the first important player of the
instrument) and a recent one. About 10 artists.

### With 1.7 and 1.8: what paths and the calendar ask for

Paths will want specific records the Crate doesn't have (a protest song's album, a sampled record). The almanac's heat
map will show months with few events. Both produce short, specific wish lists.

## What a new entry costs

| Entry | By hand | By script |
|---|---|---|
| Artist | Blurb (one or two sentences), eras, primary era, instruments, Wikipedia title, three signature tracks, video search phrase, connections or bonds | IDs and dates (`build-ids.py`), track matches (`build-tracks.py`), portrait (from Wikipedia, at run time) |
| Record | Why it matters (one or two sentences), three highlights, era, label, starter or not | Apple Music match and tracklist (`build-catalog.py`), personnel and dates (`build-sessions.py`, then review) |
| Era | See above | — |

An artist or a record is about ten minutes of writing and five of review when the facts check out. The scripts are
incremental: each only looks up what's new.

Rules for the writing, which the existing data already follows:

- Original prose. Wikipedia text is shown in its own attributed section and never pasted into ours.
- Say what the music sounds like and why it mattered, not that it's great.
- Facts in a blurb (a first, a sales claim, who was in the band) are checked against a source before they go in.
- Living artists get the same tone as historical ones: description, not promotion.

## Tools

`scripts/coverage.py` (new, with 1.1): prints the tables at the top of this file from the data, plus, as later
releases add them: tracks per station, players per lineage, versions per tune by era, and empty days in the calendar.
It also lists each floor that isn't met. Run it before choosing a batch and after.

`validate-data.py` keeps doing what it does: nothing dangling, nothing unmatched.

## Keeping it honest

A catalogue this size is an argument about what matters. Two habits keep it from hardening into one person's (or one
model's) taste:

- Every batch is proposed as a list with a line on why each entry is there, and you cut and add before anything is
  written.
- The coverage report shows the shape of the whole, so a batch can be judged by what it does to the balance and not
  just entry by entry.
