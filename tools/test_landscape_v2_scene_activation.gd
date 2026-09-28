extends SceneTree
## Reproduces the user-facing gate: opening the experimental scene in the 3D world editor.

const WorldEditor = preload("res://addons/ember_import/ember_world_editor.gd")
const SCENE := "res://scenes/landscape_v2_experimental.tscn"
const SURFACE := "res://content/world_surfaces/landscape_v2_experimental_surface.tres"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	var scene := packed.instantiate() as Node3D if packed != null else null
	if scene == null:
		printerr("FAIL Landscape V2 activation: scene failed to load")
		quit(1)
		return
	root.add_child(scene)
	var history := UndoRedo.new()
	var editor := WorldEditor.new()
	root.add_child(editor)
	editor.configure(null, history)
	var toolbar: Control = editor.build_toolbar()
	var sidebar: Control = editor.build_sidebar()
	root.add_child(toolbar)
	root.add_child(sidebar)
	editor.active = true
	editor.scene_changed(scene)
	var map := scene.get_node("Map") as EmberMapLoader
	var source := map.resolved_visual_surface() if map != null else null
	var attached := source != null and source.resource_path == SURFACE
	var owner_matches: bool = source != null and str(source.material.get("semanticOwner", "")) == map.map_id
	var opened := not editor.entry.is_empty() and str(editor.entry.get("path", "")) == SURFACE
	var switch_visible := is_instance_valid(editor._experiment_toggle) and editor._experiment_toggle.visible
	var projection: Node3D = map._visual_surface_projection if map != null else null
	var visual_started: bool = is_instance_valid(projection) and (projection.rendered_chunk_count() > 0 or projection.pending_chunk_count() > 0)
	var deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(projection) and projection.rendered_chunk_count() == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	var rendered: bool = is_instance_valid(projection) and projection.rendered_chunk_count() > 0
	print("ACTIVATION attached=", attached, " owner_matches=", owner_matches, " opened=", opened, " switch_visible=", switch_visible, " visual_started=", visual_started, " rendered=", rendered, " scene_path=", scene.scene_file_path, " resource_path=", source.resource_path if source != null else "<none>", " entry_path=", editor.entry.get("path", "<none>"))
	if not attached or not owner_matches or not opened or not switch_visible or not visual_started or not rendered:
		printerr("FAIL Landscape V2 activation: land and experimental switch must be available in the main world-editor path")
		editor.free()
		toolbar.free()
		sidebar.free()
		history.free()
		scene.free()
		quit(1)
		return
	print("PASS Landscape V2 activation: copied Surface opens and experimental switch is visible")
	editor.free()
	toolbar.free()
	sidebar.free()
	history.free()
	scene.free()
	quit()
