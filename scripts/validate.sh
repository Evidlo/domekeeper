#!/bin/bash
# Regenerate the two logged in-game seeds and print tile/biome stats for comparison.
source "$(dirname "$0")/env.sh"
cd "$WORK"
$GODOT --headless --editor --quit --path harness > /dev/null 2>&1
printf "458828460\n1521161624\n" > data/validate_seeds.txt
$GODOT --headless --path harness --script res://runner.gd -- --archetype=assignment-default \
    --seeds=$PWD/data/validate_seeds.txt --out=$PWD/data/validate 2>&1 | grep -v "^Viability" | sort | uniq -c | head -20
$PY - <<'PY'
import json
for l in open("data/validate.jsonl"):
    d = json.loads(l)
    print(d["level_seed"], "attempts", d["attempts"], "ok", d["ok"], "oob", d["oob_cells"], round(d["ms"]), "ms")
    for x in d["reports"][-1].splitlines():
        if "Tile Count" in x or x.startswith("Biome") or "rror" in x or "ailed" in x or "took" in x:
            print("   ", x)
PY
