## Architecture

- `scripts/` - pipeline (Python + bash), `env.sh` holds the shared paths
- `harness/` - minimal Godot 4.3 project that runs the game's unmodified map generator; game files are copied in by `setup.sh`
- `render/` - GDScript run *inside the game binary* (pck patched with GDRE): `render.gd` example maps, `caves.gd` room placement, `dkmode.gd` game-mode setup
- `app_src/` - viewer source (HTML/JS/CSS)

Large inputs and intermediates live out of tree in a separate work directory, `$DKWORK` (default
`~/tmp/domekeepermaps`):

- `game/` - copy of the Linux game install (`domekeeper.x86_64`, `domekeeper.pck`, `.so` libs) + `override.cfg`
- `tools/` - `gdre_tools.x86_64` ([GDRE Tools](https://github.com/GDRETools/gdsdecomp), used v2.7.4), `Godot_v4.3-stable_linux.x86_64`
- `fullproj/` - GDRE full project recovery of the game
- `harness/` - built harness project
- `data/<tag>/` - generated maps per config: `tiles.npz`, `maps.parquet`, `chambers.parquet`, `caves_<variant>.parquet`
- `renders/` - render inputs and game-rendered PNGs

## Requirements

- Linux x86_64, `xvfb-run`, `rsync`, `flock`
- Python 3 with numpy, pandas, pyarrow, scipy, pillow, matplotlib (`PY=` in `env.sh`)
- Dome Keeper (Linux build, e.g. via Steam with the Linux depot)
- optional: `chromium` for `scripts/shot.sh` (screenshots of the viewer)

## Running on a new game version

`$DKWORK` can be rebuilt from scratch with the commands below. The one manual step is
downloading the two tools into `$DKWORK/tools/` first: `gdre_tools.x86_64` from the
[GDRE Tools releases](https://github.com/GDRETools/gdsdecomp/releases) (Linux build, used
v2.7.4) and `Godot_v4.3-stable_linux.x86_64` from the
[Godot 4.3-stable release](https://github.com/godotengine/godot/releases/tag/4.3-stable).
A full rebuild takes a few hours on 16 cores.

```bash
export DKWORK=~/tmp/domekeepermaps          # optional, this is the default
scripts/setup.sh "/path/to/steamapps/common/Dome Keeper"   # copy, decompile, build harness
scripts/validate.sh                          # sanity check of the generator harness
JOBS=16 scripts/pipeline.sh <steam_build_id> # generate, place rooms, render, build app/
```

`validate.sh` regenerates two seeds taken from the game's own logs (guild assignment,
default archetype). On v5.0.8.14 the game logged, and the harness reproduces:

| seed | generated tiles | biome sizes 0–6 |
|---|---|---|
| 458828460 | 4343 | 306 489 694 790 815 793 456 |
| 1521161624 | 4290 | 301 496 685 808 820 778 402 |

`pipeline.sh` runs these stages, and each one skips work already done (so delete
`$DKWORK/data` and `$DKWORK/renders` to start from scratch after an update):

1. `configs.py > configs.json`: one config per distinct map distribution. Guild
   assignments that share an archetype and generator settings share a batch, plus Relic
   Hunt 4 sizes × {none, Maze, Triple Supplements}, 2-player co-op × 4 sizes, and
   Prestige 10k/20k. Archetype edits mirror `GameWorld.prepareLevelStart` and world
   modifiers, applied in game order so integer truncation matches.
2. `run_queue.py` → `run_batch.sh` (parallel headless Godot running `harness/runner.gd`)
   → `postprocess.py` → `analyze.py`. The runner copies the seed/retry policy of
   `LandingStage` (seed + k·123 retries, reject maps with < 300 mineable tiles).
3. `caves_all.py`: rooms. For each batch it runs the game's own
   `Map.generateChamberPlacements` + `Map.generateBiomes` + `Map.generateCaves` over the
   stored maps inside the game binary (`render/caves.gd`, headless). Variants: `base`
   (no pets left to find) and, for Relic Hunt above small size, `nest` (pets still
   unlockable, which adds the nest room).
4. `render/render_all.sh`: one example map per config, rendered by the game (Map scene,
   fully revealed, plain dirt mined, chambers dug out, rooms shown, surface backdrop, and the
   dome with shield, teleporter, furnace and the keeper; `DOME_GADGETS`/`KEEPER` in
   `render.gd`).
5. Copy `app_src/` to `app/`, draw the button icons (`render/icons.gd`: carryable items in
   the game palette; `render/room_icons.gd`: each room's item, cut from the room scenes;
   `make_icons.py` crops the relic switch from a render),
   then write the per-config data (`build_app.py`).

When the game updates, check what the copied logic depends on:

- `harness/runner.gd` (LandingStage retry policy) and `harness/stubs/*` (constants copied
  from `Data.gd`, `Const.gd`, `Map.gd`, `Utils.gd`). Diff those game files between
  versions.
- `scripts/configs.py` (`ASSIGNMENTS`, `MODIFIER_OPS`, `multiplayer_ops`, `COOP_OPS`,
  from `GameWorld.gd`, `assignments.yaml`, `upgrades.yaml`).
- `render/render.gd` / `dkmode.gd` (run-start Data values; `WORLD_OFFSET` camera offset,
  verify with `scripts/calibrate_render.py <render input json> <png>`, which should
  report dx=dy=0).

## Publishing

`./publish.sh` force-pushes `app/` as the single commit of branch `pages` on `origin`
(with `.nojekyll`). Point GitHub Pages at `pages` / root. Your working tree and `master`
are left alone.

## Notes and gotchas

- **Privacy:** `setup.sh` writes `game/override.cfg`, which blanks the crash-report DSN
  and the online-services title id, and sets a separate user-data folder. It also removes
  `crashpad_handler`. Runs never touch your real save.
- Scripts run in the game's main loop can't name autoloads (`Data`, `Level`, ...) or game
  `class_name`s at compile time. Use `root.get_node()` / `load()` at runtime.
- The pck is re-patched automatically when `render/*.gd` changes. Don't edit a bash
  script while a batch that uses it is running.
- `xvfb-run -a` races when started in parallel, so each render picks its own display.
- Room *positions* use the game's unseeded `pick_random()`, so they are a fresh draw
  every run (the room order and biome colours follow the seed). Distributions are
  unaffected.
- Holiday rooms (Halloween, Lunar New Year, April Fools) are switched off. Prestige's
  optional fixed cave order is not modelled.
- In renders, rooms are drawn above the map background, clipped to their `AlphaMap`
  shape. The game instead shows them through a cut-out in the background viewport,
  which doesn't line up in an offscreen render.
- Generation speed: about 0.65 s per map per core.
