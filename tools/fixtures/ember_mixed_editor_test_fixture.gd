extends RefCounted
## Only generated native Resources inside the guarded disposable mixed-test project.
const Content = preload("res://tools/fixtures/ember_interaction_test_fixture.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const A := "editor_fixture_a"
const B := "editor_fixture_b"
const C := "editor_fixture_destination"
const BLOCK := "editor_fixture_block"
const LAMP := "editor_fixture_lamp"
static var _source_hashes: Dictionary = {}

static func prepare(tree: SceneTree) -> bool:
	if not FileAccess.file_exists("res://.mixed-editor-test-sandbox"):
		Content.Maps.prepare(tree, "user://ember-tests/mixed-refused-%d" % OS.get_process_id())
		printerr("REFUSED: run tools/run_mixed_editor_tests.py")
		return false
	var state := Content.prepare(tree)
	if state.refused or state.error != OK: return false
	for id in [BLOCK, LAMP]:
		var model: EmberVoxelModelResource = Shapes.build("block", Vector3i(16, 16, 16), 16, Color.BROWN, id, id).source
		if id == LAMP:
			model.emissive_casts_light = true
			model.emissive.resize(model.voxels.size())
			model.emissive.fill(255)
			model.emissive_light_range = 2.0
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EmberVoxelCatalog.NATIVE_DIR))
		if ResourceSaver.save(model, EmberVoxelCatalog.native_path(id)) != OK: return false
	# Catalog labels are deliberate synthetic UI fixtures, not restored old story content.
	var dialogue := EmberDialogueCatalog.document(Content.GUARD)
	dialogue.nameRu = "Тестовый собеседник"
	if EmberDialogueCatalog.write_native(dialogue) != OK: return false
	var quest := ResourceLoader.load(EmberQuestCatalog.native_path(Content.QUEST), "", ResourceLoader.CACHE_MODE_IGNORE) as EmberQuestResource
	quest.definition.titleRu = "Тестовое задание"
	if ResourceSaver.save(quest, EmberQuestCatalog.native_path(Content.QUEST)) != OK: return false
	var action := EmberActionCatalog.document(Content.NOTICE)
	action.nameRu = "События задания · тест"
	if EmberActionCatalog.write_native(action) != OK: return false
	if not _graph_content(state.directory): return false
	for id in [A, B, C, "landscape_compact"]:
		if not _save_scene(id): return false
	var non_map := PackedScene.new()
	var plain := Node3D.new()
	non_map.pack(plain)
	plain.free()
	if ResourceSaver.save(non_map, "res://scenes/combat_lab.tscn") != OK: return false
	_source_hashes.clear()
	for path in [EmberMapTransition.scene_path(A), EmberMapTransition.scene_path(B), EmberMapTransition.scene_path(C), EmberVoxelCatalog.native_path(BLOCK), EmberVoxelCatalog.native_path(LAMP)]:
		_source_hashes[path] = FileAccess.get_sha256(path)
	return true

static func verify_sources(errors: Array[String]) -> void:
	for path in _source_hashes:
		if FileAccess.get_sha256(path) != _source_hashes[path]: errors.append("test mutated native fixture source " + path)

static func _graph_content(directory: String) -> bool:
	var branch := {"id": Content.BRANCH, "nameRu": "Тестовая развилка", "startStepId": "ask", "steps": [
		{"id": "ask", "type": "choice", "options": [{"labelRu": "Первый путь", "next": "agent_r"}, {"labelRu": "Второй путь", "next": "walk_r"}]},
		{"id": "agent_r", "type": "dialogue", "textRu": "Первый ответ", "next": "end"},
		{"id": "walk_r", "type": "dialogue", "textRu": "Второй ответ", "next": "end"}, {"id": "end", "type": "end"}]}
	branch.editorLayout = {"ask": {"x": 0.0, "y": 0.0}, "agent_r": {"x": 200.0, "y": 0.0}, "walk_r": {"x": 200.0, "y": 200.0}}
	for step in branch.steps:
		if step.type == "choice":
			for index in step.options.size(): step.options[index].id = "option_%d" % index
	if EmberDialogueCatalog.write_native(branch) != OK: return false
	var assets := EmberVnAssets.new()
	for name in ["editor_background", "expression_a", "expression_b"]:
		var path := directory.path_join(name + ".png")
		var image := Image.create(16, 24, false, Image.FORMAT_RGBA8)
		image.fill(Color.CORAL)
		if image.save_png(path) != OK: return false
		var imported: Dictionary = assets.import_background(ProjectSettings.globalize_path(path)) if name == "editor_background" else assets.import_portrait(ProjectSettings.globalize_path(path), "editor_speaker")
		if not imported.get("ok", false): return false
	var vn := {"id": "editor_vn", "nameRu": "Тестовая VN", "defaultBgArtId": "editor_background", "startStepId": "intro", "steps": [
		{"id": "intro", "type": "dialogue", "textRu": "Тестовый кадр", "speaker": "editor_speaker", "portraitKey": "expression_a", "portraitSide": "right", "next": "choice", "actors": [{"speaker": "editor_speaker", "portraitKey": "expression_a", "x": 50.0, "lockY": true, "floorY": 90.0}]},
		{"id": "choice", "type": "choice", "options": [{"labelRu": "A", "next": "brave_reply"}, {"labelRu": "B", "next": "fluster_reply"}]},
		{"id": "brave_reply", "type": "dialogue", "textRu": "Ответ A", "next": "end"},
		{"id": "fluster_reply", "type": "dialogue", "textRu": "Ответ B", "next": "end"}, {"id": "end", "type": "end"}]}
	for step in vn.steps:
		if step.type == "dialogue": step.nameRu = "Тестовый персонаж"
		if step.type == "choice":
			for index in step.options.size(): step.options[index].id = "option_%d" % index
	return EmberDialogueCatalog.write_native(vn) == OK

static func physics_surface(blocks := 24) -> EmberVoxelModelResource:
	var surface := EmberVoxelModelResource.new()
	surface.model_id = "editor_surface_fixture"
	surface.size_blocks = Vector3i(blocks, 1, blocks)
	surface.height_voxels = 32
	surface.voxels_per_block = 16
	surface.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN])
	surface.material = {"preset": "world_surface", "semanticOwner": B}
	var size := surface.grid_size()
	surface.voxels.resize(size.x * size.y * size.z)
	for z in size.z:
		for y in 8:
			for x in size.x: surface.voxels[x + z * size.x + y * size.x * size.z] = 1
	return surface

static func prepare_profile(tree: SceneTree) -> bool:
	if not prepare(tree): return false
	var surface := physics_surface()
	surface.model_id = "editor_profile_surface"
	var size := surface.grid_size()
	surface.surface_fill_levels.resize(size.x * size.z)
	surface.surface_fill_materials.resize(size.x * size.z)
	surface.surface_fill_palette.resize(size.x * size.z)
	for z in range(size.z / 2, size.z):
		for x in size.x:
			surface.surface_fill_levels[x + z * size.x] = 12
			surface.surface_fill_materials[x + z * size.x] = 1
	var path := "res://content/world_surfaces/editor_profile_surface.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if ResourceSaver.save(surface, path) != OK: return false
	var packed := ResourceLoader.load(EmberMapTransition.scene_path(A), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var scene := packed.instantiate()
	var map := scene.get_node("Map") as EmberMapLoader
	map.map_id = "editor_context_fixture"
	map.visual_surface = physics_surface(4)
	map.visual_surface.material.semanticOwner = map.map_id
	var context := PackedScene.new()
	var error := context.pack(scene)
	scene.free()
	return error == OK and ResourceSaver.save(context, "res://scenes/editor_context_fixture.tscn") == OK

static func prepare_rebuild(tree: SceneTree) -> bool:
	if not prepare(tree): return false
	var model: EmberVoxelModelResource = Shapes.build("block", Vector3i(16, 16, 16), 16, Color.BROWN, "editor_rebuild_fixture", "Rebuild fixture").source
	model.transparency.resize(model.voxels.size())
	for index in range(model.voxels.size() / 2): model.transparency[index] = 128
	model.emissive_casts_light = true
	model.emissive.resize(model.voxels.size())
	model.emissive.fill(255)
	if ResourceSaver.save(model, EmberVoxelCatalog.native_path(model.model_id)) != OK: return false
	var prop := EmberVoxelPrefab.instantiate(model.model_id, 16.0, {})
	if prop == null: return false
	var scene := Node3D.new()
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = "editor_rebuild_map"
	scene.add_child(map)
	var props := Node3D.new()
	props.name = "Props"
	map.add_child(props)
	prop.name = "RebuildProp"
	prop.placement_id = "rebuild_prop"
	props.add_child(prop)
	Content.Maps._set_owner(scene, scene)
	var packed := PackedScene.new()
	var error := packed.pack(scene)
	scene.free()
	return error == OK and ResourceSaver.save(packed, "res://scenes/editor_rebuild_map.tscn") == OK

static func _save_scene(id: String) -> bool:
	var scene := Node3D.new()
	scene.name = id
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = id
	map.authored_size_blocks = Vector2i(4, 4)
	map.hydrate_legacy_regions = false
	scene.add_child(map)
	var props := Node3D.new()
	props.name = "Props"
	map.add_child(props)
	var definitions := {
		"talk_npc": {"kind": "talk", "script_id": Content.GUARD},
		"shop_kiosk": {"kind": "shop", "shop_id": Content.SHOP, "script_id": Content.INTRO},
		"quest_sign": {"kind": "quest_marker", "quest_id": Content.QUEST, "script_id": Content.NOTICE, "quest_status": "available", "icon_id": "quest"},
		"quest_active": {"kind": "quest_marker", "quest_id": Content.QUEST, "script_id": Content.NOTICE, "quest_status": "active", "icon_id": "quest"},
		"destination_door": {"kind": "door", "target_map_id": C, "target_region_id": "missing_entry"},
		"roundtrip_door": {"kind": "door", "target_map_id": C, "target_region_id": "entry"},
		"plain_prop": {}, "lamp": {},
	}
	for name in definitions:
		var prop := EmberVoxelPrefab.make_preview_instance(LAMP if name == "lamp" else BLOCK, 16.0)
		if prop == null:
			scene.free()
			return false
		prop.name = name
		prop.placement_id = name
		props.add_child(prop)
		if not (definitions[name] as Dictionary).is_empty(): prop.add_child(EmberSceneAuthoring.make_interact(definitions[name], 16.0))
	var regions := Node3D.new()
	regions.name = "Regions"
	map.add_child(regions)
	for region_id in ["entry", "notice", "landscape_compact_start"]:
		var region := EmberRegion.new()
		region.name = region_id
		region.region_id = region_id
		region.map_id = id
		region.kind = "player_start" if region_id == "entry" else "trigger"
		region.position = Vector3(16, 0, 16)
		regions.add_child(region)
	Content.Maps._set_owner(scene, scene)
	var packed := PackedScene.new()
	var error := packed.pack(scene)
	scene.free()
	return error == OK and ResourceSaver.save(packed, EmberMapTransition.scene_path(id)) == OK
