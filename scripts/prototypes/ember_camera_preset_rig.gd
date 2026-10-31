@tool
extends Node3D
## Isolated shot study. Anchors and lens values belong to the saved scene;
## this rig never takes ownership of Ember's gameplay camera or actors.

enum Shot { TWO_SHOT, MEDIUM, CLOSE, SHOULDER, REVERSE_SHOULDER, DETAIL }
const TITLES := ["Общий · двое", "Средний · цель", "Крупный · цель", "Через плечо", "Обратное плечо", "Деталь · предмет"]

@export_node_path("Node3D") var primary_anchor: NodePath
@export_node_path("Node3D") var secondary_anchor: NodePath
@export_node_path("Node3D") var detail_anchor: NodePath
@export var primary_offset := Vector3.ZERO
@export var secondary_offset := Vector3.ZERO
@export var detail_offset := Vector3.ZERO
@export_range(0.01, 1000.0) var subject_scale := 1.0
@export_range(0.01, 1000.0) var detail_scale := 1.0
@export var shot: Shot = Shot.TWO_SHOT
@export_range(0.4, 2.5) var distance_scale := 1.0
@export_range(20.0, 80.0) var lens_fov := 38.0
@export_range(-0.6, 0.8) var height_offset := 0.0
@export_range(0.0, 2.0) var transition_seconds := 0.6
## All paired shots use this side of the dialogue axis (180 degree rule).
@export_enum("Справа от оси:1", "Слева от оси:-1") var axis_side := 1
## Enable the camera's native preview while scrubbing AnimationPlayer in Godot.
@export var preview_in_editor := true

@onready var camera: Camera3D = $Camera3D
var status := ""
var _blend_from := Transform3D.IDENTITY
var _blend_fov := 38.0
var _elapsed := 0.0
var _initialized := false
var _last_settings: Array = []


func shot_pose() -> Dictionary:
	var a := _anchor(primary_anchor)
	var b := _anchor(secondary_anchor)
	var item := _anchor(detail_anchor)
	if (shot == Shot.DETAIL and item == null) or (shot != Shot.DETAIL and a == null):
		return {}
	var focus := item.to_global(detail_offset) if shot == Shot.DETAIL else a.to_global(primary_offset)
	var partner := b.to_global(secondary_offset) if b != null else focus + Vector3.RIGHT * 2.4 * subject_scale
	if shot == Shot.REVERSE_SHOULDER:
		if b == null:
			return {}
		var old_focus := focus
		focus = partner
		partner = old_focus
	# Derive the axis from the bound actors, rather than the scene's world axes.
	var axis := partner - focus
	axis.y = 0.0
	if axis.length_squared() < 0.0001:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	# Reverse shot must keep the camera on the SAME side of the original axis.
	var side := axis.cross(Vector3.UP) * float(axis_side)
	if shot == Shot.REVERSE_SHOULDER:
		side = -side
	var position_offset := Vector3.ZERO
	var aim := focus
	match shot:
		Shot.TWO_SHOT:
			aim = (focus + partner) * 0.5
			aim.y -= 0.35 * subject_scale
			position_offset = side * maxf(focus.distance_to(partner) * 2.0, 4.8 * subject_scale) + Vector3.UP * 0.22 * subject_scale
		Shot.MEDIUM:
			position_offset = (axis * 0.6 + side) * 2.4 * subject_scale
		Shot.CLOSE:
			aim += Vector3.UP * 0.23 * subject_scale
			position_offset = (axis * 0.35 + side) * 1.2 * subject_scale
		Shot.SHOULDER, Shot.REVERSE_SHOULDER:
			position_offset = partner - focus + (axis * 0.65 + side * 0.65 + Vector3.UP * 0.08) * subject_scale
		Shot.DETAIL:
			position_offset = Vector3(0.55, 0.4, 1.15) * detail_scale
	position_offset *= distance_scale
	position_offset.y += height_offset
	var pose := Transform3D(Basis.IDENTITY, aim + position_offset).looking_at(aim, Vector3.UP)
	return {"transform": pose, "fov": lens_fov, "aim": aim}


func _anchor(path: NodePath) -> Node3D:
	return null if path.is_empty() else get_node_or_null(path) as Node3D


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	# Animated lens/offset values must not restart the shot transition every frame.
	var settings := [shot, primary_anchor, secondary_anchor, detail_anchor, axis_side]
	if settings != _last_settings:
		_blend_from = camera.global_transform
		_blend_fov = camera.fov
		_elapsed = 0.0
		_last_settings = settings
	var result := shot_pose()
	if result.is_empty():
		status = "Цель отсутствует — удерживается последний кадр"
		return
	status = TITLES[shot]
	if not _initialized:
		_elapsed = transition_seconds
	_elapsed += delta
	var weight := 1.0 if transition_seconds <= 0.0 or not _initialized else clampf(_elapsed / transition_seconds, 0.0, 1.0)
	weight = weight * weight * (3.0 - 2.0 * weight)
	camera.global_transform = _blend_from.interpolate_with(result.transform, weight)
	camera.fov = lerpf(_blend_fov, result.fov, weight)
	_initialized = true


func snap() -> void:
	_initialized = false
	_last_settings.clear()
	_process(0.0)
