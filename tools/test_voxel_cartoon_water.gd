extends SceneTree

const Prefab = preload("res://scripts/ember_voxel_prefab.gd")
const Cache = preload("res://scripts/ember_voxel_projection_cache.gd")
const SurfaceMesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const SurfaceMaterials = preload("res://scripts/ember_voxel_surface_materials.gd")
var errors: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func _init() -> void:
	_run.call_deferred()

func fixture() -> EmberVoxelModelResource:
	var source := EmberVoxelModelResource.new()
	source.model_id = "cartoon_water_fixture"
	source.display_name = "Мультяшная вода · отмель и камни"
	source.voxels_per_block = 16
	source.size_blocks = Vector3i(8,3,8)
	source.height_voxels = 48
	source.palette = PackedColorArray([Color.TRANSPARENT,Color("c5a36e"),Color("487346"),Color("598d99"),Color("31978f"),Color("8c6640")])
	var grid := source.grid_size()
	source.voxels.resize(grid.x*grid.y*grid.z)
	source.surface_fill_levels.resize(grid.x*grid.z)
	source.surface_fill_materials.resize(grid.x*grid.z)
	source.surface_fill_palette.resize(grid.x*grid.z)
	for z in grid.z:
		for x in grid.x:
			var top := roundi(38.0-29.0*smoothstep(16.0,100.0,float(x)))
			var color := 2 if x < 22 else 1
			for rock in [Vector3i(67,29,35),Vector3i(90,32,90)]:
				if pow((float(x)-rock.x)/10.0,2)+pow((float(z)-rock.z)/13.0,2) < 1.0:
					top = rock.y
					color = 3
			# A simple voxel pier supplies real water-mask boundaries at pilings.
			if x >= 40 and x <= 85 and z >= 59 and z <= 65:
				if x%18 <= 3 and (z <= 60 or z >= 64):
					top = 29
					color = 5
			for y in range(top+1): source.voxels[VoxMesher.cell_index(x,y,z,grid.x,grid.z)] = color
			if top < 24:
				var column := x+z*grid.x
				source.surface_fill_levels[column] = 24
				source.surface_fill_materials[column] = 1
				source.surface_fill_palette[column] = 4
	return source

func water_surface(mesh: Mesh) -> int:
	for surface in mesh.get_surface_count():
		if mesh.surface_get_name(surface) == "water": return surface
	return -1

func verify(prop: Node3D, source: EmberVoxelModelResource, expected: Mesh) -> void:
	var visual: MeshInstance3D = prop.get_node("Mesh")
	var water := water_surface(visual.mesh)
	check(water >= 0,"prepared prefab lost explicit water")
	if water < 0: return
	var material := visual.mesh.surface_get_material(water) as ShaderMaterial
	check(material != null and material.shader == SurfaceMaterials.water_material().shader,"prefab water used wrong material")
	check(visual.mesh.surface_get_arrays(water)[Mesh.ARRAY_VERTEX] == expected.surface_get_arrays(water_surface(expected))[Mesh.ARRAY_VERTEX],"prefab and Surface water geometry differ")
	var shape: ConcavePolygonShape3D = prop.get_node("Collision/Shape").shape
	var dry := source.duplicate(true) as EmberVoxelModelResource
	dry.surface_fill_levels.clear()
	dry.surface_fill_materials.clear()
	dry.surface_fill_palette.clear()
	var dry_prop := Prefab.prepare_resource(dry).instantiate()
	check(shape.get_faces() == dry_prop.get_node("Collision/Shape").shape.get_faces(),"water changed prefab collision")
	dry_prop.free()

func _run() -> void:
	var source := fixture()
	var before := source.to_definition()
	check(source.validation_errors().is_empty(),"invalid cartoon-water fixture")
	var expected := SurfaceMesher.build_region(source,Vector3i.ZERO,source.grid_size(),1.0/16.0)
	var packed := Prefab.prepare_resource(source)
	check(packed != null,"water prefab preparation failed")
	if packed == null:
		quit(1)
		return
	var prop := packed.instantiate() as Node3D
	verify(prop,source,expected)
	var cached := Prefab.prepare_resource(source,Cache.new()).instantiate()
	verify(cached,source,expected)
	cached.free()
	var regular := Prefab._build_visual_mesh(source.model_id,source.to_definition(),1.0/16.0,{})
	Prefab._apply_visual_materials(regular)
	check(water_surface(regular) >= 0,"ordinary saved-prefab builder lost water")
	# Read the authored scene, but neither instantiate gameplay nor save the map.
	var pier := load("res://scenes/test_pier.tscn") as PackedScene
	var bay_mesh: BoxMesh
	if pier != null:
		var state := pier.get_state()
		for node in state.get_node_count():
			if not str(state.get_node_path(node)).ends_with("Map/Terrain/BayWater/Visual"): continue
			for property in state.get_node_property_count(node):
				if state.get_node_property_name(node,property) == "mesh":
					bay_mesh = state.get_node_property_value(node,property) as BoxMesh
	check(bay_mesh != null and bay_mesh.material is ShaderMaterial,"harbour backdrop still uses plain material")
	if bay_mesh != null and bay_mesh.material is ShaderMaterial:
		check(bay_mesh.material.shader == SurfaceMaterials.water_material().shader,"backdrop uses a second water shader")
		check(bay_mesh.material.get_shader_parameter("background_water") == true,"backdrop did not opt into opaque water")
	check(source.to_definition() == before,"water builder mutated source")
	var path := "user://cartoon-water-%d.tscn"%Time.get_ticks_usec()
	check(ResourceSaver.save(packed,path) == OK,"water prefab save failed")
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	verify(reopened,source,expected)
	reopened.free()
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280,900)
		var world := Node3D.new()
		root.add_child(world)
		world.add_child(prop)
		if bay_mesh != null:
			var bay := MeshInstance3D.new()
			bay.mesh = bay_mesh
			bay.position = Vector3(192,-9,80)
			world.add_child(bay)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("203b46")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color("a5d2cd")
		environment.environment.ambient_light_energy = 0.55
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-55,-30,0)
		light.light_energy = 0.9
		light.shadow_enabled = true
		world.add_child(light)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 175
		world.add_child(camera)
		camera.position = Vector3(115,145,135)
		camera.look_at(Vector3(0,18,0))
		camera.current = true
		var deck := MeshInstance3D.new()
		deck.mesh = BoxMesh.new()
		deck.mesh.size = Vector3(47,2,9)
		deck.position = Vector3(-1,30,-2)
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("ba854c")
		deck.material_override = wood
		world.add_child(deck)
		var visual: MeshInstance3D = prop.get_node("Mesh")
		var water_material := SurfaceMaterials.water_material().duplicate() as ShaderMaterial
		visual.set_surface_override_material(water_surface(visual.mesh),water_material)
		var samples: Array[Image] = []
		for sample in [0,1]:
			water_material.set_shader_parameter("preview_time",float(sample)*4.0)
			for frame in 30: await process_frame
			RenderingServer.force_draw(false)
			var capture := root.get_texture().get_image()
			var capture_path := "user://cartoon_water_%d.png"%sample
			capture.save_png(capture_path)
			print("CARTOON_WATER_CAPTURE ",ProjectSettings.globalize_path(capture_path))
			samples.append(capture)
		var changed_pixels := 0
		for y in range(samples[0].get_height()/6,samples[0].get_height()*5/6,4):
			for x in range(samples[0].get_width()/6,samples[0].get_width()*5/6,4):
				if samples[0].get_pixel(x,y) != samples[1].get_pixel(x,y): changed_pixels += 1
		check(changed_pixels > 50,"native water animation did not move")
		print("CARTOON_WATER_CHANGED_PIXELS ",changed_pixels)
		world.free()
	else:
		prop.free()
	for message in errors: push_error(message)
	print("test_voxel_cartoon_water: ","PASS" if errors.is_empty() else "FAIL"," · ",errors.size())
	quit(0 if errors.is_empty() else 1)
