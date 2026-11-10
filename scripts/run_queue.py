"""Generate every config in configs.json that has no chambers.parquet yet.

    python run_queue.py configs.json

Each batch goes to $WORK/data/<tag> (run_batch.sh -> postprocess.py -> analyze.py).
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = Path(os.environ.get("DKWORK", Path.home() / "tmp/domekeepermaps"))
PY = sys.executable


def main(cfg_path: str):
    for c in json.load(open(cfg_path)):
        out = WORK / "data" / c["tag"]
        if (out / "chambers.parquet").exists():
            print("skip", c["tag"], flush=True)
            continue
        print("run", c["tag"], flush=True)
        subprocess.run([str(ROOT / "scripts/run_batch.sh"), c["tag"], c["archetype"], str(c["n"]),
                        *[f"--op={op}" for op in c["ops"]]], check=True)
        subprocess.run([PY, str(ROOT / "scripts/postprocess.py"), str(out)], check=True)
        # figures are a convenience; a plotting failure should not stop the queue
        subprocess.run([PY, str(ROOT / "scripts/analyze.py"), str(out)], stdout=subprocess.DEVNULL)
        shutil.rmtree(out / "chunks")


if __name__ == "__main__":
    main(sys.argv[1])
