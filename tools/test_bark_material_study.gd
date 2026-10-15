extends SceneTree
const Bark=preload("res://addons/ember_import/ember_voxel_bark_pattern.gd")
const Fixture=preload("res://scripts/prototypes/ember_bark_material_fixture.gd")
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func _initialize() -> void:
	var inputs:=Fixture.build_inputs()
	check(inputs.support_count>10 and inputs.mark_count>0,"existing tree recipe supplies real branch frames and marks")
	check(inputs.source.voxels==inputs.private_source.voxels and inputs.source.palette==inputs.private_source.palette,"private role binding preserves source occupancy and manual colours")
	check(not inputs.source.material.has("object_surface"),"legacy authoring material is untouched")
	var prop: Node=EmberVoxelPrefab.prepare_resource(inputs.private_source).instantiate()
	var arrays: Array=prop.get_node("Mesh").mesh.surface_get_arrays(0)
	var custom: PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM0]
	var roles: Dictionary={}
	for i in range(0,custom.size(),4):roles[custom[i]]=int(roles.get(custom[i],0))+1
	print("BARK_MESH roles=",roles," bounds=",prop.get_node("Mesh").mesh.get_aabb()," colours=",(arrays[Mesh.ARRAY_COLOR] as PackedColorArray).slice(0,4))
	check(roles.get(2.0,0)>0 and roles.get(0.0,0)>0,"real tree carries bark attributes and unchanged legacy leaves")
	prop.free()
	var image:=Fixture.layer(inputs,inputs.field_grid.z/2)
	check(image.get_data()==Fixture.layer(inputs,inputs.field_grid.z/2).get_data(),"deterministic derived colour and height")
	var minimum:=1.0;var maximum:=0.0
	for y in image.get_height():
		for x in image.get_width():
			var h:=image.get_pixel(x,y).a;minimum=minf(minimum,h);maximum=maxf(maximum,h)
	check(minimum<0.2 and maximum<=0.51,"bounded inward-only shallow recesses, independent of colour brightness")
	var lines: Array=[{"start":Vector3.ZERO,"finish":Vector3(0,32,0),"r0":4.0,"r1":4.0,"t0":0.0,"t1":1.0,"branch":true}]
	var support:=Bark.support_frames(lines)
	var turned: Array=[lines[0].duplicate(true)];turned[0].finish=Vector3(0,0,32)
	var turned_support:=Bark.support_frames(turned)
	for y in 32:
		var p:=Vector3(3,y,2);var c:=Bark.support_coordinates(p,support)
		var other:=Bark.support_coordinates(Vector3(p.z,p.x,p.y),turned_support)
		check(is_equal_approx(c[0],other[0]) and is_equal_approx(c[1],other[1]) and is_equal_approx(c[2],other[2]),"surface coordinates rotate with the branch, not world Y")
	var mesh:=Fixture.panel_mesh(inputs)
	check(mesh.get_surface_count()==1 and not mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0].is_empty(),"flat probe uses existing primitive and explicit bark role")
	# An optional external snapshot allows QA to prove the refactor preserves
	# actual previous marks, rather than comparing the new wrapper to itself.
	if not OS.get_cmdline_user_args().is_empty():
		var previous:=GDScript.new()
		previous.source_code=FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0])
		check(previous.reload()==OK,"previous committed bark algorithm compiles")
		var wood: Dictionary={}
		for y in 32:
			for z in range(-4,5):
				for x in range(-4,5):
					if x*x+z*z<=16:wood[Vector3i(x,y,z)]=true
		for version in [1,2]:
			for direction in 3:
				for seed in [13,391]:
					var settings: Dictionary=inputs.settings.duplicate()
					settings.bark_pattern_version=version;settings.bark_pattern_direction=direction
					check(Bark.marks(wood,lines,seed,settings)==previous.marks(wood,lines,seed,settings),"exact previous marks v%d direction%d seed%d"%[version,direction,seed])
		var actual_wood: Dictionary={}
		for y in inputs.grid.y:
			for z in inputs.grid.z:
				for x in inputs.grid.x:
					var index: int=VoxMesher.cell_index(x,y,z,inputs.grid.x,inputs.grid.z)
					if inputs.source.voxels[index] in [1,2,3]:actual_wood[Vector3i(x,y,z)-Vector3i(inputs.offset)]=true
		var actual_lines: Array=inputs.support.frames
		# Recover the original descriptors from the same unmodified private recipe.
		var built:=Fixture.Generator.build(inputs.recipe,inputs.source.palette[2],inputs.source.material,"Compatibility")
		actual_lines=built.bark_support_lines
		for version in [1,2]:
			for direction in 3:
				var settings: Dictionary=inputs.settings.duplicate()
				settings.bark_pattern_version=version;settings.bark_pattern_direction=direction
				check(Bark.marks(actual_wood,actual_lines,13,settings)==previous.marks(actual_wood,actual_lines,13,settings),"exact actual curved tree marks v%d direction%d"%[version,direction])
	print("BARK_MATERIAL_TEST ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
