@tool
extends EditorPlugin
## Enable only in the guarded disposable native Forward+ editor project.
const PanelScript = preload("res://addons/ember_import/ember_world_look_panel.gd")
var failures: Array[String] = []
func _enter_tree() -> void: run.call_deferred()
func frames(count: int) -> void:
 for i in count: await get_tree().process_frame
func check(ok: bool, message: String) -> void:
 if not ok: failures.append(message);printerr("EDITOR_SHADOW_TAA FAIL ",message)
func views_are(value: bool) -> bool:
 for index in 4:
  var viewport:=EditorInterface.get_editor_viewport_3d(index)
  if viewport==null or viewport.use_taa!=value:return false
 return true
func run() -> void:
 if not ProjectSettings.globalize_path("res://").replace("\\","/").contains("ember-shadow-grain/editor-qa/"):
  printerr("Disposable editor-qa required");return
 await frames(15)
 EditorInterface.open_scene_from_path("res://fixture.tscn")
 var deadline:=Time.get_ticks_msec()+30000
 while (EditorInterface.get_edited_scene_root()==null or not EditorInterface.get_edited_scene_root().has_node("Map")) and Time.get_ticks_msec()<deadline:await frames(1)
 var scene:=EditorInterface.get_edited_scene_root()
 check(scene!=null and scene.has_node("Map"),"native editor opened fixture")
 if scene==null or not scene.has_node("Map"):get_tree().quit(1);return
 var map: EmberMapLoader=scene.get_node("Map")
 check(views_are(false),"editor starts from project TAA default")
 var history:=get_undo_redo();var panel:=PanelScript.new();add_control_to_dock(DOCK_SLOT_RIGHT_UL,panel)
 panel.set_target(scene,map,history)
 check(views_are(true),"saved Map TAA reaches all four actual editor 3D viewports")
 panel._taa_switch.button_pressed=false
 check(not map.use_taa and views_are(false),"checkbox updates actual editor viewports")
 history.get_history_undo_redo(history.get_object_history_id(scene)).undo();check(map.use_taa and views_are(true),"Undo updates all actual editor viewports")
 history.get_history_undo_redo(history.get_object_history_id(scene)).redo();check(not map.use_taa and views_are(false),"Redo updates all actual editor viewports")
 panel._taa_switch.button_pressed=true
 check(EditorInterface.save_scene()==OK,"save fixture through native editor")
 panel.set_target(null,null,null)
 check(views_are(false),"closing Map restores editor baseline")
 EditorInterface.reload_scene_from_path("res://fixture.tscn")
 await frames(15)
 scene=EditorInterface.get_edited_scene_root();map=scene.get_node("Map")
 panel.set_target(scene,map,history)
 check(map.use_taa and views_are(true),"native editor reload retains saved Map TAA")
 panel._choices.shadow_filter.item_selected.emit(0)
 check(map.directional_shadow_filter==0,"hard shadows remain selectable in native panel")
 panel._choices.shadow_filter.item_selected.emit(5)
 check(map.directional_shadow_filter==5 and views_are(true),"soft Ultra and TAA coexist")
 await frames(12);await RenderingServer.frame_post_draw
 EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://editor-taa-controls.png")
 remove_control_from_docks(panel);panel.free()
 check(views_are(false),"panel release restores all four editor viewports")
 history.clear_history(history.get_object_history_id(scene),false)
 print("EDITOR_SHADOW_TAA ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"actual_editor_viewports":4,"history":"EditorUndoRedoManager","manual_gate":"author mouse and fly-camera OPEN"}))
 await frames(20)
 get_tree().quit(0 if failures.is_empty() else 1)
