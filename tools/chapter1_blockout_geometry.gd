extends RefCounted
## Offline authoring helpers. Output is ordinary saved Godot nodes and native terrain.
const Explore = preload("res://scripts/world_canvas.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Grass = preload("res://scripts/ember_grass_patch.gd")
const UNIT := 16.0
const FLOOR := 8.0
const TERRAIN_DIR := "res://content/world_terrains/chapter1"
const STORAGE := "user://ember-chapter1-blockout"
static var _material: ShaderMaterial
static var _mesh_cache: Dictionary = {}

static func base_map(id: String, title: String, size: Vector2i, role := "grass") -> Node3D:
	var scene := Node3D.new()
	scene.name = id
	scene.set_script(Explore)
	scene.set("map_id", id)
	scene.set("sandbox_storage_root", STORAGE)
	scene.set_meta("chapter1_blockout", true)
	scene.set_meta("blockout_title", title)
	var map := EmberMapLoader.new()
	map.name = "Map"; map.map_id = id
	map.imported_tile_size = UNIT
	map.hydrate_legacy_regions = false
	map.native_cutaway_enabled = false
	map.authored_size_blocks = size
	map.camera_distance = 170.0; map.camera_polar = 0.88; map.camera_yaw = 0.35
	map.camera_look_height = 5.0; map.camera_far = 1600.0
	map.compact_material_light_mode = 1
	map.compact_smooth_material_blend = true
	map.compact_water_visual_material = load("res://materials/ember_compact_sky_reflection_study.tres")
	map.compact_water_mesh_step = 8; map.compact_water_volume_sides = true
	map.compact_smooth_study_column_limit = 1572864
	map.compact_terrain = terrain(size, role)
	map.compact_ground_style = 1
	scene.add_child(map)
	for label in ["Look", "Terrain", "Props", "Regions"]:
		var node := Node3D.new(); node.name = label; map.add_child(node)
	look(map.get_node("Look"))
	var layer := CanvasLayer.new(); layer.name = "CanvasLayer"; scene.add_child(layer)
	var hud := Label.new(); hud.name = "Gate"; hud.position = Vector2(16, 16); layer.add_child(hud)
	var legend := Label.new(); legend.name = "BlockoutLegend"
	legend.text = title + " · ЧЕРНОВОЙ МАРШРУТ\nWASD — ходьба · F — дверь / разговор · Tab — лидер"
	legend.position = Vector2(16, 104); legend.add_theme_font_size_override("font_size", 18)
	layer.add_child(legend)
	return scene

static func terrain(size: Vector2i, role: String) -> Terrain:
	var value := Terrain.new()
	value.width = size.x * 16; value.depth = size.y * 16
	value.height_limit = 128
	value.palette = PackedColorArray([Color.TRANSPARENT, Color("8c9970"), Color("a59679"), Color("a9a49a"), Color("c3b58f"), Color("6f9aab")])
	value.palette_surface_roles = PackedStringArray(["", "grass", "soil", "stone", "sand", ""])
	value.palette_material_ids = PackedStringArray(["", "grass", "soil", "paving", "sand", ""])
	# Reuse the current accepted pigment rather than a second grass palette.
	var accepted := load("res://content/world_terrains/landscape_compact.res") as Terrain
	if accepted != null:
		for index in range(1, 5):
			var found := accepted.palette_surface_roles.find(value.palette_surface_roles[index])
			if found >= 0:
				value.palette[index] = accepted.palette[found]
				if found < accepted.palette_material_ids.size(): value.palette_material_ids[index] = accepted.palette_material_ids[found]
	var count := value.width * value.depth
	value.heights.resize(count); value.heights.fill(int(FLOOR))
	value.top_materials.resize(count); value.top_materials.fill(1 + ["grass", "soil", "stone", "sand"].find(role))
	value.base_materials = value.top_materials.duplicate()
	value.cap_depths.resize(count); value.cap_depths.fill(1)
	value.water_levels.resize(count); value.water_materials.resize(count)
	return value

static func look(parent: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new(); var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.24, 0.32, 0.48)
	sky_material.sky_horizon_color = Color(1.0, 0.6, 0.35)
	sky_material.ground_horizon_color = Color(0.68, 0.42, 0.33)
	sky.sky_material = sky_material; environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.59, 0.78)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var node := WorldEnvironment.new(); node.name = "WorldEnvironment"; node.environment = environment; parent.add_child(node)
	var sun := DirectionalLight3D.new(); sun.name = "Sun"
	sun.rotation_degrees = Vector3(-35, -55, 0)
	sun.light_color = Color(1.0, 0.79, 0.59); sun.light_energy = 1.1
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 600
	parent.add_child(sun)

static func map_of(scene: Node) -> EmberMapLoader:
	return scene.get_node("Map") as EmberMapLoader

static func props(scene: Node) -> Node3D:
	return scene.get_node("Map/Props")

static func group(parent: Node, id: String, xz: Vector2, elevation := FLOOR) -> Node3D:
	var value := Node3D.new(); value.name = id
	value.position = Vector3(xz.x * UNIT, elevation, xz.y * UNIT)
	value.set_meta("presentation_id", id)
	parent.add_child(value)
	return value

static func box(parent: Node, id: String, size: Vector3, at: Vector3, color: Color, solid := true) -> MeshInstance3D:
	var key := str(size) + str(color)
	var mesh: ArrayMesh = _mesh_cache.get(key)
	if mesh == null:
		var primitive := BoxMesh.new(); primitive.size = size
		var arrays := primitive.get_mesh_arrays()
		var colors := PackedColorArray(); colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()); colors.fill(color)
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh = ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(0, "chapter1_blockout")
		if _material == null: _material = EmberVoxelSurfaceMaterials.opaque_material()
		mesh.surface_set_material(0, _material)
		_mesh_cache[key] = mesh
	var visual := MeshInstance3D.new(); visual.name = id; visual.mesh = mesh; visual.position = at
	parent.add_child(visual)
	if solid:
		var body := StaticBody3D.new(); body.name = id + "Collision"; body.collision_layer = 1; body.collision_mask = 0; body.position = at
		var shape := CollisionShape3D.new(); shape.name = "Shape"; var geometry := BoxShape3D.new(); geometry.size = size; shape.shape = geometry
		body.add_child(shape); parent.add_child(body)
	return visual

static func label(parent: Node, text: String, at: Vector3, color := Color("fff4d4")) -> Label3D:
	var value := Label3D.new(); value.name = "Label"; value.text = text
	value.position = at; value.font_size = 32; value.pixel_size = 0.11
	value.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	value.modulate = color; value.outline_size = 8
	parent.add_child(value)
	return value

static func region(parent: Node, map_id: String, id: String, at: Vector3, kind := "player_start", target := "", target_region := "") -> EmberRegion:
	var value := EmberRegion.new(); value.name = id; value.map_id = map_id; value.region_id = id
	value.position = at; value.kind = kind; value.target_map_id = target; value.target_region_id = target_region
	var shape := CollisionShape3D.new(); shape.name = "Shape"
	var geometry := BoxShape3D.new(); geometry.size = Vector3(28, 48, 28); shape.shape = geometry
	shape.position.y = 16; value.add_child(shape); parent.add_child(value)
	return value

static func door(parent: Node, target: String, local_at: Vector3, caption := "Вход") -> EmberInteract:
	var value := EmberSceneAuthoring.make_interact({"kind": "door", "target_map_id": target, "target_region_id": "entry", "note": caption}, UNIT)
	value.name = "DoorInteraction"; value.position = local_at; parent.add_child(value)
	box(parent, "DoorPanel", Vector3(12, 23, 2), local_at + Vector3(0, 7, -4), Color("5b7781"), false)
	return value

static func building(scene: Node, id: String, caption: String, xz: Vector2, size := Vector3(64, 48, 48), target := "", return_id := "", yaw := 0.0) -> Node3D:
	var value := group(props(scene), id, xz); value.rotation.y = yaw
	box(value, "Walls", size, Vector3(0, size.y / 2, 0), Color("b1a388"))
	box(value, "Roof", Vector3(size.x + 5, 6, size.z + 5), Vector3(0, size.y + 3, 0), Color("8e6553"))
	label(value, caption, Vector3(0, size.y + 14, 0))
	if not target.is_empty():
		door(value, target, Vector3(0, 8, size.z * 0.5 + 7), caption)
		region(value, map_of(scene).map_id, return_id, Vector3(0, 0, size.z * 0.5 + 30))
	return value

static func gate(scene: Node, id: String, caption: String, xz: Vector2, destination: String, destination_entry: String, entry_xz: Vector2, own_entry: String) -> void:
	var value := group(props(scene), id, xz)
	var arrival_direction := entry_xz - xz
	if absf(arrival_direction.x) > absf(arrival_direction.y): value.rotation.y = PI * 0.5
	region(value, map_of(scene).map_id, "exit_" + own_entry, Vector3.ZERO, "trigger", destination, destination_entry)
	label(value, caption, Vector3(0, 22, 0), Color("d7e9b9"))
	box(value, "GateLeft", Vector3(3, 24, 3), Vector3(-19, 12, 0), Color("869375"))
	box(value, "GateRight", Vector3(3, 24, 3), Vector3(19, 12, 0), Color("869375"))
	region(scene.get_node("Map/Regions"), map_of(scene).map_id, own_entry, Vector3(entry_xz.x * UNIT, FLOOR, entry_xz.y * UNIT))

static func paint_path(scene: Node, points: Array[Vector2], width: float, slot := 2) -> void:
	var ground: Terrain = map_of(scene).compact_terrain
	for z in ground.depth:
		for x in ground.width:
			var point := Vector2(x + 0.5, z + 0.5) / UNIT
			for segment in range(points.size() - 1):
				var closest := Geometry2D.get_closest_point_to_segment(point, points[segment], points[segment + 1])
				if point.distance_to(closest) < width * 0.5:
					ground.top_materials[z * ground.width + x] = slot
					break

static func water_strip(scene: Node, centre_x: float, amplitude: float, half_width: float, water_level := 6) -> void:
	var ground: Terrain = map_of(scene).compact_terrain
	for z in ground.depth:
		var centre := centre_x + sin(float(z) / ground.depth * TAU) * amplitude
		for x in ground.width:
			if absf(x / UNIT - centre) > half_width: continue
			var index := z * ground.width + x
			ground.heights[index] = 1; ground.top_materials[index] = 3
			ground.water_levels[index] = water_level; ground.water_materials[index] = 5
	ground.water_flow.resize((ground.width / 16) * (ground.depth / 16)); ground.water_flow.fill(Vector2(0, 0.25))

static func tree(scene: Node, id: String, xz: Vector2, scale_factor := 0.6) -> void:
	var packed := load("res://prefabs/voxels/vox_painted_maple_autumn_palette.tscn") as PackedScene
	if packed == null: return
	var node := packed.instantiate() as EmberVoxelProp
	node.name = id; node.placement_id = map_of(scene).map_id + "_" + id
	node.position = Vector3(xz.x * UNIT, FLOOR, xz.y * UNIT)
	node.scale = Vector3.ONE * scale_factor; props(scene).add_child(node)

static func grass(scene: Node, id: String, xz: Vector2, size := Vector2(3, 3)) -> void:
	var patch := Grass.new(); patch.name = id
	patch.position = Vector3(xz.x * UNIT, FLOOR, xz.y * UNIT)
	patch.size_blocks = size; patch.tufts_per_block = 30; patch.scatter_seed = id.hash()
	props(scene).add_child(patch)

static func fence(parent: Node, xz: Vector2, length: float, yaw := 0.0) -> void:
	var value := group(parent, "Fence%d" % parent.get_child_count(), xz, 0)
	value.rotation.y = yaw
	box(value, "Rail", Vector3(length, 9, 2), Vector3(0, 4.5, 0), Color("958166"))

static func crates(scene: Node, xz: Vector2, count := 3) -> void:
	var value := group(props(scene), "Cargo%d" % props(scene).get_child_count(), xz)
	for index in count:
		box(value, "Crate%d" % index, Vector3(12, 12, 12), Vector3(index % 3 * 15, 6 + index / 3 * 12, 0), Color("927555"))

static func save(scene: Node3D) -> Error:
	var map := map_of(scene)
	if map.compact_terrain.water_materials.count(0) < map.compact_terrain.water_materials.size():
		scene.add_child(preload("res://prefabs/items/shared_world_water.tscn").instantiate())
	var regions := scene.get_node_or_null("Map/Regions")
	if regions != null:
		var entry := regions.get_node_or_null("entry")
		if entry != null: regions.move_child(entry, 0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TERRAIN_DIR))
	var terrain_path := TERRAIN_DIR.path_join(map.map_id + ".res")
	var errors := map.compact_terrain.validation_errors()
	if not errors.is_empty(): push_error(str(errors)); return ERR_INVALID_DATA
	var error := ResourceSaver.save(map.compact_terrain, terrain_path, ResourceSaver.FLAG_COMPRESS)
	if error != OK: return error
	map.compact_terrain.take_over_path(terrain_path)
	assign_owners(scene, scene)
	var packed := PackedScene.new(); error = packed.pack(scene)
	if error == OK: error = ResourceSaver.save(packed, "res://scenes/" + map.map_id + ".tscn")
	return error

static func assign_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path.is_empty(): assign_owners(child, root)
