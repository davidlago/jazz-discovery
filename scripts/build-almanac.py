#!/usr/bin/env python3
"""Flatten the guide's exact dates into Shared/Resources/almanac.json, so the app doesn't recompute them:

- births and deaths from ids.json (day precision only; a date with a disputed alternative is left out),
- recording sessions from sessions.json (reviewed albums, not compilations, day precision).

Output: {"days": {"MM-DD": [event, ...]}, "artists": {id: {"born": "...", "died": "..."}}}. Each event has a kind
(born, died, recorded), a year, and an artist or album (with the studio for sessions). With --check, exits 1 if the
file on disk differs from what would be written (the validator runs it). Usage: python3 -I scripts/build-almanac.py
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Shared", "Resources")


def exact(d):
    return isinstance(d, str) and len(d) == 10


def build():
    data = json.load(open(os.path.join(RES, "jazz.json")))
    ids = json.load(open(os.path.join(RES, "ids.json")))
    sessions = json.load(open(os.path.join(RES, "sessions.json")))
    artists = {a["id"] for a in data["artists"]}
    albums = {a["id"]: a for a in data["albums"]}
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
