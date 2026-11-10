#!/bin/bash
# Patch the game pck with render/*.gd and run one of them in the real game binary under Xvfb.
#   [HEADLESS=1] run_game_script.sh <script.gd> [game args after --]
# Each Xvfb gets its own display number (xvfb-run -a races when started in parallel).
# Several instances may run at once; the pck is patched by the first one only when stale.
set -euo pipefail
source "$(dirname "$0")/../scripts/env.sh"
SCRIPT=$1; shift
PATCH_ARGS=()
for f in "$ROOT"/render/*.gd; do PATCH_ARGS+=("--patch-file=$f=res://dkrender/$(basename $f)"); done
(
    flock 9
    if [ ! -f "$WORK/game/patched.pck" ] || [ -n "$(find "$ROOT/render" -name '*.gd' -newer "$WORK/game/patched.pck")" ]; then
        "$GDRE" --headless --pck-patch="$WORK/game/domekeeper.pck" "${PATCH_ARGS[@]}" \
            --output="$WORK/game/patched.tmp.pck" > "$WORK/game/patch.log" 2>&1
        mv "$WORK/game/patched.tmp.pck" "$WORK/game/patched.pck"  # running games keep the old file
    fi
) 9> "$WORK/game/patch.lock"
cd "$WORK/game"
if [ -n "${HEADLESS:-}" ]; then  # scripts that draw nothing (caves.gd)
    LD_LIBRARY_PATH=. timeout ${TIMEOUT:-300} ./domekeeper.x86_64 --headless \
        --main-pack patched.pck --script "res://dkrender/$SCRIPT" -- "$@" 2>&1 | tr '\r' '\n'
else
    LD_LIBRARY_PATH=. timeout ${TIMEOUT:-300} xvfb-run -n $((100 + $$ % 800)) -s "-screen 0 1920x1080x24" \
        ./domekeeper.x86_64 --main-pack patched.pck --rendering-driver opengl3 \
        --script "res://dkrender/$SCRIPT" -- "$@" 2>&1 | tr '\r' '\n'
fi
