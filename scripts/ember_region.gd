@tool
class_name EmberRegion
extends Area3D
## Map region from Ember JSON (player_start / trigger / teleport / …).

@export var region_id := ""
@export var map_id := ""
@export var kind := "trigger"
@export var target_map_id := ""
@export var target_region_id := ""
@export var bound_object_id := ""
@export var script_id := ""
@export var loot_ids: Array[String] = []
@export var closed_model_id := ""
@export var open_model_id := ""
@export var model_offset_x := 0.0
@export var model_offset_y := 0.0
@export var model_rot := 0
@export var model_scale := 1.0
var model_elev: Variant = null
@export var repeatable := false
@export var opened := false
@export var note := ""

var progress_state: EmberExploreState
var _transitioning := false
var _transition_connected := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	refresh_runtime_binding()


func refresh_runtime_binding() -> void:
	if kind == "chest" or (kind == "trigger" and not script_id.is_empty() and target_map_id.is_empty()):
		add_to_group("ember_interact")
	else:
		remove_from_group("ember_interact")
	if kind != "trigger" or target_map_id.is_empty() or _transition_connected:
		return
	# EmberPlayer is on physics layer 2. Imported regions stay inert unless they
	# are authored map-transition triggers.
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	_transition_connected = true


func _on_body_entered(body: Node3D) -> void:
	if _transitioning or not body is EmberPlayer:
		return
	if not EmberMapTransition.trigger_allowed(region_id):
		return
	_transitioning = true
	var progress := _progress()
	if progress:
		progress.save_autosave()
	var error := EmberMapTransition.change_scene(
		get_tree(),
		target_map_id,
		target_region_id,
	)
	if error != OK:
		_transitioning = false
		push_error("ember region %s: target scene %s is unavailable" % [region_id, target_map_id])


func is_player_start() -> bool:
	return kind == "player_start"


func contains_world_xz(world: Vector3) -> bool:
	var shape_node := get_node_or_null("Shape") as CollisionShape3D
	var box: BoxShape3D = shape_node.shape as BoxShape3D if shape_node else null
	if box == null:
		return false
	var local := to_local(world)
	return (
		absf(local.x) <= box.size.x * 0.5
		and absf(local.z) <= box.size.z * 0.5
	)


func prompt() -> String:
	if kind == "chest":
		var progress := _progress()
		if opened or (progress and progress.chest_is_opened(map_id, region_id)):
			return "Сундук уже открыт" if not repeatable else "Сундук"
		return "Открыть сундук"
	if kind == "trigger" and not script_id.is_empty():
		return "Действие"
	return note if not note.is_empty() else kind


func activate() -> String:
	if kind != "chest":
		return prompt()
	var progress := _progress()
	if progress == null:
		return "Состояние игры недоступно"
	var result := progress.open_chest(map_id, region_id, loot_ids, repeatable)
	if not bool(result.get("ok", false)):
		return "Сундук уже открыт"
	opened = true
	refresh_chest_visual(_visual_tile_size)
	var names: Array = result.get("names", [])
	return "Сундук пуст" if names.is_empty() else "Лут: %s" % ", ".join(names)


func refresh_chest_visual(tile_size: float) -> void:
	_visual_tile_size = maxf(1.0, tile_size)
	var existing := get_node_or_null("ChestVisual") as EmberVoxelProp
	if kind != "chest":
		if existing:
			existing.queue_free() if existing.is_inside_tree() else existing.free()
		return
	var progress := _progress()
	var is_open := opened or (progress and progress.chest_is_opened(map_id, region_id))
	var model_id := open_model_id if is_open and not open_model_id.is_empty() else closed_model_id
	if model_id.is_empty():
		if existing:
			existing.queue_free() if existing.is_inside_tree() else existing.free()
		return
	if existing == null or existing.model_id != model_id:
		if existing:
			remove_child(existing)
			existing.free()
		existing = EmberVoxelPrefab.instantiate(model_id, _visual_tile_size, {})
		if existing == null:
			push_warning("ember chest %s: visual model %s unavailable" % [region_id, model_id])
			return
		existing.name = "ChestVisual"
		existing.placement_id = "%s:chest" % region_id
		add_child(existing)
	_sync_chest_visual_transform(existing)


func _sync_chest_visual_transform(visual: EmberVoxelProp) -> void:
	visual.position = Vector3(
		clampf(model_offset_x, -4.0, 4.0) * _visual_tile_size,
		float(model_elev) * _visual_tile_size - position.y if model_elev != null else -2.0,
		clampf(model_offset_y, -4.0, 4.0) * _visual_tile_size,
	)
	visual.rotation.y = posmod(model_rot, 4) * PI * 0.5
	visual.scale = Vector3.ONE * clampf(model_scale, 0.25, 3.0)


func _progress() -> EmberExploreState:
	if progress_state != null:
		return progress_state
	return get_node_or_null("/root/EmberExploreProgress") as EmberExploreState


var _visual_tile_size := 16.0
