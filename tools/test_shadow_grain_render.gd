extends "res://tools/test_voxel_light_render.gd"
## Regression for soft-shadow grain through the real scene-owned viewport settings.
func grain(picture: Image, caster: MeshInstance3D) -> float:
 var total:=0.0;var cells:=0
 for z in range(-6,6):
  for x in range(-6,6):
   var centre:=Vector3((x+0.5)*0.25,0,(z+0.5)*0.25);var local:=caster.to_local(centre)
   if absf(local.x)<0.5 and absf(local.z)<0.75:continue
   var values: Array[Vector3]=[];var mean:=Vector3.ZERO
   for dz in range(-3,4):
    for dx in range(-3,4):
     var value:=pixel(picture,centre+Vector3(dx,0,dz)*0.014);values.append(value);mean+=value
   mean/=values.size();var variance:=0.0
   for value in values:variance+=(value-mean).length_squared()
   total+=sqrt(variance/values.size());cells+=1
 return total/cells
func run() -> void:
 if DisplayServer.get_name()=="headless":printerr("Native Forward+ required");quit(2);return
 output="user://ember-tests/shadow-grain-render";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 DisplayServer.window_set_size(Vector2i(900,600))
 var scene:=Node3D.new();root.add_child(scene);current_scene=scene
 var map:=EmberMapLoader.new();scene.add_child(map)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK;scene.add_child(environment)
 camera=Camera3D.new();scene.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4;camera.look_at_from_position(Vector3(0,6,0),Vector3.ZERO,Vector3.FORWARD);camera.make_current()
 var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(4,4)
 var arrays:=plane.get_mesh_arrays();var colours:=PackedColorArray();colours.resize(arrays[Mesh.ARRAY_VERTEX].size());colours.fill(Color(0.4,0.4,0.4));arrays[Mesh.ARRAY_COLOR]=colours
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);ground.mesh=mesh;scene.add_child(ground)
 var material:=ShaderMaterial.new();material.shader=load("res://shaders/ember_tree_bark.gdshader");material.set_shader_parameter("painted_bark_enabled",false);material.set_shader_parameter("surface_response_enabled",false);material.set_shader_parameter("voxel_light_enabled",true);material.set_shader_parameter("voxel_light_cell",0.25);material.set_shader_parameter("voxel_light_levels",32.0);ground.material_override=material
 var sun:=DirectionalLight3D.new();scene.add_child(sun);sun.rotation_degrees=Vector3(-55,-30,0);sun.shadow_enabled=true;sun.light_angular_distance=3;sun.directional_shadow_max_distance=20
 var caster:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(0.7,0.5,1.2);caster.mesh=box;caster.position=Vector3(0,0.8,0);caster.rotation.y=0.4;scene.add_child(caster)
 map.directional_shadow_filter=2;map.use_taa=false;map.apply_quality()
 var before:=await capture("baseline");var noisy:=grain(before,caster)
 check(noisy>0.002,"negative control reproduces soft-shadow grain")
 map.directional_shadow_filter=5;map.use_taa=true
 for frame in 60:await process_frame
 var after:=await capture("taa-ultra");var smooth:=grain(after,caster)
 check(root.use_taa and sun.light_angular_distance==3 and map.directional_shadow_filter==5,"soft shadows are preserved with scene-owned TAA")
 check(smooth<0.002 and smooth<noisy*0.2,"temporal filtering removes intra-cell soft-shadow grain")
 for frame in 28:camera.position.x+=0.011;await process_frame
 var moved:=await capture("moving");var motion:=grain(moved,caster)
 check(motion<0.003,"soft shadow remains smooth during camera translation")
 map.directional_shadow_filter=2;map.use_taa=false;map.apply_quality();camera.position.x=0
 var restored:=grain(await capture("disabled"),caster)
 check(not root.use_taa and restored>noisy*0.5,"switch can restore the original unfiltered appearance")
 print("SHADOW_GRAIN_RENDER ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"before":noisy,"after":smooth,"moving":motion,"restored":restored,"images":ProjectSettings.globalize_path(output)}))
 quit(0 if failures.is_empty() else 1)
