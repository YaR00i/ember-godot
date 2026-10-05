extends SceneTree
## Same scene, camera and renderer for visual comparison of 8px and 16px art.

const SCENE_PATH := "res://scenes/new_landscape4.tscn"
const SHADER_PATH := "res://shaders/ember_compact_terrain_textured.gdshader"
const OUTPUT := "res://docs/art/references"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		printerr("FAIL: scene missing")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for frame in 240:
		await process_frame
		var projection := _find_projection(scene)
		if projection != null and projection.pending_tile_count() == 0 and frame > 24:
			break
	var terrain := _find_projection(scene)
	if terrain == null or terrain.pending_tile_count() != 0:
		printerr("FAIL: terrain did not build")
		quit(1)
		return
	if "--production" in OS.get_cmdline_user_args():
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var output := "%s/compact-terrain-16x16-active-godot-20260929.png" % OUTPUT
		var error := root.get_texture().get_image().save_png(output)
		if error != OK:
			printerr("FAIL: production capture ", error_string(error))
			quit(1)
			return
		print("PASS Forward+ production capture: ", ProjectSettings.globalize_path(output))
		quit()
		return
	var material := terrain._ground_material as ShaderMaterial
	var lookup: Texture2D = material.get_shader_parameter("role_lookup")
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(SHADER_PATH)
	material.shader = shader
	material.set_shader_parameter("role_lookup", lookup)
	for size in [8, 16]:
		var atlas := Image.create(16, 4096, false, Image.FORMAT_RGBA8)
		var images := {}
		for role in ["soil", "grass", "sand", "stone"]:
			var image := Image.new()
			var path := "res://assets/terrain_textures/drafts/%d/%s.png" % [size, role]
			if image.load(path) != OK or image.get_width() != size or image.get_height() != size:
				printerr("FAIL: invalid draft: ", path)
				quit(1)
				return
			if size == 8: image.resize(16, 16, Image.INTERPOLATE_NEAREST)
			images[role] = image
		for index in terrain.document.palette_surface_roles.size():
			var role: String = terrain.document.palette_surface_roles[index]
			if images.has(role): atlas.blit_rect(images[role], Rect2i(0, 0, 16, 16), Vector2i(0, index * 16))
		material.set_shader_parameter("pattern_atlas", ImageTexture.create_from_image(atlas))
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var output := "%s/compact-terrain-%dx%d-godot-20260929.png" % [OUTPUT, size, size]
		var error := root.get_texture().get_image().save_png(output)
		if error != OK:
			printerr("FAIL: capture ", output, " ", error_string(error))
			quit(1)
			return
		print("PASS Forward+ draft capture: ", ProjectSettings.globalize_path(output))
	quit()


func _find_projection(node: Node) -> EmberTerrainPilotProjection:
	if node is EmberTerrainPilotProjection:
		return node as EmberTerrainPilotProjection
	for child in node.get_children():
		var found := _find_projection(child)
		if found != null:
			return found
	return null
