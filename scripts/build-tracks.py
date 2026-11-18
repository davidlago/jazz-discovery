#!/usr/bin/env python3
"""Resolve every track the data names to its Apple Music song, ahead of time, so the app doesn't look them up one by
one. Writes two files in Shared/Resources:

- tracklists.json: each Crate album's Apple Music tracks (one lookup per album in catalog.json).
- tracks.json: every named track ("artist|title", as TrackRef.id), from era essential tracks, album highlights and
  artists' signature tracks, and the Songbook's versions ("artist|title|year", with the record as a hint). A track on a Crate album is taken from that album's tracklist; anything else is searched,
  preferring the earliest release over a later remake and skipping karaoke and tributes.

Only what's missing is looked up, 3.1 seconds apart, saving as it goes; misses are printed and simply left out (the
app still looks those up live). Each entry is a CatalogTrack plus "album" (the Crate album it's on, if any), "era" and
"year". Add "skip": true by hand to keep a track out of the Blindfold Test.

Usage: python3 -I scripts/build-tracks.py [--redo]
"""
import json, os, re, sys, time, unicodedata, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Shared", "Resources")
BAD = ("karaoke", "tribute", "made famous", "in the style of", "lullaby", "workout", "relaxing")


def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower().replace("&", "and")
    return re.sub(r"[^a-z0-9]", "", s)


def key(s):
    """A track title without edition notes: "So What (Remastered)" -> "sowhat"."""
    return norm(re.split(r"[(\[]", s)[0]) or norm(s)


last = [0.0]


def get(url):
    wait = 3.1 - (time.time() - last[0])
    if wait > 0:
        time.sleep(wait)
    for attempt in range(6):
        last[0] = time.time()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "JazzDiscoveryCatalog/1.0"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (403, 429, 503):
                time.sleep(15 * (attempt + 1)); continue
            raise
        except Exception:
            time.sleep(4)
    return {"results": []}


def track(item):
    return {
        "trackId": item["trackId"], "name": item["trackName"], "artistName": item.get("artistName", ""),
        "albumName": item.get("collectionName"), "collectionId": item.get("collectionId"),
        "artwork": item.get("artworkUrl100"), "preview": item.get("previewUrl"),
        "url": (item.get("trackViewUrl") or "").split("?")[0] or None,
        "durationMillis": item.get("trackTimeMillis"), "trackNumber": item.get("trackNumber"),
        "discNumber": item.get("discNumber"),
        "released": (item.get("releaseDate") or "")[:4],
    }


def main():
    redo = "--redo" in sys.argv
    data = json.load(open(os.path.join(RES, "jazz.json")))
    catalog = json.load(open(os.path.join(RES, "catalog.json")))
    sessions = json.load(open(os.path.join(RES, "sessions.json")))
    albums = {a["id"]: a for a in data["albums"]}
    artists = {a["id"]: a for a in data["artists"]}
    by_name = {a["name"]: a for a in data["artists"]}

    # 1. Tracklists.
    tl_path = os.path.join(RES, "tracklists.json")
    tracklists = {} if redo or not os.path.exists(tl_path) else json.load(open(tl_path))
    for album_id, c in sorted(catalog.items()):
        if album_id in tracklists:
            continue
        res = get(f"https://itunes.apple.com/lookup?id={c['collectionId']}&entity=song&limit=200")["results"]
        songs = [track(r) for r in res if r.get("kind") == "song"]
        songs.sort(key=lambda t: (t["discNumber"] or 1, t["trackNumber"] or 0))
        for s in songs:
            s.pop("released", None)
        tracklists[album_id] = songs
        print(f"list {album_id:40} {len(songs)} tracks", flush=True)
        json.dump(tracklists, open(tl_path, "w"), indent=1, sort_keys=True, ensure_ascii=False)

    # 2. The pool of named tracks: (artist, title) -> what we know about it.
    pool = {}

    def add(artist, title, era=None, year=None, album=None, record=None, key=None):
        k = key or f"{artist}|{title}"
        e = pool.setdefault(k, {"artist": artist, "title": title, "era": era, "year": year, "album": album, "record": record})
        e["record"] = e.get("record") or record
        e["era"] = e["era"] or era
        e["year"] = e["year"] or year
        e["album"] = e["album"] or album

    for era in data["eras"]:
        for t in era["essentialTracks"]:
            add(t["artist"], t["title"], era=era["id"], year=t.get("year"))
    for a in data["albums"]:
        for h in a["highlights"]:
            add(a["artistName"], h, era=a["era"], year=a["year"], album=a["id"])
    for a in data["artists"]:
        for t in a["signatureTracks"]:
            add(a["name"], t, era=a["primaryEra"])

    # The Songbook's versions, with the year and record they were made on as hints.
    sb_path = os.path.join(RES, "songbook.json")
    if os.path.exists(sb_path):
        for tune in json.load(open(sb_path))["tunes"]:
            for v in tune["versions"]:
                era = artists[v["artist"]]["primaryEra"] if v.get("artist") in artists else None
                title = v.get("title") or tune["title"]
                add(v["artistName"], title, era=era, year=v["year"], album=v.get("album"), record=v.get("record"),
                    key=f"{v['artistName']}|{title}|{v['year']}")

    out_path = os.path.join(RES, "tracks.json")
    out = {} if redo or not os.path.exists(out_path) else json.load(open(out_path))
    out = {k: v for k, v in out.items() if k in pool}   # drop tracks the data no longer names
    misses = []

    def on_album(album_id, title):
        for t in tracklists.get(album_id, []):
            if key(t["name"]) == key(title):
                return t
        return None

    for k, p in sorted(pool.items()):
        existing = out.get(k)
        if existing and existing.get("album"):
            continue
        found, album = None, p["album"]
        if album:
            found = on_album(album, p["title"])
        if not found:
            # On one of the artist's Crate records (earliest first)?
            leader = by_name.get(p["artist"])
            cands = sorted((a for a in data["albums"] if (leader and a["artist"] == leader["id"]) or a["artistName"] == p["artist"]),
                           key=lambda a: a["year"])
            for a in cands:
                found = on_album(a["id"], p["title"])
                if found:
                    album = a["id"]; break
        if not found and leader:
            # A sideman's tune: on a Crate record they're credited on (sessions.json).
            for a in sorted(data["albums"], key=lambda a: a["year"]):
                people = {c.get("artist") for c in sessions.get(a["id"], {}).get("personnel", [])}
                if leader["id"] in people:
                    found = on_album(a["id"], p["title"])
                    if found:
                        album = a["id"]; break
        if not found and existing:
            continue   # searched before; nothing better on the Crate's records
        if not found:
            rec = norm(p.get("record") or "")
            res = []
            if rec:
                term = urllib.parse.quote(f"{p['artist']} {p['title']} {p['record']}")
                res = [r for r in get(f"https://itunes.apple.com/search?term={term}&entity=song&media=music&limit=25")["results"]
                       if r.get("kind") == "song"]
            if not any(rec and rec in norm(r.get("collectionName", "")) for r in res):
                term = urllib.parse.quote(f"{p['artist']} {p['title']}")
                res += [r for r in get(f"https://itunes.apple.com/search?term={term}&entity=song&media=music&limit=50")["results"]
                        if r.get("kind") == "song"]
            t, a = key(p["title"]), norm(p["artist"])

            def score(r):
                s = 0
                n = key(r.get("trackName", ""))
                if n == t: s += 10
                elif n.startswith(t): s += 6
                elif t in n: s += 3
                an = norm(r.get("artistName", ""))
                if a in an or (an and an in a): s += 6
                if r.get("previewUrl"): s += 1
                low = (r.get("trackName", "") + " " + r.get("collectionName", "")).lower()
                if any(b in low for b in BAD): s -= 20
                if "live" in low and "live" not in p["title"].lower() and "live" not in (p.get("record") or "").lower(): s -= 2
                if rec and rec in norm(r.get("collectionName", "")): s += 8
                # The earliest release: a point for every decade before 2030.
                y = int((r.get("releaseDate") or "2030")[:4])
                s += max(0, (2030 - y)) / 10 * 0.3
                return s

            best = max(res, key=score, default=None)
            if best and score(best) >= 14:
                found = track(best)
                # A Crate album after all?
                for aid, c in catalog.items():
                    if c["collectionId"] == best.get("collectionId"):
                        album = aid
        if not found:
            misses.append(k); print(f"MISS {k}", flush=True)
            continue
        entry = dict(found)
        released = entry.pop("released", None)
        entry["album"] = album
        if p.get("record"): entry["record"] = p["record"]
        entry["era"] = p["era"] or (albums[album]["era"] if album else None)
        entry["year"] = p["year"] or (albums[album]["year"] if album else (int(released) if released else None))
        out[k] = entry
        print(f"ok   {k:60} -> {entry['name']} / {entry.get('albumName')}", flush=True)
        json.dump(out, open(out_path, "w"), indent=1, sort_keys=True, ensure_ascii=False)

    json.dump(out, open(out_path, "w"), indent=1, sort_keys=True, ensure_ascii=False)
    print(f"\n{len(out)} of {len(pool)} resolved; {len(misses)} missing")
    for m in misses:
        print("  " + m)


if __name__ == "__main__":
    main()
