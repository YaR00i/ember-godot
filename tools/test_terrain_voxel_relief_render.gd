extends SceneTree
## GPU comparison against real stepped geometry: colour must stay on its height cell.
## No authored map or Resource writes. Run native Forward+.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func capture() -> Image:
 for frame in 30: await process_frame
 await RenderingServer.frame_post_draw
 return root.get_texture().get_image()
func error(a: Image,b: Image) -> float:
 var total := 0.0;var count := 0
 for y in range(int(a.get_height()*0.4),int(a.get_height()*0.6)):
  for x in range(int(a.get_width()*0.3),int(a.get_width()*0.7)):
   var ca := a.get_pixel(x,y);var cb := b.get_pixel(x,y)
   total += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b);count+=3
 return total/float(count)
func run() -> void:
 if DisplayServer.get_name()=="headless":printerr("Native Forward+ required");quit(2);return
 DisplayServer.window_set_size(Vector2i(500,500))
 var scene := Node3D.new();root.add_child(scene);current_scene=scene
 var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK;scene.add_child(environment)
 var colour := Image.create(256,256,false,Image.FORMAT_RGBA8)
 var height := Image.create(256,256,false,Image.FORMAT_R8)
 var high := Color(0.85,0.65,0.65);var low := Color(0.65,0.65,0.85)
 for y in 256:
  for x in 256:
   var raised := (x/8+y/8)%2==0
   colour.set_pixel(x,y,high if raised else low);height.set_pixel(x,y,Color(0.8 if raised else 0.2,0,0))
 var pattern := Materials.load_compact_terrain_variant("paving").duplicate(true) as EmberCompactTerrainPattern;pattern.role_id="stone";pattern.albedo_texture=ImageTexture.create_from_image(colour);pattern.depth_texture=ImageTexture.create_from_image(height);pattern.pattern_size_m=1;pattern.depth_mm=30;pattern.albedo_periodic=true;pattern.albedo_relief_enabled=false;pattern.style_rim_enabled=false
 var material := Materials.compact_terrain_material();material.shader=Materials.compact_terrain_bank_depth_shader()
 var roles := PackedStringArray(["","stone"]);var ids := PackedStringArray(["","fixture"])
 Materials.set_compact_terrain_roles(material,roles,ids,PackedColorArray(),{"fixture":pattern})
 Materials.set_terrain_depth_profiles(material,roles,ids,{"fixture":pattern})
 var lookup := Image.create(256,1,false,Image.FORMAT_RGBAF);lookup.fill(Color(0.5,0.5,0.5))
 material.set_shader_parameter("png_mean_lookup",ImageTexture.create_from_image(lookup));material.set_shader_parameter("png_tint_lookup",ImageTexture.create_from_image(lookup))
 for pair in [["voxel_light_enabled",true],["voxel_light_cell",0.0625],["voxel_light_levels",8.0],["terrain_depth_world_unit",1.0],["ember_texture_world_unit",1.0],["terrain_world_look",2],["look_study_mode",2],["look_study_pixel_m",0.0625],["material_depth_fade_near_m",100.0],["material_depth_fade_far_m",200.0],["material_depth_steps",64]]:material.set_shader_parameter(pair[0],pair[1])
 var shader := Shader.new();var code: String=material.shader.code
 var tail := code.rfind("}",code.find("void light()"))
 shader.code=code.insert(tail,"\n EMISSION=ALBEDO;ALBEDO=vec3(0.0);\n");material.shader=shader
 var plane := PlaneMesh.new();plane.size=Vector2.ONE
 var arrays := plane.get_mesh_arrays();var colours := PackedColorArray();colours.resize(arrays[Mesh.ARRAY_VERTEX].size());colours.fill(Color(1,0,0,1.0/255.0));arrays[Mesh.ARRAY_COLOR]=colours
 var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var visual := MeshInstance3D.new();visual.mesh=mesh;visual.material_override=material;scene.add_child(visual)
 var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.4;camera.near=0.01;camera.far=20;scene.add_child(camera);camera.look_at_from_position(Vector3(0,1.4,1.8),Vector3.ZERO);camera.make_current()
 var fixed := await capture()
 var former := Shader.new();former.code=shader.code.replace("if (look_study_mode==2) p=ember_texture_cell_coordinates(p);","p=ember_texture_coordinates(ember_look_pixel_colour_position(world_position,world_normal),png.g);")
 material.shader=former;var before := await capture();visual.hide()
 var builder := SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
 var box := BoxMesh.new();box.size=Vector3.ONE;var box_arrays := box.get_mesh_arrays()
 var vertices: PackedVector3Array=box_arrays[Mesh.ARRAY_VERTEX];var indices: PackedInt32Array=box_arrays[Mesh.ARRAY_INDEX]
 for z in 32:
  for x in 32:
   var raised := (x+z)%2==0;var top := ((0.8 if raised else 0.2)-0.5)*0.03
   builder.set_color((high if raised else low).srgb_to_linear())
   for i in indices:
    builder.add_vertex(Vector3((float(x)+0.5)/32.0-0.5, (top-0.03)*0.5,(float(z)+0.5)/32.0-0.5)+vertices[i]*Vector3(1.0/32.0,top+0.03,1.0/32.0))
 var reference := MeshInstance3D.new();reference.mesh=builder.commit();var ref_material := ShaderMaterial.new();ref_material.shader=Shader.new();ref_material.shader.code="shader_type spatial;render_mode unshaded,cull_disabled;void fragment(){ALBEDO=COLOR.rgb;}";reference.material_override=ref_material;scene.add_child(reference)
 var expected := await capture();var fixed_error := error(fixed,expected);var before_error := error(before,expected)
 if fixed_error>=0.04:failures.append("colour/relief disagree with actual stepped cells")
 if before_error<=fixed_error*1.5:failures.append("negative control must reproduce the mismatched cell grid")
 var output := "user://ember-tests/voxel-relief-render";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 fixed.save_png(output.path_join("fixed.png"));before.save_png(output.path_join("before.png"));expected.save_png(output.path_join("reference.png"))
 print("TERRAIN_VOXEL_RELIEF ",JSON.stringify({"pass":failures.is_empty(),"fixed_error":fixed_error,"before_error":before_error,"errors":failures,"images":ProjectSettings.globalize_path(output)}))
 quit(0 if failures.is_empty() else 1)
