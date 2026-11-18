#!/usr/bin/env python3
"""Check and fill places.json's coordinates from Wikipedia.

For each place with a `wikipedia` title, asks Wikipedia for the article's coordinates (which come from Wikidata) and
compares them with the ones in places.json. With --write, it replaces coordinates that are missing or more than 2 km
off; otherwise it only reports. Places Wikipedia has no coordinates for (districts, demolished clubs) keep the ones set
by hand. Usage: python3 -I scripts/build-places.py [--write]
"""
import json, math, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = next((a for a in sys.argv[1:] if a.endswith(".json")), os.path.join(ROOT, "Shared", "Resources", "places.json"))


def coords(title):
    url = ("https://en.wikipedia.org/w/api.php?action=query&prop=coordinates&format=json&redirects=1&titles="
           + urllib.parse.quote(urllib.parse.unquote(title).replace("_", " ")))
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "JazzDiscoveryData/1.0 (offline data build)"})
            with urllib.request.urlopen(req, timeout=20) as r:
                pages = json.load(r)["query"]["pages"]
            for p in pages.values():
                c = (p.get("coordinates") or [None])[0]
                if c:
                    return c["lat"], c["lon"]
            return None
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(10 * (attempt + 1)); continue
            return None
        except Exception:
            time.sleep(3)
    return None


def km(a, b):
    dlat, dlon = math.radians(b[0] - a[0]), math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(math.radians(a[0])) * math.cos(math.radians(b[0])) * math.sin(dlon / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def main():
    write = "--write" in sys.argv
    data = json.load(open(PATH))
    changed = 0
    for p in data["places"]:
        if not p.get("wikipedia"):
            continue
        c = coords(p["wikipedia"])
        time.sleep(0.5)
        here = (p.get("lat"), p.get("lon"))
        if not c:
            print(f"none  {p['id']:28} keeps {here}")
            continue
        off = km(here, c) if None not in here else float("inf")
        # Cities and regions are big: only report those far off.
        limit = 25 if p["kind"] in ("city", "district") else 2
        if off > limit:
            print(f"moved {p['id']:28} {here} -> {c} ({off:.1f} km)")
            if write:
                p["lat"], p["lon"] = round(c[0], 4), round(c[1], 4); changed += 1
        else:
            print(f"ok    {p['id']:28} ({off:.2f} km)")
    if write and changed:
        json.dump(data, open(PATH, "w"), indent=1, ensure_ascii=False)
    print(f"{changed} updated" if write else "report only (--write to update)")


if __name__ == "__main__":
    main()
