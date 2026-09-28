extends SceneTree

const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const BrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const SIZE := 192


func _initialize() -> void:
	assert(BrushMath.edit_profile("coarse").cell_stride == 8)
	assert(BrushMath.edit_profile("medium").cell_stride == 2)
	assert(BrushMath.edit_profile("detail").cell_stride == 1)
	var source := _flat_terrain()
	var original := source.heights.duplicate()
	var owner := Node3D.new()
	var undo := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"target": weakref(owner), "resource": source}, undo, owner)
	assert(brush.begin("raise", 4.0, 8, 1, 0, 16, 0, 371, 0, -99999, "medium"))
	brush.stamp(Vector2i(96, 96))
	brush.end()
	var raised := source.heights.duplicate()
	var medium_edges := _edge_counts(raised)
	assert(medium_edges.x > 0 and medium_edges.y == 0)
	_check_groups(raised)
	assert(source.heights[source.column_index(96, 96)] == 72)
	undo.undo()
	assert(source.heights == original)
	undo.redo()
	assert(source.heights == raised)
	var saved_path := "user://compact-brush-scale-%d.res" % OS.get_process_id()
	assert(ResourceSaver.save(source, saved_path) == OK)
	var loaded := ResourceLoader.load(saved_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	assert(loaded != null and loaded.heights == raised)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path)) == OK)
	undo.clear_history()
	undo.free()
	owner.free()

	var fine := _flat_terrain()
	var fine_owner := Node3D.new()
	var fine_undo := UndoRedo.new()
	var fine_brush := Brush.new()
	fine_brush.configure({"target": weakref(fine_owner), "resource": fine}, fine_undo, fine_owner)
	assert(fine_brush.begin("raise", 4.0, 8, 1, 0, 16, 0, 371, 0))
	fine_brush.stamp(Vector2i(96, 96))
	fine_brush.end()
	var fine_edges := _edge_counts(fine.heights)
	assert(fine_edges.y > 500 and medium_edges.x < fine_edges.x)
	fine_undo.clear_history()
	fine_undo.free()
	fine_owner.free()

	for mode in ["lower", "generator", "level", "smooth"]:
		_verify_medium_mode(mode)
	_verify_quarter_and_half_step()
	_verify_block_quadrants()
	_verify_footprint_shapes()
	_verify_layer_profile()
	_verify_long_stroke()
	print("COMPACT_BRUSH_SCALE medium_edges=", medium_edges.x, " tiny=", medium_edges.y, " detailed_edges=", fine_edges.x, " quadrants=ok quarter_half=ok square_circle=ok paint_water=ok continuous=ok undo_redo=ok save_reopen=ok")
	quit()


func _verify_medium_mode(mode: String) -> void:
	var source := _flat_terrain()
	if mode == "smooth":
		for z in 2:
			for x in 2:
				source.heights[96 + x + (96 + z) * SIZE] = 80
	var owner := Node3D.new()
	var undo := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"target": weakref(owner), "resource": source}, undo, owner)
	var target := 78 if mode == "level" else -99999
	assert(brush.begin(mode, 4.0, 16, 1, 0, 16, 3, 371, 1, target, "medium"))
	brush.stamp(Vector2i(96, 96))
	brush.end()
	_check_groups(source.heights)
	if mode == "level": assert(source.heights[source.column_index(96, 96)] == 80)
	if mode == "lower": assert(source.heights[source.column_index(96, 96)] == 48)
	if mode == "smooth": assert(source.heights[source.column_index(96, 96)] == 68)
	if mode == "generator": assert(_edge_counts(source.heights).x > 0)
	undo.clear_history()
	undo.free()
	owner.free()


func _verify_block_quadrants() -> void:
	var source := _flat_terrain()
	var owner := Node3D.new()
	var undo := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"target": weakref(owner), "resource": source}, undo, owner)
	assert(brush.begin("raise", 0.5, 4, 1, 0, 16, 0, 371, 0, -99999, "coarse"))
	brush.stamp(Vector2i(100, 100))
	brush.end()
	for z in range(96, 104):
		for x in range(96, 104):
			assert(source.heights[source.column_index(x, z)] == 68)
	assert(source.heights[source.column_index(104, 100)] == 64)
	assert(source.heights[source.column_index(100, 104)] == 64)
	undo.undo()
	assert(source.heights[source.column_index(100, 100)] == 64)
	undo.redo()
	assert(source.heights[source.column_index(100, 100)] == 68)
	for mode in ["paint", "water"]:
		assert(brush.begin(mode, 0.5, 4, 2, 80, 16, 0, 371, 0, -99999, "coarse"))
		brush.stamp(Vector2i(100, 100))
		brush.end()
	for z in range(96, 104):
		for x in range(96, 104):
			var index := source.column_index(x, z)
			assert(source.top_materials[index] == 2)
			assert(source.water_levels[index] == 80)
			assert(source.heights[index] == 68)
	assert(source.top_materials[source.column_index(104, 100)] == 1)
	assert(source.water_levels[source.column_index(104, 100)] == 0)
	undo.clear_history()
	undo.free()
	owner.free()


func _verify_long_stroke() -> void:
	var source := _flat_terrain()
	var owner := Node3D.new()
	var undo := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"target": weakref(owner), "resource": source}, undo, owner)
	assert(brush.begin("raise", 0.5, 8, 1, 0, 16, 0, 371, 0, -99999, "medium"))
	for point in [Vector2i(32, 96), Vector2i(96, 96), Vector2i(160, 96)]: brush.stamp(point)
	brush.end()
	for x in range(32, 161): assert(source.heights[source.column_index(x, 96)] > 64)
	_check_groups(source.heights)
	undo.undo()
	for x in range(32, 161): assert(source.heights[source.column_index(x, 96)] == 64)
	undo.clear_history()
	undo.free()
	owner.free()


func _verify_footprint_shapes() -> void:
	var corner := Vector2i(110, 110)
	for shape in ["square", "circle"]:
		var source := _flat_terrain()
		var owner := Node3D.new()
		var undo := UndoRedo.new()
		var brush := Brush.new()
		brush.configure({"target": weakref(owner), "resource": source}, undo, owner)
		assert(brush.begin("raise", 1.0, 8, 1, 0, 16, 0, 371, 0, -99999, "medium", shape))
		brush.stamp(Vector2i(96, 96))
		brush.end()
		assert(source.heights[source.column_index(corner.x, corner.y)] == (68 if shape == "square" else 64))
		_check_groups(source.heights)
		undo.undo()
		assert(source.heights[source.column_index(corner.x, corner.y)] == 64)
		undo.clear_history()
		undo.free()
		owner.free()


func _verify_quarter_and_half_step() -> void:
	for height_step in [4, 8]:
		var source := _flat_terrain()
		var owner := Node3D.new()
		var undo := UndoRedo.new()
		var brush := Brush.new()
		brush.configure({"target": weakref(owner), "resource": source}, undo, owner)
		for stroke in 2:
			assert(brush.begin("raise", 0.125, height_step, 1, 0, 16, 0, 371, 0, -99999, "medium", "square", height_step))
			brush.stamp(Vector2i(96, 96))
			brush.end()
			assert(source.heights[source.column_index(96, 96)] == 64 + (stroke + 1) * height_step)
			_check_groups(source.heights, height_step)
		undo.undo()
		assert(source.heights[source.column_index(96, 96)] == 64 + height_step)
		undo.undo()
		assert(source.heights[source.column_index(96, 96)] == 64)
		undo.clear_history()
		undo.free()
		owner.free()


func _verify_layer_profile() -> void:
	var source := _flat_terrain()
	var group := [source.column_index(96, 96), source.column_index(97, 96), source.column_index(96, 97), source.column_index(97, 97)]
	for i in 4: source.heights[group[i]] = 64 + i
	var original_heights := source.heights.duplicate()
	var owner := Node3D.new()
	var undo := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"target": weakref(owner), "resource": source}, undo, owner)
	assert(brush.begin("paint", 0.125, 8, 2, 0, 16, 0, 371, 0, -99999, "medium", "square"))
	brush.stamp(Vector2i(97, 97))
	brush.end()
	for index in group: assert(source.top_materials[index] == 2)
	assert(source.heights == original_heights)
	undo.undo()
	for index in group: assert(source.top_materials[index] == 1)
	assert(brush.begin("water", 0.125, 8, 2, 80, 16, 0, 371, 0, -99999, "medium", "square"))
	brush.stamp(Vector2i(97, 97))
	brush.end()
	for index in group: assert(source.water_levels[index] == 80 and source.water_materials[index] == 2)
	assert(source.heights == original_heights)
	assert(brush.begin("dry", 0.125, 8, 2, 0, 16, 0, 371, 0, -99999, "medium", "square"))
	brush.stamp(Vector2i(97, 97))
	brush.end()
	for index in group: assert(source.water_levels[index] == 0 and source.water_materials[index] == 0)
	undo.undo()
	for index in group: assert(source.water_levels[index] == 80 and source.water_materials[index] == 2)
	var saved_path := "user://compact-layer-profile-%d.res" % OS.get_process_id()
	assert(ResourceSaver.save(source, saved_path) == OK)
	var loaded := ResourceLoader.load(saved_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	assert(loaded != null and loaded.heights == original_heights)
	for index in group: assert(loaded.water_levels[index] == 80 and loaded.water_materials[index] == 2)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path)) == OK)
	undo.clear_history()
	undo.free()
	owner.free()


func _flat_terrain() -> Terrain:
	var source := Terrain.new()
	source.width = SIZE
	source.depth = SIZE
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.GREEN, Color.BLUE])
	source.heights.resize(SIZE * SIZE)
	source.heights.fill(64)
	source.top_materials.resize(SIZE * SIZE)
	source.top_materials.fill(1)
	source.base_materials.resize(SIZE * SIZE)
	source.base_materials.fill(1)
	source.cap_depths.resize(SIZE * SIZE)
	source.water_levels.resize(SIZE * SIZE)
	source.water_materials.resize(SIZE * SIZE)
	assert(source.validation_errors().is_empty())
	return source


func _check_groups(heights: PackedInt32Array, height_step := 4) -> void:
	for z in range(0, SIZE, 2):
		for x in range(0, SIZE, 2):
			var index := x + z * SIZE
			assert(heights[index] == heights[index + 1])
			assert(heights[index] == heights[index + SIZE])
			assert(heights[index] == heights[index + SIZE + 1])
			assert(heights[index] % height_step == 0)


func _edge_counts(heights: PackedInt32Array) -> Vector2i:
	var edges := 0
	var tiny := 0
	for z in SIZE:
		for x in SIZE:
			var index := x + z * SIZE
			for neighbor in [Vector2i(x + 1, z), Vector2i(x, z + 1)]:
				if neighbor.x >= SIZE or neighbor.y >= SIZE: continue
				var difference := absi(heights[index] - heights[neighbor.x + neighbor.y * SIZE])
				if difference > 0:
					edges += 1
					if difference <= 2: tiny += 1
	return Vector2i(edges, tiny)
