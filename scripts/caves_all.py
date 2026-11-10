"""Place rooms (caves) with the game's own code for every finished batch and variant.

    python caves_all.py <configs.json> [max_maps]

Uses $WORK/data/<tag> (tiles.npz, maps.parquet) and writes caves_<variant>.parquet/.json
there; skips variants that already exist. Runs $JOBS game instances in parallel
(render/run_game_script.sh caves.gd) over shards of up to max_maps (default 3000) maps.
"""
import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from caves import collect, export

ROOT = Path(__file__).resolve().parents[1]
WORK = Path(os.environ.get("DKWORK", Path.home() / "tmp/domekeepermaps"))
JOBS = int(os.environ.get("JOBS", 16))
VARIANT_PETS = {"base": "done", "nest": "unlockable"}


def run_shard(inp: Path, game_args: list) -> str:
    out = inp.with_name(inp.name.replace("in_", "out_").replace(".bin", ".jsonl"))
    log = subprocess.run([str(ROOT / "render/run_game_script.sh"), "caves.gd", f"--in={inp}",
                          f"--out={out}", *game_args], capture_output=True, text=True,
                         env={**os.environ, "TIMEOUT": "3600", "HEADLESS": "1"}).stdout
    return next((line for line in log.splitlines() if line.startswith("CAVES done")),
                f"FAILED {inp}\n{log[-2000:]}")


def main(cfg_path: str, max_maps: int = 3000):
    for cfg in json.load(open(cfg_path)):
        batch = WORK / "data" / cfg["tag"]
        if not (batch / "tiles.npz").exists():
            print("missing", cfg["tag"], flush=True)
            continue
        for variant in cfg["cave_variants"]:
            if (batch / f"caves_{variant}.parquet").exists():
                print("skip", cfg["tag"], variant, flush=True)
                continue
            opts = {**cfg["game_mode"], "pets": VARIANT_PETS[variant]}
            game_args = [f"--{k}={v}" for k, v in opts.items() if v != ""]
            tmp = WORK / "caves_tmp" / f"{cfg['tag']}_{variant}"
            shutil.rmtree(tmp, ignore_errors=True)
            export(batch, tmp, JOBS, max_maps)
            with ThreadPoolExecutor(JOBS) as pool:
                results = list(pool.map(lambda p: run_shard(p, game_args),
                                        sorted(tmp.glob("in_*.bin"))))
            failed = [r for r in results if r.startswith("FAILED")]
            if failed:
                print(cfg["tag"], variant, *failed, sep="\n", flush=True)
                continue
            collect(batch, tmp, variant)
            shutil.rmtree(tmp)


if __name__ == "__main__":
    main(sys.argv[1], *map(int, sys.argv[2:3]))
