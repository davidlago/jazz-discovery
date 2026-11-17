#!/usr/bin/env python3
"""Checks Shared/Resources/jazz.json and catalog.json: every reference resolves, ids are unique, connections
are symmetric and every album has an Apple Music match. Usage: python3 -I scripts/validate-data.py"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Shared", "Resources")
data = json.load(open(os.path.join(RES, "jazz.json")))
catalog = json.load(open(os.path.join(RES, "catalog.json")))
errors = []

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

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"OK: {len(eras)} eras, {len(artists)} artists, {len(albums)} albums, {len(data['milestones'])} milestones")
