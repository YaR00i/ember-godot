extends SceneTree
## Explicit first-time content creation; never overwrite an authored Surface.
const Layout = preload("res://tools/world_canvas_layout.gd")

func _init() -> void:
	if "--write" not in OS.get_cmdline_user_args():
		printerr("Use -- --write for first-time creation. Existing content is never overwritten.")
		quit(1)
		return
	if FileAccess.file_exists(Layout.SOURCE_PATH):
		printerr("Refusing to overwrite existing authored Surface: ", Layout.SOURCE_PATH)
		quit(1)
		return
	var started := Time.get_ticks_usec()
	var surface := Layout.make_surface()
	var errors := surface.validation_errors()
	if not errors.is_empty():
		printerr(errors)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(Layout.SOURCE_PATH.get_base_dir())
	var result := ResourceSaver.save(surface, Layout.SOURCE_PATH)
	if result != OK:
		printerr("Surface publication failed: ", result)
		quit(1)
		return
	print("PASS WORLD_CANVAS_CREATED ", Layout.SOURCE_PATH, " grid=", surface.grid_size(), " elapsed_ms=", (Time.get_ticks_usec()-started)/1000)
	quit()
