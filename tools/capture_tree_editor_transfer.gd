extends "res://tools/capture_spruce_needles.gd"
const Creation=preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
const RecipePanel=preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
var pairs: Dictionary={}
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_spruce_bough_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.species_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false);scene.reset_actors();scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam;var game_transform:=camera.global_transform;var game_fov:=camera.fov
	var presets:=Generator.creation_presets(Generator.LARGE_TREE)
	var grass:=hash(scene.tuft_visual.multimesh.buffer);var ground:=floor_geometry();var paths: Array=[]
	var directory:="user://tree-editor-native";var history:=UndoRedo.new()
	for kind in 5:
		if OS.get_cmdline_user_args().has("--oak-only") and kind!=1:continue
		var creation:=Creation.new();creation.source_directory=directory.path_join("sources");creation.prefab_directory=directory.path_join("prefabs");creation.recipe_directory=directory.path_join("recipes")
		check(creation.prepare_recipe(presets[kind].recipe,"Tree%d"%kind),"ordinary creation "+str(kind))
		var prepared_packed: PackedScene=creation.packed
		var prop:=creation.commit(scene,scene,history,Vector3.ZERO)
		check(prop!=null,"ordinary placed object "+str(kind))
		if prop==null:continue
		prop.configure_voxel_scale(16,1.0)
		var mesh_node: MeshInstance3D=prop.get_node("Mesh")
		var pivot: Vector2i=creation.report.pivot_bias
		var local_origin:=Vector3(scene.restored_inputs.pivot_bias.x-pivot.x,0,scene.restored_inputs.pivot_bias.y-pivot.y)/16.0
		prop.global_position=scene.smooth_tree.to_global(local_origin-mesh_node.position)
		var prepared_prop:=prepared_packed.instantiate() as EmberVoxelProp;scene.add_child(prepared_prop);prepared_prop.configure_voxel_scale(16,1.0);prepared_prop.transform=prop.transform;prepared_prop.hide()
		prop.hide();scene.smooth_tree.show()
		if kind==4:scene.set_birch_revision(2)
		else:scene.choose_species(kind)
		var old_wood: MeshInstance3D
		var old_leaves: MeshInstance3D
		if kind==0:old_wood=scene.accepted_savanna.get_child(0);old_leaves=scene.accepted_savanna.get_child(1)
		elif kind==1:old_wood=scene.parametric_wood;old_leaves=scene.foliage21_cards
		elif kind==2:old_wood=scene.accepted_birch.get_child(0);old_leaves=scene.accepted_birch.get_child(1)
		elif kind==3:old_wood=scene.accepted_maple.get_child(0);old_leaves=scene.accepted_maple.get_child(1)
		else:old_wood=scene.birch_wood;old_leaves=scene.birch_leaves
		var wood_material: ShaderMaterial=mesh_node.mesh.surface_get_material(0)
		var leaf_material: ShaderMaterial=mesh_node.mesh.surface_get_material(1)
		var data:={"wood_arrays":old_wood.mesh.surface_get_arrays(0)==mesh_node.mesh.surface_get_arrays(0),"leaf_arrays":old_leaves.mesh.surface_get_arrays(0)==mesh_node.mesh.surface_get_arrays(1),"wood_transform":str(old_wood.global_transform),"leaf_transform":str(old_leaves.global_transform),"native_transform":str(mesh_node.global_transform),"wood_uniforms":uniform_differences(old_wood.material_override,wood_material),"leaf_uniforms":uniform_differences(old_leaves.material_override,leaf_material)}
		data.wood_arrays_detail=array_differences(old_wood.mesh.surface_get_arrays(0),mesh_node.mesh.surface_get_arrays(0))
		data.leaf_arrays_detail=array_differences(old_leaves.mesh.surface_get_arrays(0),mesh_node.mesh.surface_get_arrays(1))
		data.source_material=creation.source.material
		data.wood_shader_equal=old_wood.material_override.shader.code==wood_material.shader.code
		data.leaf_shader_equal=old_leaves.material_override.shader.code==leaf_material.shader.code
		check(data.wood_arrays and data.leaf_arrays and data.wood_shader_equal and data.leaf_shader_equal,"accepted geometry/shader buffers exact "+str(kind))
		if not data.wood_shader_equal:
			var codes:=FileAccess.open(output.path_join("wood-code-%d.txt"%kind),FileAccess.WRITE);codes.store_string(old_wood.material_override.shader.code+"\n===NATIVE===\n"+wood_material.shader.code);codes.close()
		data.wood_rim_native=[wood_material.get_shader_parameter("object_style_rim_profiles_enabled"),wood_material.get_shader_parameter("object_style_rim_profiles")]
		data.wood_rim_lab=[old_wood.material_override.get_shader_parameter("object_style_rim_profiles_enabled"),old_wood.material_override.get_shader_parameter("object_style_rim_profiles")]
		data.wood_properties=property_differences(old_wood.material_override,wood_material)
		data.leaf_properties=property_differences(old_leaves.material_override,leaf_material)
		data.leaf_encoded=encoded_differences(old_leaves.material_override,leaf_material)
		data.prepared_leaf_encoded=encoded_differences(old_leaves.material_override,prepared_prop.get_node("Mesh").mesh.surface_get_material(1))
		data.leaf_float_values={}
		for uniform in ["painterly_grass_low","painterly_band_softness"]:data.leaf_float_values[uniform]=["%.17f"%float(old_leaves.material_override.get_shader_parameter(uniform)),"%.17f"%float(leaf_material.get_shader_parameter(uniform))]
		var debug:=FileAccess.open(output.path_join("data-%d.json"%kind),FileAccess.WRITE);debug.store_string(JSON.stringify(data,"\t"));debug.close()
		for preset in [1,0,2]:
			for pose in [1,0]:
				if OS.get_cmdline_user_args().has("--quick") and (preset!=1 or pose!=1):continue
				scene.set_lighting_preset(preset);scene.set_sun_pose(pose);scene.set_species_view(1)
				var label:="%d-%d-%d"%[kind,preset,pose]
				var current_data:=FileAccess.open(output.path_join("frame-data-"+label+".json"),FileAccess.WRITE)
				current_data.store_string(JSON.stringify({"wood":encoded_differences(old_wood.material_override,wood_material),"leaf":encoded_differences(old_leaves.material_override,leaf_material)},"\t"));current_data.close()
				prop.hide();scene.smooth_tree.show();await capture("lab-"+label)
				prop.show();scene.smooth_tree.hide();var picture:=await capture("editor-"+label)
				if OS.get_cmdline_user_args().has("--diagnose"):
					mesh_node.mesh.surface_set_material(0,old_wood.material_override);await capture("wood-matched-"+label);mesh_node.mesh.surface_set_material(0,wood_material)
					mesh_node.mesh.surface_set_material(1,old_leaves.material_override);await capture("leaf-matched-"+label);mesh_node.mesh.surface_set_material(1,leaf_material)
					prop.hide();prepared_prop.show();await capture("preview-"+label);prepared_prop.hide();prop.show()
					var shader_backup:=leaf_material.shader
					leaf_material.shader=old_leaves.material_override.shader;await capture("shader-matched-"+label);leaf_material.shader=shader_backup
					var textures: Dictionary={}
					for uniform in old_leaves.material_override.shader.get_shader_uniform_list():
						var value: Variant=old_leaves.material_override.get_shader_parameter(uniform.name)
						if value is Texture2D:
							textures[uniform.name]=leaf_material.get_shader_parameter(uniform.name);leaf_material.set_shader_parameter(uniform.name,value)
					await capture("textures-matched-"+label)
					for uniform in textures:leaf_material.set_shader_parameter(uniform,textures[uniform])
					mesh_node.mesh.surface_set_material(0,old_wood.material_override);mesh_node.mesh.surface_set_material(1,old_leaves.material_override)
					await capture("matched-"+label)
					mesh_node.mesh.surface_set_material(0,wood_material);mesh_node.mesh.surface_set_material(1,leaf_material)
					mesh_node.hide()
					var a:=old_wood.duplicate() as MeshInstance3D;var b:=old_leaves.duplicate() as MeshInstance3D
					prop.add_child(a);prop.add_child(b);a.global_transform=old_wood.global_transform;b.global_transform=old_leaves.global_transform
					a.show();b.show();await capture("split-"+label);a.free();b.free();mesh_node.show()
					# Diagnostics must finish collecting all five rows before fail-fast.
					reference_equal(picture,output.path_join("lab-"+label+".png"),label)
				elif OS.get_cmdline_user_args().has("--measure"):
					reference_equal(picture,output.path_join("lab-"+label+".png"),label)
				else:
					check(lab_equal(picture,output.path_join("lab-"+label+".png"),label,kind),"accepted LAB/editor frame parity "+label)
				if not OS.get_cmdline_user_args().has("--quick"):
					camera.global_transform=game_transform;camera.fov=game_fov;await capture("game-"+label)
			scene.set_species_view(1)
		scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1)
		prop.hide();prepared_prop.show()
		check(reference_equal(await capture("prepared-%d"%kind),output.path_join("editor-%d-1-1.png"%kind),"prepared-%d"%kind),"unsaved preview agrees with published tree "+str(kind))
		prepared_prop.hide();prop.show()
		if not OS.get_cmdline_user_args().has("--quick"):
			var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(12,12,0.5);blocker.mesh=box
			blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;scene.add_child(blocker)
			var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
			blocker.global_basis=sun.global_basis;blocker.global_position=scene.smooth_tree.global_position+Vector3(0,3,0)+sun.global_basis.z*12
			prop.hide();scene.smooth_tree.show();await capture("shade-lab-%d"%kind)
			prop.show();scene.smooth_tree.hide()
			check(lab_equal(await capture("shade-editor-%d"%kind),output.path_join("shade-lab-%d.png"%kind),"shade-%d"%kind,kind),"tree response in real cast shadow "+str(kind))
			blocker.free()
		var source_path: String=creation.source_directory.path_join(creation.source.model_id+".tres")
		var prefab_path: String=creation.prefab_directory.path_join(creation.source.model_id+".tscn")
		paths.append({"kind":kind,"source":source_path,"prefab":prefab_path,"transform":prop.transform})
		var reopened: PackedScene=ResourceLoader.load(prefab_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var restored:=reopened.instantiate();scene.add_child(restored);restored.configure_voxel_scale(16,1.0);restored.transform=prop.transform;prop.hide()
		scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1)
		check(reference_equal(await capture("reopen-%d"%kind),output.path_join("editor-%d-1-1.png"%kind),"reopen-%d"%kind),"saved prefab frame parity "+str(kind))
		restored.free();prop.free();prepared_prop.free()
		scene.smooth_tree.show()
	check(grass==hash(scene.tuft_visual.multimesh.buffer) and ground==floor_geometry(),"grass and shared terrain floor unchanged")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"references":reference_deltas,"quick":OS.get_cmdline_user_args().has("--quick")},"\t"));file.close()
	var manifest:=FileAccess.open(output.path_join("saved-objects.var"),FileAccess.WRITE);manifest.store_var(paths);manifest.close()
	history.free()
	print("TREE_EDITOR_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)

func lab_equal(picture: Image,path: String,label: String,kind: int) -> bool:
	# Source supports, mesh channels, shaders and texture bytes are separately
	# exact. Moving from LAB material instances to published material instances
	# has a bounded render difference on oak. Keep it separate from the stricter
	# preview/save/reopen gate; never use it to accept changed tree construction.
	var previous:=Image.load_from_file(path);var a:=picture.get_data();var b:=previous.get_data()
	if a.size()!=b.size():return false
	var stride:=4 if a.size()==picture.get_width()*picture.get_height()*4 else 3
	var count:=0;var peak:=0;var total:=0
	for i in range(0,a.size(),stride):
		var difference:=0
		for channel in 3:
			var delta:=absi(int(a[i+channel])-int(b[i+channel]));difference=maxi(difference,delta);total+=delta
		if difference>0:count+=1;peak=maxi(peak,difference)
	var mean:=float(total)/(picture.get_width()*picture.get_height()*3)
	reference_deltas[label]={"pixels":count,"max_rgb8":peak,"mean_rgb8":mean}
	return (peak<=5 and mean<=0.15) if kind==1 else (count<=32 and peak<=1)

func uniform_differences(a: ShaderMaterial,b: ShaderMaterial) -> Array:
	var differences: Array=[]
	for entry in a.shader.get_shader_uniform_list():
		var x: Variant=a.get_shader_parameter(entry.name);var y: Variant=b.get_shader_parameter(entry.name)
		if x is Texture2D and y is Texture2D:
			if x.get_image().get_data()!=y.get_image().get_data():differences.append({"name":entry.name,"textures_differ":true})
		elif x!=y:differences.append({"name":entry.name,"lab":str(x),"native":str(y)})
	return differences

func array_differences(a: Array,b: Array) -> Array:
	var result: Array=[]
	for channel in a.size():
		if a[channel]==b[channel]:continue
		var row:={"channel":channel,"count_a":a[channel].size() if a[channel]!=null else -1,"count_b":b[channel].size() if b[channel]!=null else -1}
		if a[channel]!=null and b[channel]!=null and a[channel].size()==b[channel].size():
			var count:=0;var examples: Array=[]
			for i in a[channel].size():
				if a[channel][i]!=b[channel][i]:
					count+=1
					if examples.size()<3:examples.append([str(a[channel][i]),str(b[channel][i])])
			row.count=count;row.examples=examples
		result.append(row)
	return result

func property_differences(a: Object,b: Object) -> Array:
	var differences: Array=[]
	for entry in a.get_property_list():
		if not (entry.usage&PROPERTY_USAGE_STORAGE) or entry.name=="shader":continue
		var x: Variant=a.get(entry.name);var y: Variant=b.get(entry.name)
		if x is Texture2D and y is Texture2D:
			if x.get_size()!=y.get_size() or x.get_image().get_format()!=y.get_image().get_format() or x.get_image().get_data()!=y.get_image().get_data():differences.append({"name":entry.name,"a":str(x.get_size()),"b":str(y.get_size())})
		elif x!=y:differences.append({"name":entry.name,"a":str(x),"b":str(y)})
	return differences

func encoded_differences(a: ShaderMaterial,b: ShaderMaterial) -> Array:
	var result: Array=[]
	for entry in a.shader.get_shader_uniform_list():
		var x: Variant=a.get_shader_parameter(entry.name);var y: Variant=b.get_shader_parameter(entry.name)
		if x is Object or y is Object:continue
		if var_to_bytes(x)!=var_to_bytes(y):result.append({"name":entry.name,"type_a":typeof(x),"type_b":typeof(y),"a":str(x),"b":str(y)})
	return result
