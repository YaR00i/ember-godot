extends SceneTree
## Existing World Look panel and actual exported Water owner, copied settings.
const PanelScript=preload("res://addons/ember_import/ember_world_look_panel.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);printerr("CREST_CONTROLS FAIL ",label)
func run() -> void:
	var authored: Node=load("res://scenes/landscape_compact.tscn").instantiate()
	var scene:=Node3D.new();scene.name="WaterControlsFixture"
	var map:=EmberMapLoader.new();map.name="Map";map.hydrate_legacy_regions=false
	scene.add_child(map);map.owner=scene
	var look:=Node3D.new();look.name="Look";map.add_child(look);look.owner=scene
	for name in ["Sun","WorldEnvironment"]:
		var node: Node=authored.get_node("Map/Look/"+name).duplicate()
		look.add_child(node);node.owner=scene
	var water: Node=authored.get_node("PlanarReflection").duplicate()
	scene.add_child(water);water.owner=scene;water.study_controls=false
	check(water.sea_crest_foam_strength==0.55 and water.sea_crest_foam_amount==0.35,"main map enables the approved sparse crest preset")
	check(water.sea_foam_trail_strength==0.52 and water.sea_foam_trail_lifetime==2.9,"main map retains richer trails")
	authored.free();root.add_child(scene);water.set_process(false)
	var scroll:=ScrollContainer.new();root.add_child(scroll);scroll.position=Vector2(12,12);scroll.size=Vector2(540,760)
	var panel:=PanelScript.new();scroll.add_child(panel);panel.custom_minimum_size.x=510
	var history:=UndoRedo.new();panel.set_target(scene,map,history)
	for key in ["sea_crest_foam_strength","sea_crest_foam_amount"]:
		check(panel._sliders.has(key) and panel._water_rows.is_ancestor_of(panel._sliders[key]),"native water panel contains "+key)
	var before: Dictionary=water.water_settings_snapshot()
	var actions:=history.get_history_count()
	panel._drag_started("sea_crest_foam_strength")
	panel._sliders.sea_crest_foam_strength.value=0.2;panel._sliders.sea_crest_foam_strength.value=0.4
	panel._drag_ended(true,"sea_crest_foam_strength")
	check(history.get_history_count()==actions+1 and is_equal_approx(water.sea_crest_foam_strength,0.4),"one native drag makes one history action")
	history.undo();check(water.water_settings_snapshot()==before,"Undo restores all water settings")
	history.redo();check(is_equal_approx(water.sea_crest_foam_strength,0.4),"Redo restores crest strength")
	panel._sliders.sea_crest_foam_amount.value=0.42
	var invalid: Dictionary=water.water_settings_snapshot();invalid.sea_crest_foam_amount=2.0;invalid.sea_crest_foam_strength=0.9
	var snapshot: Dictionary=water.water_settings_snapshot()
	var response: Dictionary=panel.apply_runtime_water(scene.scene_file_path,scene.get_path_to(water),invalid)
	check(not response.ok and water.water_settings_snapshot()==snapshot,"runtime snapshot validation is atomic for new fields")
	var valid:=snapshot.duplicate();valid.sea_crest_foam_strength=0.36;valid.sea_foam_trail_lifetime=3.0
	response=panel.apply_runtime_water(scene.scene_file_path,scene.get_path_to(water),valid)
	check(response.ok and water.water_settings_snapshot()==valid,"existing F6 snapshot imports new fields")
	history.undo();check(water.water_settings_snapshot()==snapshot,"bulk snapshot Undo")
	history.redo();check(water.water_settings_snapshot()==valid,"bulk snapshot Redo")
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack copied settings")
	var directory: String="user://ember-tests/crest-controls-"+str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path:=directory+"/settings.tscn"
	check(ResourceSaver.save(packed,path)==OK,"save temporary settings copy")
	var reopened: Node=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.add_child(reopened);var saved: Node=reopened.get_node("PlanarReflection");saved.set_process(false)
	check(saved.water_settings_snapshot()==valid,"fresh reopen retains all water settings")
	panel._sliders.sea_crest_foam_amount.value=0.85
	panel.set_target(reopened,reopened.get_node("Map"),history)
	check(is_equal_approx(panel._sliders.sea_crest_foam_amount.value,0.42) and saved.water_settings_snapshot()==valid,"discard restores saved crest settings")
	# Expand the existing water tab/group for a native UI capture.
	for tabs in panel.find_children("*","TabContainer",true,false):
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i).contains("Вода"):tabs.current_tab=i
	for button in panel._water_rows.find_children("*","Button",true,false):
		if button.toggle_mode:button.button_pressed=button.text.begins_with("Море и берег")
	for frame in 3:await process_frame
	scroll.ensure_control_visible(panel._readouts.sea_crest_foam_amount)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/controls.png")
	print("CREST_CONTROLS ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size()," path=",path," ui=",ProjectSettings.globalize_path(directory+"/controls.png"))
	scroll.free();history.free();reopened.free();scene.free()
	quit(0 if failures.is_empty() else 1)
