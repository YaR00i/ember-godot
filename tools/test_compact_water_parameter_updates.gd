extends SceneTree
## Derived materials retain independent sent values across updates and rebinds.
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const Sea = preload("res://scripts/prototypes/ember_compact_sea_swash.gd")
const Controller = preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")

func _initialize() -> void:
	_run.call_deferred()

func _entry() -> Dictionary:
	return {"sea": Sea.new(), "window": Rect2i(0, 0, 16, 16), "height": null, "shore": null}

func _run() -> void:
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform int object_shape_count; uniform vec4 reaction_samples[12]; uniform float preview_time; uniform vec2 caustic_sun_offset;"
	var water := ShaderMaterial.new()
	water.shader = shader
	var ground := water.duplicate() as ShaderMaterial
	water.set_shader_parameter("object_shape_count", 1)
	ground.set_shader_parameter("caustic_sun_offset", Vector2.ONE)
	var fields := Regions.new()
	fields.regions = {Vector2i.ZERO: _entry(), Vector2i.RIGHT: _entry()}
	fields.bind(water, ground, Vector2.ZERO)
	fields.set_water_parameter("object_shape_count", 1)
	assert(fields.stats.get("parameter_writes", 0) == 0)
	fields.set_water_parameter("object_shape_count", 2)
	assert(fields.stats.parameter_writes == 2)
	for entry in fields.regions.values(): assert(entry.water.get_shader_parameter("object_shape_count") == 2)
	fields.set_water_parameter("object_shape_count", 2)
	assert(fields.stats.parameter_writes == 2, "unchanged values must not be uploaded")
	var wakes := PackedVector4Array()
	wakes.resize(12)
	wakes[0] = Vector4(1, 2, 0.1, 1)
	fields.set_water_parameter("reaction_samples", wakes)
	fields.set_water_parameter("reaction_samples", wakes.duplicate())
	assert(fields.stats.parameter_writes == 4)
	wakes[0].z = 0.2
	fields.set_water_parameter("reaction_samples", wakes)
	assert(fields.stats.parameter_writes == 6, "aging wakes must continue updating")
	for entry in fields.regions.values(): assert(entry.water.get_shader_parameter("reaction_samples")[0].z == wakes[0].z)
	fields.set_ground_parameter("caustic_sun_offset", Vector2.ONE)
	assert(fields.stats.parameter_writes == 6)
	fields.set_ground_parameter("caustic_sun_offset", Vector2.ZERO)
	assert(fields.stats.parameter_writes == 8)
	# Restore the base material (Undo/reopen/settings), then rebind reused regions.
	fields.bind(water, ground, Vector2.ZERO)
	for entry in fields.regions.values():
		assert(entry.water.get_shader_parameter("object_shape_count") == 1)
		assert(entry.ground.get_shader_parameter("caustic_sun_offset") == Vector2.ONE)
	fields.set_water_parameter("object_shape_count", 2)
	assert(fields.stats.parameter_writes == 10)
	# A new region must receive current values even when older regions skip them.
	fields.regions[Vector2i(2, 0)] = _entry()
	fields.bind(water, ground, Vector2.ZERO)
	fields.set_water_parameter("object_shape_count", 2)
	assert(fields.stats.parameter_writes == 13)
	for entry in fields.regions.values(): assert(entry.water.get_shader_parameter("object_shape_count") == 2)
	var controller := Controller.new()
	controller._material = water
	controller._water_regions = fields
	controller._set_water_parameter_if_changed("object_shape_count", 3)
	assert(water.get_shader_parameter("object_shape_count") == 3)
	assert(fields.stats.parameter_writes == 16)
	controller._set_water_parameter_if_changed("object_shape_count", 3)
	assert(fields.stats.parameter_writes == 16)
	water.set_shader_parameter("object_shape_count", 0)
	controller._set_water_parameter_if_changed("object_shape_count", 3)
	assert(water.get_shader_parameter("object_shape_count") == 3)
	assert(fields.stats.parameter_writes == 16, "direct base edits must not invalidate unchanged regional values")
	controller._water_regions = null
	controller.free()
	fields.regions.clear()
	print("PASS water parameter updates: unchanged, independent regions, moving/aging arrays, ground, rebind, new region, base edits")
	quit()
