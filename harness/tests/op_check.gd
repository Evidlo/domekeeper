extends SceneTree
# Prints archetype fields after the runner's --op handling, for checking int truncation.
func _process(_d):
	var r = load("res://runner.gd").new()
	var arch = r.make_archetype({"archetype": "regular-medium", "set": [], "op": [
		"tileCount*=1.15", "width*=1.09", "depth*=1.18", "biome_size_multiplier*=1.075",
		"max_tile_count_deviation+=0.15", "depth*=1.4", "width*=1.3", "gadget_first_depth*=1.5",
		"viability_large_noise=res://content/map/generation/noises/viability_maze.tres"]})
	for k in ["tileCount", "width", "depth", "biome_size_multiplier", "max_tile_count_deviation", "gadget_first_depth", "viability_large_noise"]:
		print(k, " = ", arch.get(k), "  ", type_string(typeof(arch.get(k))))
	quit()
	return true
