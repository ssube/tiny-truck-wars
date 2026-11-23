#!/usr/bin/env python3
"""Copies the units' and structures' PixelLab rotations into assets/.

    python3 -I tools/import_units.py

Reads the ZIPs that tools/pixellab_download.py left in import_dump/pixellab
(characters/ and the top level), finds each by its id, and writes its eight
rotations to assets/units/<key>/<direction>.png (structures to
assets/structures/<key>/). Animations are not taken yet.
"""
import io
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DUMP = ROOT / "import_dump" / "pixellab"
DIRECTIONS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
UNITS = {
    "truck": "dbf0e54e", "tank": "8835f4c4", "hippy": "ab8f3c41", "helicopter": "fa77e562",
    "boss": "d14e4b58", "nurse": "e2a60da7",
    # The wrecker is a state of its own character (the others are its first).
    "wrecker": ("a86ec024", "as_a_tow_truck"),
    "tanker": ("ded1c0eb", "Idle"),
}
STRUCTURES = {"garage": "013cc06a", "depot": "ef9e255e", "helipad": "cf233dc2"}


def find(prefix):
    found = sorted(DUMP.rglob(f"*__{prefix}.zip"))
    if not found:
        sys.exit(f"No ZIP for id {prefix} in {DUMP}: fetch it with tools/pixellab_download.py --ids")
    return found[0]


def copy(kind, key, prefix):
    prefix, state = prefix if isinstance(prefix, tuple) else (prefix, None)
    out = ROOT / "assets" / kind / key
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(find(prefix)) as bundle:
        names = [n for n in bundle.namelist() if "/rotations/" in n and (state is None or n.startswith(state + "/"))]
        for direction in DIRECTIONS:
            name = next(n for n in names if n.endswith(f"/rotations/{direction}.png"))
            (out / f"{direction}.png").write_bytes(bundle.read(name))
    print(f"{kind}/{key}: {len(DIRECTIONS)} rotations")


def main():
    for key, prefix in UNITS.items():
        copy("units", key, prefix)
    for key, prefix in STRUCTURES.items():
        copy("structures", key, prefix)


if __name__ == "__main__":
    main()
