extends SceneTree
## One side cavity, paint and its actual boundary. No authoring assets are written.
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Model=preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Actions=preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")
const Fragment=preload("res://addons/ember_import/ember_voxel_fragment.gd")
var errors:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("SOLID_VOLUME_FAIL ",label)
func data(source:EmberVoxelModelResource)->Dictionary:return EmberVoxelPrefab.model_of(source.to_definition())
func saved_data(source:EmberVoxelModelResource)->Dictionary:
	var result:=source.to_definition().duplicate(true);result.erase("_resourcePath");return result
func fixture()->EmberVoxelModelResource:
	var source:=EmberVoxelModelResource.new();source.model_id="solid_volume_fixture"
	source.palette=PackedColorArray([Color(0,0,0,0),Color(0.4,0.4,0.5),Color(0.4,0.25,0.12),Color(0.3,0.5,0.2)])
	source.voxels.resize(4096);source.voxel_part_ids.resize(4096);source.merge_parts=PackedStringArray(["body"])
	for y in 16:
		for z in 16:
			for x in 16:
				var i:=Model.index_of(Vector3i(x,y,z),Vector3i(16,16,16))
				source.voxels[i]=3 if y>=13 else 2 if y>=10 else 1;source.voxel_part_ids[i]=1
	source.solid_surface={"version":1,"occupancy":Solid.occupancy_hash(source.voxels),
		"parts":[PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK])],
		"roles":PackedStringArray(["","stone","soil","grass"]),
		"material_ids":PackedStringArray(["","cartoon_stone","soil_grain","cartoon_grass"])}
	return source
func hit(mesh:Mesh,from:Vector3,to:Vector3)->Vector3:
	var faces:=mesh.get_faces();var best:=Vector3(INF,INF,INF);var distance:=INF
	for i in range(0,faces.size(),3):
		var point:Variant=Geometry3D.segment_intersects_triangle(from,to,faces[i],faces[i+1],faces[i+2])
		if point!=null and from.distance_squared_to(point)<distance:distance=from.distance_squared_to(point);best=point
	return best
func run()->void:
	if "--physical-looks" in OS.get_cmdline_user_args():
		await physical_looks();return
	if "--addition" in OS.get_cmdline_user_args():
		var source:=fixture();var original:Dictionary=source.to_definition(true).model
		var history:=UndoRedo.new();var actions:=Actions.new();actions.configure(history)
		actions.apply_stroke(source,{0:{"before":1,"after":0},1:{"before":1,"after":0}})
		actions.apply_stroke(source,{0:{"before":0,"after":1}})
		check(source.voxel_part_ids[0]==0,"ordinary Add retains the Added part")
		check(Solid.active(data(source)) and Solid.uses_volume(data(source)),"unowned addition keeps the solid volume and material renderer")
		check(source.validation_errors().is_empty(),"addition is valid Source data")
		var restored:=fixture();restored.voxel_part_ids[0]=0
		check(Solid.active(data(restored)) and Solid.uses_volume(data(restored)),"added ownership keeps volume even when occupancy matches the old hull")
		restored.voxel_part_ids[0]=restored.merge_parts.size()+1
		check(not Solid.active(data(restored)),"invalid positive part IDs remain rejected")
		if Solid.active(data(source)):
			for mesh in [Solid.build(data(source)),Solid.living_mesh(data(source),1.0,PackedFloat32Array()),Solid.build_voxel_look(data(source))]:
				check(mesh.get_surface_count()>0 and mesh.surface_get_name(0)=="solid_surface","all looks retain the solid material channel")
		var added:Dictionary=source.to_definition(true).model
		history.undo();history.undo();check(source.to_definition(true).model==original,"Undo restores original data")
		history.redo();history.redo();check(source.to_definition(true).model==added,"Redo restores added geometry and ownership")
		var path:="user://solid-addition-%d.tres"%Time.get_ticks_usec();check(ResourceSaver.save(source,path)==OK,"addition saves")
		var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
		check(reopened!=null and reopened.to_definition(true).model==added and Solid.active(data(reopened)),"saved addition reopens with the solid renderer")
		print("SOLID_ADDITION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));history.clear_history();quit(0 if errors.is_empty() else 1);return
	var source:=fixture();var before:=source.to_definition().duplicate(true)
	check(source.validation_errors().is_empty(),"fixture validates")
	var old_mesh:=Solid.build(data(source))
	var changes:=Model.oriented_stroke_changes(source,source.voxels,Vector3i(8,8,15),Vector3i(0,0,1),Model.TOOL_REMOVE,1,5,8)
	var history:=UndoRedo.new();var actions:=Actions.new();actions.configure(history)
	check(actions.apply_stroke(source,changes),"side carve uses existing stroke")
	check(Solid.active(data(source)) and Solid.uses_volume(data(source)),"edited volume retains material renderer")
	var carved:=source.to_definition().duplicate(true)
	history.undo();check(source.to_definition()==before and not history.has_undo(),"one Undo restores hull and volume")
	history.redo();check(source.to_definition()==carved,"Redo restores cavity")
	var paint:=Model.oriented_stroke_changes(source,source.voxels,Vector3i(8,8,7),Vector3i(0,0,1),Model.TOOL_PAINT,2,3,1)
	check(actions.apply_stroke(source,paint),"paint cavity with existing soil material")
	var painted:=source.to_definition().duplicate(true)
	var meshes:=[Solid.build(data(source)),Solid.build_voxel_look(data(source)),Solid.living_mesh(data(source),1.0,PackedFloat32Array())]
	check(meshes[0].get_faces()==meshes[2].get_faces(),"detailed/low poly share physical positions")
	var from:=Vector3(8.5,8.5,25)/16.0;var to:=Vector3(8.5,8.5,0)/16.0
	check(hit(old_mesh,from,to).z>0.99,"old hull would falsely close the cavity")
	for look in meshes.size():
		var mesh:Mesh=meshes[look];var point:=hit(mesh,from,to)
		check(point.is_finite() and absf(point.z-0.5)<0.04,"side cavity remains open in look%d"%look)
		var arrays:=mesh.surface_get_arrays(0);var colours:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var soil_inside:=false
		for i in colours.size():
			if int(round(colours[i].a*255))==2 and vertices[i].z<0.55 and vertices[i].y<0.6:soil_inside=true;break
		check(soil_inside,"paint is visible inside look%d"%look)
	# Watertight shared boundary, including the cavity and painted material seams.
	var faces:PackedVector3Array=meshes[0].get_faces();var edges:Dictionary={}
	for i in range(0,faces.size(),3):
		for j in 3:
			var a:=Vector3i((faces[i+j]*100000).round());var b:=Vector3i((faces[i+(j+1)%3]*100000).round())
			var key:=[a,b] if a<b else [b,a]
			edges[key]=int(edges.get(key,0))+1
	for count in edges.values():
		if count!=2:check(false,"closed surface has exactly two faces per edge");break
	var job:=Fragment.start_grab(source,Vector3(8,8,15),5,Vector3(1,0,0),75)
	while not job.done:job.step(8192,4000)
	check(not job.result.has("error"),"Grab works after carve")
	if not job.result.has("error"):
		var draft:=source.duplicate_model()
		for key in job.result.properties:draft.set(key,job.result.properties[key])
		check(Solid.uses_volume(data(draft)),"later Grab cannot restore a convex shell")
	history.undo();check(source.to_definition()==carved,"paint Undo preserves cavity")
	history.redo();check(source.to_definition()==painted,"paint Redo exact")
	var path:="user://ember-tests/solid-volume.tres";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(ResourceSaver.save(source,path)==OK,"save carved painted volume")
	var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	var saved_expected:=painted.duplicate(true);saved_expected.erase("_resourcePath")
	check(saved_data(reopened)==saved_expected and Solid.uses_volume(data(reopened)),"fresh reopen preserves shape and paint")
	check(reopened.validation_errors().is_empty(),"carved Source validates")
	var draft:=reopened.duplicate_model();draft.voxels.fill(0)
	check(saved_data(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource)==saved_expected,"discard does not write draft")
	print("SOLID_VOLUME ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"triangles":faces.size()/3}))
	history.clear_history();quit(0 if errors.is_empty() else 1)

## A stepped, carved volume exposes the one-cell difference between its
## canonical surface and voxel display. Look changes must leave physics alone.
func physical_looks()->void:
	var source:=fixture();source.model_id="solid_physics_fixture"
	for y in range(10,16):
		for z in 16:
			for x in range(8,16):
				var index:=Model.index_of(Vector3i(x,y,z),Vector3i(16,16,16))
				source.voxels[index]=0;source.voxel_part_ids[index]=0
	var model:=data(source)
	var canonical:=Solid.build(model);Solid.apply_materials(canonical,model)
	var prop:=EmberVoxelProp.new();prop.authoring_source=source
	var visual:=MeshInstance3D.new();visual.name="Mesh";visual.mesh=canonical;prop.add_child(visual)
	var body:=StaticBody3D.new();body.name="Collision";prop.add_child(body)
	var collision:=CollisionShape3D.new();collision.name="Shape";collision.shape=canonical.create_trimesh_shape();body.add_child(collision)
	root.add_child(prop);current_scene=prop
	var first:Array=[]
	for look in [0,1,2,0]:
		prop.set_world_look(look);await physics_frame;await physics_frame
		check(collision.shape.get_faces()==canonical.get_faces(),"world look %d retains canonical collider"%look)
		var heights:Array=[]
		for x in [6.5,7.5,7.75,8.0,8.25,8.5,9.5]:
			var point:=Vector3(x,30,8)
			var sample:=prop.surface_floor_sample(point)
			var ray:=PhysicsRayQueryParameters3D.create(point,point-Vector3(0,40,0),1)
			var actual:=root.world_3d.direct_space_state.intersect_ray(ray)
			check(sample.get("solid",false) and not actual.is_empty(),"step edge supports query in look %d"%look)
			if sample.get("solid",false) and not actual.is_empty():
				check(sample.position.distance_to(actual.position)<0.001,"floor uses physical triangles in look %d"%look)
				heights.append(sample.position.y)
		if first.is_empty():first=heights.duplicate()
		else:check(heights==first,"look changes cannot move the physical step")
	print("SOLID_PHYSICAL_LOOKS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"heights":first}))
	prop.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
