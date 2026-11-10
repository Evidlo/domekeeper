"""Write render-script inputs for a batch's sample maps (same crop and samples as build_app).

    python export_render_input.py <batch_dir> <out_dir>

Writes <out_dir>/<k>.json for k = 0 .. N_SAMPLES-1.
"""
import json
import sys
from pathlib import Path

from build_app import crop_box, load_tiles, sample_indices
import pandas as pd


def main(batch: Path, out: Path):
    tiles, x0, y0 = load_tiles(batch)
    maps = pd.read_parquet(batch / "maps.parquet")
    ya, yb, xa, xb = crop_box(tiles)
    out.mkdir(parents=True, exist_ok=True)
    for k, i in enumerate(sample_indices(maps)):
        t = tiles[i, :, ya:yb, xa:xb].astype(int)
        json.dump({
            "seed": int(maps.level_seed[i]), "x0": int(x0 + xa), "y0": int(y0 + ya),
            "w": int(xb - xa), "h": int(yb - ya),
            "biome": t[0].ravel().tolist(), "hardness": t[1].ravel().tolist(), "resource": t[2].ravel().tolist(),
        }, open(out / f"{k}.json", "w"))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
