@tool
extends EditorPlugin
## Real native Inspector/Undo/save gate; disposable checkout only.
const PATH="res://tools/fixtures/object_pattern_scale.tscn"
const OUT="C:/Users/novos/Documents/Codex/2026-10-27/ember-object-pattern-scale"
var errors:Array[String]=[]
func _enter_tree()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("EDITOR_PATTERN_SCALE_FAIL ",label)
func frames(count:int)->void:
	for i in count:await get_tree().process_frame
func property_editor()->EditorProperty:
	for control in EditorInterface.get_inspector().find_children("*","EditorProperty",true,false):
		if control.get_edited_property()=="material_pattern_scale":return control
	return null
func run()->void:
	if not ProjectSettings.globalize_path("res://").contains("ember-rock-pilot-"):return
	await frames(25);EditorInterface.open_scene_from_path(PATH);await frames(15)
	var scene:=EditorInterface.get_edited_scene_root()
	if scene==null or not scene.has_node("Outcrop"):check(false,"fixture opened");get_tree().quit(1);return
	var prop:EmberVoxelProp=scene.get_node("Outcrop");prop.set_world_look(0)
	EditorInterface.set_main_screen_editor("3D");await frames(5)
	EditorInterface.get_selection().clear();EditorInterface.get_selection().add_node(prop);EditorInterface.inspect_object(prop)
	await frames(12)
	if EditorInterface.get_inspector().has_method("expand_all_folding"):EditorInterface.get_inspector().call("expand_all_folding")
	await frames(3)
	var control:=property_editor();check(control!=null,"native Inspector has local size control")
	if control==null:
		var fields:Array=[]
		for editor in EditorInterface.get_inspector().find_children("*","EditorProperty",true,false):fields.append([str(editor.get_edited_property()),editor.label])
		print("INSPECTOR_FIELDS ",JSON.stringify(fields))
		await RenderingServer.frame_post_draw
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUT.path_join("native-inspector-failed.png"))
		get_tree().quit(1);return
	check(control.label=="Размер рисунка","native Russian label")
	var spinner:SpinBox=control.get("value")
	spinner.value=2.0;await frames(3)
	check(prop.material_pattern_scale==2.0,"real Inspector signal applies size")
	var manager:=get_undo_redo();var history:=manager.get_history_undo_redo(manager.get_object_history_id(scene))
	history.undo();await frames(3);check(prop.material_pattern_scale==1.0 and spinner.value==1.0,"native Undo and widget refresh")
	history.redo();await frames(3);check(prop.material_pattern_scale==2.0 and spinner.value==2.0,"native Redo and widget refresh")
	check(EditorInterface.save_scene()==OK,"native scene Save")
	var saved:Node=ResourceLoader.load(PATH,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	check(saved.get_node("Outcrop").material_pattern_scale==2.0,"fresh scene reopen");saved.free()
	spinner.value=3.0;await frames(2)
	EditorInterface.reload_scene_from_path(PATH);await frames(15)
	scene=EditorInterface.get_edited_scene_root();prop=scene.get_node("Outcrop")
	check(prop.material_pattern_scale==2.0,"native reload discards unsaved size")
	prop.set_world_look(0);EditorInterface.set_main_screen_editor("3D");EditorInterface.inspect_object(prop);await frames(10)
	var material:ShaderMaterial=prop.get_node("Mesh").get_active_material(0)
	check(material.get_shader_parameter("solid_pattern_scale")==2.0,"reopen rebinds shader size")
	var viewport:=EditorInterface.get_editor_viewport_3d(0)
	var camera:=viewport.get_camera_3d()
	if camera!=null:camera.look_at_from_position(Vector3(100,70,120),Vector3(0,16,0))
	await frames(6);await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUT.path_join("native-inspector.png"))
	FileAccess.open(OUT.path_join("native.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors},"\t"))
	print("EDITOR_PATTERN_SCALE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));get_tree().quit(0 if errors.is_empty() else 1)
