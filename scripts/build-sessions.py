#!/usr/bin/env python3
"""Drafts Shared/Resources/sessions.json from MusicBrainz (CC0): who played on each album in jazz.json, on which
tracks and instruments, when and where it was recorded, and who produced, engineered, arranged and designed it.

    python3 -I scripts/build-sessions.py                draft albums that have no entry yet
    python3 -I scripts/build-sessions.py --redo         draft every album again, except reviewed or hand-edited ones
    python3 -I scripts/build-sessions.py --only a,b     draft these albums again (even reviewed ones)

Drafts are written with "reviewed": false, and the app ignores them until a person has checked each one against the
liner notes (or the album's Wikipedia page), fixed it and set "reviewed": true. "draftNotes" lists what looked off.
A draft corrected by hand but not yet approved carries "edited": true, so --redo leaves it alone.

For each album the script finds the release group (by the leader's MusicBrainz ID from ids.json, so run
scripts/build-ids.py first, and the release year), tries up to four of its editions and keeps the one with the most
tracks credited, then turns per-track credits into one list of players with `only` / `except` for those who aren't on
every track. Albums gathered from many sessions (compilations) get the players who recur and a range of years instead.
Players are matched to jazz.json's artists by MusicBrainz ID, or else by exact name.

MusicBrainz allows one request a second and is often busy; requests are spaced, retried, and cached in
build/musicbrainz-cache, so a rerun only asks for what it hasn't seen. The script saves after every album, so it can be
stopped and started again. A report of the drafts and of the players who aren't in jazz.json yet (the candidates for
new artists, most-recorded first) goes to build/sessions-report.md."""
import hashlib, json, os, re, sys, time, unicodedata, urllib.error, urllib.parse, urllib.request
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Shared", "Resources")
OUT = os.path.join(RES, "sessions.json")
CACHE = os.path.join(ROOT, "build", "musicbrainz-cache")
REPORT = os.path.join(ROOT, "build", "sessions-report.md")
API = "https://musicbrainz.org/ws/2/"
USER_AGENT = "JazzDiscoveryCatalog/1.0"

# Albums the search can't find, or finds wrongly: album ID → MusicBrainz release group ID ("release:<id>" pins one
# edition). Fill in as review finds them.
OVERRIDES = {
    "groovin-high": "d1f677a1-710c-30ee-8f8c-716c3632bed3",          # the 1955 Savoy LP, not the 1945 78
    "jazz-at-massey-hall": "f9afcb1d-6674-353e-8a8a-0dbff1054ed7",   # credited to "The Quintet"
}

# MusicBrainz instrument names → the app's words. Anything not here is kept as MusicBrainz spells it.
INSTRUMENTS = {
    "double bass": "bass", "bass": "bass", "upright bass": "bass", "contrabass": "bass",
    "bass guitar": "electric bass", "electric bass guitar": "electric bass", "fretless bass": "electric bass",
    "drums (drum set)": "drums", "drum set": "drums", "drums": "drums",
    "hammond organ": "organ", "organ": "organ", "pipe organ": "organ",
    "electric piano": "electric piano", "rhodes piano": "electric piano", "fender rhodes": "electric piano",
    "wurlitzer electric piano": "electric piano", "keyboard": "keyboards", "synthesizer": "synthesizer",
    "electric guitar": "guitar", "acoustic guitar": "guitar", "guitar": "guitar", "classical guitar": "guitar",
    "vibraphone": "vibraphone", "marimba": "marimba", "conga": "congas", "congas": "congas", "bongos": "bongos",
    "timbales": "timbales", "percussion": "percussion", "flugelhorn": "flugelhorn", "cornet": "cornet",
    "trumpet": "trumpet", "trombone": "trombone", "valve trombone": "trombone", "tuba": "tuba",
    "french horn": "French horn", "horn": "French horn", "soprano saxophone": "soprano saxophone",
    "alto saxophone": "alto saxophone", "tenor saxophone": "tenor saxophone",
    "baritone saxophone": "baritone saxophone", "saxophone": "saxophone", "clarinet": "clarinet",
    "bass clarinet": "bass clarinet", "flute": "flute", "alto flute": "alto flute", "piano": "piano",
    "violin": "violin", "cello": "cello", "harp": "harp", "banjo": "banjo",
}
# Liner-note order: horns, then reeds, then other melody instruments, then the rhythm section, voices last.
ORDER = ["trumpet", "cornet", "flugelhorn", "trombone", "French horn", "tuba", "soprano saxophone", "alto saxophone",
         "tenor saxophone", "baritone saxophone", "saxophone", "clarinet", "bass clarinet", "flute", "alto flute",
         "violin", "vibraphone", "marimba", "guitar", "piano", "electric piano", "keyboards", "synthesizer", "organ",
         "harp", "banjo", "bass", "electric bass", "cello", "drums", "percussion", "congas", "bongos", "timbales",
         "vocals"]
CREW = {"producer": "producer", "engineer": "engineer", "recording": "engineer", "audio": "engineer",
        "arranger": "arranger", "instrument arranger": "arranger", "orchestrator": "arranger",
        "conductor": "conductor", "design/illustration": "design", "graphic design": "design", "design": "design",
        "art direction": "design", "photography": "photography"}

last_request = 0.0


def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower().replace("&", "and")
    s = re.sub(r"\bvol\b\.?", "volume", s)  # "Vol. 1" and "Volume 1" are the same title
    return re.sub(r"[^a-z0-9]", "", s)


def mb(path, **params):
    """A MusicBrainz web service call, cached on disk; at most one request a second; retried when busy."""
    global last_request
    url = API + path + "?" + urllib.parse.urlencode({**params, "fmt": "json"})
    os.makedirs(CACHE, exist_ok=True)
    cached = os.path.join(CACHE, hashlib.sha1(url.encode()).hexdigest() + ".json")
    if os.path.exists(cached):
        return json.load(open(cached))
    for attempt in range(10):
        time.sleep(max(0, last_request + 1.1 - time.time()))
        last_request = time.time()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=40) as r:
                data = json.load(r)
            json.dump(data, open(cached, "w"))
            return data
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (429, 500, 502, 503, 504):
                time.sleep(3 + 3 * attempt)
                continue
            raise
        except (urllib.error.URLError, TimeoutError):
            time.sleep(5)
    raise SystemExit(f"MusicBrainz didn't answer: {url}")


def year(d):
    return int(d[:4]) if d and d[:4].isdigit() else None


def find_release_group(album, leader_mbid):
    if album["id"] in OVERRIDES:
        return OVERRIDES[album["id"]]
    title = album["title"].replace('"', '\\"')
    queries = []
    if leader_mbid:
        queries.append(f'releasegroup:"{title}" AND arid:{leader_mbid}')
    queries.append(f'releasegroup:"{title}" AND artist:"{album["artistName"]}"')
    # The title's words, near the album's year: finds "Getz / Gilberto" for "Getz/Gilberto", which a phrase can't.
    words = " ".join(w for w in re.split(r"[^\w']+", album["title"]) if w)
    y = album["year"]
    queries.append(f"releasegroup:({words}) AND firstreleasedate:[{y - 1} TO {y + 1}]")
    if leader_mbid:  # Compilations come out decades after the music: the title's words by the leader, any year.
        queries.append(f"releasegroup:({words}) AND arid:{leader_mbid}")
    short = re.sub(r"\s*[\(\[].*?[\)\]]", "", album["title"]).strip()  # "Black Codes (From the Underground)"
    if short != album["title"] and leader_mbid:
        queries.append(f'releasegroup:"{short}" AND arid:{leader_mbid}')
    want = norm(album["title"])
    best, best_score = None, 0
    for q in queries:
        reply = mb("release-group", query=q, limit=25) or {}
        for g in reply.get("release-groups", []):
            n = norm(g["title"])
            s = 10 if n == want else 7 if n == norm(short) else 5 if n.startswith(want) or want.startswith(n) else \
                3 if want in n else 0
            if not s:
                continue
            y = year(g.get("first-release-date"))
            if y is not None:
                gap = abs(y - album["year"])
                s += 6 if gap == 0 else 4 if gap == 1 else 1 if gap <= 3 else -3
            if g.get("primary-type") == "Album":
                s += 2
            if "Live" in g.get("secondary-types", []) and "live" not in album["title"].lower():
                s -= 1
            if s > best_score:
                best, best_score = g["id"], s
        if best_score >= 14:
            break
    return best


def credits(relations):
    """(person mbid, name, instrument or "vocals") for the performing credits in a relation list."""
    for r in relations or []:
        if r.get("target-type") != "artist" or r["type"] not in ("instrument", "vocal"):
            continue
        a = r["artist"]
        if r["type"] == "vocal":
            yield a["id"], a["name"], "vocals", r
            continue
        attrs = [x for x in r.get("attributes", []) if x not in ("additional", "guest", "solo")]
        for x in attrs or ["instruments"]:
            yield a["id"], a["name"], INSTRUMENTS.get(x.lower(), x), r


def crew(relations):
    for r in relations or []:
        if r.get("target-type") == "artist" and r["type"] in CREW:
            yield r["artist"]["id"], r["artist"]["name"], CREW[r["type"]]


def summarize(release):
    """How well an edition is credited: (tracks with players, all tracks)."""
    tracks = [t for m in release.get("media", []) for t in m.get("tracks", [])]
    release_level = any(True for _ in credits(release.get("relations")))
    credited = sum(1 for t in tracks if release_level or any(True for _ in credits(t["recording"].get("relations"))))
    return credited, len(tracks)


def best_edition(group_id, album, catalog):
    if group_id.startswith("release:"):
        rid = group_id.split(":", 1)[1]
        return mb(f"release/{rid}", inc=RELEASE_INC)
    listing = mb("release", **{"release-group": group_id, "limit": 100, "inc": "media"}) or {}
    releases = listing.get("releases", [])
    if not releases:
        return None
    want_tracks = (catalog.get(album["id"]) or {}).get("trackCount")
    def count(r): return sum(m.get("track-count", 0) for m in r.get("media", []))
    by_date = sorted(releases, key=lambda r: (r.get("status") != "Official", r.get("date") or "9999"))
    by_size = sorted(releases, key=lambda r: (abs(count(r) - want_tracks) if want_tracks else 0, r.get("date") or "9999"))
    tried, best, best_key = [], None, None
    for r in by_date[:2] + by_size[:3] + by_date[2:4]:
        if r["id"] in tried or len(tried) >= 4:
            continue
        tried.append(r["id"])
        full = mb(f"release/{r['id']}", inc=RELEASE_INC)
        if not full:
            continue
        credited, total = summarize(full)
        key = (credited / max(total, 1), credited, -abs(total - want_tracks) if want_tracks else 0)
        if best_key is None or key > best_key:
            best, best_key = full, key
        if credited == total and total:
            break
    return best


RELEASE_INC = "recordings+artist-credits+recording-level-rels+artist-rels+place-rels+labels+release-groups"


def rank(instruments):
    return min((ORDER.index(i) if i in ORDER else len(ORDER) for i in instruments), default=len(ORDER))


def draft(album, data, ids, catalog):
    by_mbid = {v["musicbrainz"]: k for k, v in ids.items() if v.get("musicbrainz")}
    by_name = {norm(a["name"]): a["id"] for a in data["artists"]}
    def ours(mbid, name): return by_mbid.get(mbid) or by_name.get(norm(name))

    leader_mbid = (ids.get(album["artist"]) or {}).get("musicbrainz")
    group = find_release_group(album, leader_mbid)
    if not group:
        return None, "no release group found"
    release = best_edition(group, album, catalog)
    if not release:
        return None, f"release group {group} has no editions"

    tracks = [t for m in release.get("media", []) for t in m.get("tracks", [])]
    titles = [t["title"] for t in tracks]
    players = {}  # mbid → {name, instruments (ordered), tracks}
    dates, places = Counter(), defaultdict(Counter)
    def add(mbid, name, instrument, track_index):
        p = players.setdefault(mbid, {"name": name, "instruments": [], "tracks": set()})
        if instrument not in p["instruments"]:
            p["instruments"].append(instrument)
        p["tracks"].add(track_index)
    for i, t in enumerate(tracks):
        rels = t["recording"].get("relations", [])
        for mbid, name, instrument, r in credits(rels):
            add(mbid, name, instrument, i)
            if r.get("begin"):
                dates[r["begin"]] += 1
        for r in rels:
            if r.get("target-type") == "place" and r["type"] in ("recorded at", "recording location"):
                if r.get("begin"):
                    dates[r["begin"]] += 1
                places[r.get("begin")][r["place"]["name"]] += 1
    for mbid, name, instrument, _ in credits(release.get("relations")):
        for i in range(len(tracks)):
            add(mbid, name, instrument, i)

    crew_out, seen = [], set()
    for rels in [release.get("relations")] + [t["recording"].get("relations") for t in tracks]:
        for mbid, name, role in crew(rels):
            if (mbid, role) not in seen:
                seen.add((mbid, role))
                crew_out.append({"artist": ours(mbid, name), "name": name, "role": role})

    rg = release.get("release-group", {})
    years = sorted({year(d) for d in dates if year(d)})
    compilation = "Compilation" in rg.get("secondary-types", []) or (len(years) >= 2 and years[-1] - years[0] >= 2)
    notes = []

    personnel = []
    leader_id = album["artist"]
    for mbid, p in players.items():
        entry = {"artist": ours(mbid, p["name"]), "name": p["name"], "instruments": p["instruments"]}
        n = len(p["tracks"])
        if compilation:
            if n < max(2, len(tracks) // 4) and entry["artist"] != leader_id:
                continue
            entry["tracks"] = n
        elif n < len(tracks):
            on = [titles[i] for i in sorted(p["tracks"])]
            off = [titles[i] for i in range(len(tracks)) if i not in p["tracks"]]
            if len(on) <= len(off):
                entry["only"] = on
            else:
                entry["except"] = off
        personnel.append((entry["artist"] != leader_id, rank(p["instruments"]), -n, entry))
    personnel = [e for *_, e in sorted(personnel, key=lambda x: x[:3])]

    credited, total = summarize(release)
    if not personnel:
        notes.append("no players credited on this edition")
    elif credited < total:
        notes.append(f"only {credited} of {total} tracks have players credited")
    if personnel and not any(p["artist"] == leader_id for p in personnel):
        notes.append(f"the leader ({album['artistName']}) isn't among the credited players")
    want_tracks = (catalog.get(album["id"]) or {}).get("trackCount")
    if want_tracks and abs(want_tracks - total) > 2:
        notes.append(f"this edition has {total} tracks; the Apple Music album has {want_tracks}")
    first = year(rg.get("first-release-date"))
    if first and abs(first - album["year"]) > 1 and not compilation:
        notes.append(f"release group first issued {first}; jazz.json says {album['year']}")

    entry = {"reviewed": False, "source": f"musicbrainz:release/{release['id']}",
             "mbReleaseGroup": rg.get("id", group), "edition": f"{release.get('date', '?')} {release.get('country', '')}".strip()}
    if compilation:
        entry["kind"] = "compilation"
        if years:
            entry["recordedBetween"] = [years[0], years[-1]]
    else:
        recorded = []
        for d in sorted(dates):
            place = places.get(d, Counter()) or places.get(None, Counter())
            r = {"date": d}
            if place:
                r["place"] = place.most_common(1)[0][0]
            recorded.append(r)
        if not recorded and places.get(None):
            recorded.append({"place": places[None].most_common(1)[0][0]})
        if recorded:
            entry["recorded"] = recorded
    entry["tracks"] = titles
    entry["personnel"] = personnel
    if crew_out:
        entry["crew"] = crew_out
    if notes:
        entry["draftNotes"] = notes
    return entry, None


def main():
    data = json.load(open(os.path.join(RES, "jazz.json")))
    ids_path = os.path.join(RES, "ids.json")
    if not os.path.exists(ids_path):
        raise SystemExit("Run scripts/build-ids.py first: the MusicBrainz IDs in ids.json find the albums.")
    ids = json.load(open(ids_path))
    catalog = json.load(open(os.path.join(RES, "catalog.json")))
    out = json.load(open(OUT)) if os.path.exists(OUT) else {}
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    redo = "--redo" in sys.argv

    def wanted(a):
        if only is not None:
            return a["id"] in only
        e = out.get(a["id"])
        return e is None or (redo and not e.get("reviewed") and not e.get("edited"))

    todo = [a for a in data["albums"] if wanted(a)]
    failures = []
    for n, album in enumerate(todo, 1):
        entry, problem = draft(album, data, ids, catalog)
        if problem:
            failures.append((album["id"], problem))
            print(f"[{n}/{len(todo)}] MISS {album['id']}: {problem}", flush=True)
            continue
        out[album["id"]] = entry
        json.dump(dict(sorted(out.items())), open(OUT, "w"), indent=1, ensure_ascii=False)
        ps = entry["personnel"]
        flag = f"  ⚠ {'; '.join(entry['draftNotes'])}" if entry.get("draftNotes") else ""
        print(f"[{n}/{len(todo)}] {album['id']}: {len(ps)} players, {len(entry.get('recorded', []))} dates"
              f"{' (compilation)' if entry.get('kind') else ''}{flag}", flush=True)
    open(OUT, "a").write("\n")
    write_report(data, out, failures)
    print(f"\nDrafted {len(todo) - len(failures)} of {len(todo)}; report: {os.path.relpath(REPORT, ROOT)}")


def write_report(data, sessions, failures):
    names = {a["id"]: a["name"] for a in data["artists"]}
    titles = {a["id"]: (a["title"], a["artistName"], a["year"]) for a in data["albums"]}
    lines = ["# Sessions drafts", "", "Generated by scripts/build-sessions.py. Not committed (build/).", ""]
    if failures:
        lines += ["## Not found", ""] + [f"- `{a}`: {p}" for a, p in failures] + [""]
    lines += ["## Albums", ""]
    for album_id, s in sorted(sessions.items(), key=lambda kv: titles.get(kv[0], ("", "", 0))[2]):
        if album_id not in titles:
            continue
        t, artist, y = titles[album_id]
        status = "reviewed" if s.get("reviewed") else "draft"
        lines.append(f"### {t} — {artist}, {y} ({status})")
        lines.append(f"`{album_id}` · {s.get('source')} · edition {s.get('edition', '?')}")
        if s.get("kind") == "compilation":
            lines.append(f"Compilation, recorded {s.get('recordedBetween')}")
        for r in s.get("recorded", []):
            lines.append(f"- recorded {r.get('date', '?')} at {r.get('place', '?')}")
        for p in s["personnel"]:
            who = p["name"] + ("" if p.get("artist") else " *(no page)*")
            extra = (f" — only {', '.join(p['only'])}" if p.get("only") else
                     f" — not on {', '.join(p['except'])}" if p.get("except") else
                     f" — {p['tracks']} tracks" if p.get("tracks") else "")
            lines.append(f"- {who}: {', '.join(p['instruments'])}{extra}")
        for c in s.get("crew", []):
            lines.append(f"- *{c['role']}*: {c['name']}")
        for note in s.get("draftNotes", []):
            lines.append(f"- ⚠ {note}")
        lines.append("")

    # Players with no page, by how many curated albums they're on.
    counts = defaultdict(lambda: {"albums": set(), "instruments": Counter()})
    for album_id, s in sessions.items():
        for p in s.get("personnel", []):
            if p.get("artist") is None:
                c = counts[p["name"]]
                c["albums"].add(album_id)
                c["instruments"].update(p["instruments"])
    lines += ["## Candidates for new artists", "",
              "Players on the curated albums who have no page yet, most albums first.", "",
              "| Player | Albums | Instruments | On |", "|---|---|---|---|"]
    for name, c in sorted(counts.items(), key=lambda kv: (-len(kv[1]["albums"]), kv[0])):
        on = ", ".join(titles[a][0] for a in sorted(c["albums"]) if a in titles)
        inst = ", ".join(i for i, _ in c["instruments"].most_common(3))
        lines.append(f"| {name} | {len(c['albums'])} | {inst} | {on} |")
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    open(REPORT, "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
