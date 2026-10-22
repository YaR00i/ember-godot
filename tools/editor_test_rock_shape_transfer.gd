@tool
extends EditorPlugin
const Session=preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Store=preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Workspace=preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const OUTPUT="C:/Users/novos/Documents/Codex/2026-10-17/ember-rock-shape-transfer"
var errors: Array[String]=[]
func _enter_tree() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);printerr("FAIL ",message)
func frames(count:=10) -> void:
	for i in count:await get_tree().process_frame
func run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-tree-grass-light/project"):return
	Engine.max_fps=30;await frames(30)
	EditorInterface.open_scene_from_path("res://scenes/compact_environment_material_review.tscn")
	await frames(50)
	var scene:=EditorInterface.get_edited_scene_root()
	check(scene!=null and scene.scene_file_path=="res://scenes/compact_environment_material_review.tscn","ordinary scene opens in actual editor")
	if scene==null:get_tree().quit(1);return
	var prop: EmberVoxelProp=scene.get_node("Map/Props/PaintedRockGroup")
	var faces: PackedVector3Array=prop.get_node("Mesh").mesh.get_faces()
	check(prop.get_node("Collision/Shape").shape.get_faces()==faces,"editor visual/physical surface matches")
	EditorInterface.set_main_screen_editor("3D");EditorInterface.edit_node(prop)
	await frames(10)
	var viewport:=EditorInterface.get_editor_viewport_3d(0)
	var camera:=viewport.get_camera_3d()
	camera.global_position=Vector3(10,8,16);camera.look_at(Vector3(4.5,1.1,4.7));camera.fov=42;camera.far=250
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	RenderingServer.camera_set_transform(camera.get_camera_rid(),camera.get_camera_transform())
	await frames(10);RenderingServer.force_draw(false)
	check(viewport.get_texture().get_image().save_png(OUTPUT+"/editor-world.png")==OK,"actual editor viewport capture")
	var source: EmberVoxelModelResource=load("res://content/voxel_models/vox_painted_rock_group.tres")
	var directory:="user://rock-native-editor-%d"%Time.get_ticks_usec()
	check(Store.install_prepared_asset(source,EmberVoxelPrefab.prepare_resource(source),directory.path_join("sources/"+source.model_id+".tres"),directory.path_join("prefabs/"+source.model_id+".tscn")).ok,"disposable editor asset")
	var undo:=get_undo_redo();var edit:=Session.new()
	edit.source_directory=directory.path_join("sources");edit.prefab_directory=directory.path_join("prefabs")
	# Normal independent editing does not touch instances in other restored tabs.
	check(edit.open(prop,scene,undo,false),"existing editor session opens new form: "+edit.error)
	var canvas:=Workspace.new();EditorInterface.get_base_control().add_child(canvas);canvas.open_object(edit)
	canvas._resource.solid_surface.parts[0][0]=canvas._resource.solid_surface.parts[0][0].rotated(Vector3.FORWARD,0.02)
	check(canvas.has_unsaved_changes(),"published guides participate in ordinary dirty state")
	check(canvas.save_changes(),"existing Canvas Save: "+edit.error)
	var changed: PackedVector3Array=prop.get_node("Mesh").mesh.get_faces()
	check(changed!=faces and prop.get_node("Collision/Shape").shape.get_faces()==changed,"Canvas commits real form and collision together")
	var history:=undo.get_history_undo_redo(undo.get_object_history_id(scene))
	history.undo();check(prop.get_node("Mesh").mesh.get_faces()==faces,"actual editor Undo")
	history.redo();check(prop.get_node("Mesh").mesh.get_faces()==changed,"actual editor Redo")
	var before_discard: Dictionary=EmberVoxelModelResource.copy_authoring_value(canvas._resource.solid_surface)
	canvas._resource.solid_surface.parts[1][0]=Vector3.UP
	check(canvas.has_unsaved_changes(),"native draft changes")
	canvas.discard_changes();check(canvas._resource.solid_surface==before_discard and not canvas.has_unsaved_changes(),"native Discard restores private guide arrays")
	canvas.free();history.undo();history.clear_history()
	check(EditorInterface.save_scene()==OK,"ordinary editor scene save in disposable project")
	EditorInterface.inspect_object(null);EditorInterface.get_selection().clear()
	await frames(20)
	while EditorInterface.get_resource_filesystem().is_scanning():await frames(1)
	var result:=FileAccess.open(OUTPUT+"/editor.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"engine_is_editor":Engine.is_editor_hint(),"scene":"res://scenes/compact_environment_material_review.tscn","undo_redo":true,"discard":true,"save":true},"\t"));result.close()
	EditorInterface.inspect_object(null)
	print("ROCK_SHAPE_EDITOR ","PASS" if errors.is_empty() else errors)
	if errors.is_empty():get_tree().call_deferred("quit",0)
	else:get_tree().quit(1)
