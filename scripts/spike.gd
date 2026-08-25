extends Node3D
## One MagicaVoxel lantern + 3 OmniLight3D with shadows + sun.
## If the JOI pack is missing, falls back to a block tower.

const LANTERN_ID := "vox_fan_lantern_paper"


func _ready() -> void:
	_add_ground()
	_add_sun()
	var origin := Vector3(0, 0, 0)
	if not _try_pack_lantern(origin):
		_add_fallback_tower(origin)
	_add_omni("LampA", Vector3(-10, 14, 6), Color(1.0, 0.72, 0.35), true)
	_add_omni("LampB", Vector3(12, 10, -4), Color(0.45, 0.7, 1.0), true)
	_add_omni("LampC", Vector3(4, 8, 14), Color(1.0, 0.4, 0.55), true)
	var cam := OrbitCamera.new()
	cam.target = Vector3(0, 8, 0)
	cam.distance = 36.0
	add_child(cam)
	print("ember spike: pack=%s" % EmberPack.pack_root())


func _add_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.14, 0.12)
	mat.roughness = 0.92
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_sun() -> void:
	add_child(EmberLights.make_sun(173.0, 26.0, Color(0.47, 0.62, 0.97), 1.2))


func _try_pack_lantern(origin: Vector3) -> bool:
	var prefab_path := EmberPack.model_json_path(LANTERN_ID)
	if not FileAccess.file_exists(prefab_path):
		push_warning("ember spike: pack not found at %s" % EmberPack.pack_root())
		return false
	var prefab: Variant = EmberPack.parse_json_file(prefab_path)
	if typeof(prefab) != TYPE_DICTIONARY:
		return false
	var rel := str(prefab.get("mesh", {}).get("file", "voxels/models/%s.vox" % LANTERN_ID))
	var vox_path := EmberPack.pack_root().path_join(rel)
	if not FileAccess.file_exists(vox_path):
		return false
	var doc := VoxParser.parse_file(vox_path)
	if doc.is_empty():
		return false
	var mesh := VoxMesher.build_mesh(doc, 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Lantern"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mi.material_override = mat
	mi.position = origin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return true


func _add_fallback_tower(origin: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(4, 16, 4)
	var mi := MeshInstance3D.new()
	mi.name = "FallbackTower"
	mi.mesh = box
	mi.position = origin + Vector3(2, 8, 2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.28, 0.16)
	mi.material_override = mat
	add_child(mi)


func _add_omni(id: String, pos: Vector3, color: Color, shadows: bool) -> void:
	var light := EmberLights.make_omni(id, pos, color, 2.4, 0.8, shadows, 16.0)
	add_child(light)
