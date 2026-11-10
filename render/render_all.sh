#!/bin/bash
# Render the sample maps of every finished batch with the real game (one game start per
# batch, up to $RENDER_JOBS batches at once). Skips batches whose renders and room files
# are complete. Writes $WORK/renders/version.txt with the game version.
#   render_all.sh [configs.json]
set -euo pipefail
source "$(dirname "$0")/../scripts/env.sh"
CFG=${1:-$ROOT/scripts/configs.json}
N=$(cd "$ROOT/scripts" && $PY -c "from build_app import N_SAMPLES; print(N_SAMPLES)")

render_tag() {
    local tag=$1; shift
    local inp=$WORK/renders/inputs/$tag out=$WORK/renders/out/$tag
    mkdir -p "$inp" "$out"
    (cd "$ROOT/scripts" && $PY export_render_input.py "$WORK/data/$tag" "$inp")
    : > "$inp/list.txt"
    for f in "$inp"/[0-9]*.json; do
        echo "$f $out/$(basename "$f" .json).png" >> "$inp/list.txt"
    done
    TIMEOUT=3600 "$ROOT/render/run_game_script.sh" render.gd --list="$inp/list.txt" \
        --version-out="$WORK/renders/version.txt" --reveal=1 "$@" \
        | grep -cE "RENDER saved" | sed "s/^/$tag rendered: /"
}
export -f render_tag
export N

# one line per batch to render: "<tag> --mode=... [--mapsize=...] ..."
$PY - "$CFG" <<'PY' | xargs -P "${RENDER_JOBS:-8}" -L 1 bash -c 'render_tag "$@"' _
import json, os, sys
from pathlib import Path
work, n = Path(os.environ["WORK"]), int(os.environ["N"])
for c in json.load(open(sys.argv[1])):
    out = work / "renders/out" / c["tag"]
    if not (work / "data" / c["tag"] / "chambers.parquet").exists():
        continue
    if all((out / f"{k}.png.caves.json").exists() for k in range(n)):
        continue
    print(c["tag"], *[f"--{k}={v}" for k, v in c["game_mode"].items() if v != ""])
PY
