"""Collect runner chunks of a batch into analysis-ready files.

    python postprocess.py data/<tag>

Writes into data/<tag>/:
    tiles.npz       tiles[N, 3, H, W] int8 (layers: biome, hardness, resource; -1 = empty),
                    plus x0, y0 (grid origin in tile coords; dome entrance at (0, 0))
    maps.parquet    one row per map
    chambers.parquet one row per chamber, positioned like Map.getResourceClusterTopLeft
"""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import ndimage

LAYERS = ("biome", "hardness", "resource")
CHAMBER_TYPES = {3: "gadget", 4: "relic", 6: "relic_switch", 7: "supplement"}
TILE_IDS = {0: "iron", 1: "water", 2: "cobalt", 10: "dirt", 19: "border"}


def read_chunk(bin_path: Path):
    raw = np.fromfile(bin_path, dtype=np.uint8)
    assert raw[:4].tobytes() == b"DKMG"
    version, x0, x1, y0, y1 = raw[4:24].view(np.int32)
    w, h = x1 - x0, y1 - y0
    tiles = raw[24:].view(np.int8).reshape(-1, 3, h, w)
    return tiles, int(x0), int(y0)


def parse_report(report: str) -> dict:
    lines = report.splitlines()
    biomes = [int(l.split("size ")[1].split(" ")[0]) for l in lines if l.startswith("Biome ")]
    tile_count = [int(l.split(": ")[1]) for l in lines if l.startswith("Generated Tile Count")]
    errors = [l for l in lines if "ailed" in l or "Failsafe" in l]
    return {
        "biome_sizes": biomes,
        "n_biomes": len(biomes),
        "generated_tile_count": tile_count[0] if tile_count else -1,
        "errors": " | ".join(errors),
    }


def chambers_of(map_idx: int, tiles: np.ndarray, x0: int, y0: int) -> list:
    biome, hardness, resource = tiles
    rows = []
    structure = ndimage.generate_binary_structure(2, 1)
    for tid, name in CHAMBER_TYPES.items():
        labels, n = ndimage.label(resource == tid, structure=structure)
        for k, sl in enumerate(ndimage.find_objects(labels), start=1):
            ys, xs = np.nonzero(labels[sl] == k)
            ys, xs = ys + sl[0].start, xs + sl[1].start
            top, left = ys.min(), xs.min()
            rows.append({
                "map_idx": map_idx,
                "type": name,
                "x": int(left + x0),
                "y": int(top + y0),
                "cx": float(xs.mean() + x0),
                "cy": float(ys.mean() + y0),
                "n_cells": int(ys.size),
                "biome": int(biome[top, left]) if biome[top, left] >= 0 else int(biome[ys, xs].max()),
                "hardness_mean": float(hardness[ys, xs].mean()),
            })
    return rows


def main(batch_dir: Path):
    bins = sorted((batch_dir / "chunks").glob("map_*.bin"))
    all_tiles, meta_rows, chamber_rows = [], [], []
    for b in bins:
        tiles, x0, y0 = read_chunk(b)
        metas = [json.loads(l) for l in open(b.with_suffix(".jsonl"))]
        assert len(metas) == tiles.shape[0], b
        for t, m in zip(tiles, metas):
            idx = len(meta_rows)
            rep = parse_report(m["reports"][-1])
            res = t[2]
            meta_rows.append({
                "map_idx": idx,
                "level_seed": m["level_seed"],
                "gen_seed": m["gen_seed"],
                "attempts": m["attempts"],
                "ok": m["ok"],
                "oob_cells": m["oob_cells"],
                "ms": m["ms"],
                **rep,
                **{f"n_{v}": int((res == k).sum()) for k, v in TILE_IDS.items()},
                "max_depth": int(np.nonzero((t[0] >= 0).any(axis=1))[0].max() + y0),
            })
            chamber_rows += chambers_of(idx, t, x0, y0)
        all_tiles.append(tiles)

    tiles = np.concatenate(all_tiles)
    np.savez_compressed(batch_dir / "tiles.npz", tiles=tiles, x0=x0, y0=y0, layers=np.array(LAYERS))
    maps = pd.DataFrame(meta_rows)
    maps.to_parquet(batch_dir / "maps.parquet")
    chambers = pd.DataFrame(chamber_rows).merge(maps[["map_idx", "level_seed"]], on="map_idx")
    chambers.to_parquet(batch_dir / "chambers.parquet")

    print(f"{len(maps)} maps, {(~maps.ok).sum()} failed, attempts>1: {(maps.attempts > 1).sum()}, "
          f"oob cells: {maps.oob_cells.sum()}")
    print(chambers.groupby("type").agg(n=("x", "size"), per_map=("map_idx", lambda s: s.size / len(maps)),
                                      cells_mean=("n_cells", "mean")))


if __name__ == "__main__":
    main(Path(sys.argv[1]))
