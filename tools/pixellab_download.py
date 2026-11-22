#!/usr/bin/env python3
"""Download PixelLab object exports (the website's ZIP) and tilesets into import_dump/.

    python3 -I tools/pixellab_download.py --match 'bridge|pot|chest' --dry-run
    python3 -I tools/pixellab_download.py --match 'bridge|pot|chest'
    python3 -I tools/pixellab_download.py --watch 180      # keep syncing
    python3 -I tools/pixellab_download.py --characters --match 'smith|elf'
    python3 -I tools/pixellab_download.py --ids 8a28c52f-7b9e-47b3-9623-eb656163c0f6
    python3 -I tools/pixellab_download.py --newest 300 --match 'spell icon' --no-tilesets

Lists your objects through the PixelLab API (GET /v2/objects, paginated) and
writes the full list to <out>/index.json, then downloads the ZIP of each object
whose name, state name or prompt matches --match (GET /v2/objects/{id}/zip).
Whole ids given to --ids are fetched by
id (GET /v2/objects/{id}), with no listing and the index left alone.
Listing and exporting are free; nothing is generated. Existing ZIPs are skipped
unless --force (a ZIP that does not open is fetched again). Requests are spaced
by --delay seconds (default 1.5) to stay gentle on the API, and back off on
429/5xx. Each ZIP is written to a temporary file and renamed into place, so an
interrupted run never leaves a partial ZIP. The token comes from $PIXELLAB_API_TOKEN, or else the first line
of --token-file (default ~/.config/pixellab/token); it is never printed.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

API = "https://api.pixellab.ai/v2"
ROOT = Path(__file__).resolve().parents[1]
PAGE = 50
# A whole object id, as in a pixellab.ai/create-object/<id> link.
FULL_ID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)
DELAY = 1.5
_last = [0.0]


def pace(delay):
    """Wait so consecutive API requests are at least `delay` seconds apart."""
    wait = _last[0] + delay - time.monotonic()
    if wait > 0:
        time.sleep(wait)
    _last[0] = time.monotonic()


def token(path):
    value = os.environ.get("PIXELLAB_API_TOKEN", "").strip()
    if not value and path.is_file():
        value = path.read_text().splitlines()[0].strip() if path.read_text().strip() else ""
    if not value:
        sys.exit(f"No PixelLab token: set PIXELLAB_API_TOKEN or put it on the first line of {path}")
    return value


def request(url, secret, accept="application/json", attempts=4, delay=DELAY, method="GET", body=None):
    headers = {"Authorization": f"Bearer {secret}", "Accept": accept, "User-Agent": "tiny-truck-wars-asset-sync/1.0"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    for attempt in range(attempts):
        pace(delay)
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code in (429, 500, 502, 503, 504) and attempt + 1 < attempts:
                time.sleep(2 ** attempt * 2)
                continue
            detail = error.read()[:300].decode("utf-8", "replace")
            raise RuntimeError(f"{error.code} from {url.replace(API, '')}: {detail}") from None
        except urllib.error.URLError as error:
            if attempt + 1 < attempts:
                time.sleep(2 ** attempt * 2)
                continue
            raise RuntimeError(f"{url.replace(API, '')}: {error.reason}") from None


def list_objects(secret, delay=DELAY, kind="objects", newest=0):
    """Every object (or, with kind="characters", every character) you own,
    newest first; with `newest`, only that many of the newest."""
    objects, offset = [], 0
    while True:
        limit = min(PAGE, newest - offset) if newest else PAGE
        page = json.loads(request(f"{API}/{kind}?limit={limit}&offset={offset}", secret, delay=delay))
        batch = page.get(kind, page.get("items", []))
        objects.extend(batch)
        offset += len(batch)
        if not batch or offset >= page.get("total", 0) or (newest and offset >= newest):
            return objects


def intact(path):
    """True if the file is a ZIP that opens and holds a metadata.json."""
    try:
        with zipfile.ZipFile(path) as bundle:
            return "metadata.json" in bundle.namelist() and bundle.testzip() is None
    except (zipfile.BadZipFile, OSError):
        return False


def list_tilesets(secret, delay=DELAY):
    tilesets, offset = [], 0
    while True:
        page = json.loads(request(f"{API}/tilesets?limit={PAGE}&offset={offset}", secret, delay=delay))
        batch = page.get("tilesets", page.get("items", []))
        tilesets.extend(batch)
        offset += len(batch)
        if not batch or offset >= page.get("total", 0):
            return tilesets


def sync_tilesets(args, secret):
    """Save each completed tileset's full JSON (tile PNGs as base64, corner
    terrain per tile, prompts) once. Returns (new, failures)."""
    folder = args.out / "tilesets"
    folder.mkdir(parents=True, exist_ok=True)
    listing = list_tilesets(secret, args.delay)
    (folder / "index.json").write_text(json.dumps(listing, indent=2) + "\n")
    new = failures = 0
    for entry in listing:
        ident = entry.get("id") or entry.get("tileset_id")
        status = entry.get("status")
        if not ident or status not in (None, "completed"):
            continue
        name = slug(entry.get("name") or entry.get("lower_description") or entry.get("prompt") or "tileset")
        target = folder / f"{name}__{ident[:8]}.json"
        if target.exists() and not args.force:
            continue
        try:
            data = json.loads(request(f"{API}/tilesets/{ident}", secret, delay=args.delay))
        except (RuntimeError, ValueError) as error:
            failures += 1
            print("  FAILED tileset", target.name, "-", error, flush=True)
            continue
        if not data.get("tiles"):
            continue
        partial = target.with_suffix(".json.part")
        partial.write_text(json.dumps(data))
        partial.replace(target)
        new += 1
        print("  downloaded tileset", target.name, f"({len(data['tiles'])} tiles)", flush=True)
    return new, failures


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", (text or "").lower()).strip("_")[:48] or "object"


def filename(entry):
    """Stable, readable and unique: name, state and a short id."""
    parts = [slug(entry.get("name") or entry.get("prompt"))]
    if entry.get("state_name"):
        parts.append(slug(entry["state_name"]))
    return "__".join(parts) + f"__{entry['id'][:8]}.zip"


def sync(args, secret, quiet=False, kind="objects"):
    """One pass: refresh the index and fetch what is new. Returns (new,
    failures, total). Characters (kind="characters") go to <out>/characters."""
    pattern = re.compile(args.match, re.I)
    out = args.out if kind == "objects" else args.out / kind
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / ".gdignore").touch()
    out.mkdir(parents=True, exist_ok=True)
    if args.ids and all(FULL_ID.fullmatch(ident) for ident in args.ids):
        # Whole ids are looked up one by one: no listing of everything, and
        # the index is left as the last full sync wrote it. Each export holds
        # every state of its object.
        objects = [json.loads(request(f"{API}/{kind}/{ident}", secret, delay=args.delay)) for ident in args.ids]
        chosen = objects
    else:
        objects = list_objects(secret, args.delay, kind, args.newest)
        if not args.newest:
            # Only a full listing replaces the index.
            (out / "index.json").write_text(json.dumps(objects, indent=2) + "\n")
        chosen = [entry for entry in objects
                  if pattern.search(" ".join(str(entry.get(key) or "") for key in ("name", "state_name", "prompt")))]
    if args.ids and chosen is not objects:
        # Short ids: the ones named, and every other state of the same object.
        chosen = [entry for entry in objects
                  if any(str(entry.get(key) or "").startswith(tuple(args.ids)) for key in ("id", "group_id"))]
    if not quiet:
        print(f"{len(objects)} {kind}; {len(chosen)} match {args.match!r}")
    new = failures = waiting = 0
    for entry in chosen:
        target = out / filename(entry)
        size = entry.get("size") or {}
        label = f"{target.name} ({size.get('width')}x{size.get('height')}, {entry.get('view')}, {entry.get('status')})"
        if args.dry_run:
            print("  would download", label)
            continue
        fresh = args.fresh_minutes > 0 and target.exists() and time.time() - target.stat().st_mtime < args.fresh_minutes * 60
        if target.exists() and (not args.force or fresh) and intact(target):
            if not quiet:
                print("  have", label)
            continue
        if entry.get("status") not in (None, "completed"):
            # Still generating: its export would be incomplete. A later pass gets it.
            waiting += 1
            continue
        try:
            data = request(f"{API}/{kind}/{entry['id']}/zip", secret, accept="application/zip", delay=args.delay)
        except RuntimeError as error:
            failures += 1
            print("  FAILED", label, "-", error, flush=True)
            continue
        if not data.startswith(b"PK"):
            failures += 1
            print("  FAILED", label, "- response was not a ZIP:", data[:200].decode("utf-8", "replace"), flush=True)
            continue
        partial = target.with_suffix(".zip.part")
        partial.write_bytes(data)
        if not intact(partial):
            partial.unlink()
            failures += 1
            print("  FAILED", label, "- the ZIP does not open", flush=True)
            continue
        partial.replace(target)
        new += 1
        print("  downloaded", label, flush=True)
    if waiting:
        print(f"  {waiting} still generating; fetched on a later pass", flush=True)
    return new, failures, len(objects)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--match", default="", help="Regex (case-insensitive) on name, state name or prompt; empty matches all")
    parser.add_argument("--out", type=Path, default=ROOT / "import_dump/pixellab")
    parser.add_argument("--token-file", type=Path, default=Path.home() / ".config/pixellab/token")
    parser.add_argument("--dry-run", action="store_true", help="List and index only; download nothing")
    parser.add_argument("--force", action="store_true", help="Download again even if the ZIP exists")
    parser.add_argument("--fresh-minutes", type=float, default=0.0, metavar="MINUTES",
                        help="With --force, still skip ZIPs fetched in the last MINUTES (resume an interrupted --force sync)")
    parser.add_argument("--delay", type=float, default=DELAY, help="Seconds between API requests (default 1.5)")
    parser.add_argument("--no-tilesets", action="store_true", help="Skip top-down/sidescroller tilesets")
    parser.add_argument("--newest", type=int, default=0, metavar="N",
                        help="List only the N newest objects (the listing is newest first); the index is left alone")
    parser.add_argument("--ids", nargs="+", default=[], metavar="ID",
                        help="Only these objects, by id (as in a pixellab.ai/create-object/<id> link): whole ids are fetched "
                             "directly, without listing everything; short ones need the listing. Skips tilesets")
    parser.add_argument("--characters", action="store_true",
                        help="Sync characters (sprites and their animations) into <out>/characters instead of objects")
    parser.add_argument("--watch", type=float, default=0.0, metavar="SECONDS",
                        help="Keep syncing: repeat every SECONDS until stopped (new objects only)")
    args = parser.parse_args()
    secret = token(args.token_file)
    if args.characters:
        _, failures, _ = sync(args, secret, kind="characters")
        if failures:
            sys.exit(f"{failures} downloads failed")
        return
    if not args.watch:
        _, failures, _ = sync(args, secret)
        if not args.no_tilesets and not args.ids and not args.dry_run:
            failures += sync_tilesets(args, secret)[1]
        if failures:
            sys.exit(f"{failures} downloads failed")
        return
    while True:
        try:
            new, failures, total = sync(args, secret, quiet=True)
            if not args.no_tilesets:
                more, broken = sync_tilesets(args, secret)
                new, failures = new + more, failures + broken
            print(time.strftime("%H:%M:%S"), f"sync: {total} objects, {new} new, {failures} failed", flush=True)
        except RuntimeError as error:
            # A failed listing (network, API down) is retried next round, not fatal.
            print(time.strftime("%H:%M:%S"), "sync failed:", error, flush=True)
        time.sleep(args.watch)


if __name__ == "__main__":
    main()
