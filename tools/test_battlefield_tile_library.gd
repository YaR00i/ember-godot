extends SceneTree
## D2.1g gate: one authored MeshLibrary is shared by editor preview and arenas.

const Contract := preload("res://scripts/prototypes/ember_battlefield_tile_library.gd")
const PreviewPanel := preload("res://addons/ember_import/ember_battlefield_tile_library_panel.gd")
const BASE_SCENE := preload("res://scenes/prototypes/combat_grid_3d_world.tscn")
const E2_SCENE := preload("res://scenes/combat/arenas/colored_crossing.tscn")
const E3_SCENE := preload("res://scenes/combat/arenas/thaw_keeper.tscn")
const LAB_SCENE := preload("res://scenes/combat_lab.tscn")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var errors: Array[String] = []
	var library := Contract.default_library()
	for error in Contract.validation_errors(library):
		errors.append(error)
	if library == null or library.resource_path != Contract.RESOURCE_PATH:
		errors.append("default Battlefield MeshLibrary did not load from its authored .tres")
	else:
		_check_materials(library, errors)
		_check_preview(library, errors)
	for packed in [BASE_SCENE, E2_SCENE, E3_SCENE, LAB_SCENE]:
		_check_scene(packed, errors)
	if not errors.is_empty():
		printerr("FAIL battlefield tile library")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS battlefield tile library")
	print("  five semantic IDs share one authored MeshLibrary with mesh/collision")
	print("  Inspector preview and all arena/lab scenes use the same visual Resource")
	quit(0)


func _check_materials(library: MeshLibrary, errors: Array[String]) -> void:
	for raw_item_id in Contract.EXPECTED_NAMES:
		var item_id := int(raw_item_id)
		var mesh := library.get_item_mesh(item_id) as PrimitiveMesh
		var material := mesh.material as ShaderMaterial if mesh != null else null
		if material == null:
			errors.append("tile %d does not use the shared stylized shader" % item_id)
			continue
		if int(material.get_shader_parameter("pattern_mode")) != item_id:
			errors.append("tile %d lost its distinct visual pattern" % item_id)


func _check_preview(library: MeshLibrary, errors: Array[String]) -> void:
	var panel := PreviewPanel.new() as EmberBattlefieldTileLibraryPanel
	panel.setup(library)
	root.add_child(panel)
	var preview_meshes := panel.find_children("BattlefieldTilePreview_*", "MeshInstance3D", true, false)
	if preview_meshes.size() != 5:
		errors.append("MeshLibrary Inspector preview did not stage all five tiles")
	var diagnostics := panel.find_child("BattlefieldTileLibraryDiagnostics", true, false) as Label
	if diagnostics == null or not diagnostics.text.begins_with("✓"):
		errors.append("MeshLibrary Inspector preview lost its contract diagnostics")
	panel.free()


func _check_scene(packed: PackedScene, errors: Array[String]) -> void:
	var scene := packed.instantiate() as EmberCombatGrid3DWorld
	if scene == null:
		errors.append("battle scene no longer instantiates as EmberCombatGrid3DWorld")
		return
	var grid_map := scene.get_node_or_null("CombatGridMap") as GridMap
	if grid_map == null or grid_map.mesh_library == null:
		errors.append("battle scene has no authored visual MeshLibrary")
	elif grid_map.mesh_library.resource_path != Contract.RESOURCE_PATH:
		errors.append("battle scene owns a local MeshLibrary instead of the shared .tres")
	for error in scene.tile_library_validation_errors():
		errors.append(error)
	scene.free()
