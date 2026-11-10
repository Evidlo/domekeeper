# 2026-11-09 - Map generation analysis + viewer app

- Pipeline and gotchas are now in README.md. Harness was validated against 2 seeds from the user's game logs (values in README).
- **One crash report was likely uploaded before override.cfg was set up.** The user's real saves (`app_userdata/Dome Keeper`) must never be touched.
- `data/guild_default`→`projhell_pc3` (20k maps) and `data/guild_maze`→`assign_maze` (10k) are symlinks to older batches; a fresh run would regenerate them at configs' n.
- Findings: gadget/supplement chambers sit in tight depth bands and alternate sides 91–98%; difficulty and supplement cap don't move gadget or first-k supplement positions; mean hardness ≈2 everywhere.
- Dropped for now: 20 maps/randomize; JS-drawn maps (old prototype in `$DKWORK/old/prototypes`).

# 2026-11-10 - Rooms, cleanup, README

- Repo = code + `app/` only; everything bulky in `$DKWORK` (default `~/tmp/domekeepermaps`), `old/` there holds the obsolete scripts, partial GDRE exports, logs and `decomp/` (superseded by `fullproj/`).
- Rooms: `caves_all.py` runs the game's generateCaves headless in the game binary over the first 3000 maps per batch. Holiday flags must be forced off (Halloween is date-based and was active on Nov 10). Nest only appears in Relic Hunt medium+ while `GameWorld.unlockablePets` is non-empty (it's filled at run start, so set it explicitly). Co-op is `MODE_COOP`, so no nest.
- Room rendering: the game shows rooms through a cut-out in `ViewportBackgroundAlpha` that doesn't line up offscreen (constant shifts didn't fix it). Instead rooms are drawn above the background with z=0, using AlphaMap as a clip_children mask. The user wants rooms static/always-on in the render; the probability layer is the interactive part (no outline toggle).
- Render surface: the game only shows the sky/surface through a per-viewport clone of World's ParallaxBG (`createNewParallaxBG`), so render.gd adds one, frozen at rest; it's ~980 px wide, so wide maps have black sky edges. Dome gadgets the user asked for: shield (top left), teleporter (cellar left), furnace = the "smoker" (cellar right + chimney outside).
- Keeper and carryable drop scenes (Seed, Egg, CaveBomb) segfault or need a running level when instantiated in a script → take only their sprite node out of the scene, unrun (render.gd `_add_keeper`, room_icons.gd). The dome draws at z=2, so the keeper needs z=3.
- Layout (user's choice): left sidebar with all controls and stats, map on the right; rooms are toggle chips (no "all rooms"), selected rooms sum into one layer.
- Button icons = carryable item sprites rendered with the game palette (`render/icons.gd`); the relic switch icon is still cropped from a render.
- `xvfb-run -a` races in parallel → per-PID display number. Editing render/*.gd re-patches the pck mid-run → patch is now atomic, but avoid edits while batches run.
- Viewer labels and defaults the user chose: title "Domekeeper Probabilities"; columns "avg. depth" / "avg x offset" (values are medians); no depth column for rooms; opacity 100%, smoothing on; the about box only gives the map count.
- Not yet run end to end: `setup.sh` and `pipeline.sh` (the stages were run individually). `app/` was built with Steam build 25038893.
