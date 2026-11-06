@tool
extends RefCounted
## Action authoring lives with its Animation, inside the existing library.
## Bone names are explicit data, not a second cross-application region taxonomy.
const META := &"ember_action"
const LEFT := &"left_arm"

static func left_mask(skeleton: Skeleton3D) -> PackedStringArray:
	var root := skeleton.find_bone("J_Bip_L_Shoulder")
	var names := PackedStringArray()
	if root < 0:
		return names
	for index in skeleton.get_bone_count():
		var ancestor := index
		while ancestor >= 0 and ancestor != root:
			ancestor = skeleton.get_bone_parent(ancestor)
		if ancestor == root:
			names.append(skeleton.get_bone_name(index))
	return names

static func configure(clip: Animation, skeleton: Skeleton3D, title: String, fade_in := 0.15, fade_out := 0.20) -> Animation:
	var result := clip.duplicate() as Animation
	result.loop_mode = Animation.LOOP_NONE
	result.set_meta(META, {"version":1, "slot":LEFT, "title":title.strip_edges(),
		"bones":left_mask(skeleton), "fade_in":fade_in, "fade_out":fade_out,
		"contexts":PackedStringArray(["stand", "walk"])})
	return result

static func settings(clip: Animation) -> Dictionary:
	var value: Variant = clip.get_meta(META, {}) if clip != null else {}
	return value if value is Dictionary else {}

static func validate(clip: Animation, skeleton: Skeleton3D) -> String:
	var data := settings(clip)
	if data.get("version") != 1 or data.get("slot") != LEFT or str(data.get("title", "")).is_empty():
		return "Нужны название действия и слот «Левая рука»."
	if clip.length <= 0.0 or clip.loop_mode != Animation.LOOP_NONE:
		return "Действие должно быть конечным клипом."
	var allowed := left_mask(skeleton)
	var mask: Variant = data.get("bones")
	if not mask is PackedStringArray or mask.is_empty():
		return "Маска костей пуста."
	for name: String in mask:
		if name not in allowed:
			return "Кость вне левой руки: " + name
	for key in ["fade_in", "fade_out"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(value) or value < 0.0 or value > clip.length:
			return "Переход должен укладываться в длину клипа."
	if data.fade_in + data.fade_out > clip.length:
		return "Переходы длиннее действия."
	if data.get("contexts") != PackedStringArray(["stand", "walk"]):
		return "В этом срезе доступны только стойка и ходьба."
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D and path.get_subname_count() == 1 and String(path.get_subname(0)) in mask:
			return ""
	return "В клипе нет вращений выбранной руки."

static func weight(clip: Animation, seconds: float) -> float:
	var data := settings(clip)
	if seconds < 0.0 or seconds >= clip.length:
		return 0.0
	var enter := 1.0 if data.fade_in <= 0.0 else smoothstep(0.0, data.fade_in, seconds)
	var leave := 1.0 if data.fade_out <= 0.0 else 1.0 - smoothstep(clip.length - data.fade_out, clip.length, seconds)
	return enter * leave
