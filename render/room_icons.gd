extends SceneTree

# Room button icons: the item (or machine) each room holds, cut out of the game's own scenes
# so palette and "unstyled" art come out as in game.
#
#   --out=<dir>   writes <dir>/room_<id>.png for every entry of ROOMS
#   --only=a,b    restrict to these ids
# Cobalt, water and iron-tree rooms use the resource icons from icons.gd instead.
#
# Each scene is instantiated whole (so its scripts and styling run), then everything except
# the chosen node is made invisible and the visible pixels are cropped.

const ROOMS: = {
	"mushroom": ["res://content/caves/mushroomcave/MushroomCave.tscn", "Sprites/Sprite6/Mushroom"],
	"bomb": ["res://content/caves/bombcave/CaveBomb.tscn", "Sprite2D"],
	"helmet": ["res://content/caves/helmetextensioncave/HelmetCave.tscn", "Sprite2D"],
	"seed": ["res://content/drop/seed/Seed.tscn", "Sprite2D"],
	"seed_assignment": ["res://content/drop/seed/Seed.tscn", "Sprite2D"],
	"drone": ["res://content/caves/dronecave/DroneCave.tscn", "Drone"],
	"scanner": ["res://content/caves/scannercave/ScannerCave.tscn", "Background/Scanner"],
	"portal": ["res://content/caves/portalcave/PortalCave.tscn", "Sprites/Sprite"],
	"nest": ["res://content/drop/egg/Egg.tscn", "Sprite2D"],
}
const TARGET_PX: = 56  # icons are enlarged by the largest whole factor that fits this
const CELL: = 400
const WARMUP_FRAMES: = 10
const RENDER_FRAMES: = 10

var _frames: = 0
var _vp: SubViewport
var _ids: = []


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == WARMUP_FRAMES:
		_setup()
	elif _frames == WARMUP_FRAMES + RENDER_FRAMES:
		_save()
		quit()
	return false


func _arg(name: String, default: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="):
			return arg.trim_prefix("--" + name + "=")
	return default


func _setup() -> void:
	var only: = _arg("only", "")
	_ids = ROOMS.keys().filter(func(id): return only == "" or id in only.split(","))
	root.get_node("Style").setPalette("palette_1_1")
	_vp = SubViewport.new()
	_vp.size = Vector2i(CELL * _ids.size(), CELL)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(_vp)
	var k: = 0
	for id in _ids:
		var holder: = Node2D.new()
		holder.position = Vector2(k * CELL + CELL / 2, CELL / 2)
		_vp.add_child(holder)
		var scene: Node = load(ROOMS[id][0]).instantiate()
		var keep: Node = scene.get_node(ROOMS[id][1])
		if scene is RigidBody2D:
			# carryable drops crash outside a level: take their sprite alone, without scripts
			keep.get_parent().remove_child(keep)
			scene.free()
			keep.position = Vector2.ZERO
			holder.add_child(keep)
			_isolate(keep, keep)
		else:
			holder.add_child(scene)
			_isolate(scene, keep)
		k += 1


# Hide every canvas item except `keep` (its ancestors stay visible but draw nothing).
func _isolate(scene: Node, keep: Node) -> void:
	var stack: Array = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not n is CanvasItem or n == keep:
			continue
		if n.is_ancestor_of(keep):
			n.self_modulate.a = 0.0
		else:
			n.visible = false
	for c in keep.get_children():
		if c is CanvasItem:
			c.visible = false
	keep.visible = true
	if keep is AnimatedSprite2D:
		var sf: SpriteFrames = keep.sprite_frames
		if sf.get_frame_count(keep.animation) == 0:
			keep.animation = Array(sf.get_animation_names()).filter(
				func(a): return sf.get_frame_count(a) > 0).front()
		keep.stop()
		keep.frame = 0


func _save() -> void:
	var out: = _arg("out", ".")
	var img: Image = _vp.get_texture().get_image()
	var k: = 0
	for id in _ids:
		var cell: Image = img.get_region(Rect2i(k * CELL, 0, CELL, CELL))
		var used: Rect2i = cell.get_used_rect()
		var icon: Image = cell.get_region(used)
		var f: = maxi(1, TARGET_PX / maxi(1, maxi(used.size.x, used.size.y)))
		icon.resize(used.size.x * f, used.size.y * f, Image.INTERPOLATE_NEAREST)
		icon.save_png(out.path_join("room_" + id + ".png"))
		print("ICON ", id, " ", used.size, " x", f)
		k += 1
