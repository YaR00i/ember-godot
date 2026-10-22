extends SceneTree
## A saved pre-transfer prefab, reopened after the ordinary material binding changes.
const Surface=preload("res://scripts/ember_tree_surface.gd")
const Species=preload("res://scripts/ember_tree_species.gd")
const Refresh=preload("res://addons/ember_import/ember_voxel_scene_refresh.gd")
const IDS: Array[String]=["vox_painted_savanna","vox_painted_oak","vox_painted_birch","vox_painted_maple","vox_painted_spruce"]
const ACCEPTED:="res://content/material_studies/trees/bark_species_v1/oak-v3-painted.png"
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);push_error(label)
func run() -> void:
	var output:=OS.get_cmdline_user_args()[0].replace("\\","/")
	# Canonical prefab auto-refresh is exercised only in the disposable checkout.
	if not ProjectSettings.globalize_path("res://").contains("ember-tree-grass-light/project"):
		push_error("Oak transfer gate requires its disposable project");quit(1);return
	var source: EmberVoxelModelResource=load("res://content/voxel_models/vox_painted_oak.tres")
	var contracts: Array[String]=[];var hashes: Array[String]=[]
	for id in IDS:
		var record: EmberVoxelModelResource=load(EmberVoxelCatalog.native_path(id))
		contracts.append(EmberVoxelPrefab.source_render_contract(record.to_definition().model))
		hashes.append(FileAccess.get_sha256(EmberVoxelCatalog.native_path(id)))
	if OS.get_cmdline_user_args().has("--seed-stale"):
		var old:=EmberVoxelPrefab.ensure_saved(source.model_id,1.0,{},true)
		var prop:=old.instantiate()
		check(ResourceSaver.save(prop.get_node("Mesh").mesh.duplicate(true),output.path_join("before-oak-mesh.res"))==OK,"freeze original mesh and materials")
		var file:=FileAccess.open(output.path_join("before-contracts.var"),FileAccess.WRITE)
		file.store_var({"contracts":contracts,"hashes":hashes,"signature":prop.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META),"collision":prop.get_node("Collision/Shape").shape.get_faces()});file.close();prop.free()
		print("OAK_BARK_SEED ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1);return
	var file:=FileAccess.open(output.path_join("before-contracts.var"),FileAccess.READ)
	var before: Dictionary=file.get_var();file.close()
	check(before.hashes==hashes,"all five canonical Sources byte-exact")
	for kind in 5:check((before.contracts[kind]!=contracts[kind]) if kind==1 else (before.contracts[kind]==contracts[kind]),"only oak derived contract changes "+str(kind))
	var old: ArrayMesh=load(output.path_join("before-oak-mesh.res"))
	var seed:=EmberVoxelPrefab.prepare_resource(source).instantiate()
	seed.get_node("Mesh").mesh=old.duplicate(true);seed.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META,before.signature)
	var stale_prefab:=PackedScene.new();check(stale_prefab.pack(seed)==OK,"repeatable stale prefab fixture");seed.free()
	check(ResourceSaver.save(stale_prefab,EmberVoxelPrefab.prefab_path(source.model_id))==OK,"install stale derived fixture in QA")
	var existing: PackedScene=ResourceLoader.load(EmberVoxelPrefab.prefab_path(source.model_id),"",ResourceLoader.CACHE_MODE_REPLACE)
	check(not EmberVoxelPrefab.validate_packed(source.model_id,existing).ok,"saved old oak identified as stale")
	var packed:=EmberVoxelPrefab.ensure_saved(source.model_id,1.0,{})
	check(EmberVoxelPrefab.validate_packed(source.model_id,packed).ok,"ordinary loader refreshes stale oak")
	var prop:=packed.instantiate();var current: ArrayMesh=prop.get_node("Mesh").mesh
	for index in 2:
		check(current.surface_get_arrays(index)==old.surface_get_arrays(index),"full wood/leaf geometry and paint unchanged "+str(index))
		check(parameters(current.surface_get_material(index),index==0)==parameters(old.surface_get_material(index),index==0),"all non-bark-art shader parameters unchanged "+str(index))
	check(prop.get_node("Collision/Shape").shape.get_faces()==before.collision,"physical wood collider unchanged")
	check_art(current)
	var preview:=EmberVoxelPrefab.prepare_resource(source).instantiate()
	for i in 2:check(preview.get_node("Mesh").mesh.surface_get_arrays(i)==current.surface_get_arrays(i),"preview/runtime exact buffers "+str(i))
	check_art(preview.get_node("Mesh").mesh);preview.free()
	# Existing scene refresh owner handles stale embedded instances, with Undo/Redo.
	var dir:="user://oak-bark-transfer"
	DirAccess.make_dir_recursive_absolute(dir.path_join("sources"));DirAccess.make_dir_recursive_absolute(dir.path_join("prefabs"))
	check(ResourceSaver.save(source.duplicate_model(),dir.path_join("sources/vox_painted_oak.tres"))==OK,"fixture Source saved")
	var holder:=Node3D.new();root.add_child(holder);holder.name="OakBarkTransferFixture"
	prop.scene_file_path=""
	prop.get_node("Mesh").mesh=old.duplicate(true);prop.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META,before.signature)
	holder.add_child(prop);prop.owner=holder
	var stale:=PackedScene.new();check(stale.pack(prop)==OK,"stale instance packed")
	check(ResourceSaver.save(stale,dir.path_join("prefabs/vox_painted_oak.tscn"))==OK,"stale fixture prefab saved")
	var source_hash:=FileAccess.get_sha256(dir.path_join("sources/vox_painted_oak.tres"))
	var edited_material: ShaderMaterial=old.surface_get_material(0).duplicate()
	edited_material.set_shader_parameter("painted_bark_tint",Color(0.7,0.6,0.5))
	check(not Surface.refresh_material_matches(edited_material,current.surface_get_material(0),source.to_definition().model,0),"manual bark tint is protected")
	var edited_leaf: ShaderMaterial=old.surface_get_material(1).duplicate()
	edited_leaf.set_shader_parameter("painted_leaf_shadow_strength",0.1)
	check(not Surface.refresh_material_matches(edited_leaf,current.surface_get_material(1),source.to_definition().model,1),"manual leaf shadow setting is protected")
	var undo:=UndoRedo.new();var operation:=Refresh.new()
	operation.source_directory=dir.path_join("sources");operation.prefab_directory=dir.path_join("prefabs")
	var result: Dictionary=operation.rebuild_catalog_model(source.model_id,holder,undo)
	check(result.ok,"existing refresh updates saved instance "+str(result))
	if result.ok:
		check_art(prop.get_node("Mesh").mesh)
		undo.undo();check(parameters(prop.get_node("Mesh").mesh.surface_get_material(0),false)==parameters(old.surface_get_material(0),false),"refresh Undo restores old bark")
		undo.redo();check_art(prop.get_node("Mesh").mesh)
		check(FileAccess.get_sha256(dir.path_join("sources/vox_painted_oak.tres"))==source_hash,"refresh history never rewrites Source")
	EmberVoxelPrefab._set_pack_owner(holder,holder)
	var map:=PackedScene.new();check(map.pack(holder)==OK,"fixture map packed")
	check(ResourceSaver.save(map,dir.path_join("map.tscn"))==OK,"fixture map saved")
	var reopened: PackedScene=ResourceLoader.load(dir.path_join("map.tscn"),"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var restored:=reopened.instantiate();check_art(restored.get_child(0).get_node("Mesh").mesh);restored.free()
	prop.free();holder.free();undo.free()
	print("OAK_BARK_TRANSFER ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
func check_art(mesh: ArrayMesh) -> void:
	var material: ShaderMaterial=mesh.surface_get_material(0)
	var expected:=Surface.Bark.artwork(ACCEPTED).get_image()
	check(material.get_shader_parameter("painted_bark_albedo").get_image().get_data()==expected.get_data(),"accepted B including mipmaps bound")
	check(not material.shader.code.contains("define EMBER_OBJECT_PAINTED_BARK_RELIEF_STUDY"),"LAB depth not enabled")
func parameters(material: ShaderMaterial,exclude_art: bool) -> Dictionary:
	var result: Dictionary={"shader":material.shader.code}
	for property in material.get_property_list():
		var key:=str(property.name)
		if not key.begins_with("shader_parameter/") or (exclude_art and key=="shader_parameter/painted_bark_albedo"):continue
		var value: Variant=material.get(key)
		result[key]=value.get_image().get_data() if value is Texture2D else value
	return result
