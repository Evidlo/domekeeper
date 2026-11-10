extends SceneTree

# Render generated maps with the game's own Map scene, fully revealed, to PNGs.
#
#   --list=<file>     lines "<map.json> <map.png>"; maps are rendered one after another
#                     map.json: {seed, x0, y0, w, h, biome[], hardness[], resource[]} (row-major, -1 = empty)
#   --version-out=<f> write the game version (res://game/version.gd) to this file
#   --reveal=1        mine every plain dirt tile first ("reveal resources" view)
#   --palette=<id>    Style palette, default palette_1_1
#   --caves=1         place rooms (caves) with Map.generateCaves, as at level start, and write
#                     them to <map.png>.caves.json ({id: [[x, y], ...]}, top-left tiles); the
#                     room sprites themselves are not drawn
#   plus the game-mode options of dkmode.gd (mode, mapsize, assignment, modifiers, pets),
#   which decide which rooms may appear
#
# Each output covers tiles [x0, x0 + w) x [y0, y0 + h) at 24 px per tile.

const TILE: = 24
const TILE_DIRT_START: = 10  # Data.TILE_DIRT_START (autoloads are not resolvable at compile time here)
const CHAMBER_TILE_IDS: = [3, 4, 5, 6, 7, 11]  # Data.TILE_GADGET .. TILE_SUPPLEMENT, TILE_DIRT_MARK_BLOCKED_FOR_CHAMBER
# Map draws tile (x, y) at world (x, y) * TILE - Map.mapToWorldOffset + (0, -2); measured with
# scripts/calibrate_render.py against iron tile positions.
const WORLD_OFFSET: = Vector2(-12, 70)
# keeper standing in the dome: sprite node of the keeper scene and its offset from the dome
const KEEPER: = ["res://content/keeper/keeper1/Keeper1.tscn", "Visuals/Sprite2D"]
const KEEPER_OFFSET: = Vector2(0, 32)  # lower floor, between teleporter and furnace
# gadgets shown in the dome, (scene, Dome.addGadget slot); cellar slots fill left, then right
const DOME_GADGETS: = [
	["res://content/gadgets/shield/ShieldBattery.tscn", "primarygadget"],
	["res://content/gadgets/teleporter/TeleporterStation.tscn", "cellar"],
	["res://content/gadgets/furnace/FurnaceStation.tscn", "cellar"],
	["res://content/gadgets/furnace/FurnaceChimney.tscn", "domebackside"],
]
const WARMUP_FRAMES: = 10
const RENDER_FRAMES: = 30
const TEARDOWN_FRAMES: = 3

enum Stage { WARMUP, RENDERING, TEARDOWN }

var _opts: = {}
var _jobs: = []
var _frames: = 0
var _stage: = Stage.WARMUP
var _vp: SubViewport
var _map


func _process(_delta: float) -> bool:
	_frames += 1
	match _stage:
		Stage.WARMUP:
			if _frames >= WARMUP_FRAMES:
				_parse_args()
				_write_version()
				_start_next()
		Stage.RENDERING:
			if _frames >= RENDER_FRAMES:
				var img: Image = _vp.get_texture().get_image()
				img.save_png(_jobs[0][1])
				print("RENDER saved ", _jobs[0][1], " ", img.get_size())
				_jobs.pop_front()
				_teardown()
		Stage.TEARDOWN:
			if _frames >= TEARDOWN_FRAMES:
				_start_next()
	return false


func _start_next() -> void:
	if _jobs.is_empty():
		quit()
		return
	_setup(_jobs[0][0])
	_stage = Stage.RENDERING
	_frames = 0


func _teardown() -> void:
	var level = root.get_node("Level")
	level.map = null
	level.worldsByTeamId.clear()
	level.domesByTeamId.clear()
	_vp.queue_free()
	_vp = null
	_map = null
	_stage = Stage.TEARDOWN
	_frames = 0


# Rooms are drawn behind the map background and shown through a cut-out that Map renders in
# a side viewport; that cut-out does not line up here, so draw the rooms above the background
# instead and drop their cut-outs. Rooms are revealed and static (no parallax).
func _add_caves(caves: Dictionary) -> void:
	var alpha_images: Node = _map.get_node("ViewportBackgroundAlpha/AlphaImages")
	var n_alpha: int = alpha_images.get_child_count()
	_map.cavePlacements = caves
	_map.addCaves()
	for k in range(alpha_images.get_child_count() - 1, n_alpha - 1, -1):
		alpha_images.get_child(k).free()
	for cave in _map.get_tree().get_nodes_in_group("cave"):
		if not _map.is_ancestor_of(cave):
			continue
		cave.z_index = int(_opts.get("cave-z", "0"))
		cave.tileRevealed(cave.coord)
		cave.disableParallax()
		_mask_with_alpha_map(cave)


# Clip a room's artwork to the shape of its AlphaMap (the cut-out it would punch in the background).
func _mask_with_alpha_map(cave: Node) -> void:
	var alpha: Sprite2D = cave.find_child("AlphaMap", false)
	if alpha == null:
		return
	alpha.visible = true
	alpha.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	for child in cave.get_children():
		if child != alpha and (child is Sprite2D or child is AnimatedSprite2D or child is Control):
			child.reparent(alpha, true)


# The keeper scene needs a running level, so only its sprite is shown (idle, facing front).
func _add_keeper(dome: Node) -> void:
	var keeper: Node = load(KEEPER[0]).instantiate()
	var sprite: AnimatedSprite2D = keeper.get_node(KEEPER[1])
	sprite.get_parent().remove_child(sprite)
	keeper.free()
	for c in sprite.get_children():
		c.queue_free()
	sprite.animation = "default"
	sprite.frame = 0
	sprite.stop()
	sprite.position = dome.position + KEEPER_OFFSET
	sprite.z_index = dome.z_index + 1  # in front of the dome interior, as a keeper walking in it
	_vp.add_child(sprite)
	root.get_node("Style").init(sprite)


func _write_caves(caves: Dictionary) -> void:
	var out: = {}
	for id in caves:
		out[id] = caves[id].map(func(c): return [int(c.x), int(c.y)])
	FileAccess.open(_jobs[0][1] + ".caves.json", FileAccess.WRITE).store_string(JSON.stringify(out))
	print("RENDER caves ", out)


func _write_version() -> void:
	var version_script: GDScript = load("res://game/version.gd")
	var line: String = "v%s %s" % [version_script.VERSION, version_script.SHA]
	print("RENDER game version ", line)
	if _opts.has("version-out"):
		FileAccess.open(_opts["version-out"], FileAccess.WRITE).store_string(line)


func _parse_args() -> void:
	_opts = {"reveal": "1", "palette": "palette_1_1", "caves": "1", "pets": "done"}
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			_opts[kv[0]] = kv[1]
	for line in FileAccess.get_file_as_string(_opts["list"]).split("\n", false):
		var parts: PackedStringArray = line.strip_edges().split(" ", false)
		_jobs.append([parts[0], parts[1]])


func _setup(input_path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	var style = root.get_node("Style")
	var level = root.get_node("Level")
	var map_script: GDScript = load("res://content/map/Map.gd")
	load("res://dkrender/dkmode.gd").apply(root, _opts)
	style.setPalette(_opts["palette"])
	level.levelSeed = int(d["seed"])

	var md = load("res://content/map/MapData.tscn").instantiate()
	var x0: int = d["x0"]
	var y0: int = d["y0"]
	var w: int = d["w"]
	var h: int = d["h"]
	for j in h:
		for i in w:
			var k: = j * w + i
			var c: = Vector2i(x0 + i, y0 + j)
			if d["biome"][k] >= 0:
				md.set_biomev(c, int(d["biome"][k]))
			if d["hardness"][k] >= 0:
				md.set_hardnessv(c, int(d["hardness"][k]))
			if d["resource"][k] >= 0:
				md.set_resourcev(c, int(d["resource"][k]))

	# same order as LandingStage.generate_landmark_data; rooms need plain dirt, so before reveal
	var chambers: Dictionary = map_script.generateChamberPlacements(md)
	var biomes: Array[String] = map_script.generateBiomes()
	var caves: Dictionary = map_script.generateCaves(md, biomes) if _opts["caves"] == "1" else {}
	if _opts["reveal"] == "1":
		for c in md.get_resource_cells_by_id(TILE_DIRT_START):
			md.clear_resource(c)

	_vp = SubViewport.new()
	_vp.size = Vector2i(w * TILE, h * TILE)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(_vp)

	# surface scenery and dome, placed as LevelStage.build / addDome do
	var world = load("res://content/worlds/world1/World1.tscn").instantiate()
	world.name = "team1World"
	world.teamId = "team1"
	_vp.add_child(world)
	world.position.x = md.get_entry_coords()[0].x * TILE
	level.worldsByTeamId["team1"] = world
	# sky and surface: the game gives each player's viewport its own copy of the world's
	# parallax background (WorldViewport.add_parallax_background); left at its rest position
	var parallax = world.createNewParallaxBG()
	_vp.add_child(parallax)
	parallax.show()

	_map = load("res://content/map/Map.tscn").instantiate()
	_map.biomes = biomes
	_map.chamberPlacements = chambers
	_vp.add_child(_map)
	level.map = _map
	_map.setTileData(md)
	_map.init()
	_write_caves(caves)
	_add_caves(caves)

	for c in md.get_used_cells(0):  # MapData.LAYER_BIOME
		_map.tileCoordsToReveal.append(Vector2(c))
	_map.floodRevealTiles(true)
	_excavate_chambers(md)

	var dome = load("res://content/dome/dome1/Dome1.tscn").instantiate()
	dome.teamId = "team1"
	level.domesByTeamId["team1"] = dome
	dome.position = world.getDomePosition()
	_vp.add_child(dome)
	dome.init()
	for g in DOME_GADGETS:
		dome.addGadget(load(g[0]).instantiate(), "team1", g[1])
	_add_keeper(dome)

	var cam: = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	cam.position = Vector2(x0, y0) * TILE + WORLD_OFFSET
	_vp.add_child(cam)
	cam.make_current()


# Dig out every chamber's tiles and put it in the OPEN state, as when a keeper excavates it.
func _excavate_chambers(md) -> void:
	var chambers: = []
	var stack: Array = [_map]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var path: String = n.get_script().resource_path if n.get_script() else ""
		if path.begins_with("res://content/map/chamber/") and "tileCoords" in n:
			chambers.append(n)
	for chamber in chambers:
		for c in chamber.tileCoords:
			var abs_coord: Vector2 = chamber.coord + Vector2(c)
			md.clear_resource(abs_coord)
			if _map.tiles.has(abs_coord):
				_map.tiles[abs_coord].queue_free()
				_map.tiles.erase(abs_coord)
			_map.removeTileVisually(abs_coord)
		chamber.currentState = chamber.State.OPEN
		chamber.onStateUpdated()
	# generator cells the chamber cover does not list (e.g. the gadget chamber's 5th cell)
	for id in CHAMBER_TILE_IDS:
		for c in md.get_resource_cells_by_id(id):
			var abs_coord: = Vector2(c)
			md.clear_resource(abs_coord)
			if _map.tiles.has(abs_coord):
				_map.tiles[abs_coord].queue_free()
				_map.tiles.erase(abs_coord)
			_map.removeTileVisually(abs_coord)
	_map.updateDirtyTextures()
	print("RENDER excavated ", chambers.size(), " chambers")

