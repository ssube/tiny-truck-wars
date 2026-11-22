#!/usr/bin/env python3
"""Placeholder pixel art for the world's trees, logs and buildings.

    python3 -I tools/make_world_textures.py

Drawn in the units' style (low top-down, front three-quarter, dark outline,
three tones lit from the top left) into assets/world/. Seeded; reruns draw
the same. Replaced by real sprites later.
"""
import random
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "assets" / "world"
OUTLINE = (24, 22, 18, 255)


def outline(img):
    src = img.copy()
    for y in range(img.height):
        for x in range(img.width):
            if src.getpixel((x, y))[3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < img.width and 0 <= ny < img.height and src.getpixel((nx, ny))[3] > 200:
                    img.putpixel((x, y), OUTLINE)
                    break
    return img


def lobe(img, cx, cy, r, tones, rng):
    """A clump of foliage: a ragged disc lit from the top left."""
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if not (0 <= x < img.width and 0 <= y < img.height):
                continue
            dx, dy = x - cx, y - cy
            d = (dx * dx + dy * dy) ** 0.5
            if d <= r + rng.uniform(-0.6, 0.6):
                light = -(dx + dy) / (r * 1.4)
                tone = 2 if light > 0.35 else (0 if light < -0.3 else 1)
                if rng.random() < 0.12:
                    tone = max(0, tone - 1)
                img.putpixel((x, y), tones[tone])


def tree(kind, seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (40, 56), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    bark = [(62, 44, 30, 255), (88, 64, 42, 255), (112, 84, 56, 255)]
    draw.rectangle([18, 36, 21, 53], fill=bark[1])
    draw.line([18, 36, 18, 53], fill=bark[0])
    draw.line([21, 38, 21, 53], fill=bark[2])
    if kind == "pine":
        tones = [(30, 58, 40, 255), (44, 82, 54, 255), (70, 108, 70, 255)]
        for i, (w, y) in enumerate([(15, 40), (13, 32), (10, 24), (7, 16), (4, 9)]):
            for k in range(-w, w + 1):
                h = 9 - abs(k) * 8 // max(w, 1)
                for j in range(h):
                    px, py = 20 + k, y - j
                    tone = 2 if k < -w // 3 else (0 if k > w // 3 else 1)
                    if rng.random() < 0.1:
                        tone = max(0, tone - 1)
                    img.putpixel((px, py), tones[tone])
    else:
        tones = [(42, 70, 34, 255), (62, 98, 44, 255), (96, 132, 60, 255)]
        for _ in range(9):
            lobe(img, 20 + rng.uniform(-9, 9), 22 + rng.uniform(-11, 8), rng.uniform(5, 8), tones, rng)
    return outline(img)


def stump():
    img = Image.new("RGBA", (12, 9), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([2, 3, 9, 7], fill=(88, 64, 42, 255))
    d.ellipse([2, 1, 9, 5], fill=(170, 136, 92, 255))
    d.ellipse([4, 2, 7, 4], fill=(140, 108, 70, 255))
    return outline(img)


def log():
    """A fallen trunk lying east-west; the game rotates it."""
    img = Image.new("RGBA", (48, 10), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([2, 2, 45, 7], fill=(88, 64, 42, 255))
    d.line([2, 2, 45, 2], fill=(118, 90, 60, 255))
    d.line([2, 7, 45, 7], fill=(60, 42, 28, 255))
    d.ellipse([41, 2, 46, 7], fill=(170, 136, 92, 255))
    for x in (12, 26, 34):
        d.point((x, 4), fill=(60, 42, 28, 255))
    return outline(img)


def building(width, height, wall, roof, seed):
    """A low box seen from the front and above: a roof plane over a front wall."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    front = height * 2 // 5
    top = height - front
    d.rectangle([1, 1, width - 2, top], fill=roof[1])
    for y in range(2, top, 3):
        d.line([2, y, width - 3, y], fill=roof[0])
    d.line([1, 1, width - 2, 1], fill=roof[2])
    d.rectangle([1, top + 1, width - 2, height - 2], fill=wall[1])
    d.line([1, top + 1, width - 2, top + 1], fill=wall[0])
    for x in range(6, width - 8, 12):
        d.rectangle([x, top + 4, x + 4, top + 8], fill=(60, 74, 84, 255))
    d.rectangle([width // 2 - 3, height - 10, width // 2 + 3, height - 2], fill=(70, 52, 36, 255))
    for _ in range(width // 6):
        x, y = rng.randrange(2, width - 2), rng.randrange(top + 2, height - 2)
        d.point((x, y), fill=wall[0])
    return outline(img)


def rubble():
    rng = random.Random(9)
    img = Image.new("RGBA", (56, 32), (0, 0, 0, 0))
    tones = [(70, 66, 60, 255), (110, 104, 94, 255), (150, 142, 128, 255)]
    for _ in range(40):
        lobe(img, rng.uniform(6, 50), rng.uniform(8, 26), rng.uniform(1.5, 4), tones, rng)
    for _ in range(6):
        x, y = rng.randrange(8, 48), rng.randrange(8, 26)
        ImageDraw.Draw(img).line([x, y, x + rng.randrange(4, 9), y + rng.randrange(-2, 3)], fill=(88, 64, 42, 255), width=2)
    return outline(img)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    pieces = {
        "tree_oak_0": tree("oak", 1), "tree_oak_1": tree("oak", 2), "tree_pine_0": tree("pine", 3),
        "stump": stump(), "log": log(),
        "house": building(56, 44, [(120, 104, 84, 255), (166, 146, 118, 255), (196, 178, 150, 255)], [(96, 52, 40, 255), (132, 70, 52, 255), (164, 96, 70, 255)], 4),
        "shed": building(40, 32, [(90, 84, 70, 255), (122, 112, 92, 255), (150, 140, 118, 255)], [(70, 72, 74, 255), (98, 100, 102, 255), (128, 130, 132, 255)], 5),
        "barracks": building(76, 48, [(98, 104, 80, 255), (128, 136, 104, 255), (156, 164, 128, 255)], [(66, 74, 58, 255), (88, 98, 76, 255), (114, 124, 98, 255)], 6),
        "rubble": rubble(),
    }
    for name, image in pieces.items():
        image.save(OUT / f"{name}.png")
        print(name, image.size)


if __name__ == "__main__":
    main()
