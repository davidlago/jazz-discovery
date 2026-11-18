#!/usr/bin/env python3
"""Checks Shared/Resources/jazz.json and catalog.json: every reference resolves, ids are unique, connections
are symmetric and every album has an Apple Music match. Also checks the generated files when they exist: ids.json
(scripts/build-ids.py) and sessions.json (scripts/build-sessions.py). Problems are errors (exit 1); things for a person
to look at, such as a birth year that disagrees with Wikidata, are warnings. Usage: python3 -I scripts/validate-data.py"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Shared", "Resources")
data = json.load(open(os.path.join(RES, "jazz.json")))
catalog = json.load(open(os.path.join(RES, "catalog.json")))
errors = []
warnings = []

def unique(kind, items):
    ids = [i["id"] for i in items]
    for d in sorted({i for i in ids if ids.count(i) > 1}):
        errors.append(f"duplicate {kind} id {d}")
    return set(ids)

eras = unique("era", data["eras"])
artists = unique("artist", data["artists"])
albums = unique("album", data["albums"])
by_artist = {a["id"]: a for a in data["artists"]}

for e in data["eras"]:
    errors += [f"era {e['id']}: unknown artist {a}" for a in e["keyArtists"] if a not in artists]
    errors += [f"era {e['id']}: unknown album {a}" for a in e["keyAlbums"] if a not in albums]
for a in data["artists"]:
    errors += [f"artist {a['id']}: unknown era {e}" for e in a["eras"] if e not in eras]
    if a["primaryEra"] not in a["eras"]:
        errors.append(f"artist {a['id']}: primaryEra {a['primaryEra']} isn't in eras")
    errors += [f"artist {a['id']}: unknown album {x}" for x in a["albums"] if x not in albums]
    for c in a["connections"]:
        if c not in artists:
            errors.append(f"artist {a['id']}: unknown connection {c}")
        elif a["id"] not in by_artist[c]["connections"]:
            errors.append(f"artist {a['id']}: connection {c} isn't mutual")
for al in data["albums"]:
    if al["artist"] not in artists: errors.append(f"album {al['id']}: unknown artist {al['artist']}")
    if al["era"] not in eras: errors.append(f"album {al['id']}: unknown era {al['era']}")
    if al["id"] not in catalog: errors.append(f"album {al['id']}: no Apple Music match (run scripts/build-catalog.py)")
years = [m["year"] for m in data["milestones"]]
if years != sorted(years): errors.append("milestones aren't in chronological order")

# bonds: relationships that aren't "played on the same record" (a mentor, a band with no record in the Crate, an
# influence, a duo), each with a note saying what it was.
bond_pairs = set()
for b in data.get("bonds", []):
    where = f"bond {b.get('a')}–{b.get('b')}"
    if b.get("a") not in artists or b.get("b") not in artists: errors.append(f"{where}: unknown artist")
    if b.get("a") == b.get("b"): errors.append(f"{where}: an artist bonded to themself")
    if b.get("kind") not in ("band", "mentor", "influence", "duo"): errors.append(f"{where}: kind {b.get('kind')!r}")
    if not b.get("note", "").strip(): errors.append(f"{where}: no note")
    pair = tuple(sorted((b.get("a"), b.get("b"))))
    if pair in bond_pairs: errors.append(f"{where}: listed twice")
    bond_pairs.add(pair)

# ids.json: Wikidata and MusicBrainz IDs and exact dates (scripts/build-ids.py).
ids_path = os.path.join(RES, "ids.json")
if os.path.exists(ids_path):
    ids = json.load(open(ids_path))
    errors += [f"ids.json: unknown artist {k}" for k in ids if k not in artists]
    for a in data["artists"]:
        entry = ids.get(a["id"])
        if entry is None:
            warnings.append(f"ids.json: no entry for {a['id']} (run scripts/build-ids.py)")
            continue
        for field in ("born", "died"):
            ours, theirs = a.get(field), entry.get(field)
            also = [int(d[:4]) for d in entry.get(field + "Also", [])]
            if theirs and ours != int(theirs[:4]) and ours not in also:
                warnings.append(f"{a['id']}: {field} {ours} in jazz.json, {theirs} on Wikidata")
            elif ours and not theirs and field == "died":
                warnings.append(f"{a['id']}: died {ours} in jazz.json, no death date on Wikidata")

# sessions.json: who played on each album, when and where (scripts/build-sessions.py, then reviewed by hand).
sessions_path = os.path.join(RES, "sessions.json")
if os.path.exists(sessions_path):
    import re
    sessions = json.load(open(sessions_path))
    reviewed = 0

    def track_key(title):
        """As Session.trackKey in the app: everything from the first bracket on is ignored, then case, accents and
        punctuation ("Corcovado" is "Corcovado (Quiet Nights of Quiet Stars)")."""
        import unicodedata
        cut = re.split(r"[(\[]", title, maxsplit=1)[0]
        cut = unicodedata.normalize("NFKD", cut).encode("ascii", "ignore").decode().lower()
        return re.sub(r"[^a-z0-9]", "", cut)
    for album_id, s in sessions.items():
        where = f"sessions.json: {album_id}"
        if album_id not in albums:
            errors.append(f"{where}: unknown album")
            continue
        for c in s.get("personnel", []) + s.get("crew", []):
            if c.get("artist") is not None and c["artist"] not in artists:
                errors.append(f"{where}: unknown artist {c['artist']} ({c.get('name')})")
            tracks = {track_key(t) for t in s.get("tracks", [])}
            for t in c.get("only", []) + c.get("except", []):
                if tracks and track_key(t) not in tracks:
                    errors.append(f"{where}: {c.get('name')} lists a track that isn't on the album: {t}")
        for r in s.get("recorded", []):
            if "date" not in r and "place" not in r:
                errors.append(f"{where}: a recording session with neither a date nor a place")
            if "date" in r and not re.fullmatch(r"\d{4}(-\d{2}(-\d{2})?)?", r["date"]):
                errors.append(f"{where}: recording date {r['date']!r} isn't YYYY[-MM[-DD]]")
        if s.get("reviewed"):
            reviewed += 1
            if not s.get("personnel"):
                errors.append(f"{where}: reviewed, but nobody is credited")
            leader = next(a for a in data["albums"] if a["id"] == album_id)["artist"]
            if not any(c.get("artist") == leader for c in s.get("personnel", [])):
                warnings.append(f"{where}: the leader ({leader}) isn't among the players")
    # Every curated connection is explained: a reviewed record both are on, or a bond.
    on = {}
    for album_id, sess in sessions.items():
        if not sess.get("reviewed") or album_id not in albums: continue
        leader = next(a for a in data["albums"] if a["id"] == album_id)["artist"]
        for who in {c.get("artist") for c in sess.get("personnel", []) if c.get("artist")} | {leader}:
            on.setdefault(who, set()).add(album_id)
    for a in data["artists"]:
        for c in a["connections"]:
            if a["id"] < c and not (on.get(a["id"], set()) & on.get(c, set())) and (a["id"], c) not in bond_pairs:
                errors.append(f"connection {a['id']}–{c}: no shared record and no bond explains it")
    missing = len(albums) - len([k for k in sessions if k in albums])
    print(f"sessions.json: {reviewed} of {len(albums)} albums reviewed, {len(sessions) - reviewed} drafts, "
          f"{missing} not drafted")

if warnings:
    print("\n".join("warning: " + w for w in warnings))
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"OK: {len(eras)} eras, {len(artists)} artists, {len(albums)} albums, {len(data['milestones'])} milestones")
