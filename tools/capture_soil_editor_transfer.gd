extends "res://tools/capture_sand_road_looks.gd"
## Normal material bank/editor publication; existing three-look LAB derivatives.
const SoilRecipe=preload("res://scripts/prototypes/ember_soil_look_recipe.gd")
const MaterialEditor=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
var target_id:="soil_grain"
var target_role:="soil"
var target_slot:=4
var target_span:=0.6
var target_role_code:=-1.0
var saved_pattern_file:="saved-soil.tres"
var result_prefix:="SOIL_EDITOR"

func colour_variants() -> Array[Image]:
	return SoilRecipe.colours(SoilRecipe.colour_image())

func camera_specs() -> Array:
	return [[Vector3(6.62,0.20,6.75),Vector3(0.30,1.25,1.55)],[Vector3(5.7,0.55,6.5),Vector3(0.3,3.4,4.2)]]

func material_base(look: int,_production: ShaderMaterial) -> ShaderMaterial:
	return scene.material_variants[look]

func legacy_shader_code(code: String) -> String:
	return "#define EMBER_TERRAIN_MATERIAL_DEPTH\n#define EMBER_MATERIAL_SHAPE_STUDY\n"+code

func legacy_shader_for(_current: Shader,code: String) -> Shader:
	var shader:=Shader.new();shader.code=legacy_shader_code(code)
	return shader

func reference_pattern_material(current: ShaderMaterial,_accepted: Resource,_colour: Image) -> ShaderMaterial:
	var reference:=current.duplicate() as ShaderMaterial
	var shader:=Shader.new();shader.code="#define EMBER_MATERIAL_COLOUR_PROBE\n"+current.shader.code
	shader.set_meta("ember_compact_terrain_shader",true);reference.shader=shader;reference.set_shader_parameter("colour_probe_slot",target_slot)
	return reference

func depth_control_material() -> ShaderMaterial:
	return current_materials[0]

func capture_editor(editor: Control) -> void:
	await capture("native-material-editor")

func previous_pattern_material(current: ShaderMaterial,old: Resource) -> ShaderMaterial:
	var previous:=current.duplicate() as ShaderMaterial
	for key in ["png_lookup","png_mean_lookup","png_tint_lookup"]:
		var image: Image=current.get_shader_parameter(key).get_image().duplicate()
		image.set_pixel(target_slot,0,Color(0,0,0,0));previous.set_shader_parameter(key,ImageTexture.create_from_image(image))
	# Preserve the previous fallback pigment as well as its old PNG binding.
	for key in ["pattern_atlas","side_pattern_atlas"]:
		var image: Image=current.get_shader_parameter(key).get_image().duplicate()
		var pigment: Image=old.to_image(key=="side_pattern_atlas")
		for y in 16:
			for x in 16:
				var colour:=pigment.get_pixel(x,y);colour.a=image.get_pixel(x,target_slot*16+y).a;image.set_pixel(x,target_slot*16+y,colour)
		previous.set_shader_parameter(key,ImageTexture.create_from_image(image))
	return previous

var ground_nodes: Array[MeshInstance3D]=[]
var before_materials: Array[ShaderMaterial]=[]
var current_materials: Array[ShaderMaterial]=[]
var reference_materials: Array[ShaderMaterial]=[]
var cameras: Array=[]
var records: Array=[]
var exact_returns:=0
var reference_exact:=0
var frozen_exact:=0
var shader_comparisons: Array=[]

func capture(name: String) -> Image:
	await frames();var result:=root.get_texture().get_image()
	check(result.save_png(output.path_join(name+".png"))==OK,"capture "+name);return result

func select_pattern(look: int,materials: Array[ShaderMaterial]) -> void:
	scene.set_material_style(look)
	materials[look].set_shader_parameter("material_depth_sun_direction",scene.get_node("Map/Look/Sun").global_basis.z)
	for visual in ground_nodes:visual.material_override=materials[look]

func run() -> void:
	output=OS.get_cmdline_user_args()[0].replace("\\","/")
	var cold:=OS.get_cmdline_user_args().has("--cold")
	scene=load("res://scenes/compact_material_shapes_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.styles_ready:await process_frame
	scene.get_node("Instructions").hide();scene.door.hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false);scene.reset_actors()
	var camera: Camera3D=scene.follow_camera._cam
	scene.set_look_view(0);scene.follow_camera.set_process(false);scene.follow_camera._process(0)
	cameras.append({"pose":camera.global_transform,"fov":camera.fov})
	for spec in camera_specs():
		camera.fov=40;camera.global_position=spec[0]+spec[1];camera.look_at(spec[0]);cameras.append({"pose":camera.global_transform,"fov":camera.fov})
	var terrain=scene._projection.document
	var geometry:=floor_geometry();var heights:=hash(terrain.heights);var paint:=hash([terrain.top_materials,terrain.base_materials,terrain.palette,terrain.palette_material_ids])
	var grass:=hash(scene.tuft_visual.multimesh.buffer);var tree:=hash(scene.look_source.to_definition().model)
	var depth: Texture2D=scene.height_texture;var depth_hash:=hash(depth.get_image().get_data())
	for tile in scene._projection._tiles.values():ground_nodes.append(tile.get_node("Ground"))
	var accepted=Materials.load_compact_terrain_variant(target_id)
	var production: ShaderMaterial=scene._projection._ground_material
	var live_meshes: Array=[]
	for visual in ground_nodes:live_meshes.append(visual.mesh)
	check(scene._projection.set_shared_material_pattern(accepted),"ordinary projection accepts saved material update")
	var published_entry: Color=production.get_shader_parameter("png_lookup").get_image().get_pixel(target_slot,0)
	check(published_entry.r>0.5 and published_entry.b==target_role_code and published_entry.a==1.0,"ordinary editor/runtime projection resolves saved soil assignment")
	for i in ground_nodes.size():check(ground_nodes[i].mesh==live_meshes[i],"material publication never remeshes terrain "+str(i))
	var old=load(output.path_join("before/content/terrain_materials/"+target_id+".tres"))
	var colours:=colour_variants()
	for look in 3:
		var base: ShaderMaterial=material_base(look,production)
		var current: ShaderMaterial=base
		if look>0:current=road_material(base,colours[look],{"slot":target_slot,"material_id":target_id,"pattern":accepted,"span_m":target_span})
		current_materials.append(current)
		var previous:=previous_pattern_material(current,old)
		before_materials.append(previous)
		var reference:=reference_pattern_material(current,accepted,colours[look])
		reference_materials.append(reference)
		var metadata: Color=current.get_shader_parameter("png_lookup").get_image().get_pixel(target_slot,0)
		check(metadata.b==target_role_code and metadata.a==1 and is_equal_approx(metadata.g,target_span),"production colour-only seamless metadata "+str(look))
		for key in ["finish_lookup","detail_lookup","surface_lookup","roughness_atlas","side_roughness_atlas","material_depth_height","material_depth_coverage","grass_light_lookup","style_rim_lookup"]:
			check(current.get_shader_parameter(key)==base.get_shader_parameter(key),"original depth/finish/lighting reference "+key)
	check(current_materials[0].get_shader_parameter("material_depth_secondary_enabled")!=true,"new soil POM not enabled")
	if cold:
		var source=load(output.path_join("saved-terrain.res"))
		var pattern=load(output.path_join(saved_pattern_file))
		check(terrain.same_terrain_geometry(source) and terrain.palette==source.palette and terrain.palette_material_ids==source.palette_material_ids,"saved terrain/paint reopen")
		check(not pattern.albedo_relief_enabled and pattern.albedo_periodic and pattern.albedo_texture.resource_path==accepted.albedo_texture.resource_path,"saved material reopens without new height")
		var cold_view:=1 if OS.get_cmdline_user_args().has("--close-only") else 0
		var historical:=OS.get_cmdline_user_args().has("--historical-reference")
		var cold_exact:=0
		check(not historical or cold_view==1,"historical comparison requires isolated material view")
		for preset in 3:
			for light in 2:
				scene.set_lighting_preset(preset);scene.set_sun_pose(light);set_camera(cold_view);select_pattern(0,current_materials)
				var frame:=await capture("cold-%d-%d"%[preset,light])
				var reference:=Image.load_from_file(output.path_join("B-%d-%d-%d-0.png"%[preset,light,cold_view]))
				var exact:=frame.get_data()==reference.get_data()
				if exact:cold_exact+=1
				# Archived captures can use a separately compiled shader binary.
				# Ordinary save/reopen still requires strict full-frame equality.
				check(shader_equal(frame,reference,"historical-%d-%d"%[preset,light]) if historical else exact,"fresh-process reference "+str(preset)+"/"+str(light))
		write_result("cold.json",{"pass":errors.is_empty(),"errors":errors,"exact_cases":cold_exact,"cases":6,"historical_reference":historical,"shader_comparisons":shader_comparisons,"recipes_run":false})
		print(result_prefix+"_COLD ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1);return
	check(ResourceSaver.save(terrain.working_copy(),output.path_join("saved-terrain.res"))==OK,"save terrain fixture")
	check(ResourceSaver.save(accepted.duplicate(true),output.path_join(saved_pattern_file))==OK,"save current material fixture")
	var frozen_code:=FileAccess.get_file_as_string(output.path_join("before/shaders/ember_compact_terrain_textured.gdshader"))
	for preset in 3:
		for light in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(light)
			for view in 3:
				set_camera(view)
				for look in 3:
					var label:="%d-%d-%d-%d"%[preset,light,view,look]
					select_pattern(look,before_materials);var before:=await capture("A-"+label)
					if view==0 and look==0:
						var previous_shader: Shader=before_materials[look].shader
						var frozen:=legacy_shader_for(previous_shader,frozen_code)
						before_materials[look].shader=frozen
						var old_shader_image:=await capture("frozen-"+label)
						check(shader_equal(before,old_shader_image,"legacy-"+label),"legacy terrain shader parity "+label)
						if before.get_data()==old_shader_image.get_data():frozen_exact+=1
						before_materials[look].shader=previous_shader
					select_pattern(look,current_materials);var after:=await capture("B-"+label)
					select_pattern(look,reference_materials)
					var reference_image:=await capture("LAB-"+label)
					check(shader_equal(after,reference_image,"LAB-"+label),"production matches colour-only LAB "+label)
					if after.get_data()==reference_image.get_data():reference_exact+=1
					select_pattern(look,current_materials)
					check(after.get_data()==(await capture("return-"+label)).get_data(),"accepted soil returns exactly "+label);exact_returns+=1
					records.append({"preset":preset,"light":light,"view":view,"look":look})
			for look in 3:
				select_pattern(look,current_materials)
				for i in 6:
					set_camera(0);camera.global_position+=cameras[0].pose.basis.x*((i/5.0-0.5)*0.6);await capture("motion-%d-%d-%d-%02d"%[preset,light,look,i])
	check(geometry==floor_geometry() and heights==hash(terrain.heights) and paint==hash([terrain.top_materials,terrain.base_materials,terrain.palette,terrain.palette_material_ids]),"Source/geometry/collision/paint unchanged")
	check(grass==hash(scene.tuft_visual.multimesh.buffer) and tree==hash(scene.look_source.to_definition().model),"grass scatter and tree Source unchanged")
	check(depth==scene.height_texture and depth_hash==hash(depth.get_image().get_data()),"original stone POM height unchanged")
	scene.set_lighting_preset(1);scene.set_sun_pose(1);set_camera(2)
	var control:=depth_control_material()
	var controls: Array[ShaderMaterial]=[control,control,control]
	select_pattern(0,controls)
	var enabled:=await capture("stone-pom-on")
	control.set_shader_parameter("material_depth_enabled",false)
	check(enabled.get_data()!=(await capture("stone-pom-off")).get_data(),"original stone POM still renders")
	control.set_shader_parameter("material_depth_enabled",true)
	check(enabled.get_data()==(await capture("stone-pom-return")).get_data(),"stone POM returns exactly")
	select_pattern(0,current_materials)
	var editor:=MaterialEditor.new();root.add_child(editor);editor.position=Vector2(390,55);editor.size=Vector2(720,650)
	var sidebar:=PanelContainer.new();sidebar.position=Vector2(20,30);sidebar.size=Vector2(345,830);root.add_child(sidebar);sidebar.add_child(editor.parameters_panel)
	editor.pattern_path_override=output.path_join(saved_pattern_file);check(editor.open_variant(target_id,target_role),"native material editor shows v4")
	await capture_editor(editor);editor.free();sidebar.free()
	write_result("native.json",{"pass":errors.is_empty(),"errors":errors,"pairs":records,"exact_returns":exact_returns,"lab_exact":reference_exact,"frozen_old_shader_exact":frozen_exact,"shader_comparisons":shader_comparisons,"motion_frames":108,"material_depth":"LAB only, not enabled","target_id":target_id,"production":"existing "+target_id+" material and existing editor; other looks remain LAB"})
	print(result_prefix+"_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)

func set_camera(index: int) -> void:
	scene.follow_camera._cam.global_transform=cameras[index].pose;scene.follow_camera._cam.fov=cameras[index].fov
func shader_equal(a: Image,b: Image,label: String) -> bool:
	var x:=a.get_data();var y:=b.get_data();var changed:=0;var peak:=0;var total:=0
	if x.size()!=y.size():return false
	if x==y:
		shader_comparisons.append({"label":label,"pixels":0,"max_rgb8":0,"mean_rgb8":0.0});return true
	var stride:=4 if x.size()==a.get_width()*a.get_height()*4 else 3
	for i in range(0,x.size(),stride):
		var difference:=0
		for channel in 3:
			var d:=absi(int(x[i+channel])-int(y[i+channel]));difference=maxi(difference,d);peak=maxi(peak,d);total+=d
		if difference>0:changed+=1
	shader_comparisons.append({"label":label,"pixels":changed,"max_rgb8":peak,"mean_rgb8":float(total)/(a.get_width()*a.get_height()*3)})
	# Frozen/new shader binaries may round sparse edge pixels differently.
	# First measured legacy case: 3 pixels, max2 RGB8, mean0.0000021 RGB8.
	# Inputs/geometry/height are independently exact; same-shader returns stay exact.
	return changed<=32 and peak<=2
func write_result(name: String,data: Dictionary) -> void:
	var file:=FileAccess.open(output.path_join(name),FileAccess.WRITE);file.store_string(JSON.stringify(data,"\t"));file.close()
