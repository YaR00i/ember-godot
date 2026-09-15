extends SceneTree
## Stored authored fields and runtime material ownership. Fixtures use user://.
const Lights = preload("res://scripts/ember_lights.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Prefab = preload("res://scripts/ember_voxel_prefab.gd")
var errors: Array[String] = []

func _init() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: errors.append(message)

func stored(object: Object) -> Dictionary:
	var fields := {}
	for info in object.get_property_list():
		if (int(info.usage) & PROPERTY_USAGE_STORAGE) == 0: continue
		var value: Variant = object.get(info.name)
		fields[info.name] = str(value) if value is Object else var_to_bytes(value)
	return fields

func make_fixture() -> Node3D:
	var scene := Node3D.new()
	scene.name = "GraphicsStorageFixture"
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.hydrate_legacy_regions = false
	scene.add_child(map); map.owner = scene
	var look := Node3D.new()
	look.name = "Look"
	map.add_child(look); look.owner = scene
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = Environment.new()
	env.environment.ambient_light_color = Color(0.77,0.84,0.8)
	env.environment.ambient_light_energy = 0.35
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.background_color = Color(0.43,0.57,0.6)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	look.add_child(env); env.owner = scene
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1,0.96,0.87)
	sun.light_energy = 0.3
	sun.rotation_degrees = Vector3(-58,-32,0)
	sun.shadow_enabled = true
	look.add_child(sun); sun.owner = scene
	var box := BoxMesh.new()
	box.size = Vector3(2,0.5,2)
	var arrays := box.surface_get_arrays(0)
	var colors := PackedColorArray()
	colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	colors.fill(Color("c5a36e"))
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,Materials.opaque_material())
	var probe := MeshInstance3D.new()
	probe.name = "GraphicProbe"
	probe.mesh = mesh
	scene.add_child(probe); probe.owner = scene
	return scene

func pixels() -> PackedByteArray:
	for i in 6: await process_frame
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image().get_data()

func render_safety(scene: Node3D, environment: Environment, sun: DirectionalLight3D) -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(4,3,5)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	Lights.apply_diorama_environment(environment,null)
	var authored: PackedByteArray = await pixels()
	Lights.apply_diorama_environment(environment,sun)
	var styled: PackedByteArray = await pixels()
	check(styled != authored,"native renderer did not apply ambient effect")
	for i in 5: Lights.apply_diorama_environment(environment,sun)
	check(await pixels() == styled,"native repeated apply drifted image")
	Lights.apply_diorama_environment(environment,null)
	check(await pixels() == authored,"native clear did not restore authored image")
	sun.hide()
	var hidden: PackedByteArray = await pixels()
	sun.show(); Lights.apply_diorama_environment(environment,sun)
	await pixels()
	sun.hide()
	check(await pixels() == hidden,"automatic Sun disable left ambient tail")
	sun.show(); Lights.apply_diorama_environment(environment,sun)
	check(await pixels() == styled,"automatic Sun enable did not restore image")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK,"native render fixture pack failed")
	var reopened := packed.instantiate() as Node3D
	scene.hide(); root.add_child(reopened)
	check(await pixels() == styled,"reopened fixture did not reproduce native graphics")
	reopened.free(); scene.show()
	Lights.apply_diorama_environment(environment,sun)
	camera.free()
	print("PASS DIORAMA_NATIVE_SAFETY: pixel idempotence, exact clear, automatic disable/enable, pack/reopen pixels")

func _run() -> void:
	for pair in [[Prefab.voxel_material(),Lights.voxel_material()],
		[Prefab.voxel_transparent_material(),Lights.voxel_transparent_material()]]:
		check(pair[0].shader == pair[1].shader,"constructor and published shader differ")
		for name in ["toon_steps","band_floor","local_light_softness","shadow_tint_strength","shadow_tint","band_softness"]:
			check(pair[0].get_shader_parameter(name) == pair[1].get_shader_parameter(name),"constructor/material mismatch " + name)
	check(Materials.water_material().shader != Prefab.voxel_transparent_material().shader,"water lost its shader owner")
	check(Materials.water_material().get_shader_parameter("preview_time") == -1.0,"QA freeze escaped into production material")
	check(Materials.water_material().get_shader_parameter("ripple_alpha") == 0.01,"accepted water network changed")
	check(Materials.water_material().get_shader_parameter("patch_cell_size") == 40.0,"accepted broad water scale changed")
	var scene := make_fixture()
	var sun := scene.get_node("Map/Look/Sun") as DirectionalLight3D
	var environment := (scene.get_node("Map/Look/WorldEnvironment") as WorldEnvironment).environment
	var before_sun := stored(sun)
	var authored_transform := sun.transform
	var before_environment := stored(environment)
	root.add_child(scene)
	if "--visual" in OS.get_cmdline_user_args(): await render_safety(scene,environment,sun)
	for i in 5: Lights.apply_diorama_environment(environment,sun)
	check(stored(sun) == before_sun,"apply changed authored Sun storage")
	check(stored(environment) == before_environment,"apply changed authored Environment storage")
	var state: Dictionary = Lights._diorama_environments[environment.get_instance_id()]
	check(state.signature[0],"warm daytime Sun did not activate")
	sun.hide(); Lights._refresh_diorama_environments()
	check(not state.signature[0],"hidden Sun left daytime override")
	sun.show(); sun.light_energy = 0; Lights._refresh_diorama_environments()
	check(not state.signature[0],"zero energy left daytime override")
	sun.light_energy = 0.3; sun.light_color = Color(0.48,0.64,1)
	Lights._refresh_diorama_environments()
	check(not state.signature[0],"cool night Sun activated style by node name")
	sun.light_color = Color(1,0.96,0.87)
	Lights.apply_diorama_environment(environment,null)
	check(not Lights._diorama_environments.has(environment.get_instance_id()),"missing Sun left watcher")
	Lights.apply_diorama_environment(environment,sun)
	root.remove_child(scene); Lights._refresh_diorama_environments()
	check(not Lights._diorama_environments.has(environment.get_instance_id()),"removed target left watcher")
	root.add_child(scene)
	check(Lights._diorama_environments[environment.get_instance_id()].signature[0],"detach/reattach did not resume automatically")
	Lights.apply_diorama_environment(environment,sun)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.48,0.64,1)
	sun.get_parent().add_child(moon)
	Lights._refresh_diorama_environments()
	check(not Lights._diorama_environments[environment.get_instance_id()].signature[0],"active Sun + Moon activated day ambient")
	moon.free()
	Lights._refresh_diorama_environments()
	check(Lights._diorama_environments[environment.get_instance_id()].signature[0],"Moon removal did not restore day style")
	var sun_parent := sun.get_parent()
	sun_parent.remove_child(sun)
	Lights._refresh_diorama_environments()
	check(not Lights._diorama_environments.has(environment.get_instance_id()),"detached Sun kept active poll")
	check(not RenderingServer.frame_pre_draw.is_connected(Lights._refresh_diorama_environments),"detached-only entry kept frame callback")
	sun_parent.add_child(sun)
	check(Lights._diorama_environments[environment.get_instance_id()].signature[0],"same Sun reattach needs Map ready")
	var other_parent := Node3D.new()
	scene.add_child(other_parent)
	var other_moon := DirectionalLight3D.new()
	other_moon.name = "Moon"
	other_parent.add_child(other_moon)
	sun.reparent(other_parent,true)
	Lights._refresh_diorama_environments()
	check(not Lights._diorama_environments[environment.get_instance_id()].signature[0],"reparent to active Moon left day override")
	sun.reparent(sun_parent,true)
	Lights._refresh_diorama_environments()
	check(Lights._diorama_environments[environment.get_instance_id()].signature[0],"reparent back did not restore style")
	sun.owner = scene
	# Native reparent performs a floating-point transform round trip. Restore
	# exactly the fixture action's original transform before storage comparison.
	sun.transform = authored_transform
	other_parent.free()
	sun_parent.remove_child(sun); Lights._refresh_diorama_environments()
	var replacement := DirectionalLight3D.new()
	replacement.light_color = Color(1,0.96,0.87)
	replacement.rotation_degrees = Vector3(-58,-32,0)
	sun_parent.add_child(replacement)
	Lights.apply_diorama_environment(environment,replacement)
	check(not Lights._diorama_reentry.has(environment.get_instance_id()),"target switch retained stale reentry")
	sun_parent.add_child(sun)
	check(Lights._diorama_environments[environment.get_instance_id()].sun.get_ref() == replacement,"stale tree callback restored previous target")
	Lights.apply_diorama_environment(environment,sun)
	replacement.free()
	sun.owner = scene
	var started := Time.get_ticks_usec()
	for i in 10000: Lights._refresh_diorama_environments()
	print("DIORAMA_WATCHER mean_us_per_poll=",float(Time.get_ticks_usec()-started)/10000.0," tracked_environments=",Lights._diorama_environments.size())
	check(stored(sun) == before_sun and stored(environment) == before_environment,"toggle cycle altered authored storage")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK,"fixture pack failed")
	var path := "user://ember-tests/diorama-storage-%d.tscn" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ember-tests"))
	check(ResourceSaver.save(packed,path) == OK,"fixture save failed")
	var reopened := (ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var loaded_sun := reopened.get_node("Map/Look/Sun") as DirectionalLight3D
	var loaded_environment := (reopened.get_node("Map/Look/WorldEnvironment") as WorldEnvironment).environment
	check(stored(loaded_sun) == before_sun,"pack/save/reopen changed authored Sun")
	var env_snapshot := stored(loaded_environment)
	# Resource path is assigned by loader; all actual Environment fields must match.
	env_snapshot.erase("resource_path"); before_environment.erase("resource_path")
	check(env_snapshot == before_environment,"pack/save/reopen changed authored Environment")
	root.add_child(reopened)
	check(Lights._diorama_environments[loaded_environment.get_instance_id()].signature[0],"reopened map did not reapply effect")
	for authored in ["res://scenes/world_canvas.tscn","res://scenes/test_pier.tscn","res://scenes/fan_town.tscn"]:
		if not ResourceLoader.exists(authored): continue
		var map_scene := (load(authored) as PackedScene).instantiate()
		var env_node := map_scene.get_node_or_null("Map/Look/WorldEnvironment") as WorldEnvironment
		var day_sun := map_scene.get_node_or_null("Map/Look/Sun") as DirectionalLight3D
		var authored_moon := map_scene.get_node_or_null("Map/Look/Moon") as DirectionalLight3D
		var snapshot := stored(env_node.environment)
		var moon_snapshot := stored(authored_moon) if authored_moon != null else {}
		Lights.apply_diorama_environment(env_node.environment,day_sun)
		check(stored(env_node.environment) == snapshot,"authored Environment mutated " + authored)
		if authored_moon != null:
			check(stored(authored_moon) == moon_snapshot,"legacy Moon mutated")
			check(not Lights._diorama_environments.has(env_node.environment.get_instance_id()),"legacy night created watcher")
		map_scene.free()
	for i in 20:
		var temporary := make_fixture()
		var held_environment := (temporary.get_node("Map/Look/WorldEnvironment") as WorldEnvironment).environment
		var temporary_sun := temporary.get_node("Map/Look/Sun") as DirectionalLight3D
		root.add_child(temporary)
		Lights.apply_diorama_environment(held_environment,temporary_sun)
		temporary_sun.free()
		Lights._refresh_diorama_environments()
		check(not Lights._diorama_environments.has(held_environment.get_instance_id()),"held Environment kept freed-Sun watcher")
		temporary.free()
	reopened.free(); scene.free()
	Lights._refresh_diorama_environments()
	check(Lights._diorama_environments.is_empty(),"open/close cycle leaked watcher entries")
	check(Lights._diorama_reentry.is_empty(),"open/close cycle leaked pending reentry entries")
	check(not RenderingServer.frame_pre_draw.is_connected(Lights._refresh_diorama_environments),"empty table kept frame callback")
	if errors.is_empty(): print("PASS DIORAMA_MATERIALS: constructors, ownership, authored storage, repeated apply, disabled/missing/cool/removed Sun, pack/save/reopen, legacy Moon")
	else:
		for message in errors: printerr("FAIL DIORAMA_MATERIALS ",message)
	quit(0 if errors.is_empty() else 1)
