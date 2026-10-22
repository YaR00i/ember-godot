extends "res://tools/capture_rock_surface_detail.gd"
## One-time publication of the already accepted Source. No new shape recipe.
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var model: EmberVoxelModelResource=load(output.path_join("accepted-source.res"))
	check(model!=null and model.validation_errors().is_empty(),"accepted Source exists")
	var fingerprint:=hash([model.voxels,model.voxel_part_ids])
	var references:=ArrayMesh.new();var directions: Array=[]
	for id in model.merge_parts.size():
		var fit:=ordinary_look(model,mass_data(model,id),id)
		var normals:=PackedVector3Array()
		for plane in mesh_planes(fit.mesh):normals.append(plane.normal)
		directions.append(normals)
		var arrays: Array=fit.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():vertices[i]/=16.0
		arrays[Mesh.ARRAY_VERTEX]=vertices;references.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	model.model_id="vox_painted_rock_group";model.display_name="Рисованные камни · принятая форма"
	model.tags=PackedStringArray(["rock","painted","environment"])
	model.solid_surface={"version":1,"parts":directions,"occupancy":load("res://scripts/ember_voxel_solid_surface.gd").occupancy_hash(model.voxels),"roles":PackedStringArray(["","stone"]),"material_ids":PackedStringArray(["","cartoon_stone"])}
	check(model.validation_errors().is_empty(),"published profile validates")
	check(fingerprint==hash([model.voxels,model.voxel_part_ids]),"occupied Source and six parts unchanged")
	check(ResourceSaver.save(model,"res://content/voxel_models/vox_painted_rock_group.tres")==OK,"publish canonical voxel Source")
	check(ResourceSaver.save(references,output.path_join("accepted-mesh.res"))==OK,"independent accepted geometry reference")
	var native:=EmberVoxelPrefab.prepare_resource(model)
	check(native!=null,"ordinary prefab builds accepted Source")
	print("ROCK_SHAPE_PUBLISH ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
