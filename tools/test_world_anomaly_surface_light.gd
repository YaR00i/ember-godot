extends SceneTree
## GPU morph must light the same surface as an independently baked copy.
## Forward+ memory-only rock fixture; writes captures under user:// only.
const Correspondence = preload("res://scripts/ember_anomaly_correspondence.gd")
var output := "user://ember-tests/anomaly-surface-light"
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
 if not ok: failures.append(label); printerr("FAIL ", label)

func capture(label: String) -> Image:
 for frame in 8: await process_frame
 await RenderingServer.frame_post_draw
 var picture := root.get_texture().get_image()
 picture.save_png(output.path_join(label + ".png"))
 return picture

func bake(carrier: ArrayMesh, targets: Texture2D, sphere: Vector4, band: float) -> ArrayMesh:
 var arrays := carrier.surface_get_arrays(0)
 var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
 var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
 var image := targets.get_image()
 for i in points.size():
  var weight := 1.0 - smoothstep(sphere.w-band*0.5, sphere.w+band*0.5, points[i].distance_to(Vector3(sphere.x,sphere.y,sphere.z)))
  var index := i*4+2
  var value := image.get_pixel(index%Correspondence.WIDTH,index/Correspondence.WIDTH)
  points[i] = points[i].lerp(Vector3(value.r,value.g,value.b),weight)
  index += 1
  value = image.get_pixel(index%Correspondence.WIDTH,index/Correspondence.WIDTH)
  normals[i] = normals[i].lerp(Vector3(value.r,value.g,value.b),weight).normalized()
 arrays[Mesh.ARRAY_VERTEX] = points; arrays[Mesh.ARRAY_NORMAL] = normals
 var result := ArrayMesh.new()
 result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},carrier.surface_get_format(0))
 return result

func run() -> void:
 if DisplayServer.get_name() == "headless": printerr("Native Forward+ required"); quit(2); return
 if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 DisplayServer.window_set_size(Vector2i(1000,800))
 var scene := Node3D.new(); root.add_child(scene); current_scene = scene
 var prop = load("res://prefabs/voxels/vox_painted_rock_group.tscn").instantiate(); scene.add_child(prop)
 prop.set_world_look(1); var low: ArrayMesh = prop.get_node("Mesh").mesh
 prop.set_world_look(2); var voxel: ArrayMesh = prop.get_node("Mesh").mesh
 prop.set_world_look(0); var source: MeshInstance3D = prop.get_node("Mesh")
 source.transform = Transform3D.IDENTITY; prop._sync_solid_depth()
 var reference: ArrayMesh = source.mesh
 var carrier: ArrayMesh = await Correspondence.carrier(reference,voxel,scene)
 var targets: Array[Texture2D] = await Correspondence.prepare(carrier,low,voxel,scene,false,true)
 var visual := MeshInstance3D.new(); scene.add_child(visual); visual.mesh = carrier
 visual.custom_aabb = reference.get_aabb().merge(voxel.get_aabb())
 var material: ShaderMaterial = source.material_override.duplicate(); visual.material_override = material
 material.set_shader_parameter("ember_anomaly_prepared",true)
 material.set_shader_parameter("ember_anomaly_targets",targets[0])
 material.set_shader_parameter("material_depth_enabled",false)
 material.set_shader_parameter("surface_detail_enabled",false)
 material.set_shader_parameter("material_gray_preview",true)
 material.set_shader_parameter("voxel_light_anomaly",true)
 # Isolate light/shadow sampling from optional pigment, edge and POM layers.
 material.set_shader_parameter("stone_profiles",ImageTexture.create_from_image(Image.create(256,2,false,Image.FORMAT_RGBAF)))
 var centre := reference.get_aabb().get_center()
 var field := Vector4(centre.x+1.5,centre.y,centre.z,2.0)
 visual.set_instance_shader_parameter("ember_anomaly_sphere",field)
 visual.set_instance_shader_parameter("ember_anomaly_band_look",Vector2(0.45,2))
 source.hide()
 var plane := MeshInstance3D.new(); var plane_mesh := PlaneMesh.new(); plane_mesh.size = Vector2(25,25); plane.mesh = plane_mesh
 scene.add_child(plane); plane.position = Vector3(centre.x,-0.03,centre.z)
 var ground := StandardMaterial3D.new(); ground.albedo_color = Color(0.6,0.5,0.35); plane.material_override = ground
 var sun := DirectionalLight3D.new(); scene.add_child(sun); sun.rotation_degrees = Vector3(-40,-40,0)
 sun.shadow_enabled = true; sun.directional_shadow_max_distance = 40; sun.light_angular_distance = 0
 var world := WorldEnvironment.new(); scene.add_child(world); world.environment = Environment.new()
 world.environment.background_mode = Environment.BG_COLOR; world.environment.background_color = Color(0.16,0.2,0.23)
 world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; world.environment.ambient_light_color = Color.WHITE
 world.environment.ambient_light_energy = 0.5; world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
 var camera := Camera3D.new(); scene.add_child(camera); camera.fov = 38; camera.make_current()
 camera.look_at_from_position(centre+Vector3(7,4.5,8),centre)
 var gpu := await capture("gpu-morph")
 var baked := bake(carrier,targets[0],field,0.45)
 visual.mesh = baked
 var identity: Array[Texture2D] = await Correspondence.prepare(baked,baked,baked,scene,true,true)
 material.set_shader_parameter("ember_anomaly_targets",identity[0])
 var cpu := await capture("baked-same-surface")
 var error := 0.0; var changed := 0
 for y in gpu.get_height():
  for x in gpu.get_width():
   var a := gpu.get_pixel(x,y); var b := cpu.get_pixel(x,y)
   var difference := absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
   error += difference
   if difference > 0.10: changed += 1
 error /= gpu.get_width()*gpu.get_height()*3
 check(changed < 100 and error < 0.00001,"morph and equivalent baked surface must share lighting/shadows")
 var report := {"pass":failures.is_empty(),"errors":failures,"mean_rgb_error":error,"changed_pixels":changed}
 var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report)); file.close()
 print("ANOMALY_SURFACE_LIGHT ",JSON.stringify(report))
 scene.queue_free(); await process_frame
 quit(0 if failures.is_empty() else 1)
