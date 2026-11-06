@tool
extends SkeletonModifier3D
## One bounded rotation-only action after existing IK. The base player's clock,
## root motion and unmasked channels remain owned by the existing visual.
const Action = preload("res://scripts/ember_animation_action.gd")
var clip: Animation
var seconds := -1.0
var manual := false
var current_weight := 0.0
var _tracks: Dictionary[int, int] = {}
var _cancel_time := -1.0
var _cancel_weight := 0.0
var _contexts := PackedStringArray()

func request(candidate: Animation, context: StringName, occupied: PackedStringArray = []) -> String:
	var skeleton := get_skeleton()
	var error := Action.validate(candidate, skeleton)
	if not error.is_empty():
		return error
	var data := Action.settings(candidate)
	if context not in data.contexts:
		return "Сейчас недоступно: нужна стойка или ходьба."
	if String(data.slot) in occupied:
		return "Левая рука занята."
	if clip != null and seconds < clip.length and not manual:
		return "Действие уже выполняется."
	_bind(candidate)
	seconds = 0.0
	manual = false
	return ""

func preview(candidate: Animation, at: float) -> void:
	if clip != candidate:
		if not Action.validate(candidate, get_skeleton()).is_empty():
			clear()
			return
		_bind(candidate)
	manual = true
	seconds = at

func _bind(candidate: Animation) -> void:
	clip = candidate
	_tracks.clear()
	_cancel_time = -1.0
	var data := Action.settings(clip)
	_contexts = data.contexts
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D and path.get_subname_count() == 1 and String(path.get_subname(0)) in data.bones:
			_tracks[get_skeleton().find_bone(path.get_subname(0))] = track

func update_context(context: StringName, occupied: PackedStringArray = []) -> void:
	if clip != null and (context not in _contexts or String(Action.LEFT) in occupied):
		cancel()

func cancel() -> void:
	if clip != null and _cancel_time < 0.0:
		_cancel_time = 0.0
		_cancel_weight = Action.weight(clip, seconds)

func clear() -> void:
	clip = null
	seconds = -1.0
	_tracks.clear()
	current_weight = 0.0

func _process_modification_with_delta(delta: float) -> void:
	if clip == null:
		return
	if not manual:
		seconds += maxf(0.0, delta)
	current_weight = Action.weight(clip, seconds)
	if _cancel_time >= 0.0:
		_cancel_time += maxf(0.0, delta)
		var fade: float = maxf(0.001, Action.settings(clip).fade_out)
		current_weight = _cancel_weight * (1.0 - smoothstep(0.0, fade, _cancel_time))
		if _cancel_time >= fade:
			clear()
			return
	if seconds >= clip.length and not manual:
		clear()
		return
	var skeleton := get_skeleton()
	for bone: int in _tracks:
		var rotation := clip.rotation_track_interpolate(_tracks[bone], clampf(seconds, 0.0, clip.length))
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(rotation, current_weight))
