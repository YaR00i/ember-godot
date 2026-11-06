@tool
extends Node
## Channels shared by the workshop timeline and the gameplay overlays.

const DRAW := &"staff_draw_transition"
const DOOR := &"door_reach"
const CONTACT_TRACE_PATH := "user://ember_contact_preview.cfg"
const CABLE := &"cable_hang"
const MANTLE := &"mantle_stowed"
const MANTLE_FOOT_PHASE := 0.48
const MANTLE_KNEE_PHASE := 0.81
const LEDGE_JUMP_TAKEOFF := 0.22
const LEDGE_JUMP_LAND := 0.78
const LEDGE_JUMP_RECOVERED := 1.10
const LEDGE_JUMP_CLEARANCE := 0.22
const MANTLE_CLIP_PATH := "res://content/animations/mira_mantle.tres"
const ACTIONS := {
	"lift": &"crate_lift",
	"place": &"crate_place",
	"throw": &"crate_throw",
	"push": &"crate_push",
}
const CHANNELS := ^"MotionControls"

@export var lowering := 0.0
@export var side_exit := 0.0
@export var ready_blend := 0.0
@export var grip_weight := 0.0
@export var hip_position := Vector3(-0.36, 0.78, 0.06)
@export var hip_direction := Vector3(-0.30, 0.93, 0.20)
@export var elbow_hint := Vector3(-0.49, 0.83, -0.15)
@export var crate_travel := 0.0
@export var aim_forward := 0.0
@export var hang_tuck := 0.34

static func add_missing(library: AnimationLibrary) -> bool:
	var added := false
	if not library.has_animation(MANTLE) and ResourceLoader.exists(MANTLE_CLIP_PATH):
		library.add_animation(MANTLE, load(MANTLE_CLIP_PATH).duplicate())
		added = true
	var draw_seconds := 0.65
	if library.has_animation(&"staff_draw"):
		draw_seconds = library.get_animation(&"staff_draw").length
	if not library.has_animation(DRAW):
		var draw := _clip(draw_seconds)
		_curve(draw, &"lowering", [[0.0, 0.0], [0.27, 0.0], [0.53, 1.0], [1.0, 1.0]])
		_curve(draw, &"side_exit", [[0.0, 0.0], [0.53, 0.0], [0.75, 1.0], [1.0, 1.0]])
		_curve(draw, &"ready_blend", [[0.0, 0.0], [0.75, 0.0], [1.0, 1.0]])
		_curve(draw, &"grip_weight", [[0.0, 0.0], [0.27, 1.0], [1.0, 1.0]])
		_curve(draw, &"hip_position", [[0.0, Vector3(-0.36, 0.78, 0.06)]])
		_curve(draw, &"hip_direction", [[0.0, Vector3(-0.30, 0.93, 0.20)]])
		_curve(draw, &"elbow_hint", [[0.0, Vector3(-0.49, 0.83, -0.15)]])
		library.add_animation(DRAW, draw)
		added = true
	for action: String in ACTIONS:
		var name: StringName = ACTIONS[action]
		if library.has_animation(name):
			continue
		var seconds := 0.42 if action == "throw" else (0.95 if action == "push" else 0.55)
		var clip := _clip(seconds)
		match action:
			"lift":
				_curve(clip, &"crate_travel", [[0.0, 0.0], [0.20, 0.0], [1.0, 1.0]])
				_curve(clip, &"aim_forward", [[0.0, 0.0], [0.80, 1.0], [1.0, 1.0]])
			"place":
				_curve(clip, &"crate_travel", [[0.0, 0.0], [1.0, 1.0]])
			"throw":
				_curve(clip, &"crate_travel", [[0.0, 0.0], [0.48, 0.0], [1.0, 1.0]])
				_curve(clip, &"aim_forward", [[0.0, 0.0], [0.15, 0.0], [0.80, 1.0], [1.0, 1.0]])
			"push":
				_curve(clip, &"crate_travel", [[0.0, 0.0], [0.18, 0.0], [0.24, 1.0], [1.0, 1.0]])
		library.add_animation(name, clip)
		added = true
	if not library.has_animation(DOOR):
		var door := _clip(0.34)
		_curve(door, &"grip_weight", [[0.0, 0.0], [0.26, 0.24], [0.83, 1.0], [1.0, 1.0]])
		library.add_animation(DOOR, door)
		added = true
	if not library.has_animation(CABLE):
		var hang := _clip(1.20)
		hang.loop_mode = Animation.LOOP_LINEAR
		_curve(hang, &"hang_tuck", [[0.0, 0.30], [0.5, 0.42], [1.0, 0.30]])
		library.add_animation(CABLE, hang)
		added = true
	return added

static func add_contact_markers(library: AnimationLibrary) -> void:
	if library.has_animation(&"staff_strike"):
		var strike := library.get_animation(&"staff_strike")
		if not strike.has_marker(&"impact"):
			strike.add_marker(&"impact", minf(0.38, strike.length))
	for name: StringName in library.get_animation_list():
		var base := String(name).trim_suffix("_stowed")
		if base not in ["walk", "walk_adventure", "jog", "run"]:
			continue
		var clip := library.get_animation(name)
		if not clip.has_marker(&"left_contact"):
			var phase := 0.0 if base.begins_with("walk") else 1.0 / 24.0
			clip.add_marker(&"left_contact", phase * clip.length)

static func _clip(seconds: float) -> Animation:
	var clip := Animation.new()
	clip.length = seconds
	return clip

static func _curve(clip: Animation, channel: StringName, keys: Array) -> void:
	var track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track, NodePath("%s:%s" % [CHANNELS, channel]))
	clip.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for key: Array in keys:
		clip.track_insert_key(track, float(key[0]) * clip.length, key[1])

static func sample(clip: Animation, channel: StringName, phase: float, fallback: Variant) -> Variant:
	var track := clip.find_track(NodePath("%s:%s" % [CHANNELS, channel]), Animation.TYPE_VALUE)
	if track < 0 or clip.track_get_key_count(track) == 0 or not clip.track_is_enabled(track):
		return fallback
	return clip.value_track_interpolate(track, clampf(phase, 0.0, 1.0) * clip.length)

static func weight(clip: Animation, channel: StringName, phase: float, fallback: float) -> float:
	return clampf(float(sample(clip, channel, phase, fallback)), 0.0, 1.0)

static func draw_pose(clip: Animation, phase: float, holstered: Transform3D, ready: Transform3D) -> Transform3D:
	var lowered := holstered
	lowered.origin += Vector3(-0.19, -0.27, -0.04) * weight(clip, &"lowering", phase, 0.0)
	var hip_at: Vector3 = sample(clip, &"hip_position", phase, Vector3(-0.36, 0.78, 0.06))
	var hip_direction: Vector3 = sample(clip, &"hip_direction", phase, Vector3(-0.30, 0.93, 0.20))
	var aim := hip_direction.normalized() if hip_direction.length_squared() > 0.001 else Vector3.UP
	var up := Vector3.UP if absf(aim.y) < 0.95 else Vector3.BACK
	var hip := Transform3D(Basis.looking_at(aim, up, true), hip_at)
	return lowered.interpolate_with(hip, weight(clip, &"side_exit", phase, 0.0)).interpolate_with(ready, weight(clip, &"ready_blend", phase, phase))
