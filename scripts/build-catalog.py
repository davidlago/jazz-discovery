#!/usr/bin/env python3
"""Resolve every curated album in jazz.json to its Apple Music catalog entry
(collection ID, artwork, URL) via the public iTunes Search API and write
Shared/Resources/catalog.json. The app falls back to live lookups for
anything missing. Usage: python3 -I scripts/build-catalog.py"""
import json, os, re, sys, time, unicodedata, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Shared", "Resources")

def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower().replace("&", "and")
    return re.sub(r"[^a-z0-9]", "", s)

def get(url):
    for attempt in range(6):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "JazzDiscoveryCatalog/1.0"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (403, 429, 503):
                time.sleep(10 * (attempt + 1)); continue
            raise
        except Exception:
            time.sleep(3)
    return {"results": []}

def score(c, title, artist):
    s = 0
    n = norm(c.get("collectionName", ""))
    if n == title: s += 10
    elif n.startswith(title): s += 6
    elif title in n: s += 4
    if artist in norm(c.get("artistName", "")): s += 5
    low = c.get("collectionName", "").lower()
    if any(b in low for b in ("karaoke", "tribute", "made famous", "in the style of")): s -= 20
    return s

def main():
    data = json.load(open(os.path.join(RES, "jazz.json")))
    out_path = os.path.join(RES, "catalog.json")
    out = json.load(open(out_path)) if os.path.exists(out_path) else {}
    misses = []
    for a in data["albums"]:
        if a["id"] in out: continue
        term = urllib.parse.quote(f'{a["artistName"]} {a["title"]}')
        res = get(f"https://itunes.apple.com/search?term={term}&entity=album&media=music&limit=15")["results"]
        title = norm(a["title"])
        artist = norm(a["artistName"].split(" & ")[0])
        best = max(res, key=lambda c: score(c, title, artist), default=None)
        if best and score(best, title, artist) > 4:
            out[a["id"]] = {
                "collectionId": best["collectionId"], "name": best["collectionName"],
                "artistName": best.get("artistName", ""), "artwork": best.get("artworkUrl100"),
                "url": best.get("collectionViewUrl", "").split("?")[0],
                "releaseYear": int(best["releaseDate"][:4]) if best.get("releaseDate") else None,
                "trackCount": best.get("trackCount"),
            }
            print(f'ok   {a["id"]:40} -> {best["collectionName"]}', flush=True)
        else:
            misses.append(a["id"]); print(f'MISS {a["id"]}', flush=True)
        json.dump(out, open(out_path, "w"), indent=1, sort_keys=True)
        time.sleep(3.1)
    print(f"\n{len(out)} resolved, {len(misses)} missing: {misses}")

if __name__ == "__main__":
    main()
