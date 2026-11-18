#!/usr/bin/env python3
"""Flatten the guide's exact dates into Shared/Resources/almanac.json, so the app doesn't recompute them:

- births and deaths from ids.json (day precision only; a date with a disputed alternative is left out),
- recording sessions from sessions.json (reviewed albums, not compilations, day precision),
- release dates of Crate albums and dated milestones from scripts/almanac-dates.json, gathered by hand with a source
  for each (day precision only).

Output: {"days": {"MM-DD": [event, ...]}, "artists": {id: {"born": "...", "died": "..."}}}. Each event has a kind
(born, died, recorded), a year, and an artist or album (with the studio for sessions). The app has no "released" or
"milestone" kind yet, so a release, or a milestone that belongs to a Crate album, is written as a "recorded" event on
that album with a hand-written "line" (the album is what there is to play and open); a milestone with no album is
kept in the source file with "held" and left out until the app has a kind for it. With --check, exits 1 if the file
on disk differs from what would be written (the validator runs it). Usage: python3 -I scripts/build-almanac.py
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Shared", "Resources")
DATES = os.path.join(ROOT, "scripts", "almanac-dates.json")


def exact(d):
    return isinstance(d, str) and len(d) == 10


def release_line(album, date):
    name = album["artistName"]
    if name.startswith("The "):
        name = "the " + name[4:]
    label = f" on {album['label']}" if album.get("label") else ""
    line = f"On this day in {date[:4]}, {name} released {album['title']}{label}"
    return line if line[-1] in ".!?" else line + "."


def build():
    data = json.load(open(os.path.join(RES, "jazz.json")))
    ids = json.load(open(os.path.join(RES, "ids.json")))
    sessions = json.load(open(os.path.join(RES, "sessions.json")))
    extra = json.load(open(DATES)) if os.path.exists(DATES) else {}
    artists = {a["id"] for a in data["artists"]}
    albums = {a["id"]: a for a in data["albums"]}
    milestones = {m["title"] for m in data["milestones"]}
    days, dates = {}, {}

    def add(md, event):
        days.setdefault(md, []).append(event)

    for aid, e in sorted(ids.items()):
        if aid not in artists or not isinstance(e, dict):
            continue
        entry = {}
        if exact(e.get("born")) and not e.get("bornAlso"):
            add(e["born"][5:], {"kind": "born", "year": int(e["born"][:4]), "artist": aid})
            entry["born"] = e["born"]
        if exact(e.get("died")) and not e.get("diedAlso"):
            add(e["died"][5:], {"kind": "died", "year": int(e["died"][:4]), "artist": aid})
            entry["died"] = e["died"]
        if entry:
            dates[aid] = entry

    for album_id, s in sorted(sessions.items()):
        if album_id not in albums or not s.get("reviewed") or s.get("kind") == "compilation":
            continue
        seen = set()
        for r in s.get("recorded", []):
            d = r.get("date")
            if not exact(d) or d in seen:
                continue
            seen.add(d)
            ev = {"kind": "recorded", "year": int(d[:4]), "album": album_id}
            if r.get("place"):
                ev["place"] = r["place"]
            add(d[5:], ev)

    def check(entry, what):
        if not exact(entry.get("date")) or not entry.get("source"):
            raise SystemExit(f"almanac-dates.json: {what} needs a YYYY-MM-DD date and a source")
        if entry.get("album") and entry["album"] not in albums:
            raise SystemExit(f"almanac-dates.json: {what}: unknown album {entry['album']}")

    for r in extra.get("releases", []):
        check(r, f"release of {r.get('album')}")
        d, a = r["date"], albums[r["album"]]
        if any(e.get("album") == a["id"] and e["year"] == int(d[:4]) for e in days.get(d[5:], [])):
            continue  # released on a day it was also recorded: the session says it
        add(d[5:], {"kind": "recorded", "year": int(d[:4]), "album": a["id"], "line": release_line(a, d)})

    for m in extra.get("milestones", []):
        if m.get("milestone") not in milestones:
            raise SystemExit(f"almanac-dates.json: unknown milestone {m.get('milestone')!r}")
        check(m, f"milestone {m['milestone']!r}")
        if m.get("held"):
            continue  # needs a milestone kind in the app (DayEvent.Kind); see the source file
        if not m.get("album") or not m.get("line"):
            raise SystemExit(f"almanac-dates.json: milestone {m['milestone']!r} needs an album and a line, or held")
        d = m["date"]
        add(d[5:], {"kind": "recorded", "year": int(d[:4]), "album": m["album"], "line": m["line"]})

    order = {"recorded": 0, "born": 1, "died": 2}
    for md in days:
        days[md].sort(key=lambda e: (order[e["kind"]], e["year"], e.get("artist") or e.get("album")))
    return {"days": dict(sorted(days.items())), "artists": dates}


def main():
    out = build()
    path = os.path.join(RES, "almanac.json")
    text = json.dumps(out, indent=1, sort_keys=True, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        current = open(path).read() if os.path.exists(path) else ""
        if current != text:
            print("almanac.json is stale: run scripts/build-almanac.py", file=sys.stderr)
            sys.exit(1)
        return
    open(path, "w").write(text)
    n = sum(len(v) for v in out["days"].values())
    print(f"{n} events on {len(out['days'])} of 366 days")


if __name__ == "__main__":
    main()
