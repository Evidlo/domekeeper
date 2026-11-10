extends RefCounted

# Game-mode state that Map.generateBiomes / Map.generateCaves read, set up the way
# GameWorld.prepareLevelStart does for a fresh save.
#
# opts keys (all strings):
#   mode        CONST.MODE_* id: relichunt, assignments, coop, prestige (default relichunt)
#   mapsize     map archetype id, stored as the loadout's mapsize (default regular-small)
#   assignment  guild assignment id; its world modifiers are applied
#   modifiers   comma-separated world modifier ids (e.g. worldmodifiertreefarms)
#   pets        "unlockable" (fresh save) or "done" (every pet unlocked, so no Relic Hunt nest)
#
# Holiday caves (Halloween, Lunar New Year, April Fools) are switched off.


static func apply(root: Node, opts: Dictionary) -> void:
	var data = root.get_node("Data")
	var game_world = root.get_node("GameWorld")
	var level = root.get_node("Level")
	data.reset()
	data.apply("map.revealdistance", 1)
	data.apply("map.tileHealthMultiplierPerLayer", 2.1)

	game_world.isHalloween = false
	game_world.isAprilFools = false
	game_world.isLunarNewYear = false
	game_world.useCustomCaveOrder = false
	# GameWorld fills unlockablePets at run start (pet1 is always on the list until found)
	game_world.unlockedPets = []
	game_world.unlockablePets = ["pet1"] if opts.get("pets", "unlockable") == "unlockable" else []

	var loadout = load("res://stages/loadout/data/Loadout.gd").empty()
	loadout.modeId = opts.get("mode", "relichunt")
	loadout.modeConfig = {"mapsize": opts.get("mapsize", "regular-small")}
	level.loadout = loadout

	var modifier_ids: = []
	if opts.get("assignment", "") != "":
		var wm = data.assignments[opts["assignment"]].worldModifiers
		modifier_ids.append_array([wm] if wm is String else wm)
	modifier_ids.append_array(opts.get("modifiers", "").split(",", false))
	for modifier_id in modifier_ids:
		if modifier_id == "":
			continue
		for change in data.worldModifiers[modifier_id].get("propertychanges", []):
			if change.keyClass in ["world", "resourcemodifiers"]:
				data.applyPropertyChange(change)


static func describe(root: Node) -> String:
	var data = root.get_node("Data")
	var game_world = root.get_node("GameWorld")
	return "mode=%s pet_unlockable=%s allowed_caves=%s max_per_biome=%s min_dist=%s" % [
		root.get_node("Level").loadout.modeId, game_world.isPetUnlockable(),
		data.ofOr("world.allowed_caves", "default"), data.ofOr("world.max_caves_per_biome", 1),
		data.ofOr("world.min_cave_distance_to_center", 10)]
