extends SceneTree

# Headless batch runner around the game's own TileDataGenerator.
# Reproduces the seed/retry policy of res://stages/landing/LandingStage.gd.
#
# Usage:
#   godot --headless --path harness --script res://runner.gd -- \
#       --archetype=assignment-default --seeds=seeds.txt --out=prefix \
#       [--set=powercores:3 --set=relics:1] [--op=width*=1.3 --op=max_tile_count_deviation+=0.15]
#
# Output:
#   <prefix>.bin    header + per map 3 int8 grids (biome, hardness, resource), -1 = empty
#   <prefix>.jsonl  one metadata line per map, same order as the grids

const SEED_OFFSET_MULTIPLIER: int = 123
const MAX_ATTEMPTS: int = 15
const MIN_MINEABLE_TILES: int = 300

var TDG: GDScript
var MAPDATA: GDScript

var _started: = false


func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	run()
	quit()
	return true


func parse_args() -> Dictionary:
	var opts: = {"archetype": "assignment-default", "seeds": "", "out": "out", "set": [], "op": []}
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		if kv[0] == "set" or kv[0] == "op":
			opts[kv[0]].append(kv[1])
		else:
			opts[kv[0]] = kv[1]
	return opts


func make_archetype(opts: Dictionary) -> Resource:
	var arch: Resource = load("res://content/map/generation/archetypes/%s.tres" % opts["archetype"]).duplicate()
	for s in opts["set"]:
		var kv: PackedStringArray = s.split(":", true, 1)
		var current = arch.get(kv[0])
		var value = str_to_var(kv[1])
		arch.set(kv[0], type_convert(value, typeof(current)))
	# --op=key*=v / key+=v / key=v, applied in order with the same untyped arithmetic
	# as GameWorld.prepareLevelStart and PropertyChange; the property's declared type
	# performs any conversion on assignment.
	for s in opts["op"]:
		var op: = "="
		for candidate in ["*=", "+=", "="]:
			if s.find(candidate) > 0:
				op = candidate
				break
		var kv: PackedStringArray = s.split(op, true, 1)
		var key: = kv[0].strip_edges()
		var raw: = kv[1].strip_edges()
		var value = load(raw) if raw.begins_with("res://") else str_to_var(raw)
		var current = arch.get(key)
		match op:
			"*=":
				arch.set(key, current * value)
			"+=":
				arch.set(key, current + value)
			_:
				arch.set(key, value)
	return arch


func make_generator() -> Node2D:
	var gen = TDG.new()
	var md = MAPDATA.new()
	md.name = "MapData"
	while md.get_layers_count() < 3:
		md.add_layer(-1)
	gen.add_child(md)
	gen._mapData = md
	return gen


func layer_value(md, layer: int, cell: Vector2i) -> int:
	match layer:
		0:
			return md.get_biomev(cell)
		1:
			return md.get_hardnessv(cell)
		_:
			return md.get_resourcev(cell)


func run() -> void:
	TDG = load("res://content/map/generation/TileDataGenerator.gd")
	MAPDATA = load("res://content/map/MapData.gd")
	var opts: = parse_args()
	var seeds: = PackedInt64Array()
	var sf: = FileAccess.open(opts["seeds"], FileAccess.READ)
	while not sf.eof_reached():
		var line: = sf.get_line().strip_edges()
		if line != "":
			seeds.append(int(line))
	sf.close()

	var proto: = make_archetype(opts)
	var x0: int = -(proto.width + 2)
	var x1: int = proto.width + 2
	var y0: int = -3
	var y1: int = proto.depth * 2 + 2
	var gw: int = x1 - x0
	var gh: int = y1 - y0

	var bin: = FileAccess.open(opts["out"] + ".bin", FileAccess.WRITE)
	var meta: = FileAccess.open(opts["out"] + ".jsonl", FileAccess.WRITE)
	bin.store_buffer("DKMG".to_ascii_buffer())
	for v in [1, x0, x1, y0, y1]:
		bin.store_32(v)

	for level_seed in seeds:
		var t0: = Time.get_ticks_usec()
		var arch: = make_archetype(opts)
		var seed_offset: = 0
		var attempts: = 0
		var gen = null
		var ok: = false
		var reports: = []
		while true:
			var gen_seed: int = level_seed + seed_offset * SEED_OFFSET_MULTIPLIER
			seed_offset += 1
			attempts += 1
			gen = make_generator()
			gen.init(arch, gen_seed, "team1")
			gen.generate()
			reports.append(gen.report)
			ok = gen.finishedSuccessful and gen.getMineableTileCount() >= MIN_MINEABLE_TILES
			if ok:
				break
			gen.free()
			gen = null
			seed_offset += 1
			if seed_offset >= MAX_ATTEMPTS:
				break
			elif seed_offset >= floor(MAX_ATTEMPTS * 0.8):
				arch.tileCount = 0

		var oob: = 0
		for layer in 3:
			var grid: = PackedByteArray()
			grid.resize(gw * gh)
			grid.fill(255)
			if gen != null:
				var md = gen._mapData
				for cell: Vector2i in md.get_used_cells(layer):
					if cell.x < x0 or cell.x >= x1 or cell.y < y0 or cell.y >= y1:
						oob += 1
						continue
					grid[(cell.y - y0) * gw + (cell.x - x0)] = layer_value(md, layer, cell) & 255
			bin.store_buffer(grid)

		meta.store_line(JSON.stringify({
			"level_seed": level_seed,
			"gen_seed": gen.gen_seed if gen != null else -1,
			"attempts": attempts,
			"ok": ok,
			"final_tile_count_target": arch.tileCount,
			"oob_cells": oob,
			"ms": (Time.get_ticks_usec() - t0) / 1000.0,
			"reports": reports,
		}))
		if gen != null:
			gen.free()

	bin.close()
	meta.close()
