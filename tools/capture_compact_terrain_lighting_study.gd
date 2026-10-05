extends SceneTree
## Forward+ visual comparison at the same map and camera settings.

const SCENES := [
	["res://scenes/new_landscape4.tscn", "compact-light-before-20260929.png", false],
	["res://scenes/compact_terrain_lighting_study.tscn", "compact-light-study-20260929.png", false],
	["res://scenes/new_landscape4.tscn", "compact-material-variants-20260929.png", true],
]
const OUTPUT := "res://docs/art/references"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var fixed_camera: Camera3D
	for item in SCENES:
		var packed := load(item[0]) as PackedScene
		if packed == null:
			printerr("FAIL lighting capture: missing ", item[0])
			quit(1)
			return
		var scene := packed.instantiate()
		root.add_child(scene)
		var ready := false
		for frame in 320:
			await process_frame
			var projection := _find_projection(scene)
			if projection != null and projection.pending_tile_count() == 0 and frame > 25:
				ready = true
				break
		if not ready:
			printerr("FAIL lighting capture: terrain did not finish ", item[0])
			quit(1)
			return
		if item[2]:
			var projection := _find_projection(scene)
			var candidate := projection.document.working_copy()
			var autumn := candidate.palette.size()
			if candidate.palette_material_ids.is_empty(): candidate.palette_material_ids.resize(autumn)
			candidate.palette.append(candidate.palette[2])
			candidate.palette_surface_roles.append("grass")
			candidate.palette_material_ids.append("grass_autumn")
			for z in candidate.depth:
				for x in candidate.width:
					var index := candidate.column_index(x, z)
					if candidate.top_materials[index] == 2 and ((x / 64 + z / 64) % 2 == 0):
						candidate.top_materials[index] = autumn
			if not projection.open_document(candidate):
				printerr("FAIL lighting capture: variant preview rejected ", candidate.validation_errors())
				quit(1)
				return
			while projection.pending_tile_count() > 0: await process_frame
		for frame in 12:
			await process_frame
		if fixed_camera != null:
			fixed_camera.make_current()
			await process_frame
		var source_camera := root.get_camera_3d()
		if source_camera == null:
			printerr("FAIL lighting capture: no active camera")
			quit(1)
			return
		if fixed_camera == null:
			fixed_camera = Camera3D.new()
			root.add_child(fixed_camera)
			fixed_camera.global_transform = source_camera.global_transform
			fixed_camera.fov = source_camera.fov
			fixed_camera.far = source_camera.far
		await RenderingServer.frame_post_draw
		var output := "%s/%s" % [OUTPUT, item[1]]
		if root.get_texture().get_image().save_png(output) != OK:
			printerr("FAIL lighting capture: PNG ", output)
			quit(1)
			return
		print("PASS Forward+ lighting capture: ", ProjectSettings.globalize_path(output))
		root.remove_child(scene)
		scene.queue_free()
		await process_frame
	quit()


func _find_projection(node: Node) -> EmberTerrainPilotProjection:
	if node is EmberTerrainPilotProjection: return node as EmberTerrainPilotProjection
	for child in node.get_children():
		var found := _find_projection(child)
		if found != null: return found
	return null
