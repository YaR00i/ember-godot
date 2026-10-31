extends SceneTree
## Existing density brush on a physical, painted volume; user:// snapshots only.
const Brush=preload("res://addons/ember_import/ember_detail_brush.gd")
const Patch=preload("res://scripts/ember_grass_patch.gd")
var errors:Array[String]=[]
var scene:Node3D
var map:EmberMapLoader
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("OBJECT_DETAIL_FAIL ",label)
func patches()->Array[Node]:
	var result:Array[Node]=[]
	for node in map.get_node("Props").get_children():
		if node.get_script()==Patch:result.append(node)
	return result
func settle()->void:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		var pending:=false
		for patch in patches():pending=pending or patch._dirty or patch._rebuilding
		if not pending:
			for i in 8:await process_frame
			return
	check(false,"local scatter settles")
func count()->int:
	var total:=0
	for patch in patches():
		if patch._visual!=null and patch._visual.multimesh!=null:total+=patch._visual.multimesh.instance_count
	return total
func replace_surface(prop:EmberVoxelProp,source:EmberVoxelModelResource)->void:
	var draft:EmberVoxelProp=EmberVoxelPrefab.prepare_resource(source).instantiate()
	prop.get_node("Mesh").mesh=draft.get_node("Mesh").mesh
	prop.refresh_authoring_projection();prop._invalidate_floor_faces();draft.free()
func run()->void:
	preload("res://scripts/ember_detail_preparation.gd").cache_root="user://ember-tests/object-detail-brush-%d"%Time.get_ticks_usec()
	scene=Node3D.new();root.add_child(scene);current_scene=scene
	map=EmberMapLoader.new();map.name="Map";map.world_look=0
	var terrain:=EmberTerrainPilotResource.new();terrain.width=64;terrain.depth=64
	terrain.palette=PackedColorArray([Color.TRANSPARENT,Color.GREEN]);terrain.palette_surface_roles=PackedStringArray(["","grass"]);terrain.palette_material_ids=PackedStringArray(["","cartoon_grass"])
	for key in ["heights","top_materials","base_materials","cap_depths","water_levels","water_materials"]:terrain.get(key).resize(4096)
	terrain.heights.fill(4);terrain.top_materials.fill(1);terrain.base_materials.fill(1);terrain.cap_depths.fill(1)
	check(terrain.validation_errors().is_empty(),"valid ground fixture")
	map.compact_terrain=terrain;scene.add_child(map);map.owner=scene
	var props:=Node3D.new();props.name="Props";map.add_child(props);props.owner=scene
	var source:=EmberVoxelModelResource.new();source.model_id="object_detail_fixture";source.size_blocks=Vector3i(2,1,2)
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.GRAY,Color.BROWN,Color.GREEN])
	source.voxels.resize(32*16*32);source.voxel_part_ids.resize(source.voxels.size());source.voxel_part_ids.fill(1);source.merge_parts=PackedStringArray(["body"])
	for y in 16:
		for z in 32:
			for x in 32:source.voxels[x+z*32+y*1024]=1 if x>=24 else 3 if y>=8 else 2
	source.solid_surface={"version":1,"topology":"volume","occupancy":preload("res://scripts/ember_voxel_solid_surface.gd").occupancy_hash(source.voxels),"parts":[PackedVector3Array([Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK])],"roles":PackedStringArray(["","stone","soil","grass"]),"material_ids":PackedStringArray(["","cartoon_stone","soil_grain","cartoon_grass"])}
	check(source.validation_errors().is_empty(),"valid painted volume")
	var prop:EmberVoxelProp=EmberVoxelPrefab.prepare_resource(source).instantiate();prop.name="Cliff";prop.authoring_source=source
	props.add_child(prop);prop.owner=scene;prop.position=Vector3(24,12,24)
	for i in 12:await process_frame
	prop.set_world_look(0)
	var visual:MeshInstance3D=prop.get_node("Mesh");var bounds:AABB=visual.global_transform*visual.mesh.get_aabb()
	var point:=Vector3(lerpf(bounds.position.x,bounds.end.x,0.35),0,bounds.get_center().z)
	var stone:=Vector3(lerpf(bounds.position.x,bounds.end.x,0.90),0,bounds.get_center().z)
	var hit:=map.surface_floor_sample(point)
	check(hit.get("object")==prop and hit.get("material_role")=="grass","common sampler identifies physical grass top")
	check(map.surface_floor_sample(stone).get("material_role")=="stone","stone remains unplantable")
	var total_faces:=prop._floor_faces.size()/3;var candidates:=0
	for bucket in prop._floor_grid.values():candidates=maxi(candidates,bucket.size())
	check(candidates<total_faces/3,"root queries use local triangles")
	var history:=UndoRedo.new();var brush:=Brush.new();root.add_child(brush);check(brush.activate_details(scene,map,history),"activate existing brush")
	brush.radius_m=0.65;brush.density_per_m2=110;brush.size_value=0.65
	brush._append(stone);check(brush._drafts.is_empty(),"stone click creates no density")
	brush._append(point);await settle();check(count()>0,"grass preview on object")
	brush.cancel_stroke();check(patches().is_empty(),"Cancel removes draft")
	brush._append(point);check(brush.commit_stroke()>0,"one committed object stroke");await settle()
	var initial:=count();check(initial>0,"committed object vegetation visible")
	var snapshots:Dictionary={}
	for patch in patches():snapshots[patch.name]=patch.density_cells.duplicate()
	history.undo();check(patches().is_empty(),"one Undo removes stroke")
	history.redo();await settle();check(count()==initial,"Redo restores exact scatter count")
	for look in 3:
		map.world_look=look;await settle();check(count()==initial,"look %d preserves scatter"%look)
		var leaning:=0
		for patch in patches():
			check(patch.validation_errors().is_empty(),"patch validation")
			for i in patch._visual.multimesh.instance_count:
				var transform:Transform3D=patch.global_transform*patch._visual.multimesh.get_instance_transform(i)
				var at:Vector3=transform.origin
				if absf(transform.basis.y.x)+absf(transform.basis.y.z)>0.0001:leaning+=1
				var sample:=map.surface_floor_sample(at)
				check(sample.get("object")==prop and absf(sample.position.y-at.y)<0.01,"all looks root on physical object, not ground below")
		check(leaning>0 if look==0 else leaning==0,"only detailed edge blades lean outward")
	map.world_look=0;await settle()
	var near:=patches()[0];var old_stamp:Array=near._surface_stamp.duplicate(true)
	var far:=Patch.new();far.painted_only=true;props.add_child(far);far.position=Vector3(1000,0,1000);await settle()
	var far_generations:int=far.detail_generations
	prop.position.y+=8
	await settle();check(far.detail_generations==far_generations,"object movement does not regenerate distant patch")
	check(near._surface_stamp!=old_stamp and count()>0,"object stamp and root heights update")
	# Repainting the top to stone uses the existing Source/mesh install path.
	var before:=source.voxels.duplicate();source.voxels.fill(1)
	replace_surface(prop,source);await settle();check(count()==0,"repaint removes vegetation from stone")
	source.voxels=before
	replace_surface(prop,source);await settle()
	check(count()==initial,"restored paint restores deterministic scatter")
	far.free()
	brush.detail_kind=3;brush.cover_pattern=load(preload("res://scripts/ember_flowered_grass.gd").PATTERN_PATH);brush.density_per_m2=12
	brush._append(point);check(brush.commit_stroke()>0,"same brush paints flowers on object");await settle()
	check(count()>initial,"flowers visible above object surface")
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack scene")
	var path:="user://object-details-roundtrip.tscn";check(ResourceSaver.save(packed,path)==OK,"save")
	var reopened:Node=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	for name in snapshots:check(reopened.get_node("Map/Props/"+name).density_cells==snapshots[name],"fresh reopen keeps original density")
	brush._append(point+Vector3(1,0,0));brush.cancel_stroke()
	for name in snapshots:check(reopened.get_node("Map/Props/"+name).density_cells==snapshots[name],"discard keeps saved density")
	reopened.free();brush.deactivate();history.clear_history();history.free();brush.free()
	print("OBJECT_DETAIL_BRUSH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"instances":initial,"triangles":total_faces,"max_bucket":candidates}))
	scene.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
