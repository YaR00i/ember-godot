@tool
extends Node3D
## Presentation controls use the scene Map/material; no terrain editing owner.
@export var detail_enabled := true:
	set(value): detail_enabled=value; _update.call_deferred()
@export var gray_preview := false:
	set(value): gray_preview=value; _update.call_deferred()
var _dragging := false
func _ready() -> void:
	_update.call_deferred()
	if not Engine.is_editor_hint(): Engine.max_fps=30
func _update() -> void:
	var map := get_node_or_null("Map") as EmberMapLoader
	if map == null or not map.is_node_ready(): return
	map.compact_material_gray_preview=gray_preview
	var projection = map.get("_visual_surface_projection")
	if projection != null:
		var material: ShaderMaterial = projection.get("_ground_material")
		if material: material.set_shader_parameter("surface_detail_enabled",detail_enabled)
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F: detail_enabled=not detail_enabled
		if event.keycode == KEY_G: gray_preview=not gray_preview
		if event.keycode == KEY_L: get_node("Map/Look/Sun").rotate_y(deg_to_rad(25))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT: _dragging=event.pressed
	if event is InputEventMouseMotion and _dragging:
		var camera := get_node("Camera3D") as Camera3D
		var center := Vector3(4,0.5,4)
		var offset := camera.position-center
		offset=offset.rotated(Vector3.UP,-event.relative.x*0.007)
		camera.position=center+offset; camera.look_at(center)
