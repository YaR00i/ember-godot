@tool
class_name EmberCombatGrid3DWorld
extends Node3D
## Standard Godot 3D projection of the pure combat snapshot.
## The scene owns GridMap/camera/light nodes; combat legality stays in the resolver.

signal cell_chosen(cell: Vector2i, unit_id: String)

const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Terrain = preload("res://scripts/prototypes/ember_combat_terrain.gd")
const TileLibrary := preload("res://scripts/prototypes/ember_battlefield_tile_library.gd")
const SurfaceProjection := preload("res://scripts/ember_voxel_surface_projection.gd")
const WaterContact := preload("res://scripts/ember_water_contact_3d.gd")

const ITEM_NEUTRAL := TileLibrary.ITEM_NEUTRAL
const ITEM_WET := TileLibrary.ITEM_WET
const ITEM_EMBER := TileLibrary.ITEM_EMBER
const ITEM_FROZEN := TileLibrary.ITEM_FROZEN
const ITEM_BLOCKED := TileLibrary.ITEM_BLOCKED
const ITEM_BLOCKED_FADED := TileLibrary.ITEM_BLOCKED_FADED

const CELL_SIZE := 1.2
const ELEVATION_HEIGHT := 0.52
const TILE_HEIGHT := 0.18
const BLOCKED_HEIGHT := 0.78
const UNIT_Y_OFFSET := 0.42
const MOVE_DURATION_PER_CELL := 0.13
const STAGED_MOVE_DURATION := 0.28
const LIFT_DURATION := 0.22
const THROW_DURATION := 0.38

@export_group("Предпросмотр арены в редакторе")
@export var editor_preview_enabled := true
@export_enum("E2 · Цветная переправа", "E3 · Хранитель оттепели") var editor_preview_mode := 0
@export_group("Данные поля боя")
@export var battlefield: EmberBattlefieldResource

var _state: Dictionary = {}
var _selected_action := ""
var _selected_target := ""
var _pending_cell := Vector2i(-1, -1)
var _pending_focus_valid := false
var _move_mode := false
var _preview: Dictionary = {}
var _secondary_cell := Combat.INVALID_CELL
var _target_cell := Combat.INVALID_CELL
var _lifted_target_id := ""
var _pair_context_action := ""
var _editor_preview_signature := ""
var _visual_surface_projection: Node3D
var _last_active_id := ""
var _last_active_focus_cell := Vector2i(-1, -1)
var _last_field_size := Vector2i.ZERO
var _last_occlusion_signature := ""
var _camera_overview_requested := true
var _queued_action_animations: Array[Dictionary] = []
var _unit_roots: Dictionary = {}
var _unit_target_positions: Dictionary = {}
var _projection_field_id := ""
var _animation_generation := 0

@onready var _grid_map := get_node("CombatGridMap") as GridMap
@onready var _camera := get_node("CameraRig/CombatCamera3D") as Camera3D
@onready var _dynamic_root := get_node("CombatActors3D") as Node3D
@onready var _overlay_root := get_node("CombatOverlays3D") as Node3D
@onready var _pair_context_root := get_node("CombatPairContext3D") as Node3D


func _ready() -> void:
	if _grid_map.mesh_library == null:
		_grid_map.mesh_library = TileLibrary.default_library()
	set_process(true)
	if Engine.is_editor_hint():
		render_editor_preview()
	else:
		_rebuild_projection()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_update_occlusion()
		return
	var signature := "%s|%d|%s|%s" % [
		editor_preview_enabled,
		editor_preview_mode,
		battlefield.content_signature() if battlefield != null else "missing",
		_visual_surface_identity(),
	]
	if signature != _editor_preview_signature:
		update_configuration_warnings()
		render_editor_preview()


func render_editor_preview() -> void:
	if _grid_map == null:
		return
	_editor_preview_signature = "%s|%d|%s|%s" % [
		editor_preview_enabled,
		editor_preview_mode,
		battlefield.content_signature() if battlefield != null else "missing",
		_visual_surface_identity(),
	]
	if not editor_preview_enabled:
		_state = {}
		_rebuild_projection()
		return
	_state = (
		Grid.field_mutation_state(battlefield)
		if editor_preview_mode == 1
		else Grid.initial_state(battlefield)
	)
	_selected_action = ""
	_selected_target = ""
	_preview = {}
	_secondary_cell = Combat.INVALID_CELL
	_move_mode = false
	var actor_id := Combat.current_unit_id(_state)
	var actor := Combat.unit_definition(_state, actor_id)
	_pending_cell = actor.get("cell", Vector2i.ZERO)
	_pending_focus_valid = false
	for raw_action in actor.get("actions", []):
		var action_id := str(raw_action)
		var targets := Combat.valid_target_ids(_state, action_id)
		if targets.is_empty():
			continue
		_selected_action = action_id
		_selected_target = targets[0]
		_preview = Grid.command_preview(
			_state, _selected_action, _selected_target, _pending_cell
		)
		break
	_rebuild_projection()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if battlefield == null:
		warnings.append("Назначьте Battlefield Resource для preview и runtime данных поля.")
	else:
		warnings.append_array(PackedStringArray(battlefield.validation_errors()))
	warnings.append_array(tile_library_validation_errors())
	return warnings


func tile_library_validation_errors() -> PackedStringArray:
	var grid_map: GridMap = (
		_grid_map
		if is_instance_valid(_grid_map)
		else get_node_or_null("CombatGridMap") as GridMap
	)
	return TileLibrary.validation_errors(grid_map.mesh_library if grid_map != null else null)


func configure(
	state: Dictionary,
	selected_action: String,
	selected_target: String,
	pending_cell: Vector2i,
	move_mode: bool,
	preview: Dictionary = {},
	secondary_cell: Vector2i = Combat.INVALID_CELL,
	lifted_target_id: String = "",
	target_cell: Vector2i = Combat.INVALID_CELL,
) -> void:
	_state = state
	_selected_action = selected_action
	_selected_target = selected_target
	_pending_cell = pending_cell
	_pending_focus_valid = _is_pending_focus_valid()
	_move_mode = move_mode
	_preview = preview
	_secondary_cell = secondary_cell
	_lifted_target_id = lifted_target_id
	_target_cell = target_cell
	if is_inside_tree() and _grid_map != null:
		_update_camera_context()
		_rebuild_projection()


func projected_item_at(cell: Vector2i) -> int:
	if _grid_map == null:
		return GridMap.INVALID_CELL_ITEM
	return _grid_map.get_cell_item(_map_cell(cell))


func screen_position_for_cell(cell: Vector2i) -> Vector2:
	if _camera == null:
		return Vector2(-1.0, -1.0)
	return _camera.unproject_position(_world_position(cell, TILE_HEIGHT * 0.7))


func pick_cell_at(screen_position: Vector2) -> Vector2i:
	return _pick_cell(screen_position)


func editor_pick_cell(viewport_camera: Camera3D, screen_position: Vector2) -> Vector2i:
	return _pick_cell_from_camera(viewport_camera, screen_position)


func editor_cell_corners(cell: Vector2i) -> PackedVector3Array:
	if _grid_map == null or not Grid.is_inside(_state, cell):
		return PackedVector3Array()
	var center := _grid_map.map_to_local(_map_cell(cell))
	center.y += _cell_surface_offset(cell)
	var half := CELL_SIZE * 0.47
	return PackedVector3Array([
		_grid_map.to_global(center + Vector3(-half, 0.0, -half)),
		_grid_map.to_global(center + Vector3(half, 0.0, -half)),
		_grid_map.to_global(center + Vector3(half, 0.0, half)),
		_grid_map.to_global(center + Vector3(-half, 0.0, half)),
	])


func projected_occupant_at(cell: Vector2i) -> String:
	return _display_occupant(cell)


func set_pair_context_action(action_id: String) -> void:
	var action := Combat.command_definition(_pair_selection_state(), action_id)
	_pair_context_action = (
		action_id if not str(action.get("partnerId", "")).is_empty() else ""
	)
	_refresh_pair_context()


func pair_context_snapshot() -> Dictionary:
	return Combat.duo_partner_context(_pair_selection_state(), _pair_context_action)


func request_camera_overview() -> void:
	_camera_overview_requested = true
	_queued_action_animations.clear()


func queue_action_animation(before_state: Dictionary, resolved: Dictionary) -> void:
	if Engine.is_editor_hint() or not bool(resolved.get("ok", false)):
		return
	_queued_action_animations.append({
		"before": before_state.duplicate(true),
		"resolved": resolved.duplicate(true),
	})


func show_battlefield_overview(smooth: bool = true) -> void:
	var camera_rig := get_node_or_null("CameraRig")
	if camera_rig != null and camera_rig.has_method("return_home_view"):
		camera_rig.call("return_home_view", smooth)


func camera_control_snapshot() -> Dictionary:
	var camera_rig := get_node_or_null("CameraRig")
	return (
		camera_rig.call("control_snapshot") as Dictionary
		if camera_rig != null and camera_rig.has_method("control_snapshot")
		else {}
	)


func set_camera_invert_vertical(enabled: bool) -> void:
	_set_camera_control("set_invert_vertical", enabled)


func set_camera_axis_lock(enabled: bool) -> void:
	_set_camera_control("set_axis_lock", enabled)


func set_camera_horizontal_lock(enabled: bool) -> void:
	_set_camera_control("set_horizontal_rotation_lock", enabled)


func set_camera_vertical_lock(enabled: bool) -> void:
	_set_camera_control("set_vertical_rotation_lock", enabled)


func set_camera_angle_lock(enabled: bool) -> void:
	_set_camera_control("set_angle_lock", enabled)


func handle_camera_input(event: InputEvent) -> bool:
	var camera_rig := get_node_or_null("CameraRig")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		focus_active_unit(true)
		return true
	return (
		bool(camera_rig.call("handle_input", event))
		if camera_rig != null and camera_rig.has_method("handle_input")
		else false
	)


func choose_cell_at(screen_position: Vector2) -> bool:
	var cell := _pick_cell(screen_position)
	if not Grid.is_inside(_state, cell):
		return false
	var actual_occupant := Grid.occupant_id(_state, cell)
	if _move_mode:
		var actor_id := Combat.current_unit_id(_state)
		if cell not in Grid.reachable_cells(_state, actor_id):
			return false
		if (
			(not actual_occupant.is_empty() and actual_occupant != actor_id)
			or Grid.is_focus_cell(_state, cell)
		):
			return false
	cell_chosen.emit(cell, _display_occupant(cell))
	return true


func focus_active_unit(smooth: bool = true) -> bool:
	return _focus_active_unit(smooth)

func _rebuild_projection() -> void:
	if _grid_map == null:
		return
	var previous_positions := _capture_unit_positions()
	var field_id := _current_field_identity()
	var can_animate := (
		not Engine.is_editor_hint()
		and not previous_positions.is_empty()
		and field_id == _projection_field_id
	)
	_animation_generation += 1
	var generation := _animation_generation
	_grid_map.clear()
	_clear_children(_dynamic_root)
	_clear_children(_overlay_root)
	_clear_children(_pair_context_root)
	_unit_roots.clear()
	_unit_target_positions.clear()
	if _state.is_empty() or not _state.has("grid"):
		_projection_field_id = field_id
		_queued_action_animations.clear()
		return
	var grid: Dictionary = _state.get("grid", {})
	for y in int(grid.get("height", Grid.HEIGHT)):
		for x in int(grid.get("width", Grid.WIDTH)):
			var cell := Vector2i(x, y)
			_grid_map.set_cell_item(_map_cell(cell), _item_for(cell))
			_add_cell_label(cell)
	_refresh_visual_surface()
	_add_focus()
	_add_units(previous_positions if can_animate else {})
	if Engine.is_editor_hint():
		_add_deployment_markers()
	_add_overlays()
	_refresh_pair_context()
	_update_occlusion(true)
	_projection_field_id = field_id
	var animations := _queued_action_animations.duplicate(true)
	_queued_action_animations.clear()
	if can_animate and not animations.is_empty():
		_play_action_animations.call_deferred(animations, generation)
	elif can_animate:
		_animate_changed_units(generation)


func _visual_surface_identity() -> String:
	if battlefield == null or battlefield.visual_surface == null:
		return "none"
	var surface := battlefield.visual_surface
	return "%s|%s|%d" % [surface.resource_path, surface.model_id, surface.get_instance_id()]


func _refresh_visual_surface() -> void:
	_ensure_visual_surface_projection()
	var next := battlefield.visual_surface if battlefield != null else null
	var expected := (
		Vector2i(battlefield.width, battlefield.height)
		if battlefield != null
		else Vector2i.ZERO
	)
	_visual_surface_projection.call("configure", next, CELL_SIZE, expected, _grid_map)


func _ensure_visual_surface_projection() -> void:
	if is_instance_valid(_visual_surface_projection):
		return
	_visual_surface_projection = SurfaceProjection.new()
	_visual_surface_projection.name = "DerivedVoxelBattleSurface"
	add_child(_visual_surface_projection)


func _item_for(cell: Vector2i) -> int:
	var definition := _projected_cell_definition(cell)
	if bool(definition.get("blocked", false)):
		return ITEM_BLOCKED
	var tags: Array = definition.get("tags", [])
	if "frozen" in tags:
		return ITEM_FROZEN
	if "wet" in tags:
		return ITEM_WET
	if str(definition.get("group", "")) == "ember":
		return ITEM_EMBER
	return ITEM_NEUTRAL


func _add_units(previous_positions: Dictionary = {}) -> void:
	var active_id := Combat.current_unit_id(_state)
	var active := Combat.unit_definition(_state, active_id)
	var active_cell: Vector2i = active.get("cell", Vector2i(-1, -1))
	var reachable := Grid.reachable_cells(_state, active_id)
	var staged := (
		_pending_cell != Vector2i(-1, -1)
		and _pending_cell != active_cell
		and _pending_cell in reachable
	)
	for raw_id in _state.get("units", {}):
		var unit_id := str(raw_id)
		var unit := Combat.unit_definition(_state, unit_id)
		if int(unit.get("hp", 0)) <= 0:
			continue
		var cell: Vector2i = unit.get("cell", Vector2i.ZERO)
		var planned := staged and unit_id == active_id
		if planned:
			cell = _pending_cell
		var root := Node3D.new()
		root.name = "CombatUnit_%s" % unit_id
		var final_position := _world_position(cell, UNIT_Y_OFFSET)
		if unit_id == _lifted_target_id and _is_lift_selection_active():
			var carrier_cell := active_cell
			if staged:
				carrier_cell = _pending_cell
			final_position = _world_position(carrier_cell, UNIT_Y_OFFSET) + Vector3.UP * 1.45
		root.position = previous_positions.get(unit_id, final_position)
		_dynamic_root.add_child(root)
		_unit_roots[unit_id] = root
		_unit_target_positions[unit_id] = final_position
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.19
		capsule.height = 0.72
		var team_color: Color = unit.get(
			"battleColor",
			Color("65cfe1") if str(unit.get("team", "")) == "hero" else Color("f07883"),
		)
		body.mesh = capsule
		body.material_override = _material(team_color.lightened(0.18) if planned else team_color, planned)
		root.add_child(body)
		var outline := MeshInstance3D.new()
		outline.name = "CombatUnitOutline_%s" % unit_id
		var outline_capsule := CapsuleMesh.new()
		outline_capsule.radius = 0.215
		outline_capsule.height = 0.75
		outline.mesh = outline_capsule
		outline.material_override = _outline_material(team_color)
		root.add_child(outline)
		var water_contact: Node3D = WaterContact.new()
		water_contact.name = "WaterContact"
		water_contact.set("radius_blocks", 0.27)
		water_contact.set("feet_offset_blocks", -0.30)
		root.add_child(water_contact)
		var label := Label3D.new()
		label.text = "%s%s\n%d/%d" % [
			str(unit.get("name", unit_id)), " · план" if planned else "",
			int(unit.get("hp", 0)), int(unit.get("maxHp", 0)),
		]
		label.position.y = 0.7
		label.font_size = 34
		label.outline_size = 7
		label.pixel_size = 0.0043
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("ffe6a6") if planned else Color.WHITE
		root.add_child(label)
		_add_status_badges(root, unit_id, unit)


func _is_lift_selection_active() -> bool:
	return (
		not _lifted_target_id.is_empty()
		and _selected_target == _lifted_target_id
		and str(Combat.command_definition(_state, _selected_action).get("effect", "")) == "lift_throw"
	)


func _add_status_badges(root: Node3D, unit_id: String, unit: Dictionary) -> void:
	var visible_index := 0
	var statuses := unit.get("statuses", {}) as Dictionary
	for raw_id in statuses:
		var duration := int(statuses[raw_id])
		if duration <= 0:
			continue
		var status_id := str(raw_id)
		var definition := Combat.status_definition(status_id)
		var kind := str(definition.get("kind", "debuff"))
		var badge := Label3D.new()
		badge.name = "CombatStatus_%s_%s" % [unit_id, status_id]
		badge.text = "%s %s %s · %d" % [
			"▲" if kind == "buff" else "▼",
			str(definition.get("icon", "●")),
			str(definition.get("name", status_id)),
			duration,
		]
		badge.position.y = 1.03 + float(visible_index) * 0.21
		badge.font_size = 29
		badge.outline_size = 8
		badge.pixel_size = 0.0038
		badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		badge.modulate = definition.get("color", Color.WHITE)
		root.add_child(badge)
		visible_index += 1


func _capture_unit_positions() -> Dictionary:
	var result := {}
	for raw_id in _unit_roots:
		var unit_id := str(raw_id)
		var root := _unit_roots[raw_id] as Node3D
		if is_instance_valid(root):
			result[unit_id] = root.position
	return result


func _current_field_identity() -> String:
	var grid: Dictionary = _state.get("grid", {})
	return "%s|%dx%d" % [
		str(battlefield.field_id) if battlefield != null else "runtime",
		int(grid.get("width", 0)),
		int(grid.get("height", 0)),
	]


func _animate_changed_units(generation: int) -> void:
	if generation != _animation_generation:
		return
	for raw_id in _unit_roots:
		var unit_id := str(raw_id)
		var root := _unit_roots[raw_id] as Node3D
		var destination: Vector3 = _unit_target_positions.get(unit_id, root.position)
		if is_instance_valid(root) and root.position.distance_to(destination) > 0.01:
			_arc_tween_to(root, destination, STAGED_MOVE_DURATION, 0.18)


func _play_action_animations(animations: Array, generation: int) -> void:
	for raw_packet in animations:
		if generation != _animation_generation:
			return
		var packet := raw_packet as Dictionary
		var before := packet.get("before", {}) as Dictionary
		var resolved := packet.get("resolved", {}) as Dictionary
		var actor_id := str(resolved.get("actorId", ""))
		var target_id := str(resolved.get("targetId", ""))
		var partner_id := str(resolved.get("partnerId", ""))
		var action_id := str(resolved.get("actionId", ""))
		var action := Combat.command_definition(before, action_id)
		var effect := str(action.get("effect", ""))
		var actor_root := _unit_roots.get(actor_id) as Node3D
		var movement_tween := _path_tween(actor_root, resolved.get("movementPath", []))
		if movement_tween != null:
			await movement_tween.finished
			if generation != _animation_generation:
				return
		if not partner_id.is_empty() and partner_id != actor_id:
			var actor_pair_tween := _pulse_tween(actor_root, 1.12)
			var partner_pair_tween := _pulse_tween(
				_unit_roots.get(partner_id) as Node3D, 1.12
			)
			if partner_pair_tween != null:
				await partner_pair_tween.finished
			elif actor_pair_tween != null:
				await actor_pair_tween.finished
			if generation != _animation_generation:
				return
		if effect == "lift_throw":
			var thrown_root := _unit_roots.get(target_id) as Node3D
			var throw_destination = (resolved.get("moves", {}) as Dictionary).get(target_id)
			if is_instance_valid(thrown_root) and throw_destination is Vector2i:
				var lift_tween := _lift_throw_tween(
					thrown_root,
					actor_root,
					_world_position(throw_destination, UNIT_Y_OFFSET),
				)
				if lift_tween != null:
					await lift_tween.finished
		elif effect == "defend":
			var defend_tween := _pulse_tween(actor_root, 1.16)
			if defend_tween != null:
				await defend_tween.finished
		elif effect == "item_use":
			var item_tween := _pulse_tween(_unit_roots.get(target_id) as Node3D, 1.14)
			if item_tween != null:
				await item_tween.finished
		elif action_id == "remote_relay":
			var focus_tween := _pulse_tween(
				_dynamic_root.get_node_or_null("CombatGeoFocus3D") as Node3D, 1.22
			)
			if focus_tween != null:
				await focus_tween.finished
		elif (
			action_id in ["forge_leap", "overheat"]
			or target_id.is_empty()
		):
			var self_tween := _pulse_tween(actor_root, 1.16)
			if self_tween != null:
				await self_tween.finished
		elif not (resolved.get("restoreHp", {}) as Dictionary).is_empty():
			var heal_tween := _pulse_tween(_unit_roots.get(target_id) as Node3D, 1.18)
			if heal_tween != null:
				await heal_tween.finished
		else:
			var target_position := _position_for_unit(before, target_id)
			var lunge_tween := _lunge_tween(actor_root, target_position)
			if lunge_tween != null:
				await lunge_tween.finished
			for raw_moved_id in (resolved.get("moves", {}) as Dictionary):
				var moved_id := str(raw_moved_id)
				if moved_id == actor_id:
					continue
				var moved_root := _unit_roots.get(moved_id) as Node3D
				var moved_cell = (resolved.get("moves", {}) as Dictionary)[raw_moved_id]
				if is_instance_valid(moved_root) and moved_cell is Vector2i:
					var pushed_tween := _arc_tween_to(
						moved_root, _world_position(moved_cell, UNIT_Y_OFFSET), 0.26, 0.32
					)
					await pushed_tween.finished
		for raw_damaged_id in (resolved.get("damage", {}) as Dictionary):
			var hit_tween := _pulse_tween(_unit_roots.get(str(raw_damaged_id)) as Node3D, 1.2)
			if hit_tween != null:
				await hit_tween.finished
		if generation != _animation_generation:
			return
	_animate_changed_units(generation)


func _path_tween(root: Node3D, raw_path: Variant) -> Tween:
	if not is_instance_valid(root) or not (raw_path is Array):
		return null
	if not raw_path.is_empty() and raw_path[-1] is Vector2i:
		var final_position := _world_position(raw_path[-1], UNIT_Y_OFFSET)
		# The player already saw staged movement. Do not rewind that actor to the
		# canonical origin when the action is finally committed.
		if root.position.distance_to(final_position) <= 0.01:
			return null
	var tween := root.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var planned_start := root.position
	var segment_count := 0
	for raw_cell in raw_path:
		if not (raw_cell is Vector2i):
			continue
		var destination := _world_position(raw_cell, UNIT_Y_OFFSET)
		if planned_start.distance_to(destination) <= 0.01:
			planned_start = destination
			continue
		var segment_start := planned_start
		var duration := MOVE_DURATION_PER_CELL
		tween.tween_method(
			_set_arc_position.bind(root, segment_start, destination, 0.16),
			0.0,
			1.0,
			duration,
		)
		planned_start = destination
		segment_count += 1
	if segment_count == 0:
		tween.kill()
		return null
	return tween


func _arc_tween_to(root: Node3D, destination: Vector3, duration: float, height: float) -> Tween:
	if not is_instance_valid(root) or root.position.distance_to(destination) <= 0.01:
		return null
	var start := root.position
	var tween := root.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		_set_arc_position.bind(root, start, destination, height), 0.0, 1.0, duration
	)
	return tween


func _lift_throw_tween(root: Node3D, actor_root: Node3D, destination: Vector3) -> Tween:
	if not is_instance_valid(root):
		return null
	var start := root.position
	var carrier := actor_root.position if is_instance_valid(actor_root) else start
	var lifted := carrier + Vector3.UP * 1.45
	var tween := root.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# A player-selected target is already held above the carrier while choosing
	# the landing cell. AI actions still include the complete lift phase.
	if start.distance_to(lifted) > 0.03:
		tween.tween_method(
			_set_arc_position.bind(root, start, lifted, 0.18), 0.0, 1.0, LIFT_DURATION
		)
	tween.tween_interval(0.08)
	tween.tween_method(
		_set_arc_position.bind(root, lifted, destination, 1.0), 0.0, 1.0, THROW_DURATION
	)
	return tween


func _lunge_tween(root: Node3D, target_position: Vector3) -> Tween:
	if not is_instance_valid(root) or target_position == Vector3.INF:
		return null
	var start := root.position
	var destination := start.lerp(target_position, 0.24)
	if start.distance_to(destination) <= 0.01:
		return null
	var tween := root.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(root, "position", destination, 0.1)
	tween.tween_property(root, "position", start, 0.12)
	return tween


func _pulse_tween(root: Node3D, amount: float) -> Tween:
	if not is_instance_valid(root):
		return null
	var tween := root.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "scale", Vector3(amount, 2.0 - amount, amount), 0.1)
	tween.tween_property(root, "scale", Vector3.ONE, 0.14)
	return tween


func _position_for_unit(snapshot: Dictionary, unit_id: String) -> Vector3:
	var unit := Combat.unit_definition(snapshot, unit_id)
	return (
		_world_position(unit.get("cell", Vector2i.ZERO), UNIT_Y_OFFSET)
		if unit.has("cell")
		else Vector3.INF
	)


func _set_arc_position(
	weight: float,
	root: Node3D,
	start: Vector3,
	destination: Vector3,
	height: float,
) -> void:
	if not is_instance_valid(root):
		return
	root.position = start.lerp(destination, weight) + Vector3.UP * sin(PI * weight) * height


func _add_focus() -> void:
	var focus := Grid.focus_definition(_state)
	if focus.is_empty():
		return
	var cell: Vector2i = focus.get("cell", Vector2i(-1, -1))
	if not Grid.is_inside(_state, cell):
		return
	var root := Node3D.new()
	root.name = "CombatGeoFocus3D"
	root.position = _world_position(cell, 0.34)
	_dynamic_root.add_child(root)
	var activated: bool = "activated" in Grid.cell_definition(_state, cell).get("tags", [])
	var focus_color := Color("79d8a3") if activated else Color("ffbf47")
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.1
	mesh.bottom_radius = 0.23
	mesh.height = 0.58
	mesh.radial_segments = 6
	mesh.material = _material(focus_color, true)
	mesh_instance.mesh = mesh
	root.add_child(mesh_instance)
	var label := Label3D.new()
	label.name = "CombatFocusState"
	label.text = "✓ УЗЕЛ АКТИВЕН" if activated else "УЗЕЛ"
	label.position.y = 0.72
	label.font_size = 30
	label.outline_size = 7
	label.pixel_size = 0.0038
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = focus_color
	root.add_child(label)


func _add_deployment_markers() -> void:
	if battlefield == null:
		return
	for index in battlefield.party_deployment_cells.size():
		_add_deployment_marker(
			battlefield.party_deployment_cells[index], "Г%d" % (index + 1), Color("62d7e6")
		)
	for index in battlefield.enemy_deployment_cells.size():
		_add_deployment_marker(
			battlefield.enemy_deployment_cells[index], "В%d" % (index + 1), Color("f07883")
		)


func _add_deployment_marker(cell: Vector2i, text: String, color: Color) -> void:
	if not battlefield.contains(cell):
		return
	var root := Node3D.new()
	root.name = "CombatDeployment_%s" % text
	root.position = _world_position(cell, TILE_HEIGHT * 0.62)
	_overlay_root.add_child(root)
	var plate := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL_SIZE * 0.58, CELL_SIZE * 0.58)
	var plate_color := color
	plate_color.a = 0.38
	plane.material = _material(plate_color, true, true)
	plate.mesh = plane
	root.add_child(plate)
	var label := Label3D.new()
	label.text = text
	label.position.y = 0.025
	label.rotation_degrees.x = -90.0
	label.font_size = 30
	label.outline_size = 6
	label.pixel_size = 0.004
	label.modulate = color.lightened(0.18)
	root.add_child(label)


func _add_overlays() -> void:
	var active_id := Combat.current_unit_id(_state)
	var active := Combat.unit_definition(_state, active_id)
	var reachable := Grid.reachable_cells(_state, active_id)
	var valid_targets := _valid_targets_from_staged_state()
	var valid_target_cells := _valid_target_cells_from_staged_state()
	var approach_destination: Vector2i = _preview.get(
		"approachDestination", Combat.INVALID_CELL
	)
	var approach_fallback := bool(_preview.get("approachFallbackDefend", false))
	var approach_path: Array[Vector2i] = []
	for raw_cell in _preview.get("approachPath", []):
		if raw_cell is Vector2i:
			approach_path.append(raw_cell)
	var secondary_cells: Array[Vector2i] = []
	if (
		str(Combat.command_definition(_state, _selected_action).get("effect", "")) == "lift_throw"
		and not _selected_target.is_empty()
	):
		var staged := Grid.stage_move(_state, _pending_cell)
		if not staged.is_empty():
			secondary_cells = Combat.valid_secondary_cells(staged, _selected_action, _selected_target)
	for y in int((_state.get("grid", {}) as Dictionary).get("height", Grid.HEIGHT)):
		for x in int((_state.get("grid", {}) as Dictionary).get("width", Grid.WIDTH)):
			var cell := Vector2i(x, y)
			var color := Color.TRANSPARENT
			if cell == approach_destination:
				color = (
					Color(0.66, 0.58, 1.0, 0.66)
					if approach_fallback
					else Color(0.36, 0.92, 0.58, 0.62)
				)
			elif cell in approach_path:
				color = (
					Color(0.58, 0.52, 0.92, 0.24)
					if approach_fallback
					else Color(0.30, 0.78, 0.52, 0.22)
				)
			elif _is_changed_cell(cell):
				color = Color(0.58, 0.86, 1.0, 0.52)
			elif cell == _pending_cell and cell != active.get("cell", Vector2i(-1, -1)):
				color = Color(1.0, 0.78, 0.25, 0.56)
			elif _move_mode and cell in reachable and not Grid.is_focus_cell(_state, cell):
				color = Color(0.35, 0.95, 0.57, 0.36)
			elif cell in secondary_cells:
				color = (
					Color(1.0, 0.72, 0.20, 0.70)
					if cell == _secondary_cell
					else Color(1.0, 0.72, 0.20, 0.34)
				)
			elif cell in valid_target_cells:
				color = (
					Color(0.88, 0.70, 0.26, 0.70)
					if cell == _target_cell
					else Color(0.72, 0.57, 0.25, 0.30)
				)
			var occupant := _display_occupant(cell)
			if not occupant.is_empty() and occupant in valid_targets:
				color = Color(1.0, 1.0, 1.0, 0.34) if color.a <= 0.0 else color
			if color.a > 0.0:
				_add_overlay(cell, color)
	if approach_destination != Combat.INVALID_CELL and Grid.is_inside(_state, approach_destination):
		_add_approach_stop_marker(approach_destination, approach_fallback)


func _refresh_pair_context() -> void:
	if not is_instance_valid(_pair_context_root):
		return
	_clear_children(_pair_context_root)
	_reset_pair_outlines()
	if _pair_context_action.is_empty() or _state.is_empty() or not _state.has("grid"):
		return
	var pair_state := _pair_selection_state()
	var context := Combat.duo_partner_context(pair_state, _pair_context_action)
	if context.is_empty():
		return
	var actor := Combat.unit_definition(pair_state, str(context.get("actorId", "")))
	var partner_id := str(context.get("partnerId", ""))
	var partner := Combat.unit_definition(pair_state, partner_id)
	if actor.is_empty() or partner.is_empty() or not actor.has("cell") or not partner.has("cell"):
		return
	var actor_cell: Vector2i = actor.get("cell", Vector2i.ZERO)
	var partner_cell: Vector2i = partner.get("cell", Vector2i.ZERO)
	var radius := int(context.get("range", 0))
	var grid := pair_state.get("grid", {}) as Dictionary
	for y in int(grid.get("height", Grid.HEIGHT)):
		for x in int(grid.get("width", Grid.WIDTH)):
			var cell := Vector2i(x, y)
			if Terrain.action_distance(pair_state, actor_cell, cell) <= radius:
				_add_pair_range_overlay(cell)
	var alive := int(partner.get("hp", 0)) > 0
	var in_range := bool(context.get("inRange", false))
	var has_mp := int(partner.get("mp", 0)) >= int(
		Combat.command_definition(pair_state, _pair_context_action).get("partnerMpCost", 0)
	)
	var marker_color := (
		Color("79d8a3") if alive and in_range and has_mp
		else (Color("ffc85a") if alive and in_range else Color("f07883"))
	)
	var partner_root := _unit_roots.get(partner_id) as Node3D
	if is_instance_valid(partner_root):
		var partner_outline := partner_root.get_node_or_null(
			"CombatUnitOutline_%s" % partner_id
		) as MeshInstance3D
		if partner_outline != null:
			partner_outline.material_override = _outline_material(marker_color)
	var ring := MeshInstance3D.new()
	ring.name = "CombatPairPartnerRing_%s" % partner_id
	var torus := TorusMesh.new()
	torus.inner_radius = CELL_SIZE * 0.31
	torus.outer_radius = CELL_SIZE * 0.39
	torus.rings = 24
	torus.ring_segments = 10
	torus.material = _material(marker_color, true, true)
	ring.mesh = torus
	ring.position = _world_position(partner_cell, TILE_HEIGHT * 0.78)
	_pair_context_root.add_child(ring)
	var pointer := MeshInstance3D.new()
	pointer.name = "CombatPairPartnerPointer_%s" % partner_id
	var pointer_mesh := CylinderMesh.new()
	pointer_mesh.top_radius = 0.0
	pointer_mesh.bottom_radius = 0.16
	pointer_mesh.height = 0.34
	pointer_mesh.radial_segments = 6
	pointer_mesh.material = _material(marker_color, true, true)
	pointer.mesh = pointer_mesh
	pointer.position = _world_position(partner_cell, 1.62)
	pointer.rotation_degrees.z = 180.0
	_pair_context_root.add_child(pointer)
	var badge := Label3D.new()
	badge.name = "CombatPairPartnerBadge_%s" % partner_id
	badge.text = _pair_badge_text(context, partner, alive, has_mp)
	badge.position = _world_position(partner_cell, 1.96)
	badge.font_size = 34
	badge.outline_size = 9
	badge.pixel_size = 0.0039
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.modulate = marker_color
	_pair_context_root.add_child(badge)


func _reset_pair_outlines() -> void:
	for raw_id in _unit_roots:
		var unit_id := str(raw_id)
		var root := _unit_roots[raw_id] as Node3D
		if not is_instance_valid(root):
			continue
		var outline := root.get_node_or_null(
			"CombatUnitOutline_%s" % unit_id
		) as MeshInstance3D
		if outline == null:
			continue
		var unit := Combat.unit_definition(_state, unit_id)
		var team_color: Color = unit.get(
			"battleColor",
			Color("65cfe1") if str(unit.get("team", "")) == "hero" else Color("f07883"),
		)
		outline.material_override = _outline_material(team_color)


func _add_pair_range_overlay(cell: Vector2i) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "CombatPairRange_%s" % Grid.cell_key(cell).replace(":", "_")
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL_SIZE * 0.72, CELL_SIZE * 0.72)
	plane.material = _material(Color(0.38, 0.88, 0.76, 0.18), true, true)
	instance.mesh = plane
	instance.position = _world_position(cell, TILE_HEIGHT * 0.72)
	_pair_context_root.add_child(instance)


func _pair_badge_text(
	context: Dictionary,
	partner: Dictionary,
	alive: bool,
	has_mp: bool,
) -> String:
	var partner_name := str(context.get("partnerName", context.get("partnerId", "Партнёр")))
	var distance_copy := "%d/%d" % [
		int(context.get("distance", -1)), int(context.get("range", 0)),
	]
	if not alive:
		return "✕ СВЯЗКА · %s\nВЫВЕДЕН ИЗ БОЯ · %s" % [partner_name, distance_copy]
	if not bool(context.get("inRange", false)):
		return "✕ СВЯЗКА · %s\nВНЕ РАДИУСА · %s" % [partner_name, distance_copy]
	if not has_mp:
		return "! СВЯЗКА · %s\nВ РАДИУСЕ · %s · НЕТ MP" % [partner_name, distance_copy]
	return "✓ СВЯЗКА · %s\nВ РАДИУСЕ · %s" % [partner_name, distance_copy]


func _pair_selection_state() -> Dictionary:
	if _state.is_empty() or not _state.has("grid"):
		return _state
	var staged := Grid.stage_move(_state, _pending_cell)
	return _state if staged.is_empty() else staged


func _add_overlay(cell: Vector2i, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "CombatOverlay_%s" % Grid.cell_key(cell).replace(":", "_")
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL_SIZE * 0.86, CELL_SIZE * 0.86)
	plane.material = _material(color, true, true)
	instance.mesh = plane
	instance.position = _world_position(cell, TILE_HEIGHT * 0.58)
	_overlay_root.add_child(instance)


func _add_approach_stop_marker(cell: Vector2i, fallback_defend: bool) -> void:
	var color := Color("b5a5ff") if fallback_defend else Color("79d8a3")
	var ring := MeshInstance3D.new()
	ring.name = "CombatApproachStopRing"
	var torus := TorusMesh.new()
	torus.inner_radius = CELL_SIZE * (0.23 if fallback_defend else 0.30)
	torus.outer_radius = CELL_SIZE * 0.41
	torus.rings = 24
	torus.ring_segments = 10 if fallback_defend else 5
	torus.material = _material(color, true, true)
	ring.mesh = torus
	ring.position = _world_position(cell, TILE_HEIGHT * 0.88)
	_overlay_root.add_child(ring)
	var label := Label3D.new()
	label.name = "CombatApproachStopLabel"
	label.text = "%s · СТОП %s" % [
		"◆ ЗАЩИТА" if fallback_defend else "⚔ АТАКА",
		Grid.cell_label(cell),
	]
	label.position = _world_position(cell, 1.28)
	label.font_size = 30
	label.outline_size = 8
	label.pixel_size = 0.0038
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	_overlay_root.add_child(label)


func _add_cell_label(cell: Vector2i) -> void:
	var label := Label3D.new()
	label.name = "CombatCellLabel_%s" % Grid.cell_key(cell).replace(":", "_")
	label.text = "%s  h%d" % [Grid.cell_label(cell), Grid.elevation(_state, cell)]
	label.position = _world_position(cell, TILE_HEIGHT * 0.65)
	label.position.x -= CELL_SIZE * 0.33
	label.position.z += CELL_SIZE * 0.33
	label.rotation_degrees.x = -90.0
	label.font_size = 26
	label.outline_size = 5
	label.pixel_size = 0.0034
	label.modulate = Color("dce8f7")
	_dynamic_root.add_child(label)


func _projected_cell_definition(cell: Vector2i) -> Dictionary:
	var definition := Grid.cell_definition(_state, cell)
	var patch: Dictionary = (_preview.get("cellChanges", {}) as Dictionary).get(Grid.cell_key(cell), {})
	for raw_field in patch:
		var field := str(raw_field)
		if field != "cell":
			definition[field] = patch[raw_field]
	return definition


func _valid_targets_from_staged_state() -> Array[String]:
	if _selected_action.is_empty():
		return []
	if _preview.has("validTargetIds"):
		var preview_targets: Array[String] = []
		for raw_id in _preview.get("validTargetIds", []):
			preview_targets.append(str(raw_id))
		return preview_targets
	return Grid.approach_target_ids(_state, _selected_action, _pending_cell)


func _valid_target_cells_from_staged_state() -> Array[Vector2i]:
	if _selected_action.is_empty():
		return []
	var staged := Grid.stage_move(_state, _pending_cell)
	return [] if staged.is_empty() else Combat.valid_target_cells(staged, _selected_action)


func _map_cell(cell: Vector2i) -> Vector3i:
	return Vector3i(cell.x, Terrain.elevation(_state, cell), cell.y)


func _world_position(cell: Vector2i, y_offset: float = 0.0) -> Vector3:
	if _grid_map != null:
		return _grid_map.map_to_local(_map_cell(cell)) + Vector3.UP * y_offset
	return Vector3(
		float(cell.x) * CELL_SIZE,
		float(Terrain.elevation(_state, cell)) * ELEVATION_HEIGHT + y_offset,
		float(cell.y) * CELL_SIZE,
	)


func _is_changed_cell(cell: Vector2i) -> bool:
	return (_preview.get("cellChanges", {}) as Dictionary).has(Grid.cell_key(cell))


func _material(color: Color, emission: bool, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if emission:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b, 1.0)
		material.emission_energy_multiplier = 0.55
	if transparent or color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _outline_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.lightened(0.42), 0.58)
	material.render_priority = 12
	return material


func _pick_cell(screen_position: Vector2) -> Vector2i:
	return _pick_cell_from_camera(_camera, screen_position)


func _pick_cell_from_camera(viewport_camera: Camera3D, screen_position: Vector2) -> Vector2i:
	if viewport_camera == null or _grid_map == null:
		return Vector2i(-1, -1)
	var ray_origin := viewport_camera.project_ray_origin(screen_position)
	var ray_direction := viewport_camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 100.0, 1)
	var world := _grid_map.get_world_3d()
	if world != null:
		var hit := world.direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var local := _grid_map.to_local(
				hit.get("position", Vector3.ZERO) - hit.get("normal", Vector3.UP) * 0.02
			)
			var map_cell := _grid_map.local_to_map(local)
			var picked := Vector2i(map_cell.x, map_cell.z)
			if Grid.is_inside(_state, picked):
				return picked
	return _pick_cell_from_surfaces(ray_origin, ray_direction)


func _pick_cell_from_surfaces(ray_origin: Vector3, ray_direction: Vector3) -> Vector2i:
	if _state.is_empty() or not _state.has("grid"):
		return Vector2i(-1, -1)
	var normal := _grid_map.global_transform.basis.y.normalized()
	var denominator := ray_direction.dot(normal)
	if absf(denominator) < 0.00001:
		return Vector2i(-1, -1)
	var grid: Dictionary = _state.get("grid", {})
	var best_cell := Vector2i(-1, -1)
	var best_distance := INF
	for y in int(grid.get("height", Grid.HEIGHT)):
		for x in int(grid.get("width", Grid.WIDTH)):
			var cell := Vector2i(x, y)
			var center_local := _grid_map.map_to_local(_map_cell(cell))
			center_local.y += _cell_surface_offset(cell)
			var center_world := _grid_map.to_global(center_local)
			var distance := (center_world - ray_origin).dot(normal) / denominator
			if distance < 0.0 or distance >= best_distance:
				continue
			var intersection_local := _grid_map.to_local(ray_origin + ray_direction * distance)
			if (
				absf(intersection_local.x - center_local.x) <= _grid_map.cell_size.x * 0.49
				and absf(intersection_local.z - center_local.z) <= _grid_map.cell_size.z * 0.49
			):
				best_cell = cell
				best_distance = distance
	return best_cell


func _cell_surface_offset(cell: Vector2i) -> float:
	return (
		BLOCKED_HEIGHT - TILE_HEIGHT * 0.5
		if bool(_projected_cell_definition(cell).get("blocked", false))
		else TILE_HEIGHT * 0.5
	)


func _display_occupant(cell: Vector2i) -> String:
	var actual := Grid.occupant_id(_state, cell)
	var active_id := Combat.current_unit_id(_state)
	var active := Combat.unit_definition(_state, active_id)
	var origin: Vector2i = active.get("cell", Vector2i(-1, -1))
	if (
		_pending_cell != Vector2i(-1, -1)
		and _pending_cell != origin
		and _pending_cell in Grid.reachable_cells(_state, active_id)
	):
		if cell == origin:
			return ""
		if cell == _pending_cell:
			return active_id
	return actual


func _clear_children(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()


func _update_camera_context() -> void:
	var grid: Dictionary = _state.get("grid", {})
	var field_size := Vector2i(int(grid.get("width", 0)), int(grid.get("height", 0)))
	var camera_rig := get_node_or_null("CameraRig")
	var field_changed := field_size != _last_field_size
	if (
		camera_rig != null
		and camera_rig.has_method("set_home_view")
		and (field_changed or _camera_overview_requested)
	):
		_last_field_size = field_size
		if field_size.x > Grid.WIDTH or field_size.y > Grid.HEIGHT:
			var first := _world_position(Vector2i.ZERO, 0.0)
			var last := _world_position(
				Vector2i(maxi(0, field_size.x - 1), maxi(0, field_size.y - 1)), 0.0
			)
			var center := (first + last) * 0.5
			var fit_size := maxf(float(field_size.y) * CELL_SIZE * 1.18, float(field_size.x) * CELL_SIZE * 0.82)
			var safe_distance := Vector2(
				float(field_size.x) * CELL_SIZE, float(field_size.y) * CELL_SIZE
			).length() + CELL_SIZE * 4.0
			camera_rig.call("set_home_view", center, fit_size, safe_distance)
		elif camera_rig.has_method("restore_authored_home"):
			camera_rig.call("restore_authored_home")
		_camera_overview_requested = false
	var active_id := Combat.current_unit_id(_state)
	var active_focus_cell := _active_focus_cell()
	if field_changed or _last_active_id.is_empty():
		_last_active_id = active_id
		_last_active_focus_cell = active_focus_cell
		return
	var active_changed := not active_id.is_empty() and active_id != _last_active_id
	var focus_cell_changed := (
		active_focus_cell != Vector2i(-1, -1)
		and active_focus_cell != _last_active_focus_cell
	)
	_last_active_id = active_id
	_last_active_focus_cell = active_focus_cell
	if active_changed or focus_cell_changed:
		_focus_active_unit(true)


func _focus_active_unit(smooth: bool = true) -> bool:
	var camera_rig := get_node_or_null("CameraRig")
	if camera_rig == null or not camera_rig.has_method("focus_on"):
		return false
	var focus_cell := _active_focus_cell()
	if focus_cell == Vector2i(-1, -1):
		return false
	camera_rig.call("focus_on", _world_position(focus_cell, 0.0), smooth)
	return true


func _active_focus_cell() -> Vector2i:
	var active_id := Combat.current_unit_id(_state)
	var active := Combat.unit_definition(_state, active_id)
	if not active.has("cell"):
		return Vector2i(-1, -1)
	var active_cell: Vector2i = active.get("cell", Vector2i.ZERO)
	if _pending_focus_valid:
		return _pending_cell
	return active_cell


func _is_pending_focus_valid() -> bool:
	var active_id := Combat.current_unit_id(_state)
	var active := Combat.unit_definition(_state, active_id)
	if active_id.is_empty() or not active.has("cell"):
		return false
	var active_cell: Vector2i = active.get("cell", Vector2i.ZERO)
	return (
		_pending_cell != Vector2i(-1, -1)
		and _pending_cell != active_cell
		and _pending_cell in Grid.reachable_cells(_state, active_id)
	)


func _set_camera_control(method: String, enabled: bool) -> void:
	var camera_rig := get_node_or_null("CameraRig")
	if camera_rig != null and camera_rig.has_method(method):
		camera_rig.call(method, enabled)


func _update_occlusion(force: bool = false) -> void:
	if _camera == null or _grid_map == null or _state.is_empty():
		return
	var active_cell := _active_focus_cell()
	if active_cell == Vector2i(-1, -1):
		return
	var signature := "%s|%s" % [_camera.global_transform, active_cell]
	if not force and signature == _last_occlusion_signature:
		return
	_last_occlusion_signature = signature
	var target := _world_position(active_cell, 0.48)
	var grid: Dictionary = _state.get("grid", {})
	for y in int(grid.get("height", Grid.HEIGHT)):
		for x in int(grid.get("width", Grid.WIDTH)):
			var cell := Vector2i(x, y)
			if not Grid.is_blocked(_state, cell):
				continue
			var center := _world_position(cell, BLOCKED_HEIGHT * 0.5)
			var fade := _distance_to_segment(center, _camera.global_position, target) < CELL_SIZE * 0.58
			_grid_map.set_cell_item(_map_cell(cell), ITEM_BLOCKED_FADED if fade else ITEM_BLOCKED)


func _distance_to_segment(point: Vector3, start: Vector3, finish: Vector3) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)
