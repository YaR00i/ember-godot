class_name EmberMapLoader
extends Node3D
## Loads one Ember map JSON + sibling `.vox` meshes. Pack schema is not copied.

@export var map_id := "fan_town"

var _voxel_mat: StandardMaterial3D
var _ground_mat: StandardMaterial3D
var _mesh_cache: Dictionary = {}
var _size_cache: Dictionary = {}
var _prefab_cache: Dictionary = {}
var _stats := {
	"props": 0,
	"omni": 0,
	"omni_shadow": 0,
	"missing_vox": 0,
	"width": 0,
	"height": 0,
	"tile_size": 16,
}


func load_map(id: String) -> Dictionary:
	map_id = id
	var path := EmberPack.map_path(id)
	var data: Variant = EmberPack.parse_json_file(path)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ember map: failed to parse %s" % path)
		return _stats
	var map: Dictionary = data
	var tile_size := float(map.get("tileSize", 16))
	var width := int(map.get("width", 16))
	var height := int(map.get("height", 16))
	_stats.width = width
	_stats.height = height
	_stats.tile_size = tile_size
	_ensure_materials()
	_add_ground(width, height, tile_size)
	_add_look(map.get("light", {}), width, height, tile_size)
	var props: Array = map.get("voxelProps", [])
	for place in props:
		if typeof(place) != TYPE_DICTIONARY:
			continue
		_add_prop(place, tile_size)
	print(
		"ember map %s: props=%s omni=%s shadow=%s missing_vox=%s pack=%s"
		% [id, _stats.props, _stats.omni, _stats.omni_shadow, _stats.missing_vox, EmberPack.pack_root()]
	)
	return _stats


func stats() -> Dictionary:
	return _stats.duplicate()


func _ensure_materials() -> void:
	if _voxel_mat == null:
		_voxel_mat = StandardMaterial3D.new()
		_voxel_mat.vertex_color_use_as_albedo = true
		_voxel_mat.roughness = 0.82
		_voxel_mat.metallic = 0.0
	if _ground_mat == null:
		_ground_mat = StandardMaterial3D.new()
		_ground_mat.albedo_color = Color(0.18, 0.16, 0.14)
		_ground_mat.roughness = 0.9


func _add_ground(width: int, height: int, tile_size: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(width * tile_size, height * tile_size)
	var mesh_i := MeshInstance3D.new()
	mesh_i.name = "Ground"
	mesh_i.mesh = plane
	mesh_i.material_override = _ground_mat
	mesh_i.position = Vector3(width * tile_size * 0.5, 0.0, height * tile_size * 0.5)
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_i)


func _add_look(light: Variant, width: int, height: int, tile_size: float) -> void:
	var cfg: Dictionary = light if typeof(light) == TYPE_DICTIONARY else {}
	var atmo_raw: Variant = cfg.get("atmosphere", {})
	var atmo: Dictionary = atmo_raw if typeof(atmo_raw) == TYPE_DICTIONARY else {}
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = EmberLights.hex_color(str(atmo.get("fogColor", "#120810")), Color(0.07, 0.03, 0.08))
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = EmberLights.hex_color(str(cfg.get("ambientColor", "#032472")))
	e.ambient_light_energy = clampf(float(cfg.get("fillIntensity", 0.23)) * 1.8, 0.05, 1.2)
	e.fog_enabled = true
	e.fog_light_color = e.background_color
	e.fog_density = clampf(float(atmo.get("fog", 0.05)) * 0.35, 0.0, 0.08)
	e.glow_enabled = true
	e.glow_intensity = clampf(float(cfg.get("bloomStrength", 0.28)), 0.0, 1.0)
	env.environment = e
	add_child(env)
	var sun := EmberLights.make_sun(
		float(cfg.get("sunAzimuth", 40)),
		float(cfg.get("sunElevation", 45)),
		EmberLights.hex_color(str(cfg.get("sunColor", "#789ef7"))),
		float(cfg.get("sunIntensity", 1.0)),
	)
	var center := Vector3(width * tile_size * 0.5, 12.0, height * tile_size * 0.5)
	sun.position = center + EmberLights.sun_direction(
		float(cfg.get("sunAzimuth", 40)),
		float(cfg.get("sunElevation", 45)),
	) * 90.0
	sun.look_at(center)
	add_child(sun)


func _add_prop(place: Dictionary, tile_size: float) -> void:
	var model_id := str(place.get("modelId", ""))
	if model_id.is_empty():
		return
	var prefab := _load_prefab(model_id)
	var mesh := _mesh_for(model_id, tile_size)
	if mesh == null:
		_stats.missing_vox += 1
		return
	var size := _ember_size_of(model_id)
	var vw := tile_size / float(VoxMesher.VOXELS_PER_BLOCK)
	var w := size.x * vw
	var d := size.z * vw
	var elev := float(place.get("elev", 0))
	var rot := int(place.get("rot", 0))
	var root := Node3D.new()
	root.name = str(place.get("id", model_id))
	root.position = Vector3(
		float(place.get("x", 0)) * tile_size + w * 0.5,
		elev * tile_size,
		float(place.get("y", 0)) * tile_size + d * 0.5,
	)
	root.rotation.y = float(rot) * PI * 0.5
	var inner := MeshInstance3D.new()
	inner.mesh = mesh
	inner.material_override = _voxel_mat
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inner.position = Vector3(-w * 0.5, 0.0, -d * 0.5)
	root.add_child(inner)
	add_child(root)
	_stats.props += 1
	_maybe_add_lamp(place, prefab, root, size, vw, tile_size)


func _maybe_add_lamp(
	place: Dictionary,
	prefab: Dictionary,
	root: Node3D,
	size: Vector3i,
	vw: float,
	tile_size: float,
) -> void:
	var model: Dictionary = prefab.get("model", {})
	var casts := bool(place.get("emissiveCastsLight", model.get("emissiveCastsLight", false)))
	if not casts:
		return
	var shadows := bool(place.get("emissiveLightShadows", model.get("emissiveLightShadows", false)))
	var range_tiles := float(place.get("emissiveLightRange", model.get("emissiveLightRange", 2.0)))
	var strength := float(place.get("emissiveStrength", model.get("emissiveStrength", 0.75)))
	var color := EmberLights.hex_color("#ffb056")
	var pal: Array = model.get("palette", [])
	for i in range(pal.size() - 1, -1, -1):
		var hex := str(pal[i])
		if hex.begins_with("#") and hex.length() >= 7:
			color = EmberLights.hex_color(hex)
			break
	var lamp_pos := root.position + Vector3(0.0, size.y * vw * 0.62, 0.0)
	var light := EmberLights.make_omni(
		"%s_omni" % place.get("id", "lamp"),
		lamp_pos,
		color,
		range_tiles,
		strength,
		shadows,
		tile_size,
	)
	add_child(light)
	_stats.omni += 1
	if shadows:
		_stats.omni_shadow += 1


func _load_prefab(model_id: String) -> Dictionary:
	if _prefab_cache.has(model_id):
		return _prefab_cache[model_id]
	var parsed: Variant = EmberPack.parse_json_file(EmberPack.model_json_path(model_id))
	var prefab: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_prefab_cache[model_id] = prefab
	return prefab


func _mesh_for(model_id: String, tile_size: float) -> ArrayMesh:
	if _mesh_cache.has(model_id):
		return _mesh_cache[model_id]
	var prefab := _load_prefab(model_id)
	var rel := str(prefab.get("mesh", {}).get("file", "voxels/models/%s.vox" % model_id))
	var vox_path := EmberPack.pack_root().path_join(rel)
	if not FileAccess.file_exists(vox_path):
		_mesh_cache[model_id] = null
		return null
	var doc := VoxParser.parse_file(vox_path)
	if doc.is_empty():
		_mesh_cache[model_id] = null
		return null
	var vw := tile_size / float(VoxMesher.VOXELS_PER_BLOCK)
	var mesh := VoxMesher.build_mesh(doc, vw)
	_mesh_cache[model_id] = mesh
	_size_cache[model_id] = VoxMesher.ember_size(doc.models[0].size)
	return mesh


func _ember_size_of(model_id: String) -> Vector3i:
	if _size_cache.has(model_id):
		return _size_cache[model_id]
	_mesh_for(model_id, 16.0)
	return _size_cache.get(model_id, Vector3i(16, 16, 16))
