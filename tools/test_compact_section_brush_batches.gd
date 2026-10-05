extends SceneTree
## Regression for the multi-second sectioned brush trace: data parity first,
## then a generous stall budget. This does not replace native-editor acceptance.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")

class Sink extends RefCounted:
	var stages := {}
	func stage(name: String, us: int) -> void: stages[name] = stages.get(name, 0) + us

func _initialize() -> void: call_deferred("_run")

func _flat(width: int, depth: int) -> Terrain:
	var source := Terrain.new()
	source.width = width
	source.depth = depth
	source.palette = PackedColorArray([Color.BLACK, Color.GREEN, Color.BROWN])
	for channel in Terrain.Sections.CHANNELS:
		var values = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		values.resize(width * depth)
		values.fill(20 if channel == "heights" else 4 if channel == "cap_depths" else 1 if channel in ["top_materials", "base_materials"] else 0)
		source.set(channel, values)
	return source

func _run() -> void:
	for scale in ["detail", "medium", "coarse"]:
		for shape in ["circle", "square"]:
			for mode in ["raise", "lower", "level", "smooth", "generator", "paint", "water", "dry"]:
				_parity(mode, scale, shape)
	var part := _flat(384, 384)
	var source := Terrain.new()
	source.width = 1536
	source.depth = 1920
	source.schema_version = Terrain.SECTION_SCHEMA_VERSION
	source.palette = part.palette
	for z in 5:
		for x in 4: source.sections[Vector2i(x, z)] = part
	var baseline := source.working_copy()
	var scene := Node3D.new()
	var map := EmberMapLoader.new()
	var projection := EmberTerrainPilotProjection.new()
	root.add_child(projection)
	assert(projection.open_document(source))
	map._visual_surface_projection = projection
	var history := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"resource": source, "target": weakref(map)}, history, scene)
	var sink := Sink.new()
	brush.diagnostic_sink = sink
	assert(brush.begin("raise", 8.0, 48, 1, 0, 16, 0, 7, 0, -99999, "coarse", "square", 4))
	var started := Time.get_ticks_usec()
	brush.stamp(Vector2i(760, 760))
	var first_us := Time.get_ticks_usec() - started
	assert(brush.changed_column_count() == 61504)
	started = Time.get_ticks_usec()
	brush.stamp(Vector2i(1080, 920))
	var move_us := Time.get_ticks_usec() - started
	assert(brush.changed_column_count() == 163456)
	assert(first_us < 1000000 and move_us < 2000000, "section brush stall: %d / %d us" % [first_us, move_us])
	assert(source.same_terrain_data(projection.document))
	for key in source.sections: assert(source.sections[key] == projection.document.sections[key])
	assert(source.sections[Vector2i.ZERO] == baseline.sections[Vector2i.ZERO])
	assert(baseline.sections[Vector2i(1, 1)].heights == part.heights)
	brush.end()
	var after := source.working_copy()
	history.undo()
	assert(source.same_terrain_data(baseline) and projection.document.same_terrain_data(baseline))
	history.redo()
	assert(source.same_terrain_data(after) and projection.document.same_terrain_data(after))
	history.clear_history()
	history.free()
	brush.configure({}, null, null)
	map._visual_surface_projection = null
	projection.free()
	map.free()
	scene.free()
	print("SECTION_BRUSH_BATCHES PASS parity=48 partial-section=ok immutable=ok undo_redo=ok first_us=", first_us, " move_us=", move_us, " stages=", sink.stages)
	quit()

func _parity(mode: String, scale: String, shape: String) -> void:
	var dense := _flat(416, 64)
	for z in 64:
		for x in range(352, 416):
			var index := x + z * dense.width
			dense.heights[index] = 20 + (x / 8 + z / 8) % 3 * 4
			dense.water_levels[index] = 32
			dense.water_materials[index] = 2
	var addressed := dense.sectioned_copy()
	var original := addressed.working_copy()
	var owner := Node3D.new()
	var histories: Array[UndoRedo] = []
	for source: Terrain in [dense, addressed]:
		var history := UndoRedo.new()
		histories.append(history)
		var brush := Brush.new()
		brush.configure({"resource": source, "target": weakref(owner)}, history, owner)
		assert(brush.begin(mode, 1.0, 8, 2, 40, 16, 2, 7, 0, 12 if mode == "level" else -99999, scale, shape, 4))
		for point in [Vector2i(376, 28), Vector2i(392, 28)]: brush.stamp(point, Rect2i(352, 8, 64, 48))
		brush.end()
	var result := addressed.dense_window(Rect2i(0, 0, 416, 64))
	for channel in Terrain.Sections.CHANNELS: assert(result.get(channel) == dense.get(channel), "%s / %s / %s / %s" % [mode, scale, shape, channel])
	assert(addressed.validation_errors().is_empty())
	histories[1].undo()
	assert(addressed.same_terrain_data(original))
	histories[1].redo()
	assert(addressed.dense_window(Rect2i(0, 0, 416, 64)).same_terrain_data(result))
	for history in histories:
		history.clear_history()
		history.free()
	owner.free()
