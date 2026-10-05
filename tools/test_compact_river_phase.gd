extends SceneTree
## Phase distances must stay smooth across a bending channel and quiet banks.

const Phase = preload("res://scripts/prototypes/ember_compact_river_phase.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var straight := Terrain.new()
	straight.width = 80
	straight.depth = 128
	straight.water_flow.resize(40)
	straight.water_flow.fill(Vector2(0, -0.8))
	var distance := Phase.build(straight)
	for row in range(1, 8):
		for column in 5:
			assert(is_equal_approx(distance.get_pixel(column, row).r - distance.get_pixel(column, row - 1).r, -1.0))
		assert(is_zero_approx(distance.get_pixel(2, row).g), "arc center must stay on the channel centerline")
		assert(is_equal_approx(distance.get_pixel(0, row).g, -distance.get_pixel(4, row).g), "both sides of the front must use symmetric transverse distances")
	var sideways := Terrain.new()
	sideways.width = 128
	sideways.depth = 80
	sideways.water_flow.resize(40)
	sideways.water_flow.fill(Vector2(-0.8, 0))
	var turned := Phase.build(sideways)
	for row in 8:
		for column in 5:
			assert(is_equal_approx(distance.get_pixel(column, row).r, turned.get_pixel(row, column).r))
	var river := load("res://content/world_terrains/compact_river_water_study.res") as Terrain
	var original := river.water_flow.duplicate()
	var curved := Phase.build(river)
	assert(curved != null and river.water_flow == original)
	var max_jump := 0.0
	var checked := 0
	for z in range(24, 42):
		for x in range(1, curved.get_width() - 1):
			var flow := river.water_flow[x + z * curved.get_width()]
			if flow.length() < 0.10:
				continue
			var along := curved.get_pixel(x, z + 1).r - curved.get_pixel(x, z).r
			var across := curved.get_pixel(x + 1, z).r - curved.get_pixel(x, z).r
			assert(along < -0.45 and along > -1.8, "wave distance folds or compresses on the river bend")
			assert(absf(across) < 0.8, "cross-river phase creates a comb at the bank")
			assert(is_finite(curved.get_pixel(x, z).g), "arc coordinate must stay finite on the bend")
			max_jump = maxf(max_jump, absf(along))
			checked += 1
	assert(checked > 30)
	straight.water_flow.fill(Vector2.ZERO)
	assert(Phase.build(straight) == null)
	straight.water_flow.clear()
	assert(Phase.build(straight) == null)
	print("PASS river phase: straight/rotated spacing, continuous curved channel and banks, still water, unchanged flow; samples=", checked, " max_step=", max_jump)
	quit()
