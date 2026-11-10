"""Build per-config data for the static map viewer.

    python build_app.py <configs.json> <data_dir> <renders_dir> <app_dir> [steam_build_id]

For every config whose batch exists, writes
    <app_dir>/data/<tag>.js     DK.register(...) with quantized probability layers + stats
    <app_dir>/maps/<tag>/<k>.png  the batch's sample maps as rendered by the game
                                (render/render.gd), copied from <renders_dir>/<tag>/<k>.png
Room (cave) layers come from <data_dir>/<tag>/caves_<variant>.parquet (scripts/caves_all.py).
and <app_dir>/data/index.js listing the available configs.
"""
import base64
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image

CHAMBERS = {"gadget": 3, "supplement": 7, "relic": 4, "relic_switch": 6}
FIELDS = {"iron": 0, "water": 1, "cobalt": 2}
RANKED = ("gadget", "supplement")
RENDER_PX = 24
MAX_TILES_FULL_RES = 30000
HEADROOM_TILES = 10  # sky above the surface so the dome is in frame
N_SAMPLES = 1  # game-rendered example maps per config


def b64(a: np.ndarray) -> str:
    return base64.b64encode(np.ascontiguousarray(a).tobytes()).decode()


def quantize(p: np.ndarray):
    """uint8 codes with a per-layer max; value = code / 255 * vmax."""
    vmax = float(p.max())
    q = np.round(p / max(vmax, 1e-12) * 255).astype(np.uint8)
    return q, vmax


def rank_stats(ch: pd.DataFrame, t: str) -> list:
    sub = ch[ch.type == t].sort_values(["map_idx", "y"]).copy()
    if sub.empty:
        return []
    sub["rank"] = sub.groupby("map_idx").cumcount()
    piv = sub.pivot(index="map_idx", columns="rank", values="x")
    sgn = np.sign(piv)
    out = []
    for r in range(piv.shape[1]):
        s = sub[sub["rank"] == r]
        out.append({
            "rank": r + 1,
            "frac_maps": float(s.map_idx.nunique() / ch.map_idx.nunique()),
            "y_median": float(s.y.median()), "y_p10": float(s.y.quantile(0.1)), "y_p90": float(s.y.quantile(0.9)),
            "absx_median": float(s.x.abs().median()),
            "p_left": float((s.x < 0).mean()),
            "p_opposite_prev": None if r == 0 else float((sgn[r] * sgn[r - 1] < 0).sum() / sgn[r].notna().sum()),
        })
    return out


def load_tiles(batch: Path):
    """Batch tile grids padded with HEADROOM_TILES empty rows on top; returns (tiles, x0, y0)."""
    z = np.load(batch / "tiles.npz")
    tiles = np.pad(z["tiles"], ((0, 0), (0, 0), (HEADROOM_TILES, 0), (0, 0)), constant_values=-1)
    return tiles, int(z["x0"]), int(z["y0"]) - HEADROOM_TILES


def crop_box(tiles: np.ndarray):
    """Tile-index bounds (ya, yb, xa, xb) covering every cell inside the map in >0.2% of maps,
    plus 1 tile, plus HEADROOM_TILES of sky above (tiles must come from load_tiles)."""
    in_map = (tiles[:, 0] >= 0).mean(0)
    ys, xs = np.nonzero(in_map > 0.002)
    return ys.min() - 1 - HEADROOM_TILES, ys.max() + 2, xs.min() - 1, xs.max() + 2


def sample_indices(maps: pd.DataFrame) -> list:
    return [int(i) for i in maps.index[maps.ok][:N_SAMPLES]]


def cave_layers(batch: Path, variant: str, x0: int, y0: int, w: int, h: int):
    """Per room id: chance each tile is part of that room, and rooms per map.

    Rooms never overlap within one map, so the layers sum to the chance of any room."""
    df = pd.read_parquet(batch / f"caves_{variant}.parquet")
    meta = json.loads((batch / f"caves_{variant}.json").read_text())
    n = meta["n_maps"]
    layers, per_map = {}, {}
    for cave, sub in df.groupby("cave"):
        foot = np.array(meta["caves"][cave]["tiles"])
        cols = (sub.x.to_numpy()[:, None] + foot[None, :, 0] - x0).ravel()
        rows = (sub.y.to_numpy()[:, None] + foot[None, :, 1] - y0).ravel()
        keep = (cols >= 0) & (cols < w) & (rows >= 0) & (rows < h)
        count = np.zeros((h, w))
        np.add.at(count, (rows[keep], cols[keep]), 1)
        q, vmax = quantize(count / n)
        layers[cave] = {"vmax": vmax, "data": b64(q)}
        per_map[cave] = {"mean": float(len(sub) / n), "any": float(sub.map_idx.nunique() / n),
                         "y_median": float(sub.y.median()), "y_p10": float(sub.y.quantile(0.1)),
                         "y_p90": float(sub.y.quantile(0.9))}
    return {"layers": layers, "per_map": per_map, "settings": meta["settings"], "n_maps": n}


def build_one(cfg: dict, batch: Path, renders: Path, app: Path) -> dict:
    tiles, x0, y0 = load_tiles(batch)
    ch = pd.read_parquet(batch / "chambers.parquet")
    maps = pd.read_parquet(batch / "maps.parquet")
    n = tiles.shape[0]

    ya, yb, xa, xb = crop_box(tiles)
    res = tiles[:, 2, ya:yb, xa:xb]
    layers = {name: (res == tid).mean(0) for name, tid in {**CHAMBERS, **FIELDS}.items()}
    layers["in_map"] = (tiles[:, 0, ya:yb, xa:xb] >= 0).mean(0)
    enc = {}
    for k, v in layers.items():
        q, vmax = quantize(v)
        enc[k] = {"vmax": vmax, "data": b64(q)}

    w, h = int(xb - xa), int(yb - ya)
    px = RENDER_PX if w * h < MAX_TILES_FULL_RES else RENDER_PX // 2
    (app / "maps" / cfg["tag"]).mkdir(parents=True, exist_ok=True)
    samples = []
    for k, i in enumerate(sample_indices(maps)):
        render = renders / cfg["tag"] / f"{k}.png"
        if not render.exists():
            continue
        im = Image.open(render).convert("RGB")
        assert im.size == (w * RENDER_PX, h * RENDER_PX), (render, im.size, w, h)
        im.resize((w * px, h * px), Image.NEAREST).save(app / "maps" / cfg["tag"] / f"{k}.png", optimize=True)
        samples.append({"k": k, "seed": int(maps.level_seed[i])})
    caves = {v: cave_layers(batch, v, int(x0 + xa), int(y0 + ya), w, h)
             for v in cfg.get("cave_variants", []) if (batch / f"caves_{v}.parquet").exists()}
    data = {
        "tag": cfg["tag"], "n_maps": int(n), "w": w, "h": h,
        "x0": int(x0 + xa), "y0": int(y0 + ya), "px": px, "samples": samples,
        "per_map": {k: float(v) for k, v in (ch.groupby("type").size() / n).items()},
        "ranks": {k: rank_stats(ch, k) for k in RANKED},
        "layers": enc,
        "caves": caves,
    }
    (app / "data" / f"{cfg['tag']}.js").write_text(f"DK.register({json.dumps(data)});\n")
    meta = {k: cfg.get(k) for k in ("tag", "group", "archetype", "size", "modifier", "challenges",
                                    "game_mode")}
    meta.update({"n_maps": int(n), "w": w, "h": h})
    return meta


def main(cfg_path, data_dir, renders_dir, app_dir, steam_build="unknown"):
    app = Path(app_dir)
    (app / "data").mkdir(parents=True, exist_ok=True)
    (app / "maps").mkdir(exist_ok=True)
    index = []
    for cfg in json.load(open(cfg_path)):
        batch = Path(data_dir) / cfg["tag"]
        if not (batch / "chambers.parquet").exists():
            print("missing", cfg["tag"], flush=True)
            continue
        print("build", cfg["tag"], flush=True)
        index.append(build_one(cfg, batch, Path(renders_dir), app))
    (app / "data" / "index.js").write_text(f"DK.index({json.dumps(index)});\n")
    version = Path(renders_dir).parent / "version.txt"
    game_version = version.read_text().split()[0] if version.exists() else "unknown"
    (app / "data" / "version.js").write_text(
        f"DK.version({json.dumps({'game': game_version, 'steam_build': steam_build})});\n")


if __name__ == "__main__":
    main(*sys.argv[1:6])
