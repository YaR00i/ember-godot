extends SceneTree
## Two overlapping volumes: cavity, material identity and shared union boundary.
const Merge=preload("res://addons/ember_import/ember_voxel_merge.gd")
const Shapes=preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Model=preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Edit=preload("res://addons/ember_import/ember_voxel_object_session.gd")
var errors:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("SOLID_MERGE_FAIL ",label)
func definition(source:EmberVoxelModelResource)->Dictionary:return source.to_definition().model
func model(source:EmberVoxelModelResource)->Dictionary:return EmberVoxelPrefab.model_of(source.to_definition())
func index(cell:Vector3i,size:Vector3i)->int:return Model.index_of(cell,size)
func fixture(id:String,carve:bool)->EmberVoxelModelResource:
	var source:EmberVoxelModelResource=Shapes.build("block",Vector3i(16,16,16),16,Color(0.5,0.5,0.5),id,id).source
	source.palette.append(Color(0.4,0.25,0.1));source.palette.append(Color(0.3,0.5,0.2))
	source.merge_parts=PackedStringArray([id]);source.voxel_part_ids.resize(source.voxels.size());source.voxel_part_ids.fill(1)
	for y in range(13,16):
		for z in 16:
			for x in 16:source.voxels[index(Vector3i(x,y,z),source.grid_size())]=3
	source.solid_surface={"version":1,"occupancy":Solid.occupancy_hash(source.voxels),
		"parts":[PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK])],
		"roles":PackedStringArray(["","stone","soil","grass"]),
		"material_ids":PackedStringArray(["","cartoon_stone" if carve else "cartoon_sand","soil_grain","cartoon_grass"])}
	if carve:
		for y in range(5,11):
			for x in range(5,11):
				for z in range(8,16):
					var i:=index(Vector3i(x,y,z),source.grid_size());source.voxels[i]=0;source.voxel_part_ids[i]=0
				source.voxels[index(Vector3i(x,y,7),source.grid_size())]=2
	return source
func run()->void:
	var a:=fixture("A",true);var b:=fixture("B",false)
	if DisplayServer.get_name()!="headless":
		check_presentation(a)
		if "--presentation-only" in OS.get_cmdline_user_args():
			print("SOLID_MERGE_PRESENTATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
			quit(0 if errors.is_empty() else 1);return
	var before_a:=definition(a).duplicate(true);var before_b:=definition(b).duplicate(true)
	var inputs:Array[Dictionary]=[{"source":a,"frame":Transform3D.IDENTITY},{"source":b,"frame":Transform3D(Basis.IDENTITY,Vector3(0.5,0,-0.5))}]
	var result:=Merge.plan(inputs)
	check(not result.has("error"),str(result.get("error","plan")))
	if result.has("error"):quit(1);return
	var source:EmberVoxelModelResource=result.source;var size:=source.grid_size()
	check(source.validation_errors().is_empty(),"union Source validates")
	check(definition(a)==before_a and definition(b)==before_b,"preview leaves inputs exact")
	check(Solid.active(model(source)) and Solid.uses_volume(model(source)),"union keeps non-convex material renderer")
	check(source.solid_surface.parts.size()==2 and source.solid_surface.topology=="volume","all part profiles retained")
	# Low Z is -8, so A is offset eight cells in result. Check every output cell
	# against input matter, rather than another meshing implementation.
	for z in size.z:
		for y in size.y:
			for x in size.x:
				var ca:=Vector3i(x,y,z-8);var cb:=Vector3i(x-8,y,z)
				var va:=a.voxels[index(ca,a.grid_size())] if Model.contains(ca,a.grid_size()) else 0
				var vb:=b.voxels[index(cb,b.grid_size())] if Model.contains(cb,b.grid_size()) else 0
				var i:=index(Vector3i(x,y,z),size);var have:=int(source.voxels[i])
				if (have!=0)!=(va!=0 or vb!=0):check(false,"union occupancy exact");quit(1);return
				if have>0:
					var owner:=a if va>0 else b;var slot:=va if va>0 else vb
					check(source.palette[have]==owner.palette[slot],"colour preserved")
					check(source.solid_surface.material_ids[have]==owner.solid_surface.material_ids[slot],"artwork identity and primary priority")
	check(source.voxels[index(Vector3i(8,8,20),size)]==0,"mouth remains empty where second volume has no matter")
	var inner_slot:=int(source.voxels[index(Vector3i(8,8,15),size)])
	check(source.solid_surface.material_ids[inner_slot]=="soil_grain","paint on back wall survives overlap")
	var triangles:Array=[]
	for mesh:ArrayMesh in [Solid.build(model(source)),Solid.build_voxel_look(model(source)),Solid.living_mesh(model(source),1.0,PackedFloat32Array())]:
		check(mesh.get_surface_count()>0,"look mesh exists")
		triangles.append(mesh.get_faces())
		var faces:=mesh.get_faces();var hit_z:=-INF
		for i in range(0,faces.size(),3):
			var hit:Variant=Geometry3D.segment_intersects_triangle(Vector3(8.5,8.5,40)/16.0,Vector3(8.5,8.5,-2)/16.0,faces[i],faces[i+1],faces[i+2])
			if hit!=null:hit_z=maxf(hit_z,hit.z)
		check(absf(hit_z-1.0)<0.04,"carved wall remains open in each look")
	check(triangles[0]==triangles[2],"detailed and low poly share physical surface")
	var edges:Dictionary={};var faces:PackedVector3Array=triangles[0]
	for i in range(0,faces.size(),3):
		for j in 3:
			var p:=Vector3i((faces[i+j]*100000).round());var q:=Vector3i((faces[i+(j+1)%3]*100000).round())
			var key:=[p,q] if p<q else [q,p];edges[key]=int(edges.get(key,0))+1
	for count in edges.values():
		if count!=2:check(false,"union closed across former part seam");break
	var split:=Merge.separate(source)
	check(not split.has("error"),"separate current union")
	if not split.has("error"):
		var occupied:=0
		for item in split.pieces:
			check(item.source.validation_errors().is_empty() and Solid.uses_volume(model(item.source)),"separated volume validates")
			occupied+=item.source.voxels.size()-item.source.voxels.count(0)
		check(occupied==source.voxels.size()-source.voxels.count(0),"separation cannot resurrect intersected/removed matter")
	var path:="user://ember-tests/solid-merge.tres";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(ResourceSaver.save(source,path)==OK,"save union")
	var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	check(definition(reopened)==definition(source) and Solid.uses_volume(model(reopened)),"reopen all data and topology")
	var invalid:=source.solid_surface.duplicate(true);invalid.topology="unknown"
	check(not Solid.validation_errors(invalid,source.merge_parts.size(),source.palette.size()).is_empty(),"unknown topology rejected")
	# Quarter rotations, including baked primary frame, transform authored normals.
	inputs[0].frame=Transform3D(Basis(Vector3.UP,PI/2),Vector3.ZERO)
	inputs[1].frame=inputs[0].frame*Transform3D(Basis(Vector3.FORWARD,PI/2),Vector3(0.5,0,-0.5))
	var rotated:=Merge.plan(inputs,false,true)
	check(not rotated.has("error") and rotated.source.validation_errors().is_empty(),"rotated guides validate")
	if not rotated.has("error"):
		check(rotated.source.solid_surface.parts[1][0].is_equal_approx((inputs[1].frame as Transform3D).basis*Vector3.RIGHT),"normal follows output frame")
	var mixed:Array[Dictionary]=[{"source":a,"frame":Transform3D.IDENTITY},{"source":Shapes.build("block",Vector3i(16,16,16),16,Color.WHITE,"plain","plain").source,"frame":Transform3D.IDENTITY}]
	check(Merge.plan(mixed).has("error"),"unsupported mixed renderer rejected without loss")
	print("SOLID_MERGE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"overlap":result.overlap.size(),"triangles":faces.size()/3}))
	quit(0 if errors.is_empty() else 1)

func check_presentation(source:EmberVoxelModelResource)->void:
	var scene:=Node3D.new();root.add_child(scene)
	var prop:=EmberVoxelPrefab.prepare_resource(source).instantiate() as EmberVoxelProp
	prop.authoring_source=source
	scene.add_child(prop);prop.owner=scene;prop.set_world_look(1)
	var edit:=Edit.new();check(edit.open_created(prop,source,scene,null),edit.error)
	check(edit.can_replace_geometry(),"generated look material does not block merge")
	var visual:=prop.get_node("Mesh") as MeshInstance3D;var derived:=visual.material_override
	var authored:=StandardMaterial3D.new();visual.material_override=authored
	check(not edit.can_replace_geometry(),"unknown authored material remains protected")
	visual.material_override=derived
	prop._notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	check(visual.material_override==null,"scene save does not embed generated presentation override")
	prop._notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	scene.free()
