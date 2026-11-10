extends SceneTree

# Button icons: the carryable items as they lie in the mine, drawn with the game palette.
#
#   --out=<dir>   writes <dir>/<name>.png for every entry of ICONS (transparent background)
# Relic switches have no carryable item; scripts/make_icons.py crops theirs from a render.

const ICONS: = {
	"iron": "res://content/drop/iron/iron_smol.png",
	"water": "res://content/drop/water/water_smol.png",
	"cobalt": "res://content/drop/sand/sand_smol.png",
	"supplement": "res://content/drop/powercore/core.png",
	"gadget": "res://content/drop/gadget/gadget.png",
	"relic": "res://content/drop/relic/relic.png",
}
const TARGET_PX: = 56  # each icon is scaled by the largest whole factor that fits this
const CELL: = 64
const WARMUP_FRAMES: = 10
const RENDER_FRAMES: = 10

var _frames: = 0
var _vp: SubViewport


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == WARMUP_FRAMES:
		_setup()
	elif _frames == WARMUP_FRAMES + RENDER_FRAMES:
		_save()
		quit()
	return false


func _setup() -> void:
	root.get_node("Style").setPalette("palette_1_1")
	_vp = SubViewport.new()
	_vp.size = Vector2i(CELL * ICONS.size(), CELL)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(_vp)
	var k: = 0
	for name in ICONS:
		var s: = Sprite2D.new()
		s.texture = load(ICONS[name])
		var f: = _factor(s.texture)
		s.scale = Vector2(f, f)
		s.position = Vector2(k * CELL + CELL / 2, CELL / 2)
		_vp.add_child(s)
		root.get_node("Style").init(s)
		k += 1


static func _factor(tex: Texture2D) -> int:
	return maxi(1, TARGET_PX / maxi(tex.get_width(), tex.get_height()))


func _save() -> void:
	var out: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var img: Image = _vp.get_texture().get_image()
	var k: = 0
	for name in ICONS:
		var tex: Texture2D = load(ICONS[name])
		var size: Vector2i = tex.get_size() * _factor(tex)
		var corner: = Vector2i(k * CELL + (CELL - size.x) / 2, (CELL - size.y) / 2)
		img.get_region(Rect2i(corner, size)).save_png(out.path_join(name + ".png"))
		print("ICON ", name, " ", size)
		k += 1
