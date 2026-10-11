extends SceneTree
const Study = preload("res://scripts/prototypes/ember_object_material_study.gd")
const LargeTree = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Bush = preload("res://addons/ember_import/ember_voxel_bush_generator.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Profiles = preload("res://scripts/ember_voxel_material_profiles.gd")
const Rock = preload("res://addons/ember_import/ember_voxel_rock_generator.gd")

func _init() -> void: _run.call_deferred()

func own(node: Node, scene: Node) -> void:
	for child in node.get_children(): child.owner = scene; own(child,scene)

func _run() -> void:
	var scene := Node3D.new(); scene.name = "ObjectMaterialStudy"; scene.set_script(Study)
	var specs := [
		[Rock,{"generation_version":2,"dimensions":Vector3i(30,23,28),"rock_type":1},"Камень"],
		[LargeTree,{"generation_version":2,"height":64,"crown_spread":35,"branchiness":35},"Кора и листва"],
		[Bush,{"generation_version":3,"height":24,"spread_radius":12},"Куст"],
		[Rock,{"generation_version":2,"dimensions":Vector3i(28,34,26),"rock_type":3,"stone_color":Color("b06dd4")},"Кристалл"],
		[Rock,{"generation_version":2,"dimensions":Vector3i(28,32,26),"rock_type":4,"stone_color":Color("9ddcde")},"Лёд"],
	]
	for index in specs.size():
		var spec: Array = specs[index]
		var generated: Dictionary = spec[0].build(spec[1],7,Color.GRAY,{},spec[2],"material_study_"+str(index))
		assert(not generated.has("error"),str(generated))
		var source: EmberVoxelModelResource = generated.geometry
		if index in [3,4]:
			source.material.object_surface.optics.merge({"enabled":true,"ior":1.60 if index == 3 else 1.31,
				"body_opacity":0.14 if index == 3 else 0.21,"thickness_m":0.8,"refraction_strength":0.026},true)
		scene.sample_sources.append(source)
		var packed := EmberVoxelPrefab.prepare_resource(source); assert(packed != null)
		var prop := packed.instantiate() as EmberVoxelProp; prop.name = "Sample"+str(index)
		prop.configure_voxel_scale(source.normalized_density(),1.0)
		var visual := prop.get_node("Mesh") as MeshInstance3D
		visual.mesh = visual.mesh.duplicate(true)
		for surface in visual.mesh.get_surface_count():
			visual.mesh.surface_set_material(surface,visual.mesh.surface_get_material(surface).duplicate(true))
		prop.position = Vector3((index-2)*3.0,0,-0.1)
		scene.add_child(prop)
		var label := Label3D.new(); label.name = "Label"+str(index); label.text = spec[2]
		label.font_size = 48; label.pixel_size = 0.008; label.position = Vector3((index-2)*3.0,0.05,1.7)
		label.rotation_degrees.x = -65; label.modulate = Color("e3edf2"); scene.add_child(label)
	var glass: EmberVoxelModelResource = Shapes.build("block",Vector3i(30,32,6),16,Color("d7efec"),"material_study_glass","Стекло").source
	Profiles.assign(glass.material,"glass")
	glass.material.object_surface.optics = {"enabled":true,"ior":1.50,"body_opacity":0.06,"thickness_m":0.375,"refraction_strength":0.035}
	scene.sample_sources.append(glass)
	var glass_prop := EmberVoxelPrefab.prepare_resource(glass).instantiate() as EmberVoxelProp
	glass_prop.name = "Sample5"; glass_prop.configure_voxel_scale(16,1.0); glass_prop.position = Vector3(9,0,-0.1)
	scene.add_child(glass_prop)
	var glass_label := Label3D.new(); glass_label.name = "Label5"; glass_label.text = "Стекло"
	glass_label.font_size = 48; glass_label.pixel_size = 0.008; glass_label.position = Vector3(9,0.05,1.7)
	glass_label.rotation_degrees.x = -65; glass_label.modulate = Color("e3edf2"); scene.add_child(glass_label)
	# Opaque, high-contrast rulers make transmission/refraction visible at a glance.
	var backdrop := Node3D.new(); backdrop.name = "OpticsBackdrop"; scene.add_child(backdrop)
	for sample in [3,4,5]:
		for stripe in 12:
			var board := MeshInstance3D.new(); board.name = "Stripe%d_%d" % [sample,stripe]
			var box := BoxMesh.new(); box.size = Vector3(0.22,2.7,0.08); board.mesh = box
			board.position = Vector3((sample-2)*3.0-1.0+stripe*0.22,1.35,-1.65)
			var material := StandardMaterial3D.new(); material.albedo_color = [Color("e1e6de"),Color("182c3f"),Color("d79c53")][stripe%3]
			material.roughness = 0.85; board.material_override = material; backdrop.add_child(board)
	for sample in [3,4,5]:
		var line := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3(2.6,0.12,0.12); line.mesh = box
		line.position = Vector3((sample-2)*3.0+0.2,1.2,-1.5)
		var mat := StandardMaterial3D.new(); mat.albedo_color = Color("a9423d"); line.material_override = mat; backdrop.add_child(line)
	var floor := MeshInstance3D.new(); floor.name = "Stage"; floor.mesh = BoxMesh.new(); floor.mesh.size = Vector3(21,0.2,6)
	floor.position = Vector3(1.5,-0.12,0); var floor_material := StandardMaterial3D.new(); floor_material.albedo_color = Color("657985"); floor_material.roughness = 0.95; floor.material_override = floor_material; scene.add_child(floor)
	var environment := WorldEnvironment.new(); environment.name = "Environment"; environment.environment = Environment.new()
	var env := environment.environment; env.background_mode = Environment.BG_SKY; env.sky = Sky.new(); env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC; scene.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.name = "Sun"; sun.shadow_enabled = true; sun.directional_shadow_max_distance = 40; sun.light_angular_distance = 1.0; scene.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.name = "Fill"; fill.rotation_degrees = Vector3(-18,120,0)
	fill.light_color = Color("bdd7ee"); fill.light_energy = 0.10; fill.light_specular = 0.0
	fill.shadow_enabled = false; scene.add_child(fill)
	var camera := Camera3D.new(); camera.name = "Camera"; camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 21
	camera.position = Vector3(8,8,14); scene.add_child(camera); camera.look_at_from_position(camera.position,Vector3(1.5,1.0,0)); camera.current = true
	var ui := CanvasLayer.new(); ui.name = "UI"; scene.add_child(ui)
	var caption := Label.new(); caption.name = "Caption"; caption.position = Vector2(24,18); caption.add_theme_font_size_override("font_size",22); ui.add_child(caption)
	own(scene,scene)
	var packed := PackedScene.new(); assert(packed.pack(scene) == OK)
	var path := "res://scenes/object_material_study.tscn"
	assert(ResourceSaver.save(packed,path) == OK)
	print("prepare_object_material_study: PASS ",path)
	scene.free(); quit()
