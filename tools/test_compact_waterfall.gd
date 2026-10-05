extends SceneTree
## Fixture-only spill/impact checks; Forward+ additionally checks real motion.

const Fall = preload("res://scripts/prototypes/ember_compact_waterfall.gd")
const Builder = preload("res://tools/build_compact_waterfall_study.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Study = preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source := Builder.fixture()
	assert(source.validation_errors().is_empty())
	var original := source.working_copy()
	var field := Fall.new()
	field.build(source)
	assert(field.info.direction == Vector2.UP and is_equal_approx(field.info.top - field.info.bottom, 24.0))
	assert(field.tiles.size() <= 2 and field.state_texture != null)
	var expected_vertices := 0
	for key: Vector2i in field.tiles:
		var batch: Dictionary = field.tiles[key]
		expected_vertices += batch.vertices.size()
		var flat := MeshBuilder.build_tile(source, key.x * 64, key.y * 64, 64, 2, true)
		var spill := MeshBuilder.build_tile(source, key.x * 64, key.y * 64, 64, 2, true, PackedVector4Array(), batch)
		assert(flat.collision_faces == spill.collision_faces, "fall must not change the physical ground")
		var count := 0
		for uv in spill.water.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
			if uv.x < -3.0: count += 1
		assert(count == batch.vertices.size(), "fall must bypass flat-surface stitching")
	assert(expected_vertices > 1000 and expected_vertices < 4000)
	field.advance(0.8, 1.0, 1.0, 0.75)
	# Dummy headless rendering does not expose texture updates; inspect the
	# uploaded CPU field here, and exercise the real texture in Forward+ below.
	var image_a := field._image()
	field.advance(2.4, 1.0, 1.0, 0.75)
	var image_b := field._image()
	assert(image_a.get_data() != image_b.get_data(), "impact arcs must travel")
	var highest := 0.0
	var foamy := 0
	var trail := 0
	var sample := Vector2.ZERO
	for y in image_b.get_height():
		for x in image_b.get_width():
			var color := image_b.get_pixel(x, y)
			var cell := field.bounds.position + Vector2i(x, y)
			var index := source.column_index(cell.x, cell.y)
			var lower_wet := source.water_materials[index] > 0 and source.water_levels[index] == 16 and source.heights[index] < 16
			assert((color.a > 0.0) == lower_wet, "impact must stay on the lower wet footprint")
			if color.r > highest:
				highest = color.r
				sample = Vector2(cell) + Vector2(0.5, 0.5)
			if color.g > 0.05: foamy += 1
			if color.a > 0.0 and color.b < 4.0: trail += 1
	assert(highest > 0.25 and highest < 1.0 and foamy > 50 and trail > 100)
	assert(is_equal_approx(field.displacement(sample), highest))
	field.advance(1.2, 1.0, 2.0, 0.75)
	assert(field._image().get_data() == image_b.get_data(), "speed must scale the same lifecycle")
	field.advance(2.4, 0.0, 1.0, 0.75)
	var disabled := field._image()
	for p in field._pixels:
		var color := disabled.get_pixel(p % field.bounds.size.x, p / field.bounds.size.x)
		assert(color.r == 0.0 and color.g == 0.0 and color.b == 8.0)
	field.advance(2.4, 1.0, 1.0, 0.0)
	var foam_off := field._image()
	for p in field._pixels:
		var color := foam_off.get_pixel(p % field.bounds.size.x, p / field.bounds.size.x)
		assert(color.g == 0.0 and color.b == 8.0)
	assert(field.displacement(sample) > 0.25, "foam off must preserve the impact wave")
	var quiet := source.working_copy()
	quiet.water_flow.fill(Vector2.ZERO)
	field.build(quiet)
	assert(field.info.is_empty() and field.tiles.is_empty() and field.bounds == Rect2i() and field.state_texture == null)
	quiet.water_flow.fill(Vector2.DOWN)
	field.build(quiet)
	assert(field.info.is_empty(), "an uphill current must not fall")
	field.build(source)
	field.advance(2.4, 1.0, 1.0, 0.75)
	assert(field._image().get_data() == image_b.get_data(), "rebuild must clear stale state")
	assert(source.same_terrain_geometry(original) and source.water_flow == original.water_flow)

	var scene := Node3D.new()
	root.add_child(scene)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.hydrate_legacy_regions = false
	map.compact_terrain = source
	map.compact_water_mesh_step = 2
	map.compact_water_visual_material = load("res://materials/ember_compact_sky_reflection_study.tres")
	var look := Node3D.new()
	look.name = "Look"
	map.add_child(look)
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.25, 0.35, 0.4)
	look.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -25, 0)
	look.add_child(sun)
	scene.add_child(map)
	var study := Study.new()
	study.wave_height_voxels = 0.0
	study.river_crest_whiteness = 0.0
	study.sea_swash_height = 0.0
	study.sky_reflection = 0.0
	scene.add_child(study)
	var projection: EmberTerrainPilotProjection
	for frame in 240:
		await process_frame
		projection = map.get("_visual_surface_projection")
		if study.get("_prepared") and projection.pending_tile_count() == 0: break
	assert(study.get("_prepared") and projection.pending_tile_count() == 0)
	var shared: RefCounted = study.get("_waterfall")
	assert(not shared.info.is_empty() and projection.get("_waterfall") == shared)
	var material: ShaderMaterial = study.get("_material")
	material.set_shader_parameter("preview_time", 2.4)
	study.refresh_water_settings()
	assert(material.get_shader_parameter("waterfall_state") == shared.state_texture)
	var revision := projection.column_revision()
	var builds: int = study.get("_fields_build_count")
	projection.position = Vector3(11, 3, -7)
	var queried := projection.water_surface_sample(projection.to_global(Vector3(sample.x, 0, sample.y)))
	assert(queried.wet)
	assert(is_equal_approx(queried.position.y, 3.0 + 16.085 + study.water_level_offset_voxels + shared.displacement(sample)))
	var upper := projection.water_surface_sample(projection.to_global(Vector3(60.5, 0, 120.5)))
	assert(is_equal_approx(upper.position.y, 3.0 + 40.085 + study.water_level_offset_voxels))
	projection.position = Vector3.ZERO
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(113, 57, 19)
		camera.look_at(Vector3(60, 26, 84))
		camera.make_current()
		var output := "user://ember-tests/waterfall-fixture"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		await process_frame
		await RenderingServer.frame_post_draw
		var first := root.get_texture().get_image()
		first.save_png(output + "/moving-a.png")
		material.set_shader_parameter("preview_time", 3.9)
		study.refresh_water_settings()
		await process_frame
		await RenderingServer.frame_post_draw
		var second := root.get_texture().get_image()
		second.save_png(output + "/moving-b.png")
		var moving := _changed(first, second)
		assert(moving > 500, "real falling sheet and impact must move with all other waves disabled")
		study.waterfall_strength = 0.0
		study.refresh_water_settings()
		await process_frame
		await RenderingServer.frame_post_draw
		var off := root.get_texture().get_image()
		off.save_png(output + "/disabled.png")
		assert(_changed(second, off) > 2000, "strength zero must remove the actual rendered fall/impact")
		print("PASS WATERFALL Forward+: real sheet/impact motion pixels=", moving, ", off removes fall")
	assert(study.get("_fields_build_count") == builds and projection.column_revision() == revision and projection.pending_tile_count() == 0)
	assert(source.same_terrain_geometry(original) and source.water_flow == original.water_flow)
	projection.set_waterfall(null)
	for frame in 120:
		await process_frame
		if projection.pending_tile_count() == 0: break
	assert(projection.get("_waterfall") == null and float(material.get_shader_parameter("waterfall_available")) == 0.0)
	for mesh in projection.find_children("Water", "MeshInstance3D", true, false):
		for uv in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]: assert(uv.x >= -3.0)
	print("PASS WATERFALL fixture: flow/drop detection, unchanged collision/source, lifecycle/masks/off/rebuild, shared material/query, no animation remesh")
	quit()

func _changed(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.035: count += 1
	return count
