extends SceneTree
## Probe A/B/C on the shipped rock group. Loads the saved review scene and changes only
## in-memory instances; nothing under res:// is written. Output goes to the directory
## after "--".
##   A  current behaviour            B1 rim on, facet normals
##   B2 rim on, form normal          C  B2 + object-local form-normal projection
##   C1 C + painted-value overlap blend
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var errors: Array[String] = []
var output: String
var scene: Node
var prop: EmberVoxelProp
var visual: MeshInstance3D
var shipped: ArrayMesh
var form_mesh: ArrayMesh
var camera: Camera3D
var game_pose: Transform3D
var game_fov: float
var rim_pattern: EmberCompactTerrainPattern
var plain_pattern: EmberCompactTerrainPattern
var soft_pattern: EmberCompactTerrainPattern
var records: Array = []

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ", message)
func frames(count := 8) -> void:
	for i in count: await process_frame
	await RenderingServer.frame_post_draw
func shot(name: String) -> Image:
	await frames()
	var image := root.get_texture().get_image()
	check(image.save_png(output.path_join(name + ".png")) == OK, "capture " + name)
	return image

func material() -> ShaderMaterial: return visual.get_active_material(0) as ShaderMaterial

func set_variant(id: String) -> void:
	var m := material()
	var rim := id != "A"
	var form := id in ["B2", "B2s", "C", "C1", "C2", "C2s"]
	var local := id in ["C", "C1", "C2", "C2s"]
	visual.mesh = form_mesh if (form or local) else shipped
	var soft := id in ["B2s", "C2s"]
	prop.preview_solid_material_light(soft_pattern if soft else (rim_pattern if rim else plain_pattern), "cartoon_stone")
	m.set_shader_parameter("solid_form_rim", form)
	m.set_shader_parameter("solid_projection_mode", 1 if local else 0)
	m.set_shader_parameter("solid_height_blend", 6.0 if id == "C1" else 0.0)
	m.set_shader_parameter("solid_facet_bias", 0.35 if id in ["C2", "C2s"] else 0.0)
	m.set_shader_parameter("solid_blend_sharpness", 16.0)
	m.set_shader_parameter("solid_local_unit_m", prop.block_world_size)

func view_pose(view: int) -> void:
	camera.fov = game_fov; camera.global_transform = game_pose
	if view == 1: camera.fov = 40; camera.global_position = Vector3(3, 3.1, 6.5); camera.look_at(Vector3(2, 1.1, 2.5))
	if view == 2: camera.fov = 42; camera.global_position = Vector3(10, 8, 16); camera.look_at(Vector3(4.5, 1.1, 4.7))

func rock_centre() -> Vector3:
	return visual.global_transform * shipped.get_aabb().get_center()

func diff(a: Image, b: Image) -> Dictionary:
	var da := a.get_data(); var db := b.get_data()
	var sum := 0.0; var maximum := 0; var changed := 0
	for i in range(0, da.size(), 4):
		var local := 0
		for c in 3: local = maxi(local, absi(int(da[i + c]) - int(db[i + c])))
		sum += local; maximum = maxi(maximum, local)
		if local > 2: changed += 1
	return {"mean_max_channel_rgb8": snappedf(sum / (da.size() / 4.0), 0.0001), "max_rgb8": maximum, "pixels_gt2": changed}

func luminance_sum(image: Image) -> float:
	var d := image.get_data(); var sum := 0.0
	for i in range(0, d.size(), 4): sum += 0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]
	return sum / (d.size() / 4.0)

func rim_energy(on: Image, off: Image) -> float:
	var a := on.get_data(); var b := off.get_data(); var sum := 0.0
	for i in range(0, a.size(), 4):
		sum += maxf(0.2126 * (a[i] - b[i]) + 0.7152 * (a[i + 1] - b[i + 1]) + 0.0722 * (a[i + 2] - b[i + 2]), 0.0)
	return sum / (a.size() / 4.0)

func isolate_rock(on: bool) -> void:
	var map := scene.get_node("Map")
	for child in map.get_children():
		if child.name != "Look" and child.name != "Props" and "visible" in child: child.visible = not on
	var oak := map.get_node_or_null("Props/PaintedOak")
	if oak: oak.visible = not on
	var grass := scene.get_node_or_null("GrassTufts")
	if grass: grass.visible = not on

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scenes/compact_environment_material_review.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	while not scene.ready_for_play: await process_frame
	scene.player.set_physics_process(false); scene.camera.set_process(false)
	camera = scene.camera._cam; game_pose = camera.global_transform; game_fov = camera.fov
	prop = scene.get_node("Map/Props/PaintedRockGroup"); visual = prop.get_node("Mesh")
	shipped = visual.mesh as ArrayMesh
	var arrays_before := shipped.surface_get_arrays(0)
	form_mesh = Solid.with_form_normals(shipped, 0)
	var arrays_after := form_mesh.surface_get_arrays(0)
	var max_position_delta := 0.0; var max_normal_delta := 0.0
	for i in arrays_before[Mesh.ARRAY_VERTEX].size():
		max_position_delta = maxf(max_position_delta, (arrays_before[Mesh.ARRAY_VERTEX][i] - arrays_after[Mesh.ARRAY_VERTEX][i]).length())
		max_normal_delta = maxf(max_normal_delta, (arrays_before[Mesh.ARRAY_NORMAL][i] - arrays_after[Mesh.ARRAY_NORMAL][i]).length())
	check(max_position_delta == 0.0, "form mesh keeps exact vertex positions")
	check(max_normal_delta < 0.01, "form mesh keeps facet normals")
	check(form_mesh.get_aabb() == shipped.get_aabb(), "same bounds")
	plain_pattern = Materials.load_compact_terrain_variant("cartoon_stone")
	rim_pattern = plain_pattern.duplicate(true)
	rim_pattern.style_rim_custom = true; rim_pattern.style_rim_enabled = true; rim_pattern.style_rim_strength = 0.7
	soft_pattern = rim_pattern.duplicate(true); soft_pattern.style_rim_strength = 0.3
	check(not plain_pattern.style_rim_custom, "shipped stone has no rim override")
	var stone_hash := FileAccess.get_sha256("res://content/terrain_materials/cartoon_stone.tres")
	var variants := ["A", "B1", "B2", "B2s", "C", "C1", "C2", "C2s"]
	var base_images := {}
	# Control A must be reproducible after every other variant (flag defaults keep old path).
	for id in variants:
		set_variant(id)
		for preset in 3:
			for side in 2:
				scene.set_lighting(preset, side)
				for view in 3:
					view_pose(view)
					var name := "%s-%d-%d-%d" % [id, preset, side, view]
					var image := await shot(name)
					if id == "A": base_images[name] = image
					records.append({"variant": id, "preset": preset, "side": side, "view": view, "file": name + ".png"})
	set_variant("A")
	var returns := 0
	for name in base_images:
		var parts: PackedStringArray = name.split("-")
		scene.set_lighting(int(parts[1]), int(parts[2])); view_pose(int(parts[3]))
		var image := await shot("Areturn-" + name.substr(2))
		if image.get_data() == base_images[name].get_data(): returns += 1
	check(returns == base_images.size(), "A returns pixel-exact after all variants")
	# --- Object motion: texture-only (no sun, white ambient), rock alone.
	var environment: Environment = scene.get_node("Map/Look/WorldEnvironment").environment
	var sun: DirectionalLight3D = scene.get_node("Map/Look/Sun")
	var saved := {"energy": sun.light_energy, "ambient": environment.ambient_light_color, "ambient_energy": environment.ambient_light_energy, "source": environment.ambient_light_source, "ssao": environment.ssao_enabled}
	sun.light_energy = 0.0; environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE; environment.ambient_light_energy = 1.0; environment.ssao_enabled = false
	isolate_rock(true)
	var pivot := rock_centre()
	var prop_home := prop.global_transform
	var cam_dir := Vector3(0.62, 0.55, 0.78).normalized()
	var motion := {}
	for id in ["A", "C", "C2"]:
		set_variant(id)
		var reference: Image
		for case in ["home", "yaw22", "yaw45", "shift"]:
			var turn := Transform3D.IDENTITY
			if case == "yaw22": turn = Transform3D(Basis(Vector3.UP, deg_to_rad(22.5)), Vector3.ZERO)
			if case == "yaw45": turn = Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3.ZERO)
			var about := Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot)
			if case == "shift": about = Transform3D(Basis.IDENTITY, Vector3(1.3, 0, 0.7))
			prop.global_transform = about * prop_home
			camera.fov = 38
			camera.global_position = about * (pivot + cam_dir * 6.5); camera.look_at(about * pivot)
			var name := "motion-%s-%s" % [id, case]
			var image := await shot(name)
			if case == "home": reference = image
			else: motion["%s/%s" % [id, case]] = diff(reference, image)
		prop.global_transform = prop_home
	# --- Rim orbit: rim energy per camera yaw, flat vs form normal.
	sun.light_energy = saved.energy; environment.ambient_light_color = saved.ambient; environment.ambient_light_energy = saved.ambient_energy
	environment.ambient_light_source = saved.source; environment.ssao_enabled = saved.ssao
	scene.set_lighting(1, 1)
	var orbit := {"B1": [], "B2": [], "B2s": []}
	for step in 16:
		var yaw := deg_to_rad(step * 7.5)
		var position := pivot + Vector3(sin(yaw) * 5.2, 3.6, cos(yaw) * 5.2)
		camera.fov = 38
		set_variant("A"); camera.global_position = position; camera.look_at(pivot)
		var off_image := await shot("orbit-off-%02d" % step)
		for id in ["B1", "B2", "B2s"]:
			set_variant(id); camera.global_position = position; camera.look_at(pivot)
			var on_image := await shot("orbit-%s-%02d" % [id, step])
			orbit[id].append(rim_energy(on_image, off_image))
	var orbit_summary := {}
	for id in orbit:
		var energies: Array = orbit[id]; var jitter := 0.0; var total := 0.0
		for i in energies.size():
			total += energies[i]
			if i > 0: jitter += absf(energies[i] - energies[i - 1])
		orbit_summary[id] = {"energies": energies, "mean_energy": total / energies.size(), "mean_step_change": jitter / (energies.size() - 1)}
	orbit = orbit_summary
	isolate_rock(false)
	check(FileAccess.get_sha256("res://content/terrain_materials/cartoon_stone.tres") == stone_hash, "cartoon_stone.tres untouched")
	var file := FileAccess.open(output.path_join("probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": errors.is_empty(), "errors": errors, "frames": records, "a_returns_exact": returns, "motion": motion, "orbit": orbit, "max_position_delta": max_position_delta, "max_normal_delta": max_normal_delta}, "\t")); file.close()
	print("ROCK_FORM_PROBE ", "PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
