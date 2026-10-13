@tool
extends Node3D
## Only presentation controls. Editing stays with the existing World Editor.
@export var orbit_center:=Vector3(12,1.5,8)
@export var baseline_terrain: EmberTerrainPilotResource
var _relief_terrain: EmberTerrainPilotResource
var _baseline_visible:=false
var dragging:=false
func _ready() -> void:
	if not Engine.is_editor_hint():
		Engine.max_fps=30
		_relief_terrain=get_node("Map").compact_terrain
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():return
	var camera:=get_node("Camera3D") as Camera3D
	var center:=orbit_center
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_M:
			var map:=get_node("Map") as EmberMapLoader
			map.compact_ground_style=1-map.compact_ground_style
		if event.keycode==KEY_B and baseline_terrain!=null:
			_baseline_visible=not _baseline_visible
			get_node("Map").compact_terrain=baseline_terrain if _baseline_visible else _relief_terrain
			get_node("Instructions/Caption").text=("Исходная форма" if _baseline_visible else "Объёмная фактура")+" · B — сравнить · ПКМ — камера · колесо — масштаб · L — свет"
		if event.keycode==KEY_L:get_node("Map/Look/Sun").rotate_y(deg_to_rad(25))
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:dragging=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.position=center+(camera.position-center)*(0.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1)
			camera.look_at(center)
	if event is InputEventMouseMotion and dragging:
		camera.position=center+(camera.position-center).rotated(Vector3.UP,-event.relative.x*0.007)
		camera.look_at(center)
