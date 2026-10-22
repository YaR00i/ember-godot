extends SceneTree
const Surface=preload("res://scripts/ember_tree_surface.gd")
const Bake=preload("res://scripts/ember_tree_look_bake.gd")
var errors: Array[String]=[]
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var source: EmberVoxelModelResource=load("res://content/voxel_models/vox_painted_oak.tres")
	var model: Dictionary=source.to_definition().model
	var original:=hash(model);var smooth:=Surface.build(model)
	var original_arrays: Array=[]
	for i in smooth.get_surface_count():original_arrays.append(hash(smooth.surface_get_arrays(i)))
	var a:=Bake.build(model,0.125);var b:=Bake.build(model,0.125)
	check(a.puffs.size()==399 and a.cards==885,"accepted sites45% retained")
	check(a.cells>0,"nonempty voxel canopy")
	for i in a.mesh.get_surface_count():check(a.mesh.surface_get_arrays(i)==b.mesh.surface_get_arrays(i),"deterministic baked buffers")
	check(hash(model)==original,"canonical model unchanged")
	for i in smooth.get_surface_count():check(hash(Surface.build(model).surface_get_arrays(i))==original_arrays[i],"smooth arrays retained")
	var minimal:=model.duplicate(true);minimal.treeSurface.settings.tree_leaf_density=0
	var bare:=Bake.build(minimal,0.125)
	check(bare.cells==0 and bare.mesh.get_surface_count()==1,"zero density has no voxel foliage")
	var thinned:=model.duplicate(true);thinned.treeSurface.settings.tree_leaf_local={"1":0.0}
	var groups:=Bake.Geometry.crown_leaf_groups(Surface.leaf_layout(model))
	thinned.treeSurface.settings.tree_leaf_local={str(groups.keys()[0]):0.0}
	var selected:=Bake.build(thinned,0.125)
	check(selected.puffs.size()<a.puffs.size(),"local density reduces both looks")
	for key in selected.puffs:check(key in a.puffs,"local thinning keeps shared site identities")
	var foliage: ShaderMaterial=a.mesh.surface_get_material(1)
	check(is_equal_approx(float(foliage.get_shader_parameter("painted_leaf_shadow_strength")),0.4),"accepted shadow receiving")
	check(foliage.get_shader_parameter("painterly_grass_low")==smooth.surface_get_material(1).get_shader_parameter("painterly_grass_low"),"accepted tonal depth")
	var painted:=model.duplicate(true);painted.palette[1]="cc4433"
	check(Bake.wood_mesh(painted).surface_get_arrays(0)[Mesh.ARRAY_COLOR]!=a.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR],"manual source paint reaches voxel bark")
	var baked_path:="user://oak-voxel-derived.res"
	check(ResourceSaver.save(a.mesh,baked_path)==OK,"save derived mesh")
	var baked_again: ArrayMesh=ResourceLoader.load(baked_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	for i in a.mesh.get_surface_count():check(a.mesh.surface_get_arrays(i)==baked_again.surface_get_arrays(i),"derived mesh roundtrip")
	var saved:="user://oak-looks-source.tres"
	check(ResourceSaver.save(source,saved)==OK,"save fixture")
	var reopened: EmberVoxelModelResource=ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(reopened.voxels==source.voxels and reopened.collision_voxels==source.collision_voxels,"Source and wood collision roundtrip")
	check(Surface.same_values(reopened.tree_surface,source.tree_surface),"supports/appearance roundtrip")
	var restored:=Bake.build(reopened.to_definition().model,0.125)
	check(restored.cells==a.cells and restored.puffs==a.puffs,"rebake after reopen")
	print("OAK_LOOKS_TEST ","PASS" if errors.is_empty() else errors," cells=",a.cells," triangles=",a.triangles," ms=",a.build_ms)
	quit(0 if errors.is_empty() else 1)

