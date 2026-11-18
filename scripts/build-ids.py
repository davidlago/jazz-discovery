#!/usr/bin/env python3
"""Looks up every artist in jazz.json on Wikidata (CC0), by the Wikipedia title it already has, and writes
Shared/Resources/ids.json: the Wikidata item, the MusicBrainz artist ID and exact birth and death dates.

    python3 -I scripts/build-ids.py            only artists not in ids.json yet
    python3 -I scripts/build-ids.py --all      everyone again

Dates keep Wikidata's precision: "1926-05-26" (day), "1926-05" (month) or "1926" (year). When Wikidata has more than
one value (a disputed birth date), the preferred one is used and the others are kept as `bornAlso` / `diedAlso`.
scripts/build-sessions.py uses the MusicBrainz IDs to recognise our artists in album credits, and
scripts/validate-data.py checks the years here against jazz.json's."""
import json, os, sys, time, urllib.error, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Shared", "Resources")
OUT = os.path.join(RES, "ids.json")
API = "https://www.wikidata.org/w/api.php"
USER_AGENT = "JazzDiscoveryCatalog/1.0"


def get(params):
    url = API + "?" + urllib.parse.urlencode({**params, "format": "json"})
    for attempt in range(6):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (429, 503):
                time.sleep(5 * (attempt + 1))
                continue
            raise
        except urllib.error.URLError:
            time.sleep(3)
    raise SystemExit(f"Wikidata didn't answer: {url}")


def date(value):
    """A Wikidata time value as an ISO date cut to its precision, or None (century precision, BCE…)."""
    t, precision = value["time"], value["precision"]
    if not t.startswith("+"):
        return None
    y, m, d = t[1:11].split("-")
    if precision >= 11 and d != "00":
        return f"{y}-{m}-{d}"
    if precision == 10 and m != "00":
        return f"{y}-{m}"
    if precision == 9:
        return y
    return None


def dates(claims, prop):
    """(best, others): the preferred-rank value if there is one, else the first; deprecated values are skipped."""
    values = []
    for c in claims.get(prop, []):
        if c.get("rank") == "deprecated" or c["mainsnak"].get("snaktype") != "value":
            continue
        d = date(c["mainsnak"]["datavalue"]["value"])
        if d:
            values.append((c.get("rank") == "preferred", d))
    if not values:
        return None, []
    best = next((d for preferred, d in values if preferred), values[0][1])
    others = sorted({d for _, d in values if d != best and not best.startswith(d)})
    return best, others


def string(claims, prop):
    for c in claims.get(prop, []):
        if c["mainsnak"].get("snaktype") == "value":
            return c["mainsnak"]["datavalue"]["value"]
    return None


def main():
    data = json.load(open(os.path.join(RES, "jazz.json")))
    out = {} if "--all" in sys.argv or not os.path.exists(OUT) else json.load(open(OUT))
    todo = [a for a in data["artists"] if a["id"] not in out]
    by_title = {a["wikipedia"].replace("_", " "): a for a in todo}
    missing = []
    for i in range(0, len(todo), 50):  # wbgetentities takes up to 50 titles
        batch = todo[i:i + 50]
        reply = get({"action": "wbgetentities", "sites": "enwiki", "redirects": "yes", "props": "claims|sitelinks",
                     "sitefilter": "enwiki", "titles": "|".join(a["wikipedia"].replace("_", " ") for a in batch)})
        found = set()
        for qid, entity in reply.get("entities", {}).items():
            if qid.startswith("-"):  # a title with no item
                continue
            title = entity.get("sitelinks", {}).get("enwiki", {}).get("title")
            artist = by_title.get(title)
            if not artist:
                # Redirected: match the batch entry whose title redirected here.
                normalized = {n["from"]: n["to"] for n in reply.get("normalized", [])}
                artist = next((a for a in batch if normalized.get(a["wikipedia"].replace("_", " ")) == title), None)
            if not artist:
                continue
            claims = entity.get("claims", {})
            born, born_also = dates(claims, "P569")
            died, died_also = dates(claims, "P570")
            entry = {"wikidata": qid, "musicbrainz": string(claims, "P434"), "born": born, "died": died}
            if born_also: entry["bornAlso"] = born_also
            if died_also: entry["diedAlso"] = died_also
            out[artist["id"]] = {k: v for k, v in entry.items() if v is not None}
            found.add(artist["id"])
        missing += [a["id"] for a in batch if a["id"] not in found]
        time.sleep(1)

    json.dump(dict(sorted(out.items())), open(OUT, "w"), indent=1, ensure_ascii=False)
    open(OUT, "a").write("\n")
    no_mb = sorted(k for k, v in out.items() if "musicbrainz" not in v)
    print(f"{len(out)} artists in ids.json ({len(todo) - len(missing)} looked up now)")
    if missing: print("Not found on Wikidata (check the wikipedia title):", ", ".join(missing))
    if no_mb: print("No MusicBrainz ID on Wikidata:", ", ".join(no_mb))


if __name__ == "__main__":
    main()
