#!/usr/bin/env python3
"""The catalogue's shape, and the floors it doesn't meet yet (docs/roadmap/catalog.md).

    python3 -I scripts/coverage.py

Records by decade, artists and records by era, players by instrument and per lineage tree, the almanac's empty days,
and a list of every floor that isn't met: at least 10 records a decade from the 1920s, 6 artists (by primary era) and 8
records an era, 6 players per instrument family that has (or could have) a lineage tree.
"""
import json
import os
from collections import Counter

RES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Shared", "Resources")


def load(name):
    p = os.path.join(RES, name)
    return json.load(open(p)) if os.path.exists(p) else None


jazz = load("jazz.json")
artists, albums, eras = jazz["artists"], jazz["albums"], jazz["eras"]
lineages = (load("lineages.json") or {}).get("lineages", [])
almanac = load("almanac.json") or {}
sessions = load("sessions.json") or {}

print(f"{len(eras)} eras, {len(artists)} artists, {len(albums)} records\n")

decades = Counter(a["year"] // 10 * 10 for a in albums)
print("Records by decade")
print("  " + "  ".join(f"{d}s:{decades.get(d, 0)}" for d in range(1910, 2030, 10)))

print("\nBy era (artists by primary era / records)")
by_era_artists = Counter(a["primaryEra"] for a in artists)
by_era_records = Counter(a["era"] for a in albums)
for e in eras:
    print(f"  {e['id']:<14} {by_era_artists.get(e['id'], 0):>3} artists  {by_era_records.get(e['id'], 0):>3} records")

instruments = Counter(a["instrument"].lower() for a in artists)
print("\nArtists by listed instrument")
print("  " + ", ".join(f"{k} {v}" for k, v in instruments.most_common()))

print("\nLineage trees (players)")
for l in lineages:
    print(f"  {l['id']:<12} {len(l['players'])}")

days = set()
for k, evs in (almanac.get("days") or {}).items():
    if evs:
        days.add(k)
n_events = sum(len(v) for v in (almanac.get("days") or {}).values())
print(f"\nAlmanac: {n_events} events on {len(days)} days, {366 - len(days)} empty")

drafts = sorted(k for k, v in sessions.items() if not v.get("reviewed"))
print(f"Personnel drafts (hidden in the app): {len(drafts)} {drafts}")

print("\nFloors not met")
missing = []
for d in range(1920, 2030, 10):
    if decades.get(d, 0) < 10:
        missing.append(f"the {d}s: {decades.get(d, 0)} records (10)")
for e in eras:
    a, r = by_era_artists.get(e["id"], 0), by_era_records.get(e["id"], 0)
    if a < 6 or r < 8:
        missing.append(f"{e['id']}: {a} artists (6), {r} records (8)")
for fam in ["trombone", "clarinet", "vibraphone", "organ"]:
    n = sum(1 for a in artists if fam in a["instrument"].lower())
    if n < 6:
        missing.append(f"{fam}: {n} players listed (6 for a tree)")
for m in missing:
    print("  " + m)
if not missing:
    print("  none")
