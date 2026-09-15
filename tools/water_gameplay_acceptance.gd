extends SceneTree
## Opt-in Forward+ gameplay gate for already-implemented W04 water.
## Direct `--script` launch only. Not a second water, camera, or save owner.

const ShoreSelect := preload("res://tools/water_gameplay_acceptance_shore.gd")
const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"
const PIER_SCENE := "res://scenes/test_pier.tscn"
const QA_DIR := "res://art/water/gameplay_acceptance/qa"
const REVIEW2_PATH := "res://art/water/presets/water-lab-user-saved-review2-mix-2026-09-15.json"

var _mode := "shore"
var _qa_capture := false
var _storage_root := ""
var _abort := ""
var _sun_basis := Basis()


func _init() -> void:
	var parsed := parse_launch(OS.get_cmdline_user_args())
	if not bool(parsed.get("ok", false)):
		_abort = str(parsed.get("reason", "unknown mode"))
		_mode = str(parsed.get("mode", ""))
	else:
		_mode = str(parsed.get("mode", "shore"))
		_qa_capture = bool(parsed.get("qa_capture", false))
	node_added.connect(_on_node_added)
	_run.call_deferred()


static func parse_launch(user_args: PackedStringArray) -> Dictionary:
	var mode := "shore"
	var seen_mode := false
	var qa_capture := false
	for raw in user_args:
		var arg := str(raw).strip_edges().to_lower()
		if arg.is_empty():
			continue
		if arg == "qa-capture" or arg == "--qa-capture":
			qa_capture = true
			continue
		if arg == "shore" or arg == "pier":
			if seen_mode and mode != arg:
				return {
					"ok": false,
					"mode": arg,
					"qa_capture": qa_capture,
					"reason": "multiple modes: %s and %s" % [mode, arg],
				}
			mode = arg
			seen_mode = true
			continue
		return {
			"ok": false,
			"mode": arg,
			"qa_capture": qa_capture,
			"reason": "unknown mode '%s' (expected shore or pier)" % arg,
		}
	return {"ok": true, "mode": mode, "qa_capture": qa_capture, "reason": ""}


static func make_isolated_storage_root(
	process_id := OS.get_process_id(),
	timestamp := Time.get_ticks_usec(),
) -> String:
	return "user://ember-tests/water-gameplay-acceptance-%d-%d" % [process_id, timestamp]


static func apply_isolated_storage(progress: EmberExploreState, root_path: String) -> void:
	if progress == null or root_path.strip_edges().is_empty():
		return
	progress.storage_root = root_path
	progress.legacy_storage_root = root_path.path_join("legacy")
	progress.set_meta("test_pier_storage_root", root_path)


static func voxel_cell_world(projection: Node3D, surface: EmberVoxelModelResource, cell: Vector2i) -> Vector3:
	var density := float(surface.normalized_density())
	return projection.to_global(Vector3(
		(float(cell.x) + 0.5) / density,
		0.0,
		(float(cell.y) + 0.5) / density,
	))


func _on_node_added(node: Node) -> void:
	if str(node.name) != "EmberExploreProgress":
		return
	var progress := node as EmberExploreState
	if progress == null:
		return
	_storage_root = make_isolated_storage_root()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_storage_root))
	apply_isolated_storage(progress, _storage_root)


func _ensure_isolated_progress() -> void:
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress == null:
		return
	if _storage_root.is_empty():
		_storage_root = make_isolated_storage_root()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_storage_root))
	if progress.storage_root != _storage_root:
		apply_isolated_storage(progress, _storage_root)
		progress.reset_new_game()


func _run() -> void:
	if not _abort.is_empty():
		push_error("WATER_GAMEPLAY_ACCEPTANCE %s" % _abort)
		print("WATER_GAMEPLAY_ACCEPTANCE FAIL ", _abort)
		quit(1)
		return
	_ensure_isolated_progress()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1600, 900))
		DisplayServer.window_set_title("Ember · приёмка воды · %s" % _mode.to_upper())
		root.size = Vector2i(1600, 900)
	var scene_path := SANDBOX_SCENE if _mode == "shore" else PIER_SCENE
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("could not load %s" % scene_path)
		return
	var scene := packed.instantiate() as Node3D
	if scene == null:
		_fail("could not instantiate %s" % scene_path)
		return
	root.add_child(scene)
	current_scene = scene
	var ready: Dictionary = await _wait_scene_ready(scene)
	if not bool(ready.get("ok", false)):
		_fail(str(ready.get("reason", "scene was not ready")))
		return
	if _mode == "shore":
		var placed: Dictionary = await _place_at_canonical_shore(scene, ready)
		if not bool(placed.get("ok", false)):
			_fail(str(placed.get("reason", "shore placement failed")))
			return
		_add_overlay(scene, placed)
		if _qa_capture:
			await _capture_shore_evidence(scene, ready, placed)
			quit(0)
			return
	else:
		_add_overlay(scene, {"ok": true})
		if _qa_capture:
			await _capture_pier_evidence(scene, ready)
			quit(0)
			return
	print(
		"WATER_GAMEPLAY_ACCEPTANCE READY mode=%s storage=%s"
		% [_mode, _storage_root]
	)


func _wait_scene_ready(scene: Node) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 120000
	var last_reason := "timed out waiting for Player/FollowCamera"
	while Time.get_ticks_msec() < deadline:
		var player := scene.get_node_or_null("Player") as EmberPlayer
		var camera := scene.get_node_or_null("FollowCamera") as EmberFollowCamera
		var projection := scene.get_node_or_null("Map/DerivedVoxelWorldSurface") as Node3D
		if player == null or camera == null:
			last_reason = "Player/FollowCamera were not created by the authored scene"
			await process_frame
			continue
		if _mode == "shore":
			if projection == null:
				last_reason = "Map/DerivedVoxelWorldSurface was not created"
				await process_frame
				continue
			if not projection.has_method("is_projection_complete"):
				last_reason = "DerivedVoxelWorldSurface lost is_projection_complete"
				await process_frame
				continue
			if not bool(projection.call("is_projection_complete")):
				last_reason = "visual chunks are still pending"
				await process_frame
				continue
			if (
				projection.has_method("physics_is_ready")
				and not bool(projection.call("physics_is_ready"))
			):
				last_reason = "derived physics is not ready"
				await process_frame
				continue
		else:
			for _frame in 8:
				await physics_frame
			if not player.is_on_floor():
				last_reason = "pier spawn has not settled on authored collision"
				await physics_frame
				continue
		return {
			"ok": true,
			"player": player,
			"camera": camera,
			"projection": projection,
		}
	return {"ok": false, "reason": last_reason}


func _place_at_canonical_shore(scene: Node, ready: Dictionary) -> Dictionary:
	var map := scene.get_node_or_null("Map") as EmberMapLoader
	var player := ready.get("player") as EmberPlayer
	var camera := ready.get("camera") as EmberFollowCamera
	var projection := ready.get("projection") as Node3D
	if map == null or player == null or camera == null or projection == null:
		return {"ok": false, "reason": "shore runtime lost Map/Player/FollowCamera/projection"}
	var surface := map.resolved_visual_surface()
	if surface == null:
		return {"ok": false, "reason": "Map.resolved_visual_surface() returned null"}
	if surface.resource_path != ShoreSelect.canonical_surface_path():
		return {
			"ok": false,
			"reason": "sandbox Surface is %s, expected %s"
			% [surface.resource_path, ShoreSelect.canonical_surface_path()],
		}
	var spawn: Dictionary = ShoreSelect.select_shore_spawn(surface)
	if not bool(spawn.get("ok", false)):
		return {"ok": false, "reason": ShoreSelect.format_failure(spawn)}
	var wet_world := voxel_cell_world(
		projection, surface, spawn.get("wet_cell", Vector2i.ZERO)
	)
	var inland_world := voxel_cell_world(
		projection, surface, spawn.get("inland_cell", Vector2i.ZERO)
	)
	var water_sample: Dictionary = projection.call("water_surface_sample", wet_world)
	if not bool(water_sample.get("wet", false)):
		return {
			"ok": false,
			"reason": "selected shoreline cell is not wet via water_surface_sample · %s · %s"
			% [str(spawn.get("wet_cell", Vector2i.ZERO)), ShoreSelect.format_failure(spawn)],
		}
	var floor_sample: Dictionary = map.surface_floor_sample(inland_world)
	if not bool(floor_sample.get("solid", false)):
		return {
			"ok": false,
			"reason": "inland cell has no existing physical floor · %s · %s"
			% [str(spawn.get("inland_cell", Vector2i.ZERO)), ShoreSelect.format_failure(spawn)],
		}
	var dry_water: Dictionary = projection.call(
		"water_surface_sample",
		floor_sample.get("position", inland_world),
	)
	if bool(dry_water.get("wet", false)):
		return {
			"ok": false,
			"reason": "inland spawn is still wet via water_surface_sample · %s"
			% str(spawn.get("inland_cell", Vector2i.ZERO)),
		}
	var floor_position: Vector3 = floor_sample["position"]
	player.global_position = floor_position + Vector3(0.0, 6.0, 0.0)
	player.velocity = Vector3.ZERO
	var waterward: Vector2 = spawn.get("waterward", Vector2.RIGHT)
	var landward := -waterward
	camera.yaw = atan2(landward.x, landward.y)
	camera.reset_follow_height()
	var followers := scene.get_node_or_null("PartyFollowers")
	if followers != null and followers.has_method("reset_to_leader"):
		followers.call("reset_to_leader")
	var settled := await _wait_for_player_floor(player, 180)
	if not settled:
		return {
			"ok": false,
			"reason": "player did not settle on the existing physical surface at inland %s (pos=%s)"
			% [str(spawn.get("inland_cell", Vector2i.ZERO)), str(player.global_position)],
		}
	print(
		"WATER_GAMEPLAY_ACCEPTANCE SHORE wet=%s inland=%s beach=%s waterward=%s pos=%s"
		% [
			str(spawn.get("wet_cell", Vector2i.ZERO)),
			str(spawn.get("inland_cell", Vector2i.ZERO)),
			str(spawn.get("is_beach", false)),
			str(waterward),
			str(player.global_position),
		]
	)
	spawn["water_sample"] = water_sample
	spawn["floor_sample"] = floor_sample
	return spawn


func _add_overlay(scene: Node, spawn: Dictionary) -> void:
	var layer := scene.get_node_or_null("CanvasLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "WaterGameplayAcceptanceLayer"
		layer.layer = 80
		scene.add_child(layer)
	var panel := Panel.new()
	panel.name = "WaterGameplayAcceptanceOverlay"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.focus_mode = Control.FOCUS_NONE
	panel.position = Vector2(16, 16)
	panel.size = Vector2(560, 292)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.1, 0.72)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "Text"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.88))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.text = _overlay_text(spawn)
	panel.add_child(label)
	layer.add_child(panel)


func _overlay_text(spawn: Dictionary) -> String:
	if _mode == "pier":
		return "\n".join([
			"PIER · приёмка воды W04",
			"WASD — движение",
			"RMB — поворот камеры",
			"",
			"Смотреть: воду под настилом Причала без искусственной обрезки,",
			"отражённую волну у стенки, устойчивость бликов при повороте",
			"камеры, контакт игрока только в воде.",
			"",
			"Этот режим проверяет существующий authored TimberPier/BayWater.",
			"Канонический terrain-derived shore — режим shore.",
		])
	var kind := "пляж" if bool(spawn.get("is_beach", false)) else "стенка"
	return "\n".join([
		"SHORE · приёмка воды W04",
		"WASD — движение",
		"RMB — поворот камеры",
		"",
		"Смотреть: связность гребня, прибой, устойчивость бликов при",
		"повороте камеры, контакт игрока только в воде.",
		"",
		"Старт у существующей wet/dry-кромки (%s)." % kind,
		"Канонический terrain-derived shore карты agent_sandbox.",
		"Причал проверяйте режимом pier.",
	])


func _capture_shore_evidence(scene: Node, ready: Dictionary, spawn: Dictionary) -> void:
	var player := ready.get("player") as EmberPlayer
	var camera := ready.get("camera") as EmberFollowCamera
	var qa := _prepare_qa_dir()
	var sun := _find_sun(scene)
	if sun != null:
		_sun_basis = sun.global_transform.basis
	await _settle_frames(36)
	await _save_png(qa.path_join("shore-dry-look.png"))
	var contact := player.get_node_or_null("WaterContact")
	var dry_visible := contact != null and bool(contact.call("is_contact_visible"))
	var original_yaw := camera.yaw
	camera.yaw = original_yaw + PI * 0.5
	await _settle_frames(24)
	await _save_png(qa.path_join("shore-dry-orbit.png"))
	var sun_moved := sun != null and not sun.global_transform.basis.is_equal_approx(_sun_basis)
	camera.yaw = original_yaw
	camera.reset_follow_height()
	var water_position: Vector3 = spawn.get("water_sample", {}).get(
		"position",
		player.global_position,
	)
	var dry_position := player.global_position
	player.global_position = water_position + Vector3(0.0, 0.35, 0.0)
	player.velocity = Vector3.ZERO
	camera.reset_follow_height()
	await _settle_frames(24)
	await _save_png(qa.path_join("shore-wet-contact.png"))
	var wet_visible := contact != null and bool(contact.call("is_contact_visible"))
	player.global_position = dry_position
	player.velocity = Vector3.ZERO
	camera.reset_follow_height()
	await _settle_frames(16)
	_write_log(qa.path_join("shore-runtime.log"), [
		"mode=shore",
		"storage=%s" % _storage_root,
		"wet_cell=%s" % str(spawn.get("wet_cell", Vector2i.ZERO)),
		"inland_cell=%s" % str(spawn.get("inland_cell", Vector2i.ZERO)),
		"is_beach=%s" % str(spawn.get("is_beach", false)),
		"player=%s" % str(player.global_position),
		"dry_contact_visible=%s" % str(dry_visible),
		"wet_contact_visible=%s" % str(wet_visible),
		"sun_moved_on_orbit=%s" % str(sun_moved),
		"review2=%s" % ProjectSettings.globalize_path(REVIEW2_PATH),
	])
	print("WATER_GAMEPLAY_ACCEPTANCE QA shore written to ", ProjectSettings.globalize_path(qa))


func _capture_pier_evidence(scene: Node, ready: Dictionary) -> void:
	var player := ready.get("player") as EmberPlayer
	var camera := ready.get("camera") as EmberFollowCamera
	var qa := _prepare_qa_dir()
	var sun := _find_sun(scene)
	if sun != null:
		_sun_basis = sun.global_transform.basis
	await _settle_frames(36)
	await _save_png(qa.path_join("pier-look.png"))
	var original_yaw := camera.yaw
	camera.yaw = original_yaw + PI * 0.5
	await _settle_frames(24)
	await _save_png(qa.path_join("pier-orbit.png"))
	var sun_moved := sun != null and not sun.global_transform.basis.is_equal_approx(_sun_basis)
	camera.yaw = original_yaw
	camera.reset_follow_height()
	_write_log(qa.path_join("pier-runtime.log"), [
		"mode=pier",
		"storage=%s" % _storage_root,
		"player=%s" % str(player.global_position),
		"on_floor=%s" % str(player.is_on_floor()),
		"has_timber=%s" % str(scene.get_node_or_null("Map/Terrain/TimberPier") != null),
		"has_bay_water=%s" % str(scene.get_node_or_null("Map/Terrain/BayWater") != null),
		"sun_moved_on_orbit=%s" % str(sun_moved),
	])
	print("WATER_GAMEPLAY_ACCEPTANCE QA pier written to ", ProjectSettings.globalize_path(qa))


func _prepare_qa_dir() -> String:
	var absolute := ProjectSettings.globalize_path(QA_DIR)
	DirAccess.make_dir_recursive_absolute(absolute)
	return QA_DIR


func _save_png(res_path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(res_path)
	print("WATER_GAMEPLAY_ACCEPTANCE CAPTURE ", ProjectSettings.globalize_path(res_path), " result=", result)


func _write_log(res_path: String, lines: PackedStringArray) -> void:
	var file := FileAccess.open(res_path, FileAccess.WRITE)
	if file == null:
		push_error("could not write %s" % res_path)
		return
	file.store_string("\n".join(lines) + "\n")


func _settle_frames(count: int) -> void:
	for _frame in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _wait_for_player_floor(player: EmberPlayer, max_physics_frames: int) -> bool:
	for _frame in maxi(max_physics_frames, 1):
		await physics_frame
		if player.is_on_floor():
			return true
	return false


func _find_sun(scene: Node) -> DirectionalLight3D:
	for light_name in [&"Sun", &"Moon"]:
		var named_light := scene.find_child(light_name, true, false) as DirectionalLight3D
		if named_light != null:
			return named_light
	for node in scene.find_children("*", "DirectionalLight3D", true, false):
		var directional_light := node as DirectionalLight3D
		if directional_light != null:
			return directional_light
	return null


func _fail(reason: String) -> void:
	push_error("WATER_GAMEPLAY_ACCEPTANCE %s" % reason)
	print("WATER_GAMEPLAY_ACCEPTANCE FAIL ", reason)
	if _qa_capture:
		var qa := _prepare_qa_dir()
		_write_log(qa.path_join("%s-runtime.log" % _mode), PackedStringArray([
			"mode=%s" % _mode,
			"storage=%s" % _storage_root,
			"FAIL=%s" % reason,
		]))
	quit(1)
