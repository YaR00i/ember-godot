@tool
class_name EmberMapLoader
extends Node3D
## One-way import from Ember pack into an authored Godot scene.
## After Reimport, Ctrl+S. Geometry lives in Look / Terrain / Props / Regions.

const SurfaceProjection := preload("res://scripts/ember_voxel_surface_projection.gd")

@export_group("0 · Карта и тест")
## ID исходной карты в joi-conductor/content/ember/maps. Полный reimport затирает правки сцены.
@export var map_id := "fan_town"
## Native scenes author their regions directly and need no legacy pack hydration.
@export var hydrate_legacy_regions := true
## Одна общая художественная поверхность карты. Выбранный прямоугольник в 3D
## является только областью редактирования и не создаёт отдельный Resource.
@export var visual_surface: EmberVoxelModelResource:
	set(value):
		if visual_surface == value:
			return
		visual_surface = value
		_refresh_visual_surface_projection()
## Saved map footprint lets a native Surface validate without reading the
## temporary JOI archive. Zero keeps the legacy importer fallback for old maps.
@export var authored_size_blocks := Vector2i.ZERO
## G3 pilot: derive world collision and route heights from visual_surface.
## Kept explicit per map until agent_sandbox proves the runtime contract.
@export var use_visual_surface_physics := false
## Число ближайших фонарей с cube-тенью. Fill остальных фонарей всегда остаётся включённым.
@export_enum("Только fill · 0:0", "Быстро · 2:2", "Баланс · 4:4", "Production · 8:8", "Расширенный · 12:12", "Stress · 16:16") var lighting_test_shadows := 4
## Включайте только для проверки кадра: локальные тени в 3D viewport дороже и обновляются при движении камеры.
@export var preview_local_shadows_in_editor := false
@export_tool_button("Применить профиль света") var apply_test_profile_action: Callable = _apply_test_profile
@export_tool_button("Применить все настройки света") var apply_look_action: Callable = apply_authored_lighting

@export_group("1 · Атмосфера")
@export_subgroup("Туман")
@export var fog_enabled := true
@export var fog_depth_begin := 48.0
@export var fog_depth_end := 340.0
@export var fog_aerial := 0.5
@export var fog_sky_affect := 0.8
@export var fog_sun_scatter := 0.16
@export var fog_color_mix := 0.2

@export_subgroup("Небо")
@export var sky_energy := 1.2
@export var star_amount := 0.85
@export var moon_disc_size := 0.034

@export_group("2 · Луна и общая тень")
@export var moon_shadows := true
@export var moon_energy_scale := 1.25
@export var sun_intensity := 1.0
@export var fill_intensity := 1.0
@export var ambient_alpha := 0.5
@export var directional_shadow_distance := 520.0
@export_enum("2 splits:2", "4 splits:4") var directional_shadow_splits := 4
@export_enum("1024:1024", "2048:2048", "4096:4096", "8192:8192") var directional_shadow_size := 4096
@export_enum("Hard:0", "Very Low:1", "Low:2", "Medium:3", "High:4", "Ultra:5") var directional_shadow_filter := 2
@export_range(0.0, 1.0, 0.01) var moon_shadow_bias := 0.14
@export_range(0.0, 4.0, 0.05) var moon_shadow_normal_bias := 2.4
@export_range(0.0, 4.0, 0.05) var moon_shadow_blur := 1.35

@export_group("3 · Фонари")
@export var lamp_energy_scale := 1.15
@export var lamp_range_scale := 1.0
@export var lamp_use_map_range := true
@export var lamp_power := 1.0
@export var lamp_range_tiles := 7.0
@export var lamp_strength0 := 0.62
@export var lamp_falloff := 0.42
@export var lamp_color := Color(1.0, 0.69, 0.337)
@export var lamp_face_color := Color(1.0, 0.565, 0.188)
## 1 = плавный свет без колец; 0 = ступенчатый toon-свет как от луны.
@export_range(0.0, 1.0, 0.05) var lamp_softness := 1.0
## Runtime-бюджет ближайших фонарей с тенями. Для сравнения используйте профиль выше или F4 в Play.
@export_range(0, 16) var omni_shadow_count := 4
@export_enum("512:512", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var lamp_shadow_size := 4096
@export_enum("Hard:0", "Very Low:1", "Low:2", "Medium:3", "High:4", "Ultra:5") var lamp_shadow_filter := 1
## Depth offset локальной тени. Поднимать только если normal bias не убрал self-shadow acne.
@export_range(0.0, 1.0, 0.01) var lamp_shadow_bias := 0.18
## Основной anti-acne для Omni. Он меньше отрывает тень от объекта, чем обычный bias.
@export_range(0.0, 4.0, 0.05) var lamp_shadow_normal_bias := 1.8
## Большой blur усиливает зернистый PCF-рисунок на однотонных voxel-поверхностях.
@export_range(0.0, 2.0, 0.05) var lamp_shadow_blur := 0.25

@export_group("4 · Камера и качество")
@export var camera_fov := 40.0
@export var camera_distance := 120.0
@export var camera_polar := 0.95
@export var camera_yaw := 0.785398
@export var camera_look_height := 6.0
@export var camera_near := 1.0
@export var camera_far := 5000.0
@export_enum("Off:0", "2x:1", "4x:2", "8x:3") var msaa_3d := 2
## Добавляет fullscreen-dither против цветовых полос. На текущем voxel-стиле оставлен выключенным: узор виден сильнее banding.
@export var use_debanding := false
@export var imported_tile_size := 16.0

@export_group("5 · Интерьеры")
## Experimental Godot-native roof sections. Enabled only on agent_sandbox until visual acceptance.
@export var native_cutaway_enabled := false

var _voxel_mat: ShaderMaterial
var _look: Node3D
var _terrain: Node3D
var _props: Node3D
var _regions: Node3D
var _cutaways: Node3D
var _stats := {
	"props": 0,
	"omni": 0,
	"omni_shadow": 0,
	"missing_mesh": 0,
	"json_mesh": 0,
	"vox_mesh": 0,
	"terrain_cells": 0,
	"width": 0,
	"height": 0,
	"tile_size": 16,
}
var _omni_shadow_ids: Array = []
var _omni_shadow_candidates := 0
var _omni_shadow_active := 0
var _cutaway_sections := 0
var _cutaway_active := 0
var _visual_surface_projection: Node3D


func _apply_test_profile() -> void:
	set_lighting_test_profile(lighting_test_shadows)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func set_lighting_test_profile(shadow_count: int) -> void:
	var allowed := [0, 2, 4, 8, 12, 16]
	var best := 0
	var best_distance := 999
	for candidate in allowed:
		var distance: int = absi(candidate - shadow_count)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	lighting_test_shadows = best
	omni_shadow_count = best
	_omni_shadow_ids.clear()
	notify_property_list_changed()
	apply_authored_lighting()


func _ready() -> void:
	apply_authored_lighting()
	_refresh_visual_surface_projection()


func apply_authored_lighting() -> void:
	if _voxel_mat == null:
		_voxel_mat = EmberVoxelPrefab.voxel_material()
	if _voxel_mat:
		_voxel_mat.set_shader_parameter("local_light_softness", lamp_softness)
	var moon := _content_node("Look/Moon") as DirectionalLight3D
	if moon:
		moon.light_energy = EmberLights.moon_energy(
			sun_intensity, fill_intensity, ambient_alpha, moon_energy_scale
		)
		moon.shadow_enabled = moon_shadows
		EmberLights.tune_moon_shadows(
			moon,
			directional_shadow_distance,
			directional_shadow_splits,
			moon_shadow_bias,
			moon_shadow_normal_bias,
			moon_shadow_blur,
		)
	apply_quality()
	var ts := imported_tile_size if imported_tile_size > 0.0 else 16.0
	var map_range := maxf(ts, lamp_range_tiles * ts * lamp_range_scale)
	var energy := EmberLights.omni_energy(
		lamp_strength0, lamp_falloff, lamp_power * lamp_energy_scale, ambient_alpha
	)
	var col := EmberLights.lamp_point_color(lamp_color, lamp_face_color)
	_tune_look_environment()
	var props := _content_node("Props")
	if props:
		_retune_omnis(props, map_range, energy, col)
		_isolate_lamp_host_shadows(props)
		_omni_shadow_ids.clear()
		refresh_omni_shadow_focus(spawn_world())


func _tune_look_environment() -> void:
	var env_node := _content_node("Look/WorldEnvironment") as WorldEnvironment
	if env_node == null or env_node.environment == null:
		return
	var e := env_node.environment
	e.ssao_enabled = false
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.volumetric_fog_enabled = false


func apply_quality() -> void:
	if not is_inside_tree():
		return
	EmberLights.apply_shadow_atlas(
		directional_shadow_size,
		lamp_shadow_size,
		directional_shadow_filter,
		lamp_shadow_filter,
	)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = msaa_3d as Viewport.MSAA
		vp.use_debanding = use_debanding
		vp.positional_shadow_atlas_size = clampi(lamp_shadow_size, 512, 8192)
	var follow := get_tree().get_first_node_in_group("ember_follow_camera") as EmberFollowCamera
	if follow:
		follow.cam_near = camera_near
		follow.cam_far = play_camera_far()
		follow.fov = camera_fov
		follow.follow_distance = camera_distance
		follow.polar_angle = camera_polar
		follow.look_height = camera_look_height


func play_camera_far() -> float:
	return maxf(50.0, camera_far)


func _content_node(path: String) -> Node:
	var n := get_node_or_null(path)
	if n:
		return n
	return get_node_or_null("Map/%s" % path)


func _isolate_lamp_host_shadows(node: Node) -> void:
	var body := node as MeshInstance3D
	if body and node.name == "ShadowBody":
		body.layers = EmberLights.SHADOW_LAYER_LAMP_HOST
	var omni := node as OmniLight3D
	if omni and omni.visible:
		omni.shadow_caster_mask = EmberLights.SHADOW_LAYER_WORLD
	for child in node.get_children():
		_isolate_lamp_host_shadows(child)


func _retune_omnis(node: Node, map_range: float, energy: float, col: Color) -> void:
	var omni := node as OmniLight3D
	if omni:
		if omni.visible:
			omni.light_color = col
			omni.light_energy = energy
			if lamp_use_map_range:
				omni.omni_range = map_range
		return
	for child in node.get_children():
		_retune_omnis(child, map_range, energy, col)


func refresh_omni_shadow_focus(world: Vector3) -> void:
	var props := _content_node("Props")
	if props == null:
		return
	var lamps: Array = []
	_collect_focus_omnis(props, lamps, world)
	lamps.sort_custom(func(a, b): return a[0] < b[0])
	var budget := mini(omni_shadow_count, EmberLights.MAX_OMNI_SHADOWS)
	if Engine.is_editor_hint() and not preview_local_shadows_in_editor:
		budget = 0
	_omni_shadow_candidates = lamps.size()
	_omni_shadow_active = mini(lamps.size(), budget)
	var next_ids: Array = []
	for i in mini(lamps.size(), budget):
		next_ids.append((lamps[i][1] as OmniLight3D).get_instance_id())
	if next_ids == _omni_shadow_ids:
		return
	_omni_shadow_ids = next_ids
	for i in lamps.size():
		var omni: OmniLight3D = lamps[i][1]
		var want := i < budget
		if omni.shadow_enabled != want:
			omni.shadow_enabled = want
		if want:
			EmberLights.tune_omni_shadows(
				omni,
				lamp_shadow_bias,
				lamp_shadow_normal_bias,
				lamp_shadow_blur,
			)


func omni_shadow_active_count() -> int:
	return _omni_shadow_active


func omni_shadow_candidate_count() -> int:
	return _omni_shadow_candidates


func _collect_focus_omnis(node: Node, lamps: Array, world: Vector3) -> void:
	var omni := node as OmniLight3D
	if omni:
		if omni.visible:
			var parent := omni.get_parent()
			var mid := str(parent.get("model_id")) if parent else ""
			if EmberLights.omni_casts_world_shadow(mid):
				lamps.append([omni.global_position.distance_squared_to(world), omni])
			elif omni.shadow_enabled:
				omni.shadow_enabled = false
		return
	for child in node.get_children():
		_collect_focus_omnis(child, lamps, world)


func has_authored_content() -> bool:
	var props := _content_node("Props")
	return props != null and props.get_child_count() > 0


func stats() -> Dictionary:
	return _stats.duplicate()


func hydrate_native_cutaway() -> int:
	var existing := get_node_or_null("Cutaways")
	if existing:
		remove_child(existing)
		existing.queue_free()
	_cutaway_sections = 0
	_cutaway_active = 0
	if not native_cutaway_enabled or Engine.is_editor_hint():
		return 0
	var raw: Variant = EmberPack.parse_json_file(EmberPack.map_path(map_id))
	if typeof(raw) != TYPE_DICTIONARY:
		return 0
	var sections := EmberTileMesher.build_cutaway_roofs(raw)
	if sections.is_empty():
		return 0
	_cutaways = Node3D.new()
	_cutaways.name = "Cutaways"
	add_child(_cutaways)
	var material := EmberVoxelPrefab.voxel_material()
	for section in sections:
		var volume := EmberCutawayVolume.new()
		volume.setup(section, material)
		volume.reveal_changed.connect(_on_cutaway_reveal_changed)
		_cutaways.add_child(volume)
	_cutaway_sections = sections.size()
	return _cutaway_sections


func cutaway_section_count() -> int:
	return _cutaway_sections


func cutaway_active_count() -> int:
	return _cutaway_active


func set_cutaway_preview(revealed: bool, immediate := false) -> void:
	if not is_instance_valid(_cutaways):
		return
	for child in _cutaways.get_children():
		var volume := child as EmberCutawayVolume
		if volume:
			volume.set_revealed(revealed, immediate)


func _on_cutaway_reveal_changed(_revealed: bool) -> void:
	_cutaway_active = 0
	if not is_instance_valid(_cutaways):
		return
	for child in _cutaways.get_children():
		var volume := child as EmberCutawayVolume
		if volume and volume.is_revealed():
			_cutaway_active += 1


func spawn_world() -> Vector3:
	var regions := _content_node("Regions")
	if regions:
		for child in regions.get_children():
			# Read export, do not call EmberRegion methods (editor placeholders).
			if child is Node3D and str(child.get("kind")) == "player_start":
				var start := child as Node3D
				return start.global_position if start.is_inside_tree() else start.position
	return Vector3(16, 8, 16)


func region_world(region_id: String) -> Vector3:
	if region_id.is_empty():
		return spawn_world()
	var regions := _content_node("Regions")
	if regions:
		for child in regions.get_children():
			if child is Node3D and (
				str(child.get("region_id")) == region_id or child.name == region_id
			):
				var region := child as Node3D
				return region.global_position if region.is_inside_tree() else region.position
	push_warning("ember map %s: spawn region '%s' not found; using player_start" % [map_id, region_id])
	return spawn_world()


func hydrate_region_runtime() -> void:
	if not hydrate_legacy_regions:
		return
	var raw_map: Variant = EmberPack.parse_json_file(EmberPack.map_path(map_id))
	if typeof(raw_map) != TYPE_DICTIONARY:
		return
	var by_id := {}
	var raw_regions: Variant = raw_map.get("regions", [])
	if typeof(raw_regions) != TYPE_ARRAY:
		return
	for raw_region in raw_regions:
		if typeof(raw_region) == TYPE_DICTIONARY:
			var region_id := str(raw_region.get("id", "")).strip_edges()
			if not region_id.is_empty():
				by_id[region_id] = raw_region
	var regions := _content_node("Regions")
	if regions == null:
		return
	for child in regions.get_children():
		var area := child as EmberRegion
		if area == null or not by_id.has(area.region_id):
			continue
		_apply_region_record(area, by_id[area.region_id])
		if area.is_inside_tree() and not Engine.is_editor_hint():
			area.refresh_runtime_binding()
		area.refresh_chest_visual(imported_tile_size)
	var props := _content_node("Props")
	if props != null:
		_refresh_interact_runtime_bindings(props)


func _refresh_interact_runtime_bindings(node: Node) -> void:
	if node is EmberInteract:
		(node as EmberInteract).refresh_runtime_binding()
	for child in node.get_children():
		_refresh_interact_runtime_bindings(child)


func occupying_region_id(world: Vector3, kinds: Array[String]) -> String:
	var regions := _content_node("Regions")
	if regions == null:
		return ""
	for child in regions.get_children():
		var area := child as EmberRegion
		if area and area.kind in kinds and area.contains_world_xz(world):
			return area.region_id
	return ""


func load_map(id: String) -> Dictionary:
	map_id = id
	_clear_generated()
	_reset_stats()
	EmberVoxelPrefab.begin_import()
	var path := EmberPack.map_path(id)
	var data: Variant = EmberPack.parse_json_file(path)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ember map: failed to parse %s" % path)
		return _stats
	var map: Dictionary = data
	var tile_size := float(map.get("tileSize", 16))
	var width := int(map.get("width", 16))
	var height := int(map.get("height", 16))
	_stats.width = width
	_stats.height = height
	_stats.tile_size = tile_size
	imported_tile_size = tile_size
	_voxel_mat = EmberVoxelPrefab.voxel_material()
	_apply_camera(map.get("camera", {}), tile_size)
	var light_cfg: Variant = map.get("light", {})
	_look = _group("Look")
	_terrain = _group("Terrain")
	_props = _group("Props")
	_regions = _group("Regions")
	_add_look(light_cfg, width, height, tile_size)
	_add_terrain(map)
	var region_by_id := _add_regions(map, tile_size)
	var props: Array = map.get("voxelProps", [])
	for place in props:
		if typeof(place) != TYPE_DICTIONARY:
			continue
		_add_prop(place, tile_size, region_by_id)
	print(
		"ember reimport %s: terrain=%s props=%s vox=%s json=%s missing=%s omni=%s shadow=%s pack=%s"
		% [
			id,
			_stats.terrain_cells,
			_stats.props,
			_stats.vox_mesh,
			_stats.json_mesh,
			_stats.missing_mesh,
			_stats.omni,
			_stats.omni_shadow,
			EmberPack.pack_root(),
		]
	)
	apply_authored_lighting()
	_refresh_visual_surface_projection()
	return _stats


func _group(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	add_child(n)
	_own_root(n)
	return n


func _clear_generated() -> void:
	_visual_surface_projection = null
	for node_name in ["Look", "Terrain", "Props", "Regions", "Cutaways"]:
		var n := get_node_or_null(node_name)
		if n:
			remove_child(n)
			n.free()
	for child in get_children():
		remove_child(child)
		child.free()


func world_surface_matches_map() -> bool:
	return _world_surface_matches(visual_surface)


func resolved_visual_surface() -> EmberVoxelModelResource:
	## The explicit scene reference wins. When the author has saved the Surface
	## but not the .tscn yet, runtime/editor preview still resolve the one
	## canonical map-owned Resource by map_id instead of silently showing legacy
	## terrain. A bad explicit assignment remains visible as a warning.
	if visual_surface != null:
		return visual_surface if _world_surface_matches(visual_surface) else null
	var path := EmberVoxelModelResource.world_surface_path(map_id)
	if not ResourceLoader.exists(path):
		return null
	var candidate := ResourceLoader.load(path) as EmberVoxelModelResource
	return candidate if _world_surface_matches(candidate) else null


func _world_surface_matches(surface: EmberVoxelModelResource) -> bool:
	if surface == null:
		return false
	var owner := str(surface.material.get("semanticOwner", "")).strip_edges()
	if not owner.is_empty() and owner != map_id:
		return false
	var expected := _expected_world_surface_blocks()
	return (
		expected == Vector2i.ZERO
		or (
			surface.size_blocks.x == expected.x
			and surface.size_blocks.z == expected.y
		)
	)


func refresh_visual_surface_projection() -> void:
	_refresh_visual_surface_projection()


func surface_floor_sample(global_point: Vector3) -> Dictionary:
	if not is_instance_valid(_visual_surface_projection):
		return {"solid": false}
	return _visual_surface_projection.call("floor_surface_sample", global_point)


func surface_navigation_path(
	global_start: Vector3,
	global_goal: Vector3,
	max_step_voxels := 4,
) -> PackedVector3Array:
	if not is_instance_valid(_visual_surface_projection):
		return PackedVector3Array()
	return _visual_surface_projection.call(
		"navigation_path", global_start, global_goal, max_step_voxels
	) as PackedVector3Array


func _refresh_visual_surface_projection() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_visual_surface_projection):
		_visual_surface_projection = SurfaceProjection.new()
		_visual_surface_projection.name = "DerivedVoxelWorldSurface"
		add_child(_visual_surface_projection)
	var terrain_visual := _content_node("Terrain/Mesh") as Node3D
	var terrain_collision := _content_node("Terrain/Collision") as StaticBody3D
	var expected := _expected_world_surface_blocks()
	var source := resolved_visual_surface()
	_visual_surface_projection.call(
		"configure",
		source,
		imported_tile_size,
		expected,
		terrain_visual,
		use_visual_surface_physics,
		terrain_collision,
	)
	update_configuration_warnings()


func _expected_world_surface_blocks() -> Vector2i:
	if int(_stats.get("width", 0)) > 0 and int(_stats.get("height", 0)) > 0:
		return Vector2i(int(_stats.width), int(_stats.height))
	if authored_size_blocks.x > 0 and authored_size_blocks.y > 0:
		return authored_size_blocks
	# Inspector deserialization can ask before authored_size_blocks is assigned.
	# An unknown native footprint is valid here; it never implies legacy import.
	if not hydrate_legacy_regions or not FileAccess.file_exists(EmberPack.map_path(map_id)):
		return Vector2i.ZERO
	var raw: Variant = EmberPack.parse_json_file(EmberPack.map_path(map_id))
	if typeof(raw) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(maxi(1, int(raw.get("width", 1))), maxi(1, int(raw.get("height", 1))))


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if visual_surface != null and not world_surface_matches_map():
		var expected := _expected_world_surface_blocks()
		warnings.append(
			"Visual Surface не совпадает с картой %s: ожидается %dx%d блоков и semanticOwner=%s."
			% [map_id, expected.x, expected.y, map_id]
		)
	if use_visual_surface_physics and authored_size_blocks == Vector2i.ZERO:
		warnings.append(
			"Physical Surface требует сохранённый authored_size_blocks, чтобы runtime не зависел от legacy map JSON."
		)
	return warnings


func _reset_stats() -> void:
	_stats.props = 0
	_stats.omni = 0
	_stats.omni_shadow = 0
	_stats.missing_mesh = 0
	_stats.json_mesh = 0
	_stats.vox_mesh = 0
	_stats.terrain_cells = 0


func _edited_owner() -> Node:
	if not Engine.is_editor_hint():
		return self
	var tree := get_tree()
	if tree and tree.edited_scene_root:
		return tree.edited_scene_root
	return self


func _own_root(node: Node) -> void:
	var o := _edited_owner()
	if o:
		node.owner = o


func _own_tree(node: Node) -> void:
	_own_root(node)
	for child in node.get_children():
		_own_tree(child)


func _apply_camera(raw: Variant, tile_size: float) -> void:
	var cfg: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	camera_fov = float(cfg.get("fov", 40.0))
	camera_distance = float(cfg.get("followDistance", clampf(tile_size * 7.5, 96.0, 160.0)))
	camera_polar = float(cfg.get("polarAngle", 0.95))
	camera_yaw = float(cfg.get("yaw", 0.785398))
	camera_look_height = float(cfg.get("lookHeight", 6.0))


func _add_terrain(map: Dictionary) -> void:
	var built: Dictionary = EmberTileMesher.build(map)
	_stats.terrain_cells = int(built.get("cells", 0))
	var mesh := built.get("mesh") as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mesh_i := MeshInstance3D.new()
	mesh_i.name = "Mesh"
	mesh_i.mesh = mesh
	mesh_i.material_override = _voxel_mat
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_terrain.add_child(mesh_i)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	_terrain.add_child(body)
	_own_tree(_terrain)


func _add_look(light: Variant, width: int, height: int, tile_size: float) -> void:
	var cfg: Dictionary = light if typeof(light) == TYPE_DICTIONARY else {}
	var atmo_raw: Variant = cfg.get("atmosphere", {})
	var atmo: Dictionary = atmo_raw if typeof(atmo_raw) == TYPE_DICTIONARY else {}
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	var night := clampf(float(cfg.get("ambientAlpha", 0.5)), 0.0, 1.0)
	var fill := float(cfg.get("fillIntensity", 1.0))
	var fog_amt := float(atmo.get("fog", 0.0))
	var fog_col := EmberLights.hex_color(str(atmo.get("fogColor", "#120810")), Color(0.07, 0.03, 0.08))
	var moon_col := EmberLights.hex_color(str(cfg.get("sunColor", "#789ef7")))
	var az := float(cfg.get("sunAzimuth", 40))
	var el := float(cfg.get("sunElevation", 45))
	var dir := EmberLights.sun_direction(az, el)
	var sky_mat := EmberLights.make_sky_material(
		night,
		fog_amt,
		fog_col,
		dir,
		moon_col,
		star_amount,
		moon_disc_size,
		fog_color_mix,
	)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.background_energy_multiplier = sky_energy
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = EmberLights.hex_color(str(cfg.get("ambientColor", "#032472")))
	e.ambient_light_energy = EmberLights.night_ambient_energy(fill, night)
	e.ambient_light_sky_contribution = 0.18
	e.fog_enabled = fog_enabled
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = fog_col.lerp(Color(0.07, 0.086, 0.19), 0.45)
	e.fog_density = EmberLights.fog_density(fog_amt, float(atmo.get("haze", 0.0)))
	e.fog_aerial_perspective = fog_aerial
	e.fog_sky_affect = fog_sky_affect
	e.fog_sun_scatter = fog_sun_scatter
	e.fog_depth_begin = fog_depth_begin
	e.fog_depth_end = fog_depth_end
	e.glow_enabled = true
	e.glow_intensity = clampf(float(cfg.get("bloomStrength", 0.28)) * 1.35, 0.0, 1.2)
	e.ssao_enabled = false
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.volumetric_fog_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.22
	sun_intensity = float(cfg.get("sunIntensity", 1.0))
	fill_intensity = fill
	ambient_alpha = night
	lamp_power = float(cfg.get("lampPower", 1.0))
	lamp_range_tiles = float(cfg.get("lampRange", 7.0))
	lamp_strength0 = float(cfg.get("lampStrength0", 0.62))
	lamp_falloff = float(cfg.get("lampStrengthFalloff", 0.42))
	lamp_color = EmberLights.hex_color(str(cfg.get("lampColor", "#ffb056")))
	lamp_face_color = EmberLights.hex_color(str(cfg.get("lampFaceColor", "#ff9030")))
	env.environment = e
	_look.add_child(env)
	var moon := EmberLights.make_sun(
		az,
		el,
		moon_col,
		EmberLights.moon_energy(sun_intensity, fill_intensity, ambient_alpha, moon_energy_scale),
		moon_shadows,
	)
	EmberLights.tune_moon_shadows(
		moon,
		directional_shadow_distance,
		directional_shadow_splits,
		moon_shadow_bias,
		moon_shadow_normal_bias,
		moon_shadow_blur,
	)
	var center := Vector3(width * tile_size * 0.5, 12.0, height * tile_size * 0.5)
	moon.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), center + dir * 90.0)
	_look.add_child(moon)
	_own_tree(_look)


func _add_regions(map: Dictionary, tile_size: float) -> Dictionary:
	var by_id := {}
	var regions: Array = map.get("regions", [])
	for raw in regions:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = raw
		var rid := str(rec.get("id", ""))
		if rid.is_empty():
			continue
		var x := float(rec.get("x", 0))
		var y := float(rec.get("y", 0))
		var w := maxf(1.0, float(rec.get("w", 1)))
		var h := maxf(1.0, float(rec.get("h", 1)))
		var elev := float(rec.get("elev", 0))
		var area := EmberRegion.new()
		area.name = rid
		area.region_id = rid
		_apply_region_record(area, rec)
		area.position = Vector3(
			(x + w * 0.5) * tile_size,
			elev * tile_size + 2.0,
			(y + h * 0.5) * tile_size,
		)
		area.collision_layer = 4
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = Vector3(w * tile_size, 8.0, h * tile_size)
		shape.shape = box
		area.add_child(shape)
		_regions.add_child(area)
		area.refresh_chest_visual(tile_size)
		by_id[rid] = rec
	_own_tree(_regions)
	return by_id


func _apply_region_record(area: EmberRegion, rec: Dictionary) -> void:
	area.map_id = map_id
	area.kind = str(rec.get("kind", "trigger"))
	area.target_map_id = str(rec.get("targetMapId", ""))
	area.target_region_id = str(rec.get("targetRegionId", ""))
	area.bound_object_id = str(rec.get("boundObjectId", ""))
	area.script_id = str(rec.get("scriptId", ""))
	area.loot_ids = _region_loot_ids(rec.get("lootIds", []))
	area.closed_model_id = str(rec.get("closedModelId", "")).strip_edges()
	area.open_model_id = str(rec.get("openModelId", "")).strip_edges()
	area.model_offset_x = float(rec.get("modelOffsetX", 0.0))
	area.model_offset_y = float(rec.get("modelOffsetY", 0.0))
	area.model_rot = int(rec.get("modelRot", 0))
	area.model_scale = float(rec.get("modelScale", 1.0))
	area.model_elev = rec.get("modelElev", null)
	area.repeatable = bool(rec.get("repeatable", false))
	area.opened = bool(rec.get("opened", false))
	area.note = str(rec.get("note", ""))


func _region_loot_ids(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	var values: Array = raw if typeof(raw) == TYPE_ARRAY else str(raw).split(",")
	for value in values:
		var item_id := str(value).strip_edges()
		if not item_id.is_empty() and item_id not in result:
			result.append(item_id)
	return result


func _instantiate_prop(model_id: String, tile_size: float) -> EmberVoxelProp:
	var packed := EmberVoxelPrefab.ensure_saved(model_id, tile_size, _stats)
	if packed == null:
		return null
	var edit := PackedScene.GEN_EDIT_STATE_DISABLED
	if Engine.is_editor_hint():
		edit = PackedScene.GEN_EDIT_STATE_INSTANCE
	var prop := packed.instantiate(edit) as EmberVoxelProp
	if prop:
		prop.configure_voxel_scale(prop.voxels_per_block, tile_size)
	return prop


func _add_prop(place: Dictionary, tile_size: float, region_by_id: Dictionary) -> void:
	var model_id := str(place.get("modelId", ""))
	if model_id.is_empty():
		return
	var inst := _instantiate_prop(model_id, tile_size)
	if inst == null:
		return
	var prefab := EmberVoxelPrefab.load_json(model_id)
	var model := EmberVoxelPrefab.model_of(prefab)
	var blocks: Dictionary = model.get("sizeBlocks", {})
	var fw := maxf(1.0, float(blocks.get("x", 1))) * tile_size
	var fd := maxf(1.0, float(blocks.get("z", 1))) * tile_size
	var elev := float(place.get("elev", 0))
	var rot := int(place.get("rot", 0))
	inst.name = str(place.get("id", model_id))
	inst.placement_id = str(place.get("id", ""))
	inst.position = Vector3(
		float(place.get("x", 0)) * tile_size + fw * 0.5,
		elev * tile_size,
		float(place.get("y", 0)) * tile_size + fd * 0.5,
	)
	inst.rotation.y = float(rot) * PI * 0.5
	_tune_lamp(inst, place, model, tile_size)
	_maybe_interact(inst, place, region_by_id, tile_size)
	_props.add_child(inst)
	_own_root(inst)
	var extra := inst.get_node_or_null("Interact")
	if extra:
		_own_tree(extra)
	_stats.props += 1
	var omni := inst.get_node_or_null("Omni") as OmniLight3D
	if omni and omni.visible:
		_stats.omni += 1
		if omni.shadow_enabled:
			_stats.omni_shadow += 1


func _tune_lamp(inst: Node3D, place: Dictionary, model: Dictionary, tile_size: float) -> void:
	var omni := inst.get_node_or_null("Omni") as OmniLight3D
	if omni == null:
		return
	var casts := bool(place.get("emissiveCastsLight", model.get("emissiveCastsLight", false)))
	if not casts:
		omni.visible = false
		omni.shadow_enabled = false
		return
	var can_shadow := bool(place.get("emissiveLightShadows", model.get("emissiveLightShadows", false)))
	var range_tiles := float(place.get("emissiveLightRange", model.get("emissiveLightRange", 2.0)))
	if lamp_use_map_range and can_shadow:
		range_tiles = maxf(range_tiles, lamp_range_tiles)
	range_tiles *= lamp_range_scale
	var strength := float(place.get("emissiveStrength", model.get("emissiveStrength", 0.75)))
	omni.light_color = EmberLights.lamp_point_color(lamp_color, lamp_face_color)
	omni.omni_range = maxf(tile_size, range_tiles * tile_size)
	omni.light_energy = (
		EmberLights.omni_energy(lamp_strength0, lamp_falloff, lamp_power * lamp_energy_scale, ambient_alpha)
		* (0.7 + clampf(strength, 0.0, 1.2) * 0.4)
	)
	# Prefab defaults leave cubes on; ranker enables K nearest lanterns after import.
	omni.shadow_enabled = false


func _maybe_interact(
	inst: Node3D,
	place: Dictionary,
	region_by_id: Dictionary,
	tile_size: float,
) -> void:
	var raw: Variant = place.get("interactivity", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var inter: Dictionary = raw
	var kind := str(inter.get("kind", ""))
	if kind.is_empty():
		return
	var values := {
		"kind": kind,
		"trigger_id": str(inter.get("triggerId", "")),
		"shop_id": str(inter.get("shopId", "")),
		"script_id": str(inter.get("scriptId", "")),
		"quest_id": str(inter.get("questId", "")),
		"icon_id": str(inter.get("iconId", "")),
		"quest_status": str(inter.get("questStatus", "")),
	}
	if not str(values.trigger_id).is_empty() and region_by_id.has(values.trigger_id):
		var region: Dictionary = region_by_id[values.trigger_id]
		values.target_map_id = str(region.get("targetMapId", ""))
		values.target_region_id = str(region.get("targetRegionId", ""))
		values.note = str(region.get("note", ""))
	var area := EmberSceneAuthoring.make_interact(values, tile_size)
	inst.add_child(area)
