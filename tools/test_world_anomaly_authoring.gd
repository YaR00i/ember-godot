extends SceneTree
## Targeted scene/editor contract only. Never saves the authored map.
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); printerr("FAIL ", message)

func run() -> void:
	var scene := Node3D.new()
	var map := EmberMapLoader.new(); map.name = "Map"; scene.add_child(map); map.owner = scene
	var sphere = load("res://scripts/ember_world_anomaly_3d.gd").new()
	sphere.name = "WorldAnomaly"; map.add_child(sphere); sphere.owner = scene
	var panel = load("res://addons/ember_import/ember_world_look_panel.gd").new()
	root.add_child(panel); panel.hide()
	var history := UndoRedo.new(); panel.set_target(scene, map, history)
	check(sphere.validation_errors().is_empty(), "sphere validates in map")
	check(panel._target("anomaly_radius") == sphere, "native panel discovers sphere")
	panel._commit("anomaly_x", 0.0, 5.0, false)
	check(sphere.position.x == 80.0, "centre edits use map metres")
	history.undo(); check(sphere.position == Vector3.ZERO, "centre Undo")
	history.redo(); check(sphere.position == Vector3(80,0,0), "centre Redo")
	panel._commit("anomaly_y", 0.0, 1.5, false)
	panel._commit("anomaly_z", 0.0, 11.0, false)
	panel._choices.anomaly_look.item_selected.emit(1)
	check(sphere.inner_look == 2, "voxel option resolves enum id")
	history.undo(); check(sphere.inner_look == 1, "look Undo")
	history.redo(); check(sphere.inner_look == 2, "look Redo")
	panel._commit("anomaly_radius",4.5,3.0,false)
	panel._commit("anomaly_feather",0.45,0.65,false)
	panel._choices.anomaly_enabled.item_selected.emit(0)
	check(not sphere.enabled, "disable sphere through panel")
	history.undo(); check(sphere.enabled, "enable Undo")
	var packed := PackedScene.new(); check(packed.pack(scene) == OK, "pack scene-owned sphere")
	var path := "user://world-anomaly-authoring.tscn"
	check(ResourceSaver.save(packed,path) == OK, "save isolated scene")
	var fresh = (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved = fresh.get_node("Map/WorldAnomaly")
	check(saved.position == Vector3(80,24,176) and saved.inner_look == 2 and saved.radius_m == 3.0 and saved.feather_m == 0.65 and saved.enabled, "all sphere settings survive fresh reopen")
	panel._commit("anomaly_radius",3.0,8.0,false)
	check(saved.radius_m == 3.0, "discard leaves saved sphere intact")
	sphere.radius_m = -5.0; sphere.feather_m = INF; sphere.inner_look = 9
	check(sphere.radius_m > 0 and is_finite(sphere.feather_m) and sphere.inner_look == 2, "invalid parameters are bounded")
	print("WORLD_ANOMALY_AUTHORING ",JSON.stringify({"pass":failures.is_empty(),"failures":failures,"manual":"mouse and gameplay feel OPEN"}))
	history.clear_history(); history.free(); panel.free(); fresh.free(); scene.free()
	quit(0 if failures.is_empty() else 1)
