@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const Fixture=preload("res://scripts/prototypes/ember_terrain_shape_fixture.gd")
var output: String
func stroke(world: Node) -> void:
	world.camera=_camera
	var point:=_camera.get_viewport().get_visible_rect().size*0.5
	var pick: Dictionary=world._pick_compact(point)
	check(not pick.is_empty(),"real editor rule pick")
	var mesh: int=world.map._visual_surface_projection._tiles[Vector2i.ZERO].get_node("Ground").mesh.get_instance_id()
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.button_mask=MOUSE_BUTTON_MASK_LEFT;event.position=point
	world._forward_compact(event)
	check(world._compact_brush.active(),"native press starts rule brush")
	check(world.entry.resource.surface_rules.is_empty(),"native press leaves source unmodified")
	check(world.map._visual_surface_projection._tiles[Vector2i.ZERO].get_node("Ground").mesh.get_instance_id()==mesh,"native press doesn't remesh")
	await frames(3)
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false;event.position=point
	world._forward_compact(event);await ready_tiles(world.map._visual_surface_projection)
	check(not world._compact_brush.active(),"native release commits")
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-shape-brush"):get_tree().quit(1);return
	output=OS.get_cmdline_user_args()[0]
	var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	check(importer!=null,"existing Ember editor plugin")
	if importer==null:get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+60000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline:await frames(1)
	check(importer._editor_preparation._complete,"editor prepared")
	var directory:="res://qa_shape/";DirAccess.make_dir_recursive_absolute(directory)
	var source_path:=directory+"source_%d.res"%OS.get_process_id();var scene_path:=directory+"scene_%d.tscn"%OS.get_process_id()
	check(ResourceSaver.save(Fixture.source(),source_path)==OK,"private source")
	var fixture: Node3D=load("res://scenes/compact_terrain_shape_study.tscn").instantiate()
	fixture.get_node("Map").compact_terrain=ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var packed:=PackedScene.new();packed.pack(fixture);check(ResourceSaver.save(packed,scene_path)==OK,"private scene");fixture.free()
	EditorInterface.get_resource_filesystem().update_file(source_path);EditorInterface.get_resource_filesystem().update_file(scene_path)
	await frames(6);EditorInterface.open_scene_from_path(scene_path)
	deadline=Time.get_ticks_msec()+60000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=scene_path) and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(12);EditorInterface.set_main_screen_editor("3D")
	var scene:=EditorInterface.get_edited_scene_root();var map:=scene.get_node("Map") as EmberMapLoader
	var world: Node=importer._world_editor;world.enabled.button_pressed=true;world.scene_changed(scene)
	world.category.select(0);world._category_changed(0);world.tools.select(2);world._tool_changed()
	check(world._mode()=="smooth" and world.compact_shape_action.selected==0,"common sculpt stays default")
	world.compact_shape_action.select(2);world.compact_shape_action.item_selected.emit(2)
	check(world._shape_rule_active() and world._compact_edit_scale()=="detail","explicit smooth-view scope")
	await frames(3)
	check(world.compact_shape_action.is_visible_in_tree() and world.compact_shape_action.get_global_rect().position.y<700,"rule choice visible in main parameter panel")
	world.brush_shape.select(1);world.brush_shape.item_selected.emit(1);world.radius.value=0.7
	world.compact_shape_strength.value=1.0
	var projection:=map._visual_surface_projection;await ready_tiles(projection)
	var entry: Dictionary=world.sessions.open_map(map,scene);var before=entry.resource.working_copy()
	_camera=Camera3D.new();EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	var aim: Dictionary=map.surface_floor_sample(Vector3(2,8,1.1875))
	_camera.look_at_from_position(Vector3(9,7,9),aim.position);_camera.far=200;_camera.make_current();await frames(8)
	await stroke(world)
	var after=entry.resource.working_copy()
	check(not after.surface_rules.is_empty() and after.heights==before.heights and after.top_materials==before.top_materials,"native rule preserves common heights/paint")
	var history=importer.get_undo_redo().get_history_undo_redo(importer.get_undo_redo().get_object_history_id(scene))
	history.undo();await ready_tiles(projection);check(entry.resource.same_terrain_data(before),"real editor Undo")
	history.redo();await ready_tiles(projection);check(entry.resource.same_terrain_data(after),"real editor Redo")
	world.look_panel._choices.compact_ground_style.item_selected.emit(0);await ready_tiles(projection)
	check(projection.ground_style==0 and entry.resource.same_terrain_data(after),"voxel view keeps same source rules")
	history.undo();await ready_tiles(projection)
	check(world.sessions.save_all(scene),"native save: "+world.sessions.error)
	var reopened=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_terrain.same_terrain_data(after),"native reopen exact");reopened.free()
	# A private second stroke then Discard follows the established session owner.
	world.compact_shape_action.select(3);world.compact_shape_action.item_selected.emit(3)
	world._compact_brush.begin("shape_clear",1.0,1,1,0,16,0,1,0);world._compact_brush.stamp(Vector2i(32,19));world._compact_brush.end()
	await ready_tiles(projection);world.sessions.discard(scene);await ready_tiles(projection)
	check(world.sessions.open_map(map,scene).resource.same_terrain_data(after),"native Discard")
	world.compact_shape_action.select(2);world.compact_shape_action.item_selected.emit(2)
	await frames(10);await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("editor.png"))
	_camera.queue_free();await frames(10)
	var filesystem:=EditorInterface.get_resource_filesystem()
	filesystem.update_file(source_path);filesystem.update_file(scene_path)
	filesystem.scan()
	deadline=Time.get_ticks_msec()+15000
	while filesystem.is_scanning() and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(120)
	print("SURFACE_RULES_EDITOR_SCAN_IDLE ",not filesystem.is_scanning())
	print("SURFACE_RULES_EDITOR ","PASS" if errors.is_empty() else errors)
	get_tree().quit(0 if errors.is_empty() else 1)
