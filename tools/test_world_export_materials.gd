extends SceneTree
const Export=preload("res://addons/ember_import/ember_terrain_cache_export.gd")
func _initialize()->void:
	var scene:=Node3D.new()
	var derived:=MeshInstance3D.new();var authored:=MeshInstance3D.new()
	var first:=ShaderMaterial.new();first.set_meta("ember_derived_solid_material",true)
	var second:=StandardMaterial3D.new();second.albedo_color=Color.MAGENTA
	derived.mesh=BoxMesh.new();derived.material_override=first
	authored.mesh=SphereMesh.new();authored.material_override=second
	scene.add_child(derived);scene.add_child(authored)
	var shape:=derived.mesh
	assert(Export.strip_derived_material_overrides(scene))
	assert(derived.material_override==null and derived.mesh==shape)
	assert(authored.material_override==second and second.albedo_color==Color.MAGENTA)
	assert(not Export.strip_derived_material_overrides(scene))
	assert(first.get_meta("ember_derived_solid_material"),"shared source material was modified")
	var layered:=MeshInstance3D.new();var mesh:=ArrayMesh.new()
	var arrays:=BoxMesh.new().get_mesh_arrays()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.set_meta("solid_surface_material_ids",PackedStringArray(["stone"]))
	mesh.surface_set_material(0,first);layered.mesh=mesh;scene.add_child(layered)
	assert(Export.strip_derived_material_overrides(scene))
	assert(layered.mesh!=mesh and layered.mesh.surface_get_material(0)==null)
	assert(mesh.surface_get_material(0)==first,"source mesh material was modified")
	assert(layered.mesh.surface_get_arrays(0)==mesh.surface_get_arrays(0),"geometry changed")
	assert(layered.mesh.get_meta("solid_surface_material_ids")==mesh.get_meta("solid_surface_material_ids"))
	scene.free()
	print("WORLD_EXPORT_MATERIALS PASS disposable override only/authored material/geometry/source/idempotence")
	quit()
