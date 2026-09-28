extends SceneTree

const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const BrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")

const WIDTH := 192
const RADIUS_BLOCKS := 4.0
const DEPTH := 8
const DETAIL := 3
const SEED := 371
const BOUNDS := Rect2i(0, 0, 160, 160)
const PATH: Array[Vector2i] = [
	Vector2i(80, 80), Vector2i(84, 80), Vector2i(90, 80),
	Vector2i(90, 90), Vector2i(80, 90), Vector2i(80, 80),
	Vector2i(80, 80), Vector2i(2, 4), Vector2i(7, 8),
]


func _initialize() -> void:
	for mode in ["raise", "lower", "generator"]:
		for direction in [-1, 0, 1] if mode == "generator" else [0]:
			_verify(mode, direction)
	print("COMPACT_BRUSH_OVERLAP same_result=ok undo_redo=ok")
	quit()


func _verify(mode: String, direction: int) -> void:
	var source := TerrainResource.new()
	source.width = WIDTH
	source.depth = WIDTH
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.WHITE])
	source.heights.resize(WIDTH * WIDTH)
	source.heights.fill(48)
	source.top_materials.resize(WIDTH * WIDTH)
	source.top_materials.fill(1)
	source.base_materials.resize(WIDTH * WIDTH)
	source.base_materials.fill(1)
	source.cap_depths.resize(WIDTH * WIDTH)
	source.water_levels.resize(WIDTH * WIDTH)
	source.water_materials.resize(WIDTH * WIDTH)
	assert(source.validation_errors().is_empty())
	var expected := source.heights.duplicate()
	var influence := PackedInt32Array()
	influence.resize(WIDTH * WIDTH)
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 16.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = DETAIL
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	var target := Node3D.new()
	var history := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"target": weakref(target), "resource": source}, history, target)
	assert(brush.begin(mode, RADIUS_BLOCKS, DEPTH, 1, 0, 16, DETAIL, SEED, direction))
	var previous := Vector2i(-1, -1)
	for cell in PATH:
		brush.stamp(cell, BOUNDS)
		if previous.x < 0:
			_reference_stamp(expected, influence, noise, mode, direction, cell)
		else:
			var steps := maxi(1, ceili(Vector2(previous).distance_to(Vector2(cell)) / (RADIUS_BLOCKS * 8.0)))
			for step in range(1, steps + 1):
				var point := Vector2(previous).lerp(Vector2(cell), float(step) / float(steps))
				_reference_stamp(expected, influence, noise, mode, direction, Vector2i(roundi(point.x), roundi(point.y)))
		previous = cell
	brush.end()
	assert(source.heights == expected, "%s direction=%d differs from full footprint" % [mode, direction])
	history.undo()
	for height in source.heights:
		assert(height == 48)
	history.redo()
	assert(source.heights == expected)
	history.clear_history()
	history.free()
	target.free()


func _reference_stamp(expected: PackedInt32Array, influence: PackedInt32Array, noise: FastNoiseLite, mode: String, direction: int, cell: Vector2i) -> void:
	var radius := roundi(RADIUS_BLOCKS * 16.0)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var distance_squared := dx * dx + dz * dz
			if distance_squared > radius * radius:
				continue
			var x := cell.x + dx
			var z := cell.y + dz
			if x < 0 or z < 0 or x >= WIDTH or z >= WIDTH or not BOUNDS.has_point(Vector2i(x, z)):
				continue
			var index := x + z * WIDTH
			var falloff := BrushMath.falloff(dx, dz, radius)
			if mode == "generator":
				var strength := roundi(falloff * 4096.0)
				if strength <= influence[index]:
					continue
				influence[index] = strength
				expected[index] = clampi(48 + BrushMath.noise_offset(noise, x, z, falloff, DEPTH, DETAIL, direction), 1, 128)
			else:
				var amount := BrushMath.relief_amount(falloff, DEPTH)
				if amount <= influence[index]:
					continue
				influence[index] = amount
				expected[index] = clampi(48 + (amount if mode == "raise" else -amount), 1, 128)
