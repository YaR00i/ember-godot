extends SceneTree
## Real World Look controls on a disposable copy of the authored Sun/Environment.
## Native Forward+; no authored map, terrain, material, or editor cache writes.
const PanelScript = preload("res://addons/ember_import/ember_world_look_panel.gd")
var failures: Array[String] = []
func _init() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
 if not ok:failures.append(label);printerr("SHADOW_CONTROLS FAIL ",label)
func run() -> void:
 if DisplayServer.get_name()=="headless":printerr("Native Forward+ required");quit(2);return
 var authored: Node=load("res://scenes/landscape_compact.tscn").instantiate()
 var original_map: EmberMapLoader=authored.get_node("Map")
 var source_sun: DirectionalLight3D=authored.get_node("Map/Look/Sun")
 var scene := Node3D.new();scene.name="ShadowControlsFixture"
 var map := EmberMapLoader.new();map.name="Map";map.imported_tile_size=original_map.imported_tile_size;map.directional_shadow_size=original_map.directional_shadow_size;map.directional_shadow_filter=original_map.directional_shadow_filter;map.use_taa=original_map.use_taa
 scene.add_child(map);map.owner=scene
 var look := Node3D.new();look.name="Look";map.add_child(look);look.owner=scene
 var sun := source_sun.duplicate() as DirectionalLight3D;look.add_child(sun);sun.owner=scene
 var environment := WorldEnvironment.new();environment.name="WorldEnvironment";environment.environment=authored.get_node("Map/Look/WorldEnvironment").environment.duplicate();look.add_child(environment);environment.owner=scene
 var initial_resolution := map.directional_shadow_size
 var initial_cascades := sun.directional_shadow_mode
 var initial_taa := map.use_taa
 var initial_distance := sun.directional_shadow_max_distance
 var initial_snapshot := EmberLights.sun_look_snapshot(sun)
 var initial_pancake := sun.directional_shadow_pancake_size
 authored.free()
 root.add_child(scene)
 var panel := PanelScript.new();root.add_child(panel);var history := UndoRedo.new();panel.set_target(scene,map,history)
 check(is_equal_approx(panel._sliders.sun_shadow_distance.value,initial_distance/map.imported_tile_size),"existing Sun distance displayed in metres")
 check(sun.directional_shadow_max_distance==initial_distance and sun.directional_shadow_pancake_size==initial_pancake,"opening panel preserves authored values")
 check(panel._light_rows.is_ancestor_of(panel._sliders.shadow_softness) and panel._light_rows.is_ancestor_of(panel._choices.shadow_filter) and panel._taa_switch.get_parent()==panel._light_rows and not panel._shadow_advanced.is_ancestor_of(panel._choices.shadow_filter),"softness/filter/TAA are together outside Advanced")
 check(panel._taa_switch.button_pressed==initial_taa and root.use_taa==initial_taa,"opening panel displays saved TAA and applies runtime viewport")
 var taa_actions:=history.get_history_count()
 panel._taa_switch.button_pressed=not initial_taa
 check(map.use_taa==not initial_taa and root.use_taa==not initial_taa and history.get_history_count()==taa_actions+1,"checkbox changes Map and viewport in one action")
 history.undo();check(map.use_taa==initial_taa and root.use_taa==initial_taa,"TAA Undo reaches viewport")
 history.redo();check(map.use_taa==not initial_taa and root.use_taa==not initial_taa,"TAA Redo reaches viewport")
 panel._taa_switch.button_pressed=true
 var preview:=SubViewport.new();preview.size=Vector2i(64,64);root.add_child(preview);map.apply_viewport_quality(preview)
 check(preview.use_taa==map.use_taa and preview.msaa_3d==map.msaa_3d,"shared viewport binding reaches SubViewport")
 preview.free()
 check(not panel._shadow_advanced.visible,"advanced settings start collapsed")
 panel._shadow_advanced_toggle.button_pressed=true;check(panel._shadow_advanced.visible,"native disclosure opens advanced controls")
 var count := history.get_history_count()
 panel._drag_started("sun_shadow_distance");panel._sliders.sun_shadow_distance.value=60;panel._sliders.sun_shadow_distance.value=80;panel._drag_ended(true,"sun_shadow_distance")
 check(history.get_history_count()==count+1 and is_equal_approx(sun.directional_shadow_max_distance,80*map.imported_tile_size),"one drag changes Sun, one history action, metres converted")
 history.undo();check(sun.directional_shadow_max_distance==initial_distance,"Undo restores original physical distance")
 history.redo();check(is_equal_approx(sun.directional_shadow_max_distance,80*map.imported_tile_size),"Redo restores distance")
 panel._sliders.sun_shadow_fade.value=50;check(is_equal_approx(sun.directional_shadow_fade_start,0.5),"fade percent converts to native fraction")
 var chosen_cascades:=2 if initial_cascades!=2 else 1
 panel._choices.sun_shadow_mode.item_selected.emit(chosen_cascades);check(sun.directional_shadow_mode==chosen_cascades,"choice changes actual Sun cascades")
 history.undo();check(sun.directional_shadow_mode==initial_cascades,"cascade Undo")
 history.redo()
 panel._choices.sun_shadow_mode.item_selected.emit(1)
 panel._choices.shadow_resolution.item_selected.emit(1);check(map.directional_shadow_size==2048,"resolution item ID selects existing Map quality field")
 history.undo();check(map.directional_shadow_size==initial_resolution,"resolution Undo")
 history.redo()
 panel._choices.shadow_filter.item_selected.emit(3);check(map.directional_shadow_filter==3,"filter routes to existing quality owner")
 panel._choices.shadow_filter.item_selected.emit(0);check(map.directional_shadow_filter==0 and sun.light_angular_distance==initial_snapshot.shadow_softness,"hard filter keeps remembered Sun softness")
 panel._choices.shadow_filter.item_selected.emit(5);check(map.directional_shadow_filter==5 and map.use_taa,"Ultra and TAA remain independently selectable")
 panel._sliders.sun_shadow_bias.value=0.02;panel._sliders.sun_shadow_normal_bias.value=1.25;panel._sliders.sun_shadow_pancake.value=3.5;panel._sliders.sun_shadow_blur.value=0.5
 check(is_equal_approx(sun.shadow_bias,0.02) and is_equal_approx(sun.shadow_normal_bias,1.25),"advanced biases reach actual Sun")
 check(is_equal_approx(sun.directional_shadow_pancake_size,3.5*map.imported_tile_size),"pancake uses map metres")
 check(EmberLights.sun_look_snapshot(sun)==initial_snapshot,"existing runtime water/sun snapshot contract unchanged")
 var packed := PackedScene.new();check(packed.pack(scene)==OK,"pack existing owners")
 DirAccess.make_dir_recursive_absolute("user://ember-tests")
 var path := "user://ember-tests/world-shadow-controls.tscn"
 check(ResourceSaver.save(packed,path)==OK,"save disposable copy")
 var reopened: Node=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
 root.add_child(reopened)
 var saved_sun: DirectionalLight3D=reopened.get_node("Map/Look/Sun")
 check(is_equal_approx(saved_sun.directional_shadow_max_distance,80*map.imported_tile_size) and is_equal_approx(saved_sun.directional_shadow_fade_start,0.5),"runtime-ready reopened scene retains distance/fade")
 check(saved_sun.directional_shadow_mode==DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and is_equal_approx(saved_sun.shadow_bias,0.02) and is_equal_approx(saved_sun.shadow_normal_bias,1.25),"reopen retains cascades/bias")
 check(is_equal_approx(saved_sun.directional_shadow_pancake_size,3.5*map.imported_tile_size) and is_equal_approx(saved_sun.shadow_blur,0.5),"reopen retains advanced depth/blur")
 check(reopened.get_node("Map").use_taa and root.use_taa,"fresh reopen applies saved TAA")
 check(reopened.get_node("Map").directional_shadow_size==2048 and reopened.get_node("Map").directional_shadow_filter==5,"reopen applies existing Map quality values")
 panel._taa_switch.button_pressed=false
 panel._sliders.sun_shadow_distance.value=12
 panel.set_target(reopened,reopened.get_node("Map"),history)
 check(panel._taa_switch.button_pressed and root.use_taa,"discard and retarget restore saved TAA")
 check(is_equal_approx(panel._sliders.sun_shadow_distance.value,80),"discard unsaved distance by retargeting saved copy")
 # History still targets the original Sun, using that Sun's map scale.
 reopened.get_node("Map").imported_tile_size=8
 history.undo();check(is_equal_approx(sun.directional_shadow_max_distance,80*map.imported_tile_size),"Undo after switching maps retains original target's scale")
 check(is_equal_approx(saved_sun.directional_shadow_max_distance,80*map.imported_tile_size),"old history never writes reopened scene")
 panel.set_target(null,null,null);check(panel._taa_switch.disabled,"closed owner disables TAA control");check(not panel._sliders.sun_shadow_distance.editable and panel._choices.shadow_resolution.disabled,"closed scene disables stale controls")
 history.clear_history();history.free();panel.free();reopened.free();scene.free()
 print("WORLD_SHADOW_CONTROLS ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"manual_gate":"author mouse/fly-camera visual acceptance OPEN"}))
 quit(0 if failures.is_empty() else 1)
