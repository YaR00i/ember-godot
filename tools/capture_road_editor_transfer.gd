extends "res://tools/capture_soil_editor_transfer.gd"
## Same transfer harness; road keeps its own existing role, tint and span.
func _init() -> void:
	target_id="cartoon_sand";target_role="sand";target_slot=2;target_span=1.5;target_role_code=-3.0
	saved_pattern_file="saved-road.tres";result_prefix="ROAD_EDITOR"
func colour_variants() -> Array[Image]:
	return Road.painted_variants(Road.painted_image())
func camera_specs() -> Array:
	return [[Vector3(3.55,0.45,5.2),Vector3(0.3,3.4,3.3)],[Vector3(5.1,0.5,6.0),Vector3(0.5,5.0,6.5)]]
