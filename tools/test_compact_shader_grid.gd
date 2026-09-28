extends SceneTree
## Hover must change only editor overlay state, never terrain or grid geometry.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const WorldEditor = preload("res://addons/ember_import/ember_world_editor.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var visible_forward := DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "forward_plus"
	if visible_forward:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1024, 768))
		root.size = Vector2i(1024, 768)
	var terrain := TerrainResource.new()
	terrain.width = 128
	terrain.depth = 128
	terrain.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.GREEN])
	var columns := terrain.width * terrain.depth
	terrain.heights.resize(columns)
	terrain.heights.fill(8)
	terrain.top_materials.resize(columns)
	terrain.top_materials.fill(2)
	terrain.base_materials.resize(columns)
	terrain.base_materials.fill(1)
	terrain.cap_depths.resize(columns)
	terrain.cap_depths.fill(4)
	terrain.water_levels.resize(columns)
	terrain.water_materials.resize(columns)
	for z in range(48, 80):
		for x in range(48, 80):
			terrain.heights[terrain.column_index(x, z)] = 12
	assert(ResourceSaver.save(terrain, "user://compact_shader_grid_fixture.res") == OK)
	terrain.resource_path = "user://compact_shader_grid_fixture.res"
	var heights_before := terrain.heights.duplicate()
	var map := EmberMapLoader.new()
	map.map_id = "compact_shader_grid_fixture"
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(8, 8)
	map.compact_terrain = terrain
	root.add_child(map)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	while projection.pending_tile_count() > 0:
		await process_frame
	var ground := projection.get_node("TerrainTile_0_0/Ground") as MeshInstance3D
	var ground_mesh := ground.mesh
	var camera: Camera3D
	var base_draw_calls := -1
	if visible_forward:
		camera = Camera3D.new()
		camera.position = Vector3(64, 110, 130)
		camera.far = 500.0
		root.add_child(camera)
		camera.look_at(Vector3(64, 10, 64))
		camera.make_current()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		base_draw_calls = RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var editor := WorldEditor.new()
	map.add_child(editor)
	var undo := UndoRedo.new()
	editor.configure(null, undo)
	editor.build_toolbar()
	editor.build_sidebar()
	editor.scene = map
	editor.map = map
	editor._target_changed(0)
	editor.active = true
	var initial_children := projection.get_child_count(true)
	editor.hover = {"cell": Vector2i(32, 32)}
	editor._update_overlay()
	assert(ground.material_overlay is ShaderMaterial, "Hover needs a shader on the existing ground mesh")
	assert(projection.get_child_count(true) == initial_children, "Hover added grid nodes")
	var overlay := ground.material_overlay
	for cell in [Vector2i(40, 32), Vector2i(88, 88), Vector2i(32, 32)]:
		editor.hover = {"cell": cell}
		editor._update_overlay()
		assert(projection.get_child_count(true) == initial_children)
		assert(ground.mesh == ground_mesh)
		assert(terrain.heights == heights_before and projection.document.heights == heights_before)
	assert(ground.material_overlay == overlay)
	if visible_forward:
		editor.hover = {"cell": Vector2i(64, 64)}
		editor._update_overlay()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var overlay_draw_calls := RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var image_path := "user://compact_shader_grid_visible.png"
		assert(root.get_texture().get_image().save_png(image_path) == OK)
		print("COMPACT_SHADER_GRID base_draw_calls=", base_draw_calls, " overlay_draw_calls=", overlay_draw_calls, " image=", ProjectSettings.globalize_path(image_path))
		camera.queue_free()
	editor.hover.clear()
	editor._update_overlay()
	assert(ground.material_overlay == null)
	editor.hover = {"cell": Vector2i(32, 32)}
	editor._update_overlay()
	assert(ground.material_overlay == overlay)
	editor._deactivate()
	assert(ground.material_overlay == null)
	print("COMPACT_SHADER_GRID hover_nodes=0 mesh_rebuilds=0 terrain=unchanged exit_cleared=ok")
	editor.toolbar.free()
	editor.sidebar.free()
	map.queue_free()
	undo.free()
	await process_frame
	quit()
