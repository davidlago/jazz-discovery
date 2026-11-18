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
    for nxt in e.get("leadsTo", []):
        if nxt not in eras: errors.append(f"era {e['id']}: leadsTo unknown era {nxt}")
        if nxt == e["id"]: errors.append(f"era {e['id']}: leads to itself")
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

# tracks.json: every key is a track the data still names; albums and eras resolve; thin eras reported.
tp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Shared", "Resources", "tracks.json")
if os.path.exists(tp):
    named = set()
    for e in data["eras"]:
        named |= {f"{t['artist']}|{t['title']}" for t in e["essentialTracks"]}
    for al in data["albums"]:
        named |= {f"{al['artistName']}|{h}" for h in al["highlights"]}
    for a in data["artists"]:
        named |= {f"{a['name']}|{t}" for t in a["signatureTracks"]}
    sbp = os.path.join(os.path.dirname(tp), "songbook.json")
    if os.path.exists(sbp):
        for t in json.load(open(sbp))["tunes"]:
            named |= {f"{v['artistName']}|{v.get('title') or t['title']}|{v['year']}" for v in t["versions"]}
    tracks = json.load(open(tp))
    per_era = {}
    for k, t in tracks.items():
        if k not in named: errors.append(f"tracks.json: {k} isn't named anywhere in jazz.json (rerun build-tracks.py)")
        if t.get("album") and t["album"] not in albums: errors.append(f"tracks.json: {k}: unknown album {t['album']}")
        era = t.get("era") or (next((a["era"] for a in data["albums"] if a["id"] == t.get("album")), None))
        if era and era not in eras: errors.append(f"tracks.json: {k}: unknown era {era}")
        if era: per_era[era] = per_era.get(era, 0) + 1
    thin = [f"{e} ({per_era.get(e, 0)})" for e in eras if per_era.get(e, 0) < 12]
    print(f"tracks.json: {len(tracks)} of {len(named)} named tracks resolved" + (f"; thin stations: {', '.join(thin)}" if thin else ""))

# songbook.json: references resolve; each tune has three versions with notes, a landmark, two eras or more.
sp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Shared", "Resources", "songbook.json")
if os.path.exists(sp):
    book = json.load(open(sp))["tunes"]
    ids = [t["id"] for t in book]
    if len(ids) != len(set(ids)): errors.append("songbook.json: duplicate tune IDs")
    tracks_have = json.load(open(tp)) if os.path.exists(tp) else {}
    def era_of(v):
        if v.get("artist") in by_artist: return by_artist[v["artist"]]["primaryEra"]
        cands = [e for e in data["eras"] if e["start"] <= v["year"] <= e["end"]]
        return max(cands, key=lambda e: e["start"])["id"] if cands else None
    unresolved = []
    for t in book:
        w = f"songbook {t['id']}"
        if t.get("builtOn") and t["builtOn"] not in ids: errors.append(f"{w}: builtOn {t['builtOn']} isn't a tune")
        if len(t["versions"]) < 3: errors.append(f"{w}: fewer than three versions")
        if not any(v.get("landmark") for v in t["versions"]): errors.append(f"{w}: no landmark version")
        years = [v["year"] for v in t["versions"]]
        if max(years) - min(years) < 15 and len({era_of(v) for v in t["versions"]}) < 2:
            errors.append(f"{w}: its versions are from one era and less than 15 years apart")
        for v in t["versions"]:
            if v.get("artist") is not None and v["artist"] not in artists: errors.append(f"{w}: unknown artist {v['artist']}")
            if v.get("album") and v["album"] not in albums: errors.append(f"{w}: unknown album {v['album']}")
            if not v.get("note"): errors.append(f"{w}: a version without a note")
            key = f"{v['artistName']}|{v.get('title') or t['title']}|{v['year']}"
            if key not in tracks_have: unresolved.append(key)
    print(f"songbook.json: {len(book)} tunes, {sum(len(t['versions']) for t in book)} versions, {len(unresolved)} not resolved"
          + (": " + "; ".join(unresolved) if unresolved else ""))

# places.json and labels.json
res_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Shared", "Resources")
pp = os.path.join(res_dir, "places.json")
if os.path.exists(pp):
    places = json.load(open(pp))["places"]
    pids = {p["id"]: p for p in places}
    if len(pids) != len(places): errors.append("places.json: duplicate IDs")
    session_names = {r.get("place", "").lower() for s in sessions.values() for r in s.get("recorded", []) if r.get("place")} if "sessions" in dir() else set()
    for p in places:
        w = f"place {p['id']}"
        if p.get("city") and (p["city"] not in pids or pids[p["city"]]["kind"] != "city"): errors.append(f"{w}: city {p['city']} isn't a city")
        if not (-90 <= p["lat"] <= 90 and -180 <= p["lon"] <= 180) or (p["lat"] == 0 and p["lon"] == 0): errors.append(f"{w}: bad coordinates")
        if p.get("to") is not None and p["to"] < p["from"]: errors.append(f"{w}: to is before from")
        errors += [f"{w}: unknown era {e}" for e in p["eras"] if e not in eras]
        errors += [f"{w}: unknown artist {a}" for a in p.get("artists", []) if a not in artists]
        if not p["eras"]: errors.append(f"{w}: no era")
        for n in p.get("sessionNames", []):
            if session_names and n.lower() not in session_names: warnings.append(f"{w}: no session is recorded at '{n}'")
    print(f"places.json: {len(places)} places")
lp = os.path.join(res_dir, "labels.json")
if os.path.exists(lp):
    labels = json.load(open(lp))["labels"]
    seen = {}
    for l in labels:
        for m in l["matches"]:
            if m in seen: errors.append(f"label {l['id']}: '{m}' also matches {seen[m]}")
            seen[m] = l["id"]
        n = sum(1 for a in data["albums"] if a["label"] in l["matches"])
        if n < 2: errors.append(f"label {l['id']}: only {n} record(s) in the Crate")
        errors += [f"label {l['id']}: unknown era {e}" for e in l["eras"] if e not in eras]
        if l.get("city") and os.path.exists(pp) and l["city"] not in pids: errors.append(f"label {l['id']}: unknown city {l['city']}")
        for person in l.get("people", []):
            if person.get("place") and os.path.exists(pp) and person["place"] not in pids: errors.append(f"label {l['id']}: unknown place {person['place']}")
    print(f"labels.json: {len(labels)} labels")

if warnings:
    print("\n".join("warning: " + w for w in warnings))
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"OK: {len(eras)} eras, {len(artists)} artists, {len(albums)} albums, {len(data['milestones'])} milestones")
