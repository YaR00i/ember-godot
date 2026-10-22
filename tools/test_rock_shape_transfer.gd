extends SceneTree
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Session=preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Store=preload("res://addons/ember_import/ember_voxel_model_store.gd")
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);printerr("FAIL ",message)
func run() -> void:
	var output:=OS.get_cmdline_user_args()[0]
	var source: EmberVoxelModelResource=load("res://content/voxel_models/vox_painted_rock_group.tres")
	var accepted: EmberVoxelModelResource=load(output.path_join("accepted-source.res"))
	check(source.voxels==accepted.voxels and source.voxel_part_ids==accepted.voxel_part_ids,"accepted occupancy and part IDs exact")
	check(source.validation_errors().is_empty(),"source validates")
	var reference: ArrayMesh=load(output.path_join("accepted-mesh.res"))
	var reference_faces:=reference.get_faces()
	var prepared:=EmberVoxelPrefab.prepare_resource(source,load("res://scripts/ember_voxel_projection_cache.gd").new())
	var prop:=prepared.instantiate() as EmberVoxelProp
	var mesh: ArrayMesh=prop.get_node("Mesh").mesh
	var faces:=mesh.get_faces()
	check(faces.size()==reference_faces.size(),"ordinary editor/runtime uses accepted triangle count, including cache path")
	var largest:=0.0
	for point in faces:
		var best:=INF
		for other in reference_faces:best=minf(best,point.distance_to(other))
		largest=maxf(largest,best)
	print("ROCK_MAX_VERTEX_DELTA_M ",largest)
	# Reconstructing support planes from the LAB's triangulated hull can move
	# near-parallel intersections slightly; limit this to 2mm (fine cell=62.5mm).
	check(largest<0.002,"ordinary geometry matches accepted LAB within 2mm")
	check(prop.get_node("Collision/Shape").shape.get_faces()==faces,"visual and collider use identical triangles")
	var legacy:=source.duplicate_model();legacy.solid_surface={}
	var old:=EmberVoxelPrefab.prepare_resource(legacy).instantiate()
	check(old.get_node("Mesh").mesh.get_faces().size()!=faces.size(),"negative control detects a missing form transfer")
	old.free();prop.free()
	var directory:="user://rock-shape-%d"%Time.get_ticks_usec()
	var source_path:=directory.path_join("sources/"+source.model_id+".tres")
	var prefab_path:=directory.path_join("prefabs/"+source.model_id+".tscn")
	check(Store.install_prepared_asset(source,prepared,source_path,prefab_path).ok,"ordinary library publication")
	var holder:=Node3D.new();root.add_child(holder)
	var packed: PackedScene=load(prefab_path)
	var placed:=packed.instantiate() as EmberVoxelProp;holder.add_child(placed);placed.owner=holder
	placed.configure_voxel_scale(16,1.0)
	var visual: MeshInstance3D=placed.get_node("Mesh")
	var material: ShaderMaterial=visual.get_active_material(0)
	var lookup: Texture2D=material.get_shader_parameter("style_rim_lookup")
	var pattern: EmberCompactTerrainPattern=load("res://content/terrain_materials/cartoon_stone.tres")
	var preview:=pattern.duplicate(true) as EmberCompactTerrainPattern
	preview.style_rim_custom=true;preview.style_rim_enabled=true;preview.style_rim_strength=0.31
	placed.preview_solid_material_light(preview,"cartoon_stone")
	check(material.get_shader_parameter("style_rim_lookup")==lookup and is_equal_approx(lookup.get_image().get_pixel(1,0).b,0.31),"existing material light preview updates solid lookup in place")
	placed.preview_solid_material_light(pattern,"cartoon_stone")
	check(lookup.get_image().get_pixel(1,0).r==(1.0 if pattern.style_rim_custom else 0.0) and is_equal_approx(lookup.get_image().get_pixel(1,0).b,pattern.style_rim_strength),"material preview restore uses saved pattern")
	var undo:=UndoRedo.new();var edit:=Session.new()
	edit.source_directory=directory.path_join("sources");edit.prefab_directory=directory.path_join("prefabs")
	check(edit.open(placed,holder,undo,true),"ordinary object editor opens accepted form: "+edit.error)
	var before: PackedVector3Array=placed.get_node("Mesh").mesh.get_faces()
	var next:=edit.draft.duplicate_model()
	# One existing guide is an ordinary saved property, not another mesh owner.
	next.solid_surface.parts[0][0]=next.solid_surface.parts[0][0].rotated(Vector3.FORWARD,0.02)
	var result:=edit.save(next)
	check(result.get("ok",false),"ordinary save updates Source, mesh and collider: "+str(result.get("error","")))
	if result.get("ok",false):
		var after: PackedVector3Array=placed.get_node("Mesh").mesh.get_faces()
		check(after!=before,"guide preview/save changes real geometry")
		check(placed.get_node("Collision/Shape").shape.get_faces()==after,"editor commit updates collision with geometry")
		undo.undo();check(placed.get_node("Mesh").mesh.get_faces()==before,"geometry and Source Undo")
		undo.redo();check(placed.get_node("Mesh").mesh.get_faces()==after,"geometry and Source Redo")
		var reopened: EmberVoxelModelResource=ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var restored:=EmberVoxelPrefab.prepare_resource(reopened).instantiate()
		check(restored.get_node("Mesh").mesh.get_faces()==after,"save/reopen rebuild retains form")
		restored.free()
	var invalid:=source.duplicate_model();invalid.solid_surface.parts[0][0]=Vector3(NAN,0,0)
	check(not invalid.validation_errors().is_empty(),"nonfinite guide validation")
	var sculpted:=source.duplicate_model();var removed:=sculpted.voxels.find(1)
	sculpted.voxels[removed]=0;sculpted.voxel_part_ids[removed]=0
	check(not Solid.active(sculpted.to_definition().model),"manual sculpt uses exact voxel mesh instead of a stale smooth hull")
	check(sculpted.validation_errors().is_empty(),"ordinary sculpt remains a valid Source")
	var voxel_prop:=EmberVoxelPrefab.prepare_resource(sculpted).instantiate() as EmberVoxelProp;holder.add_child(voxel_prop)
	check(voxel_prop.get_node("Mesh").mesh.surface_get_name(0)!="solid_surface","sculpt preview/commit uses the exact voxel path")
	check(voxel_prop.get_node("Mesh").mesh.get_faces()==voxel_prop.get_node("Collision/Shape").shape.get_faces(),"sculpt keeps one visual/physical surface")
	voxel_prop.free()
	var copied:=source.duplicate_model();copied.solid_surface.parts[0][0]=Vector3.UP
	check(copied.solid_surface!=source.solid_surface,"draft guides do not mutate source")
	var file:=FileAccess.open(output.path_join("geometry-test.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"accepted_triangles":faces.size()/3,"max_vertex_delta_m":largest,"negative_control":true},"\t"));file.close()
	holder.free();undo.free()
	print("ROCK_SHAPE_TRANSFER ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
