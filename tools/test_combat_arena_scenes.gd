extends SceneTree
## Separate arena scenes must be openable and able to render their editor preview.

const E2_SCENE := preload("res://scenes/combat/arenas/colored_crossing.tscn")
const E3_SCENE := preload("res://scenes/combat/arenas/thaw_keeper.tscn")
const WorldProjection = preload("res://scripts/prototypes/ember_combat_grid_3d_world.gd")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var errors: Array[String] = []
	await _check_arena(E2_SCENE, 0, false, errors)
	await _check_arena(E3_SCENE, 1, true, errors)
	if not errors.is_empty():
		printerr("FAIL combat arena scenes")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat arena scenes")
	print("  E2 and E3 are separate openable tscn arenas with editor preview modes")
	print("  preview renders scene-owned GridMap, camera, actors and semantic field state")
	quit(0)


func _check_arena(
	packed: PackedScene,
	expected_mode: int,
	expect_frozen: bool,
	errors: Array[String],
) -> void:
	var arena := packed.instantiate() as Node3D
	if arena == null:
		errors.append("arena scene could not instantiate for mode %d" % expected_mode)
		return
	root.add_child(arena)
	await process_frame
	if int(arena.get("editor_preview_mode")) != expected_mode:
		errors.append("arena did not preserve editor preview mode %d" % expected_mode)
	arena.call("render_editor_preview")
	await process_frame
	await physics_frame
	var grid_map := arena.find_child("CombatGridMap", true, false) as GridMap
	var camera := arena.find_child("CombatCamera3D", true, false) as Camera3D
	var camera_rig := arena.find_child("CameraRig", true, false) as Node3D
	var actor_root := arena.find_child("CombatActors3D", true, false) as Node3D
	var field := arena.get("battlefield") as EmberBattlefieldResource
	var surface_root := arena.find_child("DerivedVoxelBattleSurface", true, false) as Node3D
	var expected_cells := 63 if expected_mode == 1 else 35
	if grid_map == null or grid_map.get_used_cells().size() != expected_cells:
		errors.append("arena mode %d did not render %d authored preview cells" % [expected_mode, expected_cells])
	if camera_rig == null or actor_root == null or actor_root.get_child_count() < 6:
		errors.append("arena mode %d lacks scene-owned camera or actor preview" % expected_mode)
	elif actor_root.find_child("WaterContact", true, false) == null:
		errors.append("arena mode %d units lack automatic water contact visuals" % expected_mode)
	if field != null and field.visual_surface != null:
		if surface_root == null or surface_root.get_child_count() == 0:
			errors.append("arena visual Surface did not begin its frame-budgeted scene projection")
		elif not is_equal_approx(surface_root.scale.x, WorldProjection.CELL_SIZE):
			errors.append("arena visual Surface does not align one art block to one battle cell")
	var tide_probe := Vector2i(3, 2) if expect_frozen else Vector2i(3, 1)
	var item := int(arena.call("projected_item_at", tide_probe))
	if expect_frozen and item != WorldProjection.ITEM_WET:
		errors.append("E3 editor preview did not project its authored Wet tide panels")
	if not expect_frozen and item == WorldProjection.ITEM_FROZEN:
		errors.append("E2 editor preview leaked E3 Frozen field state")
	var probe := Vector2i(2, 2)
	var screen: Vector2 = arena.call("screen_position_for_cell", probe)
	var picked: Vector2i = Vector2i(-1, -1) if camera == null else arena.call("editor_pick_cell", camera, screen)
	if picked != probe:
		errors.append("3D authoring ray picked %s instead of %s" % [picked, probe])
	if (arena.call("editor_cell_corners", probe) as PackedVector3Array).size() != 4:
		errors.append("3D authoring hover has no canonical cell outline")
	arena.queue_free()
	await process_frame
