"""Find the pixel shift between a render and its input map by matching iron tiles to orange pixels.

    python calibrate_render.py <map.json> <render.png>
"""
import json
import sys

import numpy as np
from PIL import Image

d = json.load(open(sys.argv[1]))
img = np.asarray(Image.open(sys.argv[2]).convert("RGB")).astype(int)
r, g, b = img[..., 0], img[..., 1], img[..., 2]
orange = ((r > 170) & (g > 80) & (g < 190) & (b < 110)).astype(float)
res = np.array(d["resource"]).reshape(d["h"], d["w"])
expect = np.kron((res == 0).astype(float), np.ones((24, 24)))
best = max(((float((np.roll(np.roll(expect, dy, 0), dx, 1) * orange).sum()), dx, dy)
            for dy in range(-120, 121, 2) for dx in range(-60, 61, 2)))
print(f"overlap {best[0]:.0f} of {orange.sum():.0f} orange px; image content is shifted by dx={best[1]} dy={best[2]} px")
