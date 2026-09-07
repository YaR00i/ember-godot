class_name EmberCombatGrid3DView
extends SubViewportContainer
## Compatibility adapter for the old embedded laboratory view.
## It instantiates the same standard Node3D world used by combat_lab.tscn.

signal cell_chosen(cell: Vector2i, unit_id: String)

const WorldScene := preload("res://scenes/prototypes/combat_grid_3d_world.tscn")
const ITEM_NEUTRAL := 0
const ITEM_WET := 1
const ITEM_EMBER := 2
const ITEM_FROZEN := 3
const ITEM_BLOCKED := 4

var _viewport: SubViewport
var _world: Node3D


func _ready() -> void:
	name = "CombatGrid3DField"
	custom_minimum_size = Vector2(720, 440)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.name = "CombatGrid3DViewport"
	_viewport.size = Vector2i(900, 560)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	add_child(_viewport)
	_world = WorldScene.instantiate() as Node3D
	_world.cell_chosen.connect(_forward_cell_chosen)
	_viewport.add_child(_world)


func configure(
	state: Dictionary,
	selected_action: String,
	selected_target: String,
	pending_cell: Vector2i,
	move_mode: bool,
	preview: Dictionary = {},
	secondary_cell: Vector2i = Vector2i(-999999, -999999),
	target_cell: Vector2i = Vector2i(-999999, -999999),
) -> void:
	if _world != null:
		_world.call(
			"configure", state, selected_action, selected_target, pending_cell, move_mode,
			preview, secondary_cell, "", target_cell,
		)


func projected_item_at(cell: Vector2i) -> int:
	return int(_world.call("projected_item_at", cell)) if _world != null else GridMap.INVALID_CELL_ITEM


func screen_position_for_cell(cell: Vector2i) -> Vector2:
	return _world.call("screen_position_for_cell", cell) as Vector2 if _world != null else Vector2(-1.0, -1.0)


func pick_cell_at(screen_position: Vector2) -> Vector2i:
	return _world.call("pick_cell_at", screen_position) as Vector2i if _world != null else Vector2i(-1, -1)


func projected_occupant_at(cell: Vector2i) -> String:
	return str(_world.call("projected_occupant_at", cell)) if _world != null else ""


func set_pair_context_action(action_id: String) -> void:
	if _world != null and _world.has_method("set_pair_context_action"):
		_world.call("set_pair_context_action", action_id)


func _gui_input(event: InputEvent) -> void:
	if _world == null:
		return
	if bool(_world.call("handle_camera_input", event)):
		accept_event()
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and bool(_world.call("choose_cell_at", event.position)):
		accept_event()


func _forward_cell_chosen(cell: Vector2i, unit_id: String) -> void:
	cell_chosen.emit(cell, unit_id)
