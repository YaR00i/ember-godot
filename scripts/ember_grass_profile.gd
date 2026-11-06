@tool
extends RefCounted

const PATH := "res://content/terrain_materials/grass_profile.json"
const FIELDS := {
	"grass_amount": [0.0, 100.0, 1.0],
	"grass_width": [0.25, 6.0, 0.05],
	"grass_height": [0.25, 3.0, 0.05],
	"camera_distance": [2.0, 40.0, 0.1],
	"camera_fov": [40.0, 90.0, 1.0],
	"camera_polar": [10.0, 85.0, 0.1],
}
const DEFAULTS := {
	"grass_amount": 50.0, "grass_width": 6.0, "grass_height": 0.30,
	"camera_distance": 12.5, "camera_fov": 45.0, "camera_polar": 50.4202859715124,
}

static var _settings: Dictionary


static func settings() -> Dictionary:
	if _settings.is_empty():
		_settings = DEFAULTS.duplicate()
		_settings.merge(read_settings(PATH), true)
	return _settings.duplicate()


static func read_settings(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return {}
	return validated(data.get("settings", {}))


static func validated(values: Variant) -> Dictionary:
	var result := {}
	if not values is Dictionary:
		return result
	for key: String in FIELDS:
		var value: Variant = values.get(key)
		if (value is float or value is int) and is_finite(float(value)):
			result[key] = clampf(float(value), FIELDS[key][0], FIELDS[key][1])
	return result


static func fill_native(scatter: MultiMesh, transforms: Array[Transform3D], profile: Dictionary) -> void:
	var amount := float(profile.grass_amount) / 100.0
	# The native cards already have the wide silhouette of the reference preset.
	var width := float(profile.grass_width) / 6.0
	var scale := Vector3(width, float(profile.grass_height), width)
	scatter.instance_count = roundi(transforms.size() * amount)
	for i in scatter.instance_count:
		var source := floori((i + 0.5) * transforms.size() / scatter.instance_count)
		scatter.set_instance_transform(i, transforms[source].scaled_local(scale))


static func save_settings(values: Dictionary, path := PATH) -> Error:
	var clean := validated(values)
	if clean.size() != FIELDS.size():
		return ERR_INVALID_DATA
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"settings": clean}, "\t", true, true) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(path + ".tmp", path)
	if error == OK and path == PATH:
		_settings = clean
	return error


static func native_card_mesh(source: ArrayMesh) -> ArrayMesh:
	if source.get_surface_count()!=1:return source
	var arrays:=source.surface_get_arrays(0)
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	if indices.size()!=24:return source
	var middle:=indices.slice(0,18)
	var far:=indices.slice(0,6)
	far.append_array(indices.slice(12,18))
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{0.015:middle,0.035:far},source.surface_get_format(0))
	mesh.surface_set_name(0,source.surface_get_name(0))
	mesh.surface_set_material(0,source.surface_get_material(0))
	for key in source.get_meta_list():mesh.set_meta(key,source.get_meta(key))
	mesh.custom_aabb=source.get_aabb()
	return mesh
