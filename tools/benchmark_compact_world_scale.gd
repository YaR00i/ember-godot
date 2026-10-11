extends SceneTree
## Disposable filled-world measurement. No authored map or editor state is written.
## Run build headless, then cold/warm in separate Forward+ processes in a QA copy:
## --script res://tools/benchmark_compact_world_scale.gd -- --phase=build|cold|warm|play
## --out=user://ember-tests/world-scale-256-<unique-run-id>

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const TerrainMath = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const CELLS := 4096
const GROUP := 8
const SAMPLES := 180
var directory := ""
var phase := ""
var controller: Node
var projection: Node3D
var camera: Camera3D
var observer: Node3D
var rows: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): directory = argument.trim_prefix("--out=")
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
	if not directory.begins_with("user://ember-tests/world-scale-256-") or ".." in directory or phase not in ["build", "cold", "warm", "play"]:
		printerr("Choose a unique user://ember-tests/world-scale-256-* directory and build/cold/warm phase.")
		quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if phase == "build":
		await _build_fixture()
		return
	if DisplayServer.get_name() == "headless":
		printerr("Render measurements require native Forward+."); quit(1); return
	if phase == "cold" and (DirAccess.dir_exists_absolute(directory.path_join("geometry")) or DirAccess.dir_exists_absolute(directory.path_join("water"))):
		printerr("Cold requires empty caches; build a new unique fixture directory."); quit(1); return
	if phase == "warm" and not FileAccess.file_exists(directory.path_join("cold-startup.json")):
		printerr("Warm requires a completed cold preparation in this directory."); quit(1); return
	if phase == "play": await _play_startup()
	else: await _benchmark()

func _play_startup() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var started := Time.get_ticks_msec()
	var source := load(directory.path_join("terrain.res")) as Terrain
	assert(source != null and source.width == CELLS)
	var scene := (load("res://scenes/compact_material_light_study.tscn") as PackedScene).instantiate()
	scene.sandbox_storage_root = directory.path_join("play-save")
	var map := scene.get_node("Map") as EmberMapLoader
	map.compact_terrain = source; map.authored_size_blocks = Vector2i(256, 256)
	var probe := Vector2i(2048, 2900)
	var ground := source.column_value("heights", source.column_index(probe.x, probe.y))
	scene.get_node("Map/Regions/PlayerStart").position = Vector3(probe.x, ground + 16, probe.y)
	root.add_child(scene); current_scene = scene
	projection = map._visual_surface_projection
	projection.runtime_geometry_cache_directory = directory.path_join("geometry")
	controller = scene.get_node("PlanarReflection")
	controller._water_regions = Regions.new()
	controller._region_projection_id = projection.get_instance_id()
	controller._water_regions.cache_directory = directory.path_join("water")
	var deadline := started + 300000
	var saw_cover := false
	while not scene._startup_complete and Time.get_ticks_msec() < deadline:
		saw_cover = saw_cover or scene.get_node_or_null("WorldLoadingScreen") != null
		await process_frame
	assert(scene._startup_complete and saw_cover, "full WorldCanvas startup did not complete under its cover")
	assert(scene._player != null and controller._prepared)
	assert(projection.pending_tile_count() == 0 and projection.pending_physics_chunk_count() == 0 and projection.pending_runtime_lod_count() == 0)
	var stats := {"ready_ms": Time.get_ticks_msec() - started, "geometry": projection.profile_snapshot(),
		"water": controller._water_regions.stats.duplicate(true), "static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"note": "actual WorldCanvas startup barrier, player and physics; native QA fixture, not author acceptance"}
	var player: Node3D = scene._player
	var before := player.global_position
	Input.action_press("move_east")
	for frame in 18: await physics_frame
	Input.action_release("move_east")
	stats.movement = Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	assert(stats.movement > 1.0 and player.global_position.y > ground - 32, "player movement/ground failed after preparation")
	_save("play-startup.json", stats)
	print("WORLD_SCALE_PLAY_READY ", JSON.stringify(stats))
	scene.queue_free(); await process_frame; quit()

func _build_fixture() -> void:
	var path := directory.path_join("terrain.res")
	if FileAccess.file_exists(path):
		printerr("Fixture exists; use another run directory."); quit(1); return
	var started := Time.get_ticks_msec()
	var recipe := TerrainMath.DEFAULTS.duplicate(true)
	recipe.merge({"seed": 7, "profile": "hills", "sea_m": 4.0, "land_m": 3.0,
		"relief_m": 24.0, "feature_m": 36.0, "shore_m": 12.0, "land_fraction": 0.72}, true)
	assert(TerrainMath.parameter_error(recipe).is_empty())
	var creation := Creation.new()
	creation.scene_directory = directory
	creation.terrain_directory = directory
	assert(creation.prepare("scale_fixture", 24, 24, 12), creation.error)
	var source: Terrain = creation.source.duplicate(false)
	source.width = CELLS; source.depth = CELLS; source.height_limit = 512
	source.schema_version = Terrain.SECTION_SCHEMA_VERSION
	source.sections = {}
	for channel in Terrain.Sections.CHANNELS:
		source.set(channel, PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray())
	var sampler := TerrainMath.new()
	sampler.configure(Rect2(0, 0, 256, 256), recipe)
	# The production sampler and its half-metre grouping/quarter-metre rounding.
	# Only fixture assembly bypasses the UI's 96 m per-operation bound.
	for sz in ceili(float(CELLS) / Terrain.Sections.CELLS):
		for sx in ceili(float(CELLS) / Terrain.Sections.CELLS):
			var start := Vector2i(sx, sz) * Terrain.Sections.CELLS
			var part: Terrain = creation.source.duplicate(false)
			part.width = mini(Terrain.Sections.CELLS, CELLS - start.x)
			part.depth = mini(Terrain.Sections.CELLS, CELLS - start.y)
			part.height_limit = source.height_limit
			var heights := PackedInt32Array(); var tops := PackedByteArray()
			var waters := PackedInt32Array(); var colors := PackedByteArray()
			for gz in range(0, part.depth, GROUP):
				var row_h := PackedInt32Array(); var row_t := PackedByteArray()
				var row_w := PackedInt32Array(); var row_c := PackedByteArray()
				for gx in range(0, part.width, GROUP):
					var h := clampi(roundi(sampler.height_m((Vector2(start + Vector2i(gx, gz)) + Vector2.ONE * 4.0) / 16.0) * 4.0) * 4, 4, source.height_limit)
					var sea := 64
					var block_h := PackedInt32Array(); block_h.resize(GROUP); block_h.fill(h)
					var block_t := PackedByteArray(); block_t.resize(GROUP); block_t.fill(3 if h <= sea + 8 else 2)
					var block_w := PackedInt32Array(); block_w.resize(GROUP); block_w.fill(sea if h < sea else 0)
					var block_c := PackedByteArray(); block_c.resize(GROUP); block_c.fill(5 if h < sea else 0)
					row_h.append_array(block_h); row_t.append_array(block_t)
					row_w.append_array(block_w); row_c.append_array(block_c)
				for dz in GROUP:
					heights.append_array(row_h); tops.append_array(row_t)
					waters.append_array(row_w); colors.append_array(row_c)
			part.heights = heights; part.top_materials = tops
			part.water_levels = waters; part.water_materials = colors
			part.base_materials = PackedByteArray(); part.base_materials.resize(heights.size()); part.base_materials.fill(1)
			part.cap_depths = PackedByteArray(); part.cap_depths.resize(heights.size()); part.cap_depths.fill(3)
			source.sections[Vector2i(sx, sz)] = part
		await process_frame
		print("WORLD_SCALE_BUILD row=", sz + 1, "/11 static_bytes=", Performance.get_monitor(Performance.MEMORY_STATIC))
	assert(source.stored_column_count() == CELLS * CELLS)
	assert(source.validation_errors().is_empty(), str(source.validation_errors()))
	assert(ResourceSaver.save(source, path, ResourceSaver.FLAG_COMPRESS) == OK)
	_save("fixture.json", {"metres": 256, "cells": CELLS, "sections": source.sections.size(), "recipe": recipe,
		"build_ms": Time.get_ticks_msec() - started, "source_channel_bytes": CELLS * CELLS * 12})
	print("WORLD_SCALE_BUILD_READY ", ProjectSettings.globalize_path(path))
	quit()

func _benchmark() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var started := Time.get_ticks_msec()
	var source := load(directory.path_join("terrain.res")) as Terrain
	assert(source != null and source.width == CELLS and source.stored_column_count() == CELLS * CELLS)
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	var scene := (load("res://scenes/compact_material_light_study.tscn") as PackedScene).instantiate()
	scene.set_script(null)
	scene.get_node("CanvasLayer").free()
	var map := scene.get_node("Map") as EmberMapLoader
	map.compact_terrain = source
	map.authored_size_blocks = Vector2i(256, 256)
	camera = Camera3D.new(); camera.fov = 55; camera.far = 14000
	scene.add_child(camera)
	observer = Node3D.new(); observer.name = "Player"; scene.add_child(observer)
	var centre := Vector3(CELLS * 0.5, 64, CELLS * 0.5)
	camera.look_at_from_position(centre + Vector3(2200, 4300, 4300), centre)
	camera.make_current()
	root.add_child(scene)
	projection = map._visual_surface_projection
	projection.runtime_geometry_cache_directory = directory.path_join("geometry")
	controller = scene.get_node("PlanarReflection")
	# Install the existing owner with its isolated root before starting its worker.
	controller._water_regions = Regions.new()
	controller._region_projection_id = projection.get_instance_id()
	controller._water_regions.cache_directory = directory.path_join("water")
	var deadline := started + 600000
	var next_progress := started
	var peak_static := 0.0
	while not controller._prepared or projection.pending_tile_count() > 0 or projection.pending_runtime_lod_count() > 0:
		await process_frame
		peak_static = maxf(peak_static, Performance.get_monitor(Performance.MEMORY_STATIC))
		if Time.get_ticks_msec() > next_progress:
			print("WORLD_SCALE_LOADING ms=", Time.get_ticks_msec() - started, " tiles=", projection.pending_tile_count(), " lod=", projection.pending_runtime_lod_count(), " water=", controller._prepared)
			next_progress = Time.get_ticks_msec() + 10000
		if Time.get_ticks_msec() > deadline:
			printerr("World preparation timed out."); quit(1); return
	var startup := {"phase": phase, "ready_ms": Time.get_ticks_msec() - started,
		"peak_static_bytes": peak_static, "geometry": projection.profile_snapshot(),
		"water": controller._water_regions.stats.duplicate(true), "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info().string,
		"resolution": str(root.size), "note": "render harness, player-height camera; not actual F6 hero startup"}
	_save(phase + "-startup.json", startup)
	print("WORLD_SCALE_READY ", JSON.stringify(startup))
	for canvas in controller.find_children("*", "CanvasLayer", true, false): canvas.visible = false
	for viewport: Viewport in [root, controller._floor_viewport, controller._viewport]:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	await _measure("wide_live")
	var probe := Vector2i(2048, 2900)
	var ground := source.column_value("heights", source.column_index(probe.x, probe.y))
	observer.position = Vector3(probe.x, ground + 32, probe.y)
	camera.look_at_from_position(observer.position + Vector3(0, 18, 64), Vector3(2048, ground + 18, 1900))
	await _measure("player_live")
	# Main-camera-only A/B never hides shared nodes or alters physics/reflections.
	# Fixed time avoids animated pixels obscuring incorrect culling.
	controller.set_process(false)
	for target: ShaderMaterial in [controller._material, controller._ground_material, controller._shaft_material]:
		if target != null: target.set_shader_parameter("preview_time", 7.0)
	controller._water_regions.set_water_parameter("preview_time", 7.0)
	controller._water_regions.set_ground_parameter("preview_time", 7.0)
	var occluder_started := Time.get_ticks_msec()
	var count := _add_interior_occluders(source, projection)
	_save(phase + "-occluders.json", {"count": count, "build_ms": Time.get_ticks_msec() - occluder_started, "policy": "16m solid interiors, min height minus 0.5m; main viewport only"})
	print("WORLD_SCALE_OCCLUDERS count=", count)
	for view in ["player", "wide", "shore", "reflection"]:
		if view == "wide": camera.look_at_from_position(centre + Vector3(2200, 4300, 4300), centre)
		if view in ["shore", "reflection"]:
			camera.look_at_from_position(Vector3(2048, 150, 3900), Vector3(2048, 80, 3100))
		if view == "reflection": controller.scene_reflection = 0.65; controller._apply_parameters()
		controller._process(0.0)
		for target: ShaderMaterial in [controller._material, controller._ground_material, controller._shaft_material]:
			if target != null: target.set_shader_parameter("preview_time", 7.0)
		controller._water_regions.set_water_parameter("preview_time", 7.0)
		controller._water_regions.set_ground_parameter("preview_time", 7.0)
		for round_index in 2:
			for enabled in [false, true]:
				root.use_occlusion_culling = enabled
				await _measure(view + "_" + str(round_index) + ("_on" if enabled else "_off"), true)
	_save(phase + "-frames.json", rows)
	root.use_occlusion_culling = false
	scene.queue_free(); await process_frame; quit()

func _add_interior_occluders(source: Terrain, parent: Node3D) -> int:
	var count := 0
	# Fixture columns are uniform in each GROUP square. Scan every square,
	# including all boundaries; proxies never cover air or the beach/swash.
	for sz in range(0, CELLS, 256):
		for sx in range(0, CELLS, 256):
			var minimum := source.height_limit
			for z in range(sz, sz + 256, GROUP):
				for x in range(sx, sx + 256, GROUP):
					minimum = mini(minimum, source.column_value("heights", source.column_index(x, z)))
			if minimum < 96: continue
			var box := BoxOccluder3D.new()
			box.size = Vector3(254, minimum - 10, 254)
			var instance := OccluderInstance3D.new()
			instance.occluder = box
			instance.position = Vector3(sx + 128, 2 + box.size.y * 0.5, sz + 128)
			parent.add_child(instance)
			count += 1
	return count

func _measure(label: String, capture := false) -> void:
	for i in 60: await process_frame
	var gpu := []; var cpu := []; var frame := []; var floor_gpu := []; var mirror_gpu := []
	var previous := Time.get_ticks_usec()
	for i in SAMPLES:
		await process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		floor_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(controller._floor_viewport.get_viewport_rid()))
		mirror_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(controller._viewport.get_viewport_rid()))
		var now := Time.get_ticks_usec(); frame.append((now - previous) / 1000.0); previous = now
	gpu.sort(); cpu.sort(); frame.sort(); floor_gpu.sort(); mirror_gpu.sort()
	var row := {"case": label, "gpu_ms": gpu[SAMPLES / 2], "cpu_ms": cpu[SAMPLES / 2],
		"frame_ms": frame[SAMPLES / 2], "frame_p95_ms": frame[int(SAMPLES * 0.95)],
		"floor_gpu_ms": floor_gpu[SAMPLES / 2], "mirror_gpu_ms": mirror_gpu[SAMPLES / 2],
		"static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"primitives": root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"draws": root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"near": controller._water_regions.stats.get("near_regions", 0), "far": controller._water_regions.stats.get("far_regions", 0)}
	rows.append(row)
	print("WORLD_SCALE_FRAME ", JSON.stringify(row))
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(phase + "-" + label + ".png"))

func _save(filename: String, value: Variant) -> void:
	var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value, "\t"))
