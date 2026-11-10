extends SceneTree
# Boot probe: report whether the game's autoloads initialised inside the real binary.
var frames: = 0
func _process(_d):
	frames += 1
	if frames == 30:
		print("PROBE user dir: ", OS.get_user_data_dir())
		print("PROBE sentry dsn: '", ProjectSettings.get_setting("sentry/options/dsn", "?"), "'")
		print("PROBE autoloads: ", root.get_children().map(func(c): return c.name))
		print("PROBE assignments: ", root.get_node("Data").assignments.size())
		print("PROBE palette: ", root.get_node("Style").paletteId)
		print("PROBE adapter: ", RenderingServer.get_video_adapter_name())
		quit()
	return false
