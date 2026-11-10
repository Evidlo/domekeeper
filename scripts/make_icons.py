"""Crop button icons (game sprites, game palette) out of a rendered sample map.

Used for the relic switch, which has no carryable item; the other buttons show the
item sprites drawn by render/icons.gd.

    python make_icons.py <render_input.json> <render.png> <out_dir>

Chambers are cropped around their whole generator cluster, resources around one tile.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

PX = 24
ICONS = {"relic_switch": 6}
SINGLE_TILE = {"iron", "water", "cobalt", "relic_switch"}
# chamber sprites are drawn offset from their tile cluster: (dx, dy, size) in px around the cluster centre
CHAMBER_CROP = {"gadget": (0, -12, 48), "supplement": (0, 5, 48), "relic": (0, 0, 88)}


def main(inp, render, out):
    d = json.load(open(inp))
    res = np.array(d["resource"]).reshape(d["h"], d["w"])
    img = Image.open(render).convert("RGB")
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for name, tid in ICONS.items():
        labels, n = ndimage.label(res == tid)
        sizes = ndimage.sum(np.ones_like(res), labels, range(1, n + 1))
        k = int(np.argmax(sizes)) + 1 if name not in SINGLE_TILE else int(np.argmin(sizes)) + 1
        ys, xs = np.nonzero(labels == k)
        if name in SINGLE_TILE:
            ys, xs = ys[:1], xs[:1]
        if name in SINGLE_TILE:
            box = (xs.min() * PX - 2, ys.min() * PX - 2, (xs.max() + 1) * PX + 2, (ys.max() + 1) * PX + 2)
        else:
            dx, dy, size = CHAMBER_CROP[name]
            cx = (xs.min() + xs.max() + 1) * PX // 2 + dx
            cy = (ys.min() + ys.max() + 1) * PX // 2 + dy
            box = (cx - size // 2, cy - size // 2, cx + size // 2, cy + size // 2)
        crop = img.crop(box)
        side = max(crop.size)
        sq = Image.new("RGB", (side, side), crop.getpixel((0, 0)))
        sq.paste(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
        sq.save(out / f"{name}.png")
        print(name, box, sq.size)


if __name__ == "__main__":
    main(*sys.argv[1:4])
