extends SceneTree
## Reproduce tail starvation in the actual bounded sleeping-patch scanner.
const Preparation = preload("res://scripts/ember_detail_preparation.gd")
const Policy = preload("res://scripts/prototypes/ember_world_detail_policy.gd")
class Map extends EmberMapLoader:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
class Surface extends Node3D:
	var document := Resource.new()
	var detail_policy = Policy.new()
	var _live_brush_active := false
	func editor_detail_active() -> bool: return true
	func column_revision() -> int: return 0
	func detail_world_anchor() -> Vector3: return Vector3(detail_policy.anchor.x,0,detail_policy.anchor.y)
class Patch extends Node3D:
	var _detail_poll_projection_id := 0
	var _detail_resident := false
	var _detail_preview := {}
	var _dirty := false
	var admissions := 0
	var area_queries := 0
	func _world_area() -> Rect2:
		area_queries += 1
		return Rect2(Vector2(global_position.x,global_position.z), Vector2.ONE)
	func _process(_delta: float) -> void:
		_detail_resident = true
		admissions += 1
var errors: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label); printerr("GRASS_ADMISSION_CHURN_FAIL ",label)
func _initialize() -> void: run.call_deferred()
func make_patch(map: Node3D, context: RefCounted, at: Vector3) -> Patch:
	var patch := Patch.new(); patch.position = at; map.add_child(patch)
	context.sleep_patch(patch)
	return patch
func run() -> void:
	var map := Map.new(); map.imported_tile_size = 1; root.add_child(map)
	var projection := Surface.new(); map.add_child(projection)
	projection.detail_policy.cells_per_m = 1
	var context = Preparation.for_projection(projection)
	# Conservative square bins contain genuinely ineligible neighbours before
	# a patch that is already inside the existing 30m preparation circle.
	var prefix: Array[Patch] = []
	for i in 640: prefix.append(make_patch(map,context,Vector3(-35,0,-35)))
	var target := make_patch(map,context,Vector3(29.5,0,0))
	var churn := make_patch(map,context,Vector3(-36,0,-36))
	var first_admission := -1
	for step in 12:
		# Release/return and transform invalidation can dirty the sleeping index
		# while the same candidate window still needs more than one budget pass.
		churn.position.x += 0.001
		Preparation.moved_sleeping_patch(churn)
		projection.detail_policy.anchor.x += 0.01
		context.invalidate_detail_poll()
		context.poll_sleeping()
		if target.admissions > 0 and first_admission < 0: first_admission = step
	check(first_admission >= 0, "index churn must not indefinitely restart before an eligible tail patch")
	check(target.admissions == 1, "eligible patch admitted exactly once")
	# Control: the same data/cost admits the tail as soon as index churn stops.
	for step in 12:
		context.poll_sleeping()
		if target.admissions > 0: break
	check(target.admissions == 1, "unchanged-index control admits the same patch")
	var prefix_queries := 0
	for patch in prefix:
		prefix_queries += patch.area_queries
		check(not patch._detail_resident, "conservative-bin neighbours stay outside residency")
	Preparation.release_projection(projection); map.free(); await process_frame
	print("GRASS_ADMISSION_CHURN ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"first_admission_step":first_admission,"prefix_queries":prefix_queries}))
	quit(0 if errors.is_empty() else 1)
