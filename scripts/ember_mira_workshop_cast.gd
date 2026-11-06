extends RefCounted
## A workshop cast is a bounded set of local upper-body rotation offsets.
const PATH := "user://mira-workshop-cast.json"
const BONES := [
	"J_Bip_C_Spine", "J_Bip_C_Chest", "J_Bip_C_UpperChest", "J_Bip_C_Neck", "J_Bip_C_Head",
	"J_Bip_R_Shoulder", "J_Bip_R_UpperArm", "J_Bip_R_LowerArm", "J_Bip_R_Hand",
	"J_Bip_L_Shoulder", "J_Bip_L_UpperArm", "J_Bip_L_LowerArm", "J_Bip_L_Hand",
]

static func read_for(skeleton: Skeleton3D) -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null or file.get_length() > 180000:
		return {}
	var layer: Variant = JSON.parse_string(file.get_as_text())
	if not layer is Dictionary or layer.get("schema") != 1 or not layer.get("tracks") is Array:
		return {}
	var tracks: Dictionary = {}
	for track: Variant in layer.tracks:
		if not track is Dictionary or track.get("bone") not in BONES or not track.get("keys") is Array:
			return {}
		var bone := skeleton.find_bone(track.bone)
		if bone < 0 or tracks.has(bone) or track.keys.size() != 60:
			return {}
		var rest := quaternion(track.get("rest"))
		if not rest.is_normalized() or rest.angle_to(skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()) > 0.025:
			return {}
		var keys: Array[Quaternion] = []
		for key: Variant in track.keys:
			var rotation := quaternion(key)
			if not rotation.is_normalized():
				return {}
			keys.append(rotation)
		tracks[bone] = keys
	if tracks.is_empty():
		return {}
	if layer.get("mode") == "authored":
		var grip := quaternion(layer.get("grip"))
		if not grip.is_normalized():
			return {}
		return {"tracks": tracks, "grip": grip}
	return {"tracks": tracks}

static func quaternion(value: Variant) -> Quaternion:
	if not value is Array or value.size() != 4:
		return Quaternion(0, 0, 0, 0)
	for number: Variant in value:
		if not (number is float or number is int) or not is_finite(float(number)):
			return Quaternion(0, 0, 0, 0)
	var result := Quaternion(value[0], value[1], value[2], value[3])
	return result.normalized() if absf(result.length_squared() - 1.0) < 0.02 else Quaternion(0, 0, 0, 0)

static func sample(keys: Array, phase: float) -> Quaternion:
	var frame := clampf(phase, 0.0, 1.0) * (keys.size() - 1)
	var first := floori(frame)
	var a: Quaternion = keys[first]
	var b: Quaternion = keys[mini(first + 1, keys.size() - 1)]
	return a.slerp(b, frame - first)

static func sample_cast(keys: Array, phase: float) -> Quaternion:
	var center := sample(keys, phase)
	var near := sample(keys, phase - 0.06).slerp(sample(keys, phase + 0.06), 0.5)
	var filtered := center.slerp(near, 0.65)
	var blend := smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.86, 1.0, phase))
	return Quaternion.IDENTITY.slerp(filtered, blend)
