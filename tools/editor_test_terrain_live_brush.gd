@tool
extends EditorPlugin
## Native regression: finished sculpt steps must become visible before release.
## Install as a temporary plugin ONLY in the disposable pilot checkout.
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Surface=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const DATA="user://terrain-live-brush.res"
const SCENE="res://qa_terrain_live_brush.tscn"
var failures: Array[String]=[]
var cases: Array=[]
var map: EmberMapLoader
var scene: Node
var world: Node
var entry: Dictionary
var projection: EmberTerrainPilotProjection
func _enter_tree() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error("TERRAIN_LIVE "+message)
func frames(count: int) -> void:
	for i in count:await get_tree().process_frame
func settle() -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await frames(1)
		if projection.pending_tile_count()==0 and projection._look_pending.is_empty():return
	check(false,"surface settle timeout")
func stroke(mode: String) -> void:
	var brush: RefCounted=world._compact_brush
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	var history_before:=history.get_history_count()
	var initial_vertices: Dictionary={}
	for key: Vector2i in projection._tiles:
		initial_vertices[key]=projection._look_meshes[key][0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var published_before:=int(projection.profile_snapshot().get("editor_shape_published",0))
	var first_visible_ms:=-1.0
	var started:=Time.get_ticks_usec()
	check(brush.begin(mode,3.31,4,1,0,16,0,7,0,-99999,"detail","circle"),"stroke begins")
	for i in 32:
		brush.stamp(Vector2i(24+i*2,68));await frames(1)
		if first_visible_ms<0.0 and int(projection.profile_snapshot().get("editor_shape_published",0))>published_before:
			for key: Vector2i in initial_vertices:
				# Smooth can change the footprint's edges while the centre is flat.
				if projection._look_meshes[key][0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]!=initial_vertices[key]:
					first_visible_ms=(Time.get_ticks_usec()-started)/1000.0;break
	var published_held:=int(projection.profile_snapshot().get("editor_shape_published",0))-published_before
	check(first_visible_ms>0 and published_held>=2,mode+": surface changes repeatedly while pointer is still held")
	check(history.get_history_count()==history_before,"live display does not add Undo actions")
	brush.end();await settle()
	check(history.get_history_count()==history_before+1,"one completed stroke is one Undo")
	cases.append({"mode":mode,"first_visible_ms":first_visible_ms,"published_while_held":published_held})
func check_published_surface() -> void:
	# Source equality alone misses a late worker repainting the viewport after cancel.
	for key: Vector2i in projection._tiles:
		var bounds:=Rect2i(key*64,Vector2i(64,64))
		var expected: Dictionary=Surface.build(entry.resource,bounds,true)
		var tile: Node3D=projection._tiles[key]
		var mesh: ArrayMesh=projection._look_meshes[key][0]
		check(mesh.surface_get_arrays(0)==expected.terrain.surface_get_arrays(0),"published mesh follows restored Source")
		check((tile.get_node("GroundPhysics/Shape").shape as ConcavePolygonShape3D).get_faces()==expected.collision_faces,"physics follows published mesh")
		check(projection._smooth_fields[key]==expected.smooth_field,"floor/picking follows published mesh")
func run() -> void:
	if ProjectSettings.get_setting("application/config/name")!="Ember Rock Pilot" or not ProjectSettings.globalize_path("res://").contains("ember-rock-pilot-"):
		printerr("Live brush QA requires a disposable pilot checkout.");return
	Engine.max_fps=60;OS.low_processor_usage_mode=false
	await frames(20)
	var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	if importer==null:check(false,"world editor missing");get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline:await frames(1)
	var source:=Fixture.base()
	check(ResourceSaver.save(source,DATA)==OK,"fixture baseline saves")
	source.take_over_path(DATA)
	var root:=Node3D.new();root.name="TerrainLiveFixture"
	var initial_map:=EmberMapLoader.new();initial_map.name="Map"
	initial_map.compact_ground_style=1;initial_map.compact_smooth_material_blend=true
	initial_map.compact_terrain=source;initial_map.world_look=2
	root.add_child(initial_map);initial_map.owner=root
	var packed:=PackedScene.new()
	check(packed.pack(root)==OK and ResourceSaver.save(packed,SCENE)==OK,"fixture scene saves")
	root.free()
	if SCENE in EditorInterface.get_open_scenes():EditorInterface.reload_scene_from_path(SCENE)
	EditorInterface.open_scene_from_path(SCENE);await frames(5)
	scene=EditorInterface.get_edited_scene_root();map=scene.get_node("Map")
	projection=map._visual_surface_projection;await settle()
	world=importer._world_editor;world.enabled.button_pressed=true;world.scene_changed(scene)
	entry=world.sessions.open_map(map,scene)
	if entry.is_empty():check(false,"fixture session opens: "+world.sessions.error);get_tree().quit(1);return
	world._compact_brush.configure(entry,get_undo_redo(),scene);await settle()
	var baseline: Resource=entry.resource.working_copy()
	await stroke("raise");await stroke("smooth")
	var edited: Resource=entry.resource.working_copy()
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();history.undo();await settle()
	check(entry.resource.same_terrain_data(baseline),"Undo restores both strokes")
	history.redo();history.redo();await settle()
	check(entry.resource.same_terrain_data(edited),"Redo restores both strokes")
	var brush: RefCounted=world._compact_brush
	for mode in ["raise","lower"]:
		brush.begin(mode,3.31,4,1,0,16,0,7,0,-99999,"detail","circle");brush.stamp(Vector2i(64,68))
		await frames(2);brush.cancel()
	await settle()
	check(entry.resource.same_terrain_data(edited) and projection.document.same_terrain_data(edited),"cancel and immediate new stroke cannot revive old data")
	check_published_surface()
	check(world.save_all(),"World Editor saves fixture")
	var fresh=ResourceLoader.load(DATA,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(fresh.same_terrain_data(edited) and fresh.validation_errors().is_empty(),"fresh saved fixture validates")
	brush.begin("raise",3.31,4,1,0,16,0,7,0,-99999,"detail","circle");brush.stamp(Vector2i(64,68));brush.end()
	await frames(2);world.sessions.discard(scene);await settle()
	check(entry.resource.same_terrain_data(edited) and projection.document.same_terrain_data(edited),"discard cancels pending publication")
	check_published_surface()
	EditorInterface.reload_scene_from_path(SCENE);await frames(5)
	scene=EditorInterface.get_edited_scene_root();map=scene.get_node("Map");projection=map._visual_surface_projection
	await settle()
	check(map.compact_terrain.same_terrain_data(edited),"reopened scene retains saved terrain")
	var report:={"pass":failures.is_empty(),"failures":failures,"cases":cases,"renderer":RenderingServer.get_current_rendering_method()}
	var file:=FileAccess.open("user://terrain-live-brush.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("TERRAIN_LIVE ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
