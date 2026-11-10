#!/bin/bash
# Full run after setup.sh: generate every config, place rooms, render samples, build app/.
#   pipeline.sh [steam_build_id]       (Steam build id is shown in the viewer only)
# Each stage skips work that is already done, so the script can be re-run after a failure.
set -euo pipefail
source "$(dirname "$0")/env.sh"
CFG=$ROOT/scripts/configs.json
cd "$ROOT/scripts"
$PY configs.py > "$CFG"
$PY run_queue.py "$CFG"
$PY caves_all.py "$CFG"
"$ROOT/render/render_all.sh" "$CFG"
APP=$ROOT/app
mkdir -p "$APP/fonts"
cp "$ROOT"/app_src/* "$APP/"
cp "$WORK/fullproj/gui/fonts/Kollektif.ttf" "$APP/fonts/"
"$ROOT/render/run_game_script.sh" icons.gd --out="$APP/icons" | grep "^ICON"
"$ROOT/render/run_game_script.sh" room_icons.gd --out="$APP/icons" | grep "^ICON"
$PY make_icons.py "$WORK/renders/inputs/guild_default/0.json" \
    "$WORK/renders/out/guild_default/0.png" "$APP/icons"
$PY build_app.py "$CFG" "$WORK/data" "$WORK/renders/out" "$APP" "${1:-unknown}"
echo "app built $(date)"
