extends SceneTree
## Native addon capability and coordinate smoke. The adapter itself stays
## dynamic so removing addons/zylann.voxel restores the stock fallback.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const NativePreview = preload("res://addons/ember_import/ember_voxel_tools_preview.gd")


func _init() -> void:
	var errors: Array[String] = []
	for native_class in ["VoxelBuffer", "VoxelColorPalette", "VoxelMesherCubes"]:
		if not ClassDB.class_exists(native_class):
			errors.append("missing native class %s" % native_class)
	if not errors.is_empty():
		_finish(errors)
		return

	var buffer: Object = ClassDB.instantiate("VoxelBuffer")
	buffer.call("create", 3, 3, 3)
	var colors := PackedByteArray()
	colors.resize(27)
	colors.fill(0)
	# Voxel Tools flat buffers use ZXY order: y + x*sy + z*sx*sy.
	colors[1 + 1 * 3 + 1 * 9] = 1
	buffer.call("set_channel_from_byte_array", 2, colors)

	var palette: Object = ClassDB.instantiate("VoxelColorPalette")
	var palette_colors := PackedColorArray()
	palette_colors.resize(256)
	palette_colors.fill(Color(0, 0, 0, 0))
	palette_colors[1] = Color(0.9, 0.2, 0.1, 1.0)
	palette.set("colors", palette_colors)

	var mesher: Object = ClassDB.instantiate("VoxelMesherCubes")
	mesher.set("color_mode", 1)
	mesher.set("palette", palette)
	mesher.set("greedy_meshing_enabled", true)
	var mesh := mesher.call("build_mesh", buffer, [], {}) as Mesh
	if mesh == null or mesh.get_surface_count() == 0:
		errors.append("native cube mesher produced no surface")
	else:
		var aabb := mesh.get_aabb()
		if not aabb.size.is_equal_approx(Vector3.ONE):
			errors.append("single native voxel has unexpected bounds: %s" % aabb)
		print("  native voxel AABB: ", aabb)
	_test_ember_region(errors)
	_finish(errors)


func _test_ember_region(errors: Array[String]) -> void:
	var resource := Model.make_pilot()
	var alias_values := resource.voxels
	var alias_before := int(resource.voxels[0])
	alias_values[0] = 5 if alias_before != 5 else 4
	if int(resource.voxels[0]) != int(alias_values[0]):
		errors.append("PackedByteArray property did not preserve live gesture aliasing")
	alias_values[0] = alias_before
	var relief_started := Time.get_ticks_usec()
	var baseline := resource.voxels.duplicate()
	var changes := Model.relief_changes(
		resource, baseline, Vector3i(64, 0, 64), Model.TOOL_RAISE, 5, 16, 8, false
	)
	var relief_elapsed := Time.get_ticks_usec() - relief_started
	print("  Ember radius-16 relief calculation: %dus · %d changes" % [relief_elapsed, changes.size()])
	var cache := {}
	# Warm the same columns once, as the workspace does during one held gesture.
	Model.relief_changes(
		resource, baseline, Vector3i(64, 0, 64), Model.TOOL_RAISE, 5, 16, 1, false, cache
	)
	var cached_started := Time.get_ticks_usec()
	var cached_changes := Model.relief_changes(
		resource, baseline, Vector3i(64, 0, 64), Model.TOOL_RAISE, 5, 16, 8, false, cache
	)
	var cached_elapsed := Time.get_ticks_usec() - cached_started
	print("  cached held relief calculation: %dus · %d columns" % [cached_elapsed, cache.size()])
	if cached_changes.size() != changes.size():
		errors.append("cached relief changed sculpt semantics")
	var gesture_resource := Model.make_pilot()
	var gesture_baseline := gesture_resource.voxels.duplicate()
	var gesture_cache := {}
	var gesture_amount_cache := {}
	var gesture_peak := 0
	var gesture_total := 0
	var gesture_first := 0
	var gesture_last := 0
	for height in range(1, 9):
		var tick_started := Time.get_ticks_usec()
		var tick_changes := Model.relief_changes(
			gesture_resource,
			gesture_baseline,
			Vector3i(64, 0, 64),
			Model.TOOL_RAISE,
			5,
			16,
			height,
			false,
			gesture_cache,
			height - 1,
			gesture_amount_cache,
		)
		var live_values := gesture_resource.voxels
		for raw_index in tick_changes:
			live_values[int(raw_index)] = int((tick_changes[raw_index] as Dictionary)["after"])
		var tick_elapsed := Time.get_ticks_usec() - tick_started
		if height == 1:
			gesture_first = tick_elapsed
		gesture_last = tick_elapsed
		gesture_peak = maxi(gesture_peak, tick_elapsed)
		gesture_total += tick_elapsed
	print(
		"  incremental live gesture: first %dus · last %dus · peak %dus · total %dus"
		% [gesture_first, gesture_last, gesture_peak, gesture_total]
	)
	var revisit_started := Time.get_ticks_usec()
	var revisit_changes := Model.relief_changes(
		gesture_resource,
		gesture_baseline,
		Vector3i(64, 0, 64),
		Model.TOOL_RAISE,
		5,
		16,
		8,
		false,
		gesture_cache,
		0,
		gesture_amount_cache,
	)
	var revisit_elapsed := Time.get_ticks_usec() - revisit_started
	print("  revisited relief footprint: %dus · %d changes" % [revisit_elapsed, revisit_changes.size()])
	if not revisit_changes.is_empty():
		errors.append("revisited relief footprint produced duplicate changes")
	var sweep_resource := Model.make_pilot()
	var sweep_baseline := sweep_resource.voxels.duplicate()
	var sweep_top_cache := {}
	var sweep_amount_cache := {}
	var forward_started := Time.get_ticks_usec()
	var sweep_changes := Model.relief_segment_changes(
		sweep_resource, sweep_baseline,
		Vector3i(48, 0, 64), Vector3i(80, 0, 64), Model.TOOL_RAISE,
		5, 16, 2, false, sweep_top_cache, 0, sweep_amount_cache,
	)
	var sweep_values := sweep_resource.voxels
	for raw_index in sweep_changes:
		sweep_values[int(raw_index)] = int(
			(sweep_changes[raw_index] as Dictionary)["after"]
		)
	var forward_elapsed := Time.get_ticks_usec() - forward_started
	var reverse_started := Time.get_ticks_usec()
	var reverse_changes := Model.relief_segment_changes(
		sweep_resource, sweep_baseline,
		Vector3i(80, 0, 64), Vector3i(48, 0, 64), Model.TOOL_RAISE,
		5, 16, 2, false, sweep_top_cache, 0, sweep_amount_cache,
	)
	var reverse_change_count := reverse_changes.size()
	var reverse_elapsed := Time.get_ticks_usec() - reverse_started
	print(
		"  relief sweep forward/revisit: %dus -> %dus · %d revisit changes"
		% [forward_elapsed, reverse_elapsed, reverse_change_count]
	)
	if reverse_change_count != 0:
		errors.append("reverse relief sweep revisited completed shells")
	var shell_resource := Model.make_pilot()
	var shell_baseline := shell_resource.voxels.duplicate()
	var shell_started := Time.get_ticks_usec()
	var shell_changes := Model.shell_relief_segment_changes(
		shell_resource,
		shell_baseline,
		Vector3i(24, 0, 32),
		Vector3i(80, 0, 32),
		5,
		16,
		8,
		false,
	)
	var shell_elapsed := Time.get_ticks_usec() - shell_started
	var solid_resource := Model.make_pilot()
	var solid_started := Time.get_ticks_usec()
	var solid_changes := Model.relief_segment_changes(
		solid_resource,
		solid_resource.voxels.duplicate(),
		Vector3i(24, 0, 32),
		Vector3i(80, 0, 32),
		Model.TOOL_RAISE,
		5,
		16,
		8,
		false,
	)
	var solid_elapsed := Time.get_ticks_usec() - solid_started
	print(
		"  shell/solid ridge: %dus %d voxels / %dus %d voxels"
		% [shell_elapsed, shell_changes.size(), solid_elapsed, solid_changes.size()]
	)
	var large_shell := Model.make_pilot()
	var large_shell_started := Time.get_ticks_usec()
	var large_shell_changes := Model.shell_relief_segment_changes(
		large_shell,
		large_shell.voxels.duplicate(),
		Vector3i(64, 0, 64),
		Vector3i(64, 0, 64),
		5,
		32,
		8,
		false,
	)
	var large_shell_elapsed := Time.get_ticks_usec() - large_shell_started
	print(
		"  shell radius-32 stamp: %dus · %d changes"
		% [large_shell_elapsed, large_shell_changes.size()]
	)
	var line_resource := Model.make_pilot()
	var line_baseline := line_resource.voxels.duplicate()
	var line_changes := {}
	var line_started := Time.get_ticks_usec()
	var line_centers := Model.line_cells(Vector3i(8, 1, 64), Vector3i(119, 1, 64))
	for center in line_centers:
		var point_changes := Model.oriented_stroke_changes(
			line_resource,
			line_baseline,
			center,
			Vector3i.UP,
			Model.TOOL_ADD,
			5,
			8,
			4,
			false,
			"square",
		)
		for raw_index in point_changes:
			line_changes[raw_index] = point_changes[raw_index]
	var line_elapsed := Time.get_ticks_usec() - line_started
	print(
		"  precision line 112x radius-8 depth-4 plan: %dus · %d changes"
		% [line_elapsed, line_changes.size()]
	)
	if line_changes.is_empty():
		errors.append("precision line plan produced no changes")
	var smooth_resource := Model.make_pilot()
	var smooth_baseline := smooth_resource.voxels.duplicate()
	var smooth_top_cache := {}
	var smooth_applied_cache := {}
	var smooth_heightfield_started := Time.get_ticks_usec()
	var smooth_heightfield := Model.column_heights(
		smooth_baseline, smooth_resource.grid_size()
	)
	var smooth_heightfield_elapsed := Time.get_ticks_usec() - smooth_heightfield_started
	var smooth_started := Time.get_ticks_usec()
	var smooth_changes := Model.smooth_segment_changes(
		smooth_resource,
		smooth_baseline,
		Vector3i(24, 0, 64),
		Vector3i(104, 0, 64),
		5,
		32,
		2,
		false,
		smooth_top_cache,
		smooth_applied_cache,
		smooth_heightfield,
	)
	var smooth_elapsed := Time.get_ticks_usec() - smooth_started
	smooth_resource.voxels = Model.values_with_changes(
		smooth_resource.voxels, smooth_changes, true
	)
	var smooth_revisit_started := Time.get_ticks_usec()
	var smooth_revisit := Model.smooth_segment_changes(
		smooth_resource,
		smooth_baseline,
		Vector3i(104, 0, 64),
		Vector3i(24, 0, 64),
		5,
		32,
		2,
		false,
		smooth_top_cache,
		smooth_applied_cache,
		smooth_heightfield,
	)
	var smooth_revisit_elapsed := Time.get_ticks_usec() - smooth_revisit_started
	print(
		"  smooth heightfield/sweep/revisit: %dus + %dus -> %dus · %d/%d changes"
		% [smooth_heightfield_elapsed, smooth_elapsed, smooth_revisit_elapsed, smooth_changes.size(), smooth_revisit.size()]
	)
	if not smooth_revisit.is_empty():
		errors.append("Smooth radius-32 revisit processed completed columns twice")
	var common_started := Time.get_ticks_usec()
	var common_changes := Model.smooth_segment_changes(
		Model.make_pilot(),
		smooth_baseline,
		Vector3i(24, 0, 64),
		Vector3i(104, 0, 64),
		5,
		32,
		2,
		false,
		{},
		{},
		smooth_heightfield,
		true,
		true,
	)
	var common_elapsed := Time.get_ticks_usec() - common_started
	print(
		"  smooth common radius-32 sweep: %dus · %d changes"
		% [common_elapsed, common_changes.size()]
	)
	var generated := Model.make_pilot()
	var generated_started := Time.get_ticks_usec()
	var generated_changes := Model.generative_relief_segment_changes(
		generated,
		generated.voxels.duplicate(),
		Vector3i(24, 0, 64),
		Vector3i(104, 0, 64),
		5,
		32,
		8,
		16,
		3,
		7,
		0,
		"soil",
		false,
		{},
		{},
		smooth_heightfield,
	)
	var generated_elapsed := Time.get_ticks_usec() - generated_started
	print(
		"  generative relief radius-32 sweep: %dus · %d changes"
		% [generated_elapsed, generated_changes.size()]
	)
	var adapter := NativePreview.new()
	var started := Time.get_ticks_usec()
	var projection := adapter.build_region(
		resource.voxels,
		resource.grid_size(),
		resource.palette,
		resource.transparency,
		Vector3i(32, 0, 32),
		Vector3i(16, 24, 16),
		1.0 / float(resource.normalized_density()),
		StandardMaterial3D.new(),
		StandardMaterial3D.new(),
	)
	var elapsed := Time.get_ticks_usec() - started
	var mesh := projection.get("mesh") as Mesh
	if mesh == null or mesh.get_surface_count() == 0:
		errors.append("Ember pilot did not project through native adapter")
		return
	var transform := Transform3D(
		Basis.from_scale(projection.get("scale", Vector3.ONE)),
		projection.get("position", Vector3.ZERO),
	)
	var world_bounds := transform * mesh.get_aabb()
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0 or world_bounds.size.z <= 0.0:
		errors.append("native Ember projection has empty world bounds")
	print("  Ember native preview: %dus · %s" % [elapsed, world_bounds])


func _finish(errors: Array[String]) -> void:
	if errors.is_empty():
		print("PASS Voxel Tools backend")
		quit(0)
		return
	printerr("FAIL Voxel Tools backend")
	for error in errors:
		printerr(" - ", error)
	quit(1)
