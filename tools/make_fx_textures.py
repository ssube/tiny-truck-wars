#!/usr/bin/env python3
"""Draws the particle flipbooks (placeholder pixel art) into assets/fx/.

    python3 -I tools/make_fx_textures.py

Each sheet is one row of frames, read by CPUParticles2D through a
CanvasItemMaterial's particles animation. Seeded, so a rerun draws the same.
"""
import random
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "assets" / "fx"


def outline(img, color=(24, 18, 12, 255)):
    """A dark one-pixel edge around every opaque clump, so it reads on any ground."""
    src = img.copy()
    for y in range(img.height):
        for x in range(img.width):
            if src.getpixel((x, y))[3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < img.width and 0 <= ny < img.height and src.getpixel((nx, ny))[3] > 200:
                    img.putpixel((x, y), color)
                    break
    return img


def sheet(frames, size):
    return Image.new("RGBA", (frames * size, size), (0, 0, 0, 0))


def blob(img, ox, cx, cy, r, colors, rng, roughness=0.35):
    """A rough pixel clump: a disc with a ragged edge, lit from the top left."""
    for y in range(img.height):
        for x in range(ox, ox + img.height):
            dx, dy = x - ox - cx, y - cy
            d = (dx * dx + dy * dy) ** 0.5
            if d <= r + rng.uniform(-roughness, roughness) * r:
                shade = 2 if dx + dy < -r * 0.4 else (0 if dx + dy > r * 0.5 else 1)
                img.putpixel((x, y), colors[shade])


def mud_clods():
    rng = random.Random(1)
    size, frames = 6, 4
    img = sheet(frames, size)
    colors = [(70, 50, 32, 255), (104, 78, 50, 255), (150, 120, 84, 255)]
    for f in range(frames):
        blob(img, f * size, 2.5 + rng.uniform(-0.4, 0.4), 2.5, [0.7, 1.0, 0.8, 1.3][f], colors, rng, 0.2)
    return outline(img)


def droplets():
    rng = random.Random(2)
    size, frames = 6, 4
    img = sheet(frames, size)
    colors = [(120, 150, 150, 220), (180, 205, 200, 235), (235, 245, 240, 255)]
    for f in range(frames):
        r = [1.2, 1.6, 1.2, 0.8][f]
        blob(img, f * size, 2.5, 2.5, r, colors, rng, 0.1)
    return img


def dust():
    rng = random.Random(3)
    size, frames = 16, 6
    img = sheet(frames, size)
    base = [(150, 132, 100), (178, 160, 124), (204, 188, 152)]
    for f in range(frames):
        grow = 3.0 + f * 1.1
        fade = 1.0 - f / frames
        for y in range(size):
            for x in range(size):
                dx, dy = x - 7.5, y - 8.0
                d = (dx * dx + dy * dy) ** 0.5 / grow
                if d < 1.0 and rng.random() < 0.35 + 0.65 * fade * (1.0 - d * 0.5):
                    shade = 2 if dx + dy < -grow * 0.3 else (0 if dx + dy > grow * 0.4 else 1)
                    c = base[shade]
                    img.putpixel((f * size + x, y), (c[0], c[1], c[2], int(90 + 150 * fade)))
    return img


def debris():
    rng = random.Random(4)
    size, frames = 6, 4
    img = sheet(frames, size)
    colors = [(52, 50, 48, 255), (90, 86, 80, 255), (140, 134, 124, 255)]
    for f in range(frames):
        blob(img, f * size, 2.5, 2.5, 1.4, colors, rng, 0.5)
    return outline(img, (16, 14, 12, 255))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, image in [("mud_clods", mud_clods()), ("droplets", droplets()), ("dust", dust()), ("debris", debris())]:
        image.save(OUT / f"{name}.png")
        print(name, image.size)


if __name__ == "__main__":
    main()
