extends SceneTree

# Run the game's own room (cave) placement, Map.generateCaves, over stored maps.
#
#   --in=<file>    maps from scripts/export_caves_input.py:
#                  int32 n, h, w, x0, y0; int64 seed[n]; then per map int8 biome, hardness,
#                  resource grids (h * w each, row-major, -1 = empty)
#   --out=<file>   JSON lines: first {"meta": ...} (cave footprints, rules, settings), then
#                  one {"i", "biomes", "caves": {id: [[x, y], ...]}} per map
#   plus the game-mode options of dkmode.gd (mode, mapsize, assignment, modifiers, pets)
#
# Like the game, chambers are placed first (Map.generateChamberPlacements) so rooms only
# land on plain dirt. Room positions use the unseeded global RNG (pick_random), so they
# are a fresh draw on every run; the room order and biome colours follow the level seed.

const MAPS_PER_FRAME: = 20
const WARMUP_FRAMES: = 10

var _opts: = {}
var _frames: = 0
var _in: FileAccess
var _out: FileAccess
var _n: = 0
var _h: = 0
var _w: = 0
var _x0: = 0
var _y0: = 0
var _seeds: = []
var _next: = 0
var _map_script: GDScript


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == WARMUP_FRAMES:
		_start()
	elif _frames > WARMUP_FRAMES:
		for _k in MAPS_PER_FRAME:
			if _next >= _n:
				_out.close()
				print("CAVES done ", _n, " maps")
				quit()
				return false
			_one(_next)
			_next += 1
	return false


static func _s32(v: int) -> int:
	return v - (1 << 32) if v >= (1 << 31) else v


func _start() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			_opts[kv[0]] = kv[1]
	var dkmode: GDScript = load("res://dkrender/dkmode.gd")
	dkmode.apply(root, _opts)
	_map_script = load("res://content/map/Map.gd")

	_in = FileAccess.open(_opts["in"], FileAccess.READ)
	_n = _in.get_32()
	_h = _in.get_32()
	_w = _in.get_32()
	_x0 = _s32(_in.get_32())
	_y0 = _s32(_in.get_32())
	for _i in _n:
		_seeds.append(_in.get_64())

	_out = FileAccess.open(_opts["out"], FileAccess.WRITE)
	var settings: String = dkmode.describe(root)
	print("CAVES ", settings)
	_out.store_line(JSON.stringify({"meta": {"caves": _cave_rules(), "settings": settings}}))


func _cave_rules() -> Dictionary:
	var data = root.get_node("Data")
	var scenes: Dictionary = data.CAVE_SCENES.duplicate()
	scenes.merge(data.SPECIAL_CAVE_SCENES)
	var rules: = {}
	for id in scenes:
		var cave = scenes[id].instantiate()
		cave.updateUsedTileCoords()
		rules[id] = {
			"tiles": cave.tileCoords.map(func(c): return [int(c.x), int(c.y)]),
			"biome": cave.biome, "minLayer": cave.minLayer, "maxCount": cave.maxCount,
			"minRelativeDepth": cave.minRelativeDepth, "maxRelativeDepth": cave.maxRelativeDepth,
		}
		cave.free()
	return rules


func _one(i: int) -> void:
	var grids: = []
	for _g in 3:
		grids.append(_in.get_buffer(_h * _w))
	var md = load("res://content/map/MapData.tscn").instantiate()
	for j in _h:
		for x in _w:
			var k: = j * _w + x
			var b: int = grids[0][k]
			if b >= 128:
				continue
			var c: = Vector2i(_x0 + x, _y0 + j)
			md.set_biomev(c, b)
			var hd: int = grids[1][k]
			if hd < 128:
				md.set_hardnessv(c, hd)
			var r: int = grids[2][k]
			if r < 128:
				md.set_resourcev(c, r)

	root.get_node("Level").levelSeed = _seeds[i]
	_map_script.generateChamberPlacements(md)
	var biomes: Array[String] = _map_script.generateBiomes()
	var caves: Dictionary = _map_script.generateCaves(md, biomes)
	var out: = {}
	for id in caves:
		out[id] = caves[id].map(func(c): return [int(c.x), int(c.y)])
	_out.store_line(JSON.stringify({"i": i, "biomes": biomes.slice(0, 16), "caves": out}))
	md.free()
