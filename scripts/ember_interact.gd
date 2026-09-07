@tool
class_name EmberInteract
extends Area3D
## Placement interactivity from Ember (door / talk / shop / quest / custom).
## Door destinations use the existing Ember targetMapId/targetRegionId contract.

const KINDS := ["door", "talk", "quest_marker", "shop", "custom", "trigger", "chest"]
const ACTIVATION_MODES := ["press", "enter"]
const QuestState = preload("res://scripts/ember_quest_state.gd")
const QUEST_MARKER_CLEARANCE := 4.0
const QUEST_MARKER_PIXEL_SIZE := 0.00175

@export var kind := "door"
@export var trigger_id := ""
@export var target_map_id := ""
@export var target_region_id := ""
@export var shop_id := ""
@export var script_id := ""
@export var quest_id := ""
@export var icon_id := ""
@export_enum("available", "active", "done") var quest_status := "available"
@export_group("Launch Rules")
@export var condition_flag_id := ""
@export var condition_expected := true
@export var condition_value: Variant = null
@export var fallback_script_id := ""
@export var one_shot := false
@export var completion_flag_id := ""
@export_enum("press", "enter") var activation_mode := "press"
@export_group("")
@export var note := ""

var _quest_marker: Node3D
var _quest_marker_icon: Sprite3D
var _quest_marker_state_visible := true


func _ready() -> void:
	_bind_progress()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	refresh_runtime_binding()


func _exit_tree() -> void:
	var progress := _progress()
	if progress and progress.progress_changed.is_connected(_on_progress_changed):
		progress.progress_changed.disconnect(_on_progress_changed)


func refresh_runtime_binding() -> void:
	var base_actionable := false
	match kind:
		"door":
			base_actionable = not target_map_id.is_empty()
		"talk":
			base_actionable = not script_id.is_empty()
		"shop":
			base_actionable = not shop_id.is_empty() or not script_id.is_empty()
		"custom", "trigger":
			base_actionable = not script_id.is_empty()
		"quest_marker":
			base_actionable = not resolved_action_script_id().is_empty()
	var route := runtime_route()
	var actionable := bool(route.get("available", false)) and (
		base_actionable or not str(route.get("scriptId", "")).is_empty()
	)
	if kind == "quest_marker" and not Engine.is_editor_hint():
		actionable = actionable and bool(effective_quest_marker_projection().get("visible", true))
	if actionable and activation_mode == "press":
		add_to_group("ember_interact")
	else:
		remove_from_group("ember_interact")
	collision_mask = 2 if activation_mode == "enter" else 0
	monitoring = not Engine.is_editor_hint() and activation_mode == "enter" and actionable
	_refresh_quest_marker()
	set_process(kind == "quest_marker")


func _process(_delta: float) -> void:
	if not is_instance_valid(_quest_marker):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var lod := QuestState.marker_lod(global_position.distance_to(camera.global_position))
	_quest_marker.scale = Vector3(lod.x, lod.x, lod.x)
	_quest_marker.visible = _quest_marker_state_visible and lod.y > 0.01
	if not is_instance_valid(_quest_marker_icon):
		return
	var marker_color := _quest_marker_icon.modulate
	marker_color.a = lod.y
	_quest_marker_icon.modulate = marker_color


func resolved_action_script_id() -> String:
	if kind == "quest_marker":
		# Native quest binding separates the action chain from quest progress.
		if not quest_id.is_empty():
			return script_id
		# Legacy scenes stored the quest status flag in script_id and routed the
		# action through a bound imported region. Keep that path read-only until
		# the first Inspector save migrates the marker to quest_id.
		if not trigger_id.is_empty():
			var region := _bound_region()
			if region != null and not region.script_id.is_empty():
				return region.script_id
			var map := _map_owner()
			if map != null:
				var source_region := EmberInteractionContent.region_definition(map.map_id, trigger_id)
				var source_script_id := str(source_region.get("scriptId", "")).strip_edges()
				if not source_script_id.is_empty():
					return source_script_id
		if not EmberQuestCatalog.definition_for_status_flag(script_id).is_empty():
			return ""
	return script_id


func runtime_route(flags_override: Variant = null) -> Dictionary:
	var flags: Dictionary = {}
	if typeof(flags_override) == TYPE_DICTIONARY:
		flags = flags_override
	else:
		var progress := _progress()
		if progress != null:
			flags = progress.flags
	return EmberInteractRules.route(
		resolved_action_script_id(),
		condition_flag_id,
		condition_value if condition_value != null else condition_expected,
		fallback_script_id,
		one_shot,
		completion_flag_id,
		flags,
	)


func runtime_available(flags_override: Variant = null) -> bool:
	return bool(runtime_route(flags_override).get("available", false))


func routed_script_id(flags_override: Variant = null) -> String:
	return str(runtime_route(flags_override).get("scriptId", ""))


func complete_primary_activation(progress: EmberExploreState) -> bool:
	if progress == null or not one_shot or completion_flag_id.strip_edges().is_empty():
		return false
	return progress.set_flag(completion_flag_id, true, false)


func activation_title() -> String:
	return "При входе" if activation_mode == "enter" else "Клавиша F"


func _on_body_entered(body: Node3D) -> void:
	if activation_mode != "enter" or not body is EmberPlayer:
		return
	(body as EmberPlayer).activate_interact(self)


func effective_quest_status() -> String:
	var progress := _progress()
	var flags: Dictionary = progress.flags if progress else {}
	if not quest_id.is_empty():
		return EmberQuestCatalog.marker_status_for_quest(quest_status, quest_id, flags)
	return EmberQuestCatalog.marker_status(quest_status, script_id, flags)


func effective_quest_id() -> String:
	if not quest_id.is_empty():
		return quest_id
	var legacy := EmberQuestCatalog.definition_for_status_flag(script_id)
	return str(legacy.get("id", ""))


func effective_quest_status_flag_id() -> String:
	var definition_value := EmberQuestCatalog.definition(effective_quest_id())
	if not definition_value.is_empty():
		return EmberQuestCatalog.status_flag_id_for(definition_value)
	return script_id if quest_id.is_empty() else ""


func effective_quest_icon_id() -> String:
	var marker := effective_quest_marker_projection()
	return QuestState.resolve_icon_id(icon_id, str(marker.get("status", effective_quest_status())))


func effective_quest_marker_projection(flags_override: Variant = null) -> Dictionary:
	var flags: Dictionary = {}
	if typeof(flags_override) == TYPE_DICTIONARY:
		flags = flags_override
	else:
		var progress := _progress()
		if progress != null:
			flags = progress.flags
	var definition_value := EmberQuestCatalog.definition(effective_quest_id())
	if definition_value.is_empty():
		return QuestState.marker_projection({}, [], effective_quest_status())
	var action_steps: Array = []
	var action_id := resolved_action_script_id()
	if not action_id.is_empty():
		var built := EmberActionScript.queue_for(action_id)
		if bool(built.get("ok", false)):
			action_steps.assign(built.get("steps", []))
	return QuestState.marker_projection(
		EmberQuestCatalog.projection(definition_value, flags),
		action_steps,
		quest_status,
	)


func prompt() -> String:
	match kind:
		"door":
			if target_map_id.is_empty():
				return "Дверь"
			return "Дверь → %s" % target_map_id
		"talk":
			return "Разговор"
		"shop":
			return "Лавка" if shop_id.is_empty() else "Лавка (%s)" % shop_id
		"quest_marker":
			match str(effective_quest_marker_projection().get("status", effective_quest_status())):
				"active": return "Задание в работе"
				"done": return "Задание выполнено"
			return "Новое задание"
		"custom":
			return "Действие"
		"trigger":
			return "Зона"
		"chest":
			return "Сундук"
		_:
			return kind


func distance_to_world(world: Vector3) -> float:
	var shape_node := get_node_or_null("Shape") as CollisionShape3D
	var self_world := _resolved_transform(self)
	if shape_node == null or shape_node.shape == null:
		return self_world.origin.distance_to(world)
	var shape_world := _resolved_transform(shape_node)
	var local := shape_world.affine_inverse() * world
	var delta_local := Vector3.ZERO
	if shape_node.shape is BoxShape3D:
		var half := (shape_node.shape as BoxShape3D).size * 0.5
		delta_local = Vector3(
			maxf(absf(local.x) - half.x, 0.0),
			maxf(absf(local.y) - half.y, 0.0),
			maxf(absf(local.z) - half.z, 0.0),
		)
	elif shape_node.shape is SphereShape3D:
		var excess := maxf(local.length() - (shape_node.shape as SphereShape3D).radius, 0.0)
		delta_local = local.normalized() * excess if excess > 0.0 else Vector3.ZERO
	else:
		return self_world.origin.distance_to(world)
	return (shape_world.basis * delta_local).length()


func _resolved_transform(node: Node3D) -> Transform3D:
	if node.is_inside_tree():
		return node.global_transform
	var resolved := node.transform
	var parent := node.get_parent()
	while parent != null:
		if parent is Node3D:
			resolved = (parent as Node3D).transform * resolved
		parent = parent.get_parent()
	return resolved


func activate() -> String:
	if kind == "door" and not target_map_id.is_empty():
		var progress := get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
		if progress:
			progress.save_autosave()
		var error := EmberMapTransition.change_scene(
			get_tree(),
			target_map_id,
			target_region_id,
		)
		if error == OK:
			return "enter %s" % target_map_id
		return "карта не импортирована: %s" % target_map_id
	if kind == "shop":
		return "shop %s (UI later)" % (shop_id if not shop_id.is_empty() else "?")
	if kind == "talk":
		return "talk %s" % (script_id if not script_id.is_empty() else "?")
	return prompt()


func _bound_region() -> EmberRegion:
	var current: Node = self
	while current != null and not current is EmberMapLoader:
		current = current.get_parent()
	if current == null:
		return null
	var regions := current.get_node_or_null("Regions")
	if regions == null:
		regions = current.get_node_or_null("Map/Regions")
	if regions == null:
		return null
	for child in regions.get_children():
		var region := child as EmberRegion
		if region != null and (region.region_id == trigger_id or str(region.name) == trigger_id):
			return region
	return null


func _map_owner() -> EmberMapLoader:
	var current: Node = self
	while current != null:
		if current is EmberMapLoader:
			return current as EmberMapLoader
		current = current.get_parent()
	return null


func _bind_progress() -> void:
	var progress := _progress()
	if progress and not progress.progress_changed.is_connected(_on_progress_changed):
		progress.progress_changed.connect(_on_progress_changed)


func _progress() -> EmberExploreState:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EmberExploreProgress") as EmberExploreState


func _on_progress_changed() -> void:
	refresh_runtime_binding()
	_refresh_quest_marker()


func _refresh_quest_marker() -> void:
	if kind != "quest_marker":
		if is_instance_valid(_quest_marker):
			_quest_marker.queue_free()
		_quest_marker = null
		_quest_marker_icon = null
		return
	if not is_instance_valid(_quest_marker):
		_quest_marker = get_node_or_null("QuestMarker") as Node3D
	# Runtime markers used to be bare Label3D glyphs. Replace an old live node
	# after script reload instead of nesting the new visual under it.
	if is_instance_valid(_quest_marker) and _quest_marker is Label3D:
		_quest_marker.free()
		_quest_marker = null
	if not is_instance_valid(_quest_marker):
		_quest_marker = Node3D.new()
		_quest_marker.name = "QuestMarker"
		add_child(_quest_marker)
	_quest_marker.position = _quest_marker_anchor()
	if not is_instance_valid(_quest_marker_icon):
		_quest_marker_icon = _quest_marker.get_node_or_null("Icon") as Sprite3D
	if not is_instance_valid(_quest_marker_icon):
		_quest_marker_icon = Sprite3D.new()
		_quest_marker_icon.name = "Icon"
		_quest_marker.add_child(_quest_marker_icon)
	# A 64 px SVG at this pixel size has virtually the same near-screen extent
	# as the accepted 30 px Label3D glyph at 0.0035, while giving each state a
	# distinct silhouette. The parent remains the sole LOD/anchor pivot.
	_quest_marker_icon.pixel_size = QUEST_MARKER_PIXEL_SIZE
	_quest_marker_icon.centered = true
	_quest_marker_icon.offset = Vector2.ZERO
	_quest_marker_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_quest_marker_icon.no_depth_test = true
	_quest_marker_icon.fixed_size = true
	var marker := effective_quest_marker_projection()
	var status := str(marker.get(
		"authoringStatus" if Engine.is_editor_hint() else "status",
		effective_quest_status(),
	))
	_quest_marker_state_visible = Engine.is_editor_hint() or bool(marker.get("visible", true))
	_quest_marker.visible = _quest_marker_state_visible
	_quest_marker_icon.texture = load(QuestState.marker_icon_path(icon_id, status)) as Texture2D
	_quest_marker_icon.modulate = Color.WHITE


func _quest_marker_anchor() -> Vector3:
	var prop := get_parent() as Node3D
	if prop == null:
		return Vector3(0.0, 28.0, 0.0)
	var mesh := prop.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return Vector3(0.0, 28.0, 0.0)
	var bounds := mesh.get_aabb()
	var top_center := bounds.position + Vector3(
		bounds.size.x * 0.5,
		bounds.size.y,
		bounds.size.z * 0.5,
	)
	var anchor_in_prop := mesh.transform * top_center + Vector3.UP * QUEST_MARKER_CLEARANCE
	return transform.affine_inverse() * anchor_in_prop
