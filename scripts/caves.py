"""Inputs and outputs of render/caves.gd (room placement run inside the game).

    python caves.py export <batch_dir> <work_dir> <n_shards> [max_maps]
        writes <work_dir>/in_<k>.bin, one shard of maps each
    python caves.py collect <batch_dir> <work_dir> <variant>
        reads <work_dir>/out_*.jsonl, writes <batch_dir>/caves_<variant>.parquet
        (map_idx, cave, x, y, layer) and <batch_dir>/caves_<variant>.json
        (cave footprints and rules, game settings, n_maps)
"""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def export(batch: Path, work: Path, n_shards: int, max_maps: int = 3000):
    """Write map shards in the binary layout read by render/caves.gd."""
    z = np.load(batch / "tiles.npz")
    tiles = z["tiles"][:max_maps].astype(np.int8)
    seeds = pd.read_parquet(batch / "maps.parquet").level_seed.to_numpy()[:max_maps]
    n, _, h, w = tiles.shape
    work.mkdir(parents=True, exist_ok=True)
    for k, idx in enumerate(np.array_split(np.arange(n), n_shards)):
        with open(work / f"in_{k:03d}.bin", "wb") as f:
            f.write(np.array([len(idx), h, w, z["x0"], z["y0"]], "<i4").tobytes())
            f.write(seeds[idx].astype("<i8").tobytes())
            f.write(tiles[idx].tobytes())
        (work / f"in_{k:03d}.idx").write_text(json.dumps(idx.tolist()))


def collect(batch: Path, work: Path, variant: str):
    """Merge shard outputs into one table of placed rooms (top-left cell per room)."""
    rows, meta, n_maps = [], None, 0
    for out in sorted(work.glob("out_*.jsonl")):
        idx = json.loads(out.with_name(out.name.replace("out_", "in_")
                                       .replace(".jsonl", ".idx")).read_text())
        lines = out.read_text().splitlines()
        meta = json.loads(lines[0])["meta"]
        assert len(lines) - 1 == len(idx), (out, len(lines) - 1, len(idx))
        n_maps += len(idx)
        for line in lines[1:]:
            d = json.loads(line)
            rows += [(idx[d["i"]], cave, x, y)
                     for cave, cells in d["caves"].items() for x, y in cells]
    df = pd.DataFrame(rows, columns=["map_idx", "cave", "x", "y"])
    z = np.load(batch / "tiles.npz")
    biome = z["tiles"][df.map_idx.to_numpy(), 0, df.y - int(z["y0"]), df.x - int(z["x0"])]
    df["layer"] = biome.astype(int)
    df.to_parquet(batch / f"caves_{variant}.parquet")
    meta["n_maps"] = n_maps
    (batch / f"caves_{variant}.json").write_text(json.dumps(meta, indent=1))
    print(variant, n_maps, "maps", df.groupby("cave").size().to_dict())


if __name__ == "__main__":
    cmd, batch, work, *rest = sys.argv[1:]
    if cmd == "export":
        export(Path(batch), Path(work), *map(int, rest))
    else:
        collect(Path(batch), Path(work), rest[0])
