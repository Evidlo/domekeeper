#!/bin/bash
# Generate a batch of maps with the game's own generator, in parallel.
#
#   run_batch.sh <tag> <archetype> <n_maps> [--set=key:value ...] [--op=key*=value ...]
#
# Seeds are uniform random uint32 (like Level.randomizeSeed -> randi()), drawn
# from a fixed RNG seeded by the tag so that a batch is reproducible.
# Output: $WORK/data/<tag>/{seeds.txt, chunks/*.bin, chunks/*.jsonl, config.json}
# The harness project must be set up first (setup_harness.sh).
set -euo pipefail
source "$(dirname "$0")/env.sh"
TAG=$1; ARCH=$2; N=$3; shift 3
SETS=("$@")
CHUNK=${CHUNK:-50}
G=$GODOT
HARNESS=$WORK/harness
OUT=$WORK/data/$TAG

mkdir -p "$OUT/chunks"
$G --headless --editor --quit --path "$HARNESS" > /dev/null 2>&1

$PY - "$TAG" "$N" "$OUT/seeds.txt" <<'PY'
import sys, zlib, numpy as np
tag, n, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rng = np.random.default_rng(zlib.crc32(tag.encode()))
np.savetxt(path, rng.integers(0, 2**32, size=n, dtype=np.uint64), fmt="%d")
PY

$PY - "$OUT/config.json" "$ARCH" "$N" "${SETS[@]}" <<'PY'
import sys, json
path, arch, n, *sets = sys.argv[1:]
json.dump({"archetype": arch, "n": int(n), "sets": sets}, open(path, "w"), indent=1)
PY

rm -f "$OUT"/chunks/*
split -l "$CHUNK" -d -a 5 "$OUT/seeds.txt" "$OUT/chunks/seeds_"

run_chunk() {
    local f=$1; shift
    local base=${f%/seeds_*}/map_${f##*/seeds_}
    "$G" --headless --path "$HARNESS" --script res://runner.gd -- \
        --archetype="$ARCH" --seeds="$f" --out="$base" "$@" > "$base.log" 2>&1
}
export -f run_chunk
export G HARNESS ARCH

SET_ARGS=()
for s in "${SETS[@]}"; do [[ $s == --* ]] && SET_ARGS+=("$s") || SET_ARGS+=("--set=$s"); done

start=$(date +%s)
ls "$OUT"/chunks/seeds_* | xargs -P "$JOBS" -I{} bash -c 'run_chunk "$@"' _ {} "${SET_ARGS[@]}"
echo "generated $N maps in $(( $(date +%s) - start )) s -> $OUT"
