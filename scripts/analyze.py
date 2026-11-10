"""Heatmaps and placement statistics for a postprocessed batch.

    python analyze.py data/<tag>

Writes data/<tag>/figs/*.png and data/<tag>/stats.json.
Tile coords: x right, y down; the dome entrance is (0, 0).
"""
import json
import sys
from pathlib import Path

import matplotlib
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap
from scipy import ndimage

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

SURFACE = "#fcfcfb"
INK, INK2, MUTED = "#1f1f1e", "#5c5c58", "#9a9994"
SEQ = ["#fcfcfb", "#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]
CMAP = LinearSegmentedColormap.from_list("seq_blue", SEQ)
TYPES = [("gadget", "Gadget chambers"), ("supplement", "Supplement chambers"),
         ("relic", "Relic chamber"), ("relic_switch", "Relic switches")]
RANK_COLORS = ["#2a78d6", "#eb6834", "#1d9e75"]  # categorical slots 1-3

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": MUTED, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "text.color": INK, "font.size": 10, "axes.spines.top": False, "axes.spines.right": False,
})


def load(batch: Path):
    z = np.load(batch / "tiles.npz")
    maps = pd.read_parquet(batch / "maps.parquet")
    ch = pd.read_parquet(batch / "chambers.parquet")
    return z["tiles"], int(z["x0"]), int(z["y0"]), maps, ch


def heatmaps(tiles, x0, y0, ch, n_maps, out: Path):
    h, w = tiles.shape[2:]
    in_map = (tiles[:, 0] >= 0).mean(axis=0)
    ys, xs = np.nonzero(in_map > 0.005)
    crop = (slice(ys.min(), ys.max() + 1), slice(xs.min(), xs.max() + 1))
    extent = (xs.min() + x0 - 0.5, xs.max() + x0 + 0.5, ys.max() + y0 + 0.5, ys.min() + y0 - 0.5)

    fig, axes = plt.subplots(1, 4, figsize=(17, 5.0), sharey=True, constrained_layout=True)
    for ax, (t, title) in zip(axes, TYPES):
        sub = ch[ch.type == t]
        grid = np.zeros((h, w))
        np.add.at(grid, (sub.y.values - y0, sub.x.values - x0), 1.0)
        grid = ndimage.gaussian_filter(grid, 0.8) / n_maps
        img = ax.imshow(grid[crop], cmap=CMAP, extent=extent, interpolation="nearest",
                        vmin=0, vmax=np.quantile(np.append(grid[crop][grid[crop] > 0], 1e-9), 0.995))
        ax.contour(np.arange(extent[0] + 0.5, extent[1]), np.arange(extent[3] + 0.5, extent[2]),
                   in_map[crop], levels=[0.05, 0.5, 0.95], colors=[MUTED], linewidths=[0.6, 1.0, 0.6],
                   linestyles=["dotted", "solid", "dotted"])
        ax.plot(0, -1, marker="^", ms=9, color=INK, mec=SURFACE, mew=1.5)
        ax.set_title(f"{title}\n{len(sub) / n_maps:.2f} per map", loc="left", fontsize=11)
        ax.set_xlabel("x (tiles from dome)")
        fig.colorbar(img, ax=ax, shrink=0.6, label="P(chamber top-left at tile), smoothed σ=0.8")
    axes[0].set_ylabel("depth y (tiles)")
    fig.suptitle(f"Where chambers spawn — {n_maps:,} maps.  Lines: map footprint in 5% / 50% / 95% "
                 "of maps.  ▲ dome", x=0.01, ha="left", fontsize=12, color=INK2)
    fig.savefig(out / "heatmap_chambers.png", dpi=130)
    plt.close(fig)


def ranked(ch, t):
    sub = ch[ch.type == t].sort_values(["map_idx", "y"]).copy()
    sub["rank"] = sub.groupby("map_idx").cumcount()
    return sub


def depth_hists(ch, out: Path):
    fig, axes = plt.subplots(1, 2, figsize=(13, 4.2), constrained_layout=True)
    for ax, t in zip(axes, ["gadget", "supplement"]):
        sub = ranked(ch, t)
        bins = np.arange(0, sub.y.max() + 3)
        for r in range(sub["rank"].max() + 1):
            ax.hist(sub.y[sub["rank"] == r], bins=bins, histtype="step", lw=2, color=RANK_COLORS[r % 3],
                    label=f"{['1st', '2nd', '3rd'][r] if r < 3 else f'{r + 1}th'} shallowest")
        ax.set_title(f"{t.capitalize()} chamber depth, by depth rank within a map", loc="left")
        ax.set_xlabel("depth y (tiles)")
        ax.set_ylabel("maps")
        ax.legend(frameon=False)
        ax.grid(axis="y", color="#e7e6e2", lw=0.8)
    fig.savefig(out / "depth_by_rank.png", dpi=130)
    plt.close(fig)


def iron_proximity(tiles, x0, y0, ch, maps):
    """Distance from each chamber's center to the nearest iron tile vs. a random dirt tile."""
    rng = np.random.default_rng(0)
    rows = []
    sample = maps.map_idx.values[: min(3000, len(maps))]
    for i in sample:
        res = tiles[i, 2]
        d_iron = ndimage.distance_transform_edt(res != 0)
        dirt_y, dirt_x = np.nonzero(res == 10)
        k = rng.integers(0, dirt_y.size, 20)
        rows += [("random dirt", d) for d in d_iron[dirt_y[k], dirt_x[k]]]
        for c in ch[ch.map_idx == i].itertuples():
            cy, cx = int(round(c.cy)) - y0, int(round(c.cx)) - x0
            rows += [(c.type, d_iron[cy, cx])]
    df = pd.DataFrame(rows, columns=["what", "dist"])
    return df.groupby("what").dist.describe()[["mean", "25%", "50%", "75%"]].round(2)


def side_stats(ch):
    stats = {}
    for t in ["gadget", "supplement"]:
        sub = ranked(ch, t)
        piv = sub.pivot(index="map_idx", columns="rank", values="x")
        sgn = np.sign(piv)
        stats[t] = {
            "P(rank1 on left)": float((sgn[0] < 0).mean()),
            **{f"P(rank{r + 1} opposite side of rank{r})": float((sgn[r] * sgn[r - 1] < 0).mean())
               for r in range(1, piv.shape[1])},
            "median |x| by rank": [float(piv[r].abs().median()) for r in range(piv.shape[1])],
            "median y by rank": [float(sub[sub["rank"] == r].y.median()) for r in range(piv.shape[1])],
        }
    g, s = ranked(ch, "gadget"), ranked(ch, "supplement")
    g1 = g[g["rank"] == 0].set_index("map_idx").x
    s1 = s[s["rank"] == 0].set_index("map_idx").x
    stats["P(1st supplement same side as 1st gadget)"] = float((np.sign(g1) == np.sign(s1.reindex(g1.index))).mean())
    return stats


def main(batch: Path):
    out = batch / "figs"
    out.mkdir(exist_ok=True)
    tiles, x0, y0, maps, ch = load(batch)
    n = len(maps)
    heatmaps(tiles, x0, y0, ch, n, out)
    depth_hists(ch, out)
    stats = side_stats(ch)
    prox = iron_proximity(tiles, x0, y0, ch, maps)
    stats["dist to nearest iron tile"] = prox.to_dict(orient="index")
    json.dump(stats, open(batch / "stats.json", "w"), indent=1)
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    main(Path(sys.argv[1]))
