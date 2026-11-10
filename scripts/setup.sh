#!/bin/bash
# Prepare $WORK for a (new) game version. Idempotent; re-run after a game update.
#   1. copy the game from a Steam install:    setup.sh <path/to/Dome Keeper>
#   2. decompile it (GDRE full recovery)  ->  $WORK/fullproj
#   3. build the generator harness        ->  $WORK/harness (repo harness/ + game generator files)
#   4. write game/override.cfg (no crash reports / telemetry, separate user dir)
# Needs $WORK/tools: gdre_tools.x86_64 (GDRE Tools) and Godot_v4.3-stable_linux.x86_64.
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$WORK"/{game,data,renders}

if [ $# -ge 1 ]; then
    rsync -a --exclude='*.pdb' --exclude=crashpad_handler "$1"/ "$WORK/game/"
    rm -f "$WORK/game/patched.pck" "$WORK/game/crashpad_handler"
    rm -rf "$WORK/fullproj"
fi

if [ ! -d "$WORK/fullproj" ]; then
    "$GDRE" --headless --recover="$WORK/game/domekeeper.pck" --output="$WORK/fullproj" \
        > "$WORK/fullproj.log" 2>&1
fi

H=$WORK/harness
mkdir -p "$H"
rsync -a --exclude=.godot "$ROOT/harness/" "$H/"
G=$WORK/fullproj/content/map
mkdir -p "$H/content/map/generation/archetypes" "$H/content/map/generation/noises"
cp "$G/MapData.gd" "$H/content/map/"
cp "$G/generation/TileDataGenerator.gd" "$G/generation/MapArchetype.gd" "$H/content/map/generation/"
cp "$G"/generation/archetypes/*.tres "$H/content/map/generation/archetypes/"
cp "$G"/generation/noises/*.tres "$H/content/map/generation/noises/"
"$GODOT" --headless --editor --quit --path "$H" > /dev/null 2>&1 || true

cat > "$WORK/game/override.cfg" <<'CFG'
; Render runs only: no crash reporting, separate user data folder.
[sentry]
options/dsn=""
options/attach_screenshot=false
options/attach_scene_tree=false

[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="DomeKeeperRender"

[playfab]
title_id=""
CFG

grep -h "VERSION\|SHA" "$WORK/fullproj/game/version.gd" | head -2
