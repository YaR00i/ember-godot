@tool
extends EditorPlugin
## Real World Editor session/save and native history on a disposable fixture.
const Fixture = preload("res://tools/test_compact_brush_material_depth.gd")
const DATA := "user://brush-cap-native.res"
const SCENE := "res://qa_brush_cap_native.tscn"
var failures: Array[String] = []
func _enter_tree() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message);printerr("FAIL native material cap: ",message)
func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
func settle(map: EmberMapLoader) -> void:
	var deadline := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await frames(1)
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		if projection != null and projection.pending_tile_count() == 0: return
	check(false,"terrain preparation timeout")
func run() -> void:
	if ProjectSettings.get_setting("application/config/name") != "Ember Rock Pilot" or not ProjectSettings.globalize_path("res://").contains("ember-rock-pilot-"):
		printerr("Material cap editor QA requires disposable pilot project.");return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"world editor missing");get_tree().quit(1);return
	var deadline := Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline: await frames(1)
	var source := Fixture.fixture(32)
	check(ResourceSaver.save(source,DATA) == OK,"save fixture baseline")
	source.take_over_path(DATA)
	var initial := Node3D.new();initial.name = "CapFixture"
	var map := EmberMapLoader.new();map.name = "Map";map.compact_terrain = source
	initial.add_child(map);map.owner = initial
	var packed := PackedScene.new();check(packed.pack(initial) == OK and ResourceSaver.save(packed,SCENE) == OK,"save disposable scene")
	initial.free()
	EditorInterface.open_scene_from_path(SCENE)
	await frames(5)
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == SCENE,"fixture opens")
	if scene == null: get_tree().quit(1);return
	map = scene.get_node("Map")
	await settle(map)
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	world.scene_changed(scene)
	var entry: Dictionary = world.sessions.open_map(map,scene)
	check(not entry.is_empty(),"existing session opens")
	if entry.is_empty(): get_tree().quit(1);return
	var baseline: Resource = entry.resource.working_copy()
	var brush: RefCounted = world._compact_brush
	brush.configure(entry,get_undo_redo(),scene)
	check(brush.begin("level",0.125,1,1,0,16,0,7,0,entry.resource.origin_y+8,"detail","square"),"native flatten begins")
	brush.stamp(Vector2i(16,16));brush.end()
	await settle(map)
	check(entry.resource.validation_errors().is_empty(),"native lowered draft validates")
	var edited: Resource = entry.resource.working_copy()
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();await settle(map)
	check(entry.resource.same_terrain_data(baseline) and map._visual_surface_projection.document.same_terrain_data(baseline),"native Undo restores all depth")
	history.redo();await settle(map)
	check(entry.resource.same_terrain_data(edited) and map._visual_surface_projection.document.same_terrain_data(edited),"native Redo restores depth and preview")
	var projection: EmberTerrainPilotProjection = map._visual_surface_projection
	var floor_hit := projection.floor_surface_sample(projection.to_global(Vector3(16.5,100,16.5)))
	check(floor_hit.get("solid",false) and is_equal_approx(floor_hit.position.y,projection.to_global(Vector3(16.5,entry.resource.origin_y+8,16.5)).y),"physical floor follows lowered height")
	check(projection.built_tile_count() > 0,"native geometry rebuilt")
	check(world.save_all(),"World Editor saves lowered terrain: "+str(world.sessions.error))
	var reopened = ResourceLoader.load(DATA,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened != null and reopened.validation_errors().is_empty() and reopened.same_terrain_data(edited),"fresh native save validates and retains depth")
	check(brush.begin("level",0.125,1,1,0,16,0,7,0,entry.resource.origin_y+2,"detail","square"),"native unsaved edit begins")
	brush.stamp(Vector2i(16,16));brush.end()
	world.sessions.discard(scene)
	await settle(map)
	check(entry.resource.same_terrain_data(edited) and map._visual_surface_projection.document.same_terrain_data(edited),"session discard restores saved depth")
	history.clear_history()
	EditorInterface.reload_scene_from_path(SCENE)
	await frames(5)
	scene = EditorInterface.get_edited_scene_root();map = scene.get_node("Map")
	await settle(map)
	check(map.compact_terrain.validation_errors().is_empty() and map.compact_terrain.same_terrain_data(edited),"scene reopen retains lowered height and depth")
	var report := {"pass":failures.is_empty(),"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"history":"EditorUndoRedoManager","manual":"mouse and visual material feel OPEN"}
	var file := FileAccess.open("user://brush-material-depth-editor-checks.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"))
	print("BRUSH_MATERIAL_DEPTH_EDITOR ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
