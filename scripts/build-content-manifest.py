#!/usr/bin/env python3
"""Writes Shared/Resources/content.json: the SHA-256 and size of every data file the apps read.

The apps follow the data on main (Shared/Services/Content.swift): they fetch content.json from GitHub, download the
files whose hash differs from the ones they have, check each against it, and use them from their next launch. So
content.json has to match the files: run this after editing any of them. CI runs it with --check and fails when it's
out of date.

    python3 -I scripts/build-content-manifest.py            rewrite content.json
    python3 -I scripts/build-content-manifest.py --check    exit 1 if content.json doesn't match the files
    python3 -I scripts/build-content-manifest.py --schema 2 also bump the schema (see "schema" below)

"schema" is the data format's version. An app only takes published content with its own schema
(JazzContent.schema in Shared/Services/Content.swift), so bump both together when a change would break older apps: a field
they need renamed, removed or given another type. New fields and new files don't need it (older apps ignore them).
"""
import hashlib, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Shared", "Resources")
OUT = os.path.join(RES, "content.json")
# Not data the apps read: the manifest itself, and ids.json, which only the build scripts use.
SKIP = {"content.json", "ids.json"}


def build(schema):
    files = {}
    for name in sorted(os.listdir(RES)):
        if not name.endswith(".json") or name in SKIP:
            continue
        data = open(os.path.join(RES, name), "rb").read()
        json.loads(data)  # a file that isn't JSON fails here, not in the apps
        files[name] = {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
    return json.dumps({"schema": schema, "files": files}, indent=2, sort_keys=True) + "\n"


def main(argv):
    current = open(OUT).read() if os.path.exists(OUT) else None
    schema = json.loads(current)["schema"] if current else 1
    if "--schema" in argv:
        schema = int(argv[argv.index("--schema") + 1])
    text = build(schema)
    if "--check" in argv:
        if text != current:
            print("Shared/Resources/content.json is out of date: run python3 -I scripts/build-content-manifest.py")
            return 1
        print(f"content.json: {len(json.loads(text)['files'])} files, schema {schema}, up to date")
        return 0
    if text != current:
        open(OUT, "w").write(text)
        print(f"Wrote content.json: {len(json.loads(text)['files'])} files, schema {schema}")
    else:
        print("content.json already up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
