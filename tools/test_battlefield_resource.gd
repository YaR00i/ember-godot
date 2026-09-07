extends SceneTree
## D2.1 battlefield Resource gate: authored data, scene links and round-trip.

const E2_PATH := "res://content/combat/battlefields/colored_crossing.tres"
const E3_PATH := "res://content/combat/battlefields/thaw_keeper.tres"
const E2_SCENE := preload("res://scenes/combat/arenas/colored_crossing.tscn")
const E3_SCENE := preload("res://scenes/combat/arenas/thaw_keeper.tscn")
const BattlefieldPanel := preload("res://addons/ember_import/ember_battlefield_inspector_panel.gd")
const BattlefieldActions := preload("res://addons/ember_import/ember_battlefield_editor_actions.gd")
const BattlefieldPainter := preload("res://addons/ember_import/ember_battlefield_3d_painter.gd")
const SculptModel := preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const BattleSurfaceProjection := preload("res://scripts/ember_battle_surface_projection.gd")
const SurfaceInspectorPanel := preload("res://addons/ember_import/ember_voxel_surface_inspector_panel.gd")


func _init() -> void:
	var errors: Array[String] = []
	var e2 := load(E2_PATH) as EmberBattlefieldResource
	var e3 := load(E3_PATH) as EmberBattlefieldResource
	_check_field(e2, "colored_crossing", errors)
	_check_field(e3, "thaw_keeper", errors)
	if e2 != null:
		var grid := e2.to_grid_dictionary()
		if (grid.get("cells", {}) as Dictionary).size() != 35:
			errors.append("E2 Resource did not produce 35 canonical cells")
		if not bool(e2.cell_definition(Vector2i(3, 0)).get("blocked", false)):
			errors.append("E2 Resource lost its authored blocker")
		if int(e2.cell_definition(Vector2i(0, 0)).get("elevation", 0)) < 1:
			errors.append("E2 Resource lost its authored raised cell")
		var panel := BattlefieldPanel.new() as EmberBattlefieldInspectorPanel
		panel.setup(e2)
		if panel.find_child("BattlefieldCellPreview", true, false).get_child_count() != 35:
			errors.append("battlefield Inspector preview does not show every cell")
		var diagnostics := panel.find_child("BattlefieldDiagnostics", true, false) as Label
		if diagnostics == null or not diagnostics.text.begins_with("✓"):
			errors.append("battlefield Inspector preview lost validation feedback")
		var brush := panel.find_child("BattlefieldBrush", true, false) as OptionButton
		if brush == null or brush.item_count != 10:
			errors.append("battlefield Inspector lost its ten guided paint/deployment tools")
		elif brush.get_item_icon(0) == null or brush.get_item_icon(9) == null:
			errors.append("battlefield Inspector palette lost its visual swatches")
		if panel.find_child("BattlefieldResizeControls", true, false) == null:
			errors.append("battlefield Inspector lost safe resize controls")
		if panel.find_child("BattlefieldResizePreview", true, false) == null:
			errors.append("battlefield Inspector lost resize loss preview")
		if panel.find_child("BattlefieldWaterSyncControls", true, false) == null:
			errors.append("battlefield Inspector lost Visual Surface to Wet controls")
		if panel.find_child("BattlefieldWaterSyncPreview", true, false) == null:
			errors.append("battlefield Inspector lost water coverage preview")
		if panel.find_child("BattlefieldHeightSyncApply", true, false) == null:
			errors.append("battlefield Inspector lost Surface height sync controls")
		if panel.find_child("BattlefieldHeightSyncPreview", true, false) == null:
			errors.append("battlefield Inspector lost Surface height preview")
		panel.free()
		_test_cell_selections(e2, errors)
		_test_3d_toolbar(errors)
		_test_paint_undo(e2, errors)
		_test_resize_undo(e2, errors)
		_test_surface_handoff(e2, errors)
		_test_surface_water_sync(e2, errors)
		_test_surface_height_sync(e2, errors)
		_test_surface_inspector_navigation(e2, errors)
		_test_embedded_surface_externalization(e2, errors)
		_test_runtime_deployments(e2, errors)
		_round_trip(e2, errors)
	_check_scene_field(E2_SCENE, "colored_crossing", errors)
	_check_scene_field(E3_SCENE, "thaw_keeper", errors)
	if not errors.is_empty():
		printerr("FAIL battlefield Resource")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS battlefield Resource")
	print("  E2/E3 arena scenes reference validated semantic .tres fields")
	print("  save/reopen preserves cells, terrain, focus and party/enemy deployment")
	print("  resize/remap previews loss and commits one atomic Undo action")
	quit(0)


func _check_field(
	field: EmberBattlefieldResource,
	expected_id: String,
	errors: Array[String],
) -> void:
	if field == null:
		errors.append("could not load battlefield %s" % expected_id)
		return
	if field.field_id != expected_id:
		errors.append("battlefield ID mismatch for %s" % expected_id)
	for error in field.validation_errors():
		errors.append("%s: %s" % [expected_id, error])


func _check_scene_field(packed: PackedScene, expected_id: String, errors: Array[String]) -> void:
	var arena := packed.instantiate() as EmberCombatGrid3DWorld
	if arena == null or arena.battlefield == null:
		errors.append("arena %s has no Battlefield Resource" % expected_id)
	elif arena.battlefield.field_id != expected_id:
		errors.append("arena %s references %s" % [expected_id, arena.battlefield.field_id])
	if arena != null:
		arena.free()


func _round_trip(field: EmberBattlefieldResource, errors: Array[String]) -> void:
	var copy := field.duplicate(true) as EmberBattlefieldResource
	var path := "user://battlefield_resource_roundtrip.tres"
	var result := ResourceSaver.save(copy, path)
	if result != OK:
		errors.append("battlefield Resource could not be saved")
		return
	var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberBattlefieldResource
	if reopened == null or reopened.content_signature() != field.content_signature():
		errors.append("battlefield Resource changed after save/reopen")
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


func _test_paint_undo(field: EmberBattlefieldResource, errors: Array[String]) -> void:
	var editable := field.duplicate(true) as EmberBattlefieldResource
	var undo := UndoRedo.new()
	var actions := BattlefieldActions.new() as EmberBattlefieldEditorActions
	actions.configure(undo)
	var cells: Array[Vector2i] = [Vector2i(0, 4), Vector2i(2, 4), Vector2i(4, 4)]
	var before: Array[Dictionary] = []
	for cell in cells:
		before.append(editable.cell_definition(cell))
	if not actions.paint_cells(editable, cells, EmberBattlefieldResource.PaintTool.WET, "river"):
		errors.append("paint palette rejected a valid three-cell stroke")
		return
	for cell in cells:
		var painted := editable.cell_definition(cell)
		if "wet" not in painted.get("tags", []) or str(painted.get("group", "")) != "river":
			errors.append("3D stroke did not write terrain + guided group to %s" % cell)
	undo.undo()
	for index in cells.size():
		if editable.cell_definition(cells[index]) != before[index]:
			errors.append("one Ctrl+Z did not restore the full three-cell stroke")
	undo.redo()
	for cell in cells:
		if "wet" not in editable.cell_definition(cell).get("tags", []):
			errors.append("one Ctrl+Shift+Z did not restore the full three-cell stroke")
	if not actions.paint_cell(editable, cells[0], EmberBattlefieldResource.PaintTool.HEIGHT_UP):
		errors.append("height paint tool rejected a valid edit")
	elif int(editable.cell_definition(cells[0]).get("elevation", 0)) != 1:
		errors.append("height paint tool did not update canonical elevation")
	if not actions.paint_cell(editable, Vector2i(2, 4), EmberBattlefieldResource.PaintTool.FOCUS):
		errors.append("focus paint tool rejected a valid edit")
	elif editable.focus_cell != Vector2i(2, 4):
		errors.append("focus paint tool did not move the canonical Geo focus")
	var party_count := editable.party_deployment_cells.size()
	if not actions.paint_cell(editable, Vector2i(4, 4), EmberBattlefieldResource.PaintTool.PARTY_DEPLOYMENT):
		errors.append("party deployment tool rejected a free canonical cell")
	elif editable.party_deployment_cells.size() != party_count + 1:
		errors.append("party deployment tool did not append an ordered start cell")
	undo.undo()
	if editable.party_deployment_cells.size() != party_count:
		errors.append("one Ctrl+Z did not restore deployment toggle")
	if actions.paint_cell(editable, editable.focus_cell, EmberBattlefieldResource.PaintTool.BLOCKED):
		errors.append("blocked tool was allowed to erase the canonical focus")
	undo.clear_history()
	undo.free()


func _test_cell_selections(field: EmberBattlefieldResource, errors: Array[String]) -> void:
	var rectangle := field.rectangle_cells(Vector2i(1, 1), Vector2i(3, 2))
	if rectangle.size() != 6 or Vector2i(1, 1) not in rectangle or Vector2i(3, 2) not in rectangle:
		errors.append("rectangle authoring selection did not cover its six canonical cells")
	var fixture := field.duplicate(true) as EmberBattlefieldResource
	fixture.width = 3
	fixture.height = 2
	fixture.terrain_kinds = PackedByteArray([1, 1, 1, 1, 1, 1])
	fixture.elevations = PackedInt32Array([0, 0, 1, 0, 0, 1])
	fixture.blocked = PackedByteArray([0, 0, 0, 0, 0, 0])
	fixture.groups = PackedStringArray(["tide", "tide", "tide", "tide", "tide", "tide"])
	fixture.focus_cell = Vector2i.ZERO
	fixture.party_deployment_cells = [Vector2i(0, 1)]
	fixture.enemy_deployment_cells = [Vector2i(1, 1)]
	var fill := fixture.connected_matching_cells(Vector2i.ZERO)
	if fill.size() != 4:
		errors.append("guided fill expected four connected matching fixture cells, got %d" % fill.size())
	if Vector2i(2, 0) in fill or Vector2i(2, 1) in fill:
		errors.append("guided fill crossed into a different gameplay elevation")


func _test_3d_toolbar(errors: Array[String]) -> void:
	var painter := BattlefieldPainter.new() as EmberBattlefield3DPainter
	painter.configure(null, null, null)
	var toolbar := painter.build_toolbar()
	var toggle := toolbar.find_child("Battlefield3DPaintToggle", true, false) as Button
	var brush := toolbar.find_child("Battlefield3DBrush", true, false) as OptionButton
	var shape := toolbar.find_child("Battlefield3DShape", true, false) as OptionButton
	var more_menu := toolbar.find_child("Battlefield3DMoreMenu", true, false) as MenuButton
	if toggle == null or brush == null or brush.item_count != 10:
		errors.append("native 3D paint toolbar lost its toggle or ten brushes")
	elif brush.get_item_icon(0) == null or brush.get_item_icon(9) == null:
		errors.append("native 3D paint toolbar lost its visual brush swatches")
	if shape == null or shape.item_count != 3:
		errors.append("native 3D paint toolbar lost brush/rectangle/fill modes")
	else:
		painter.call("_select_tool", EmberBattlefieldResource.PaintTool.FOCUS)
		if not shape.disabled or shape.selected != EmberBattlefield3DPainter.PaintShape.BRUSH:
			errors.append("Focus tool did not lock authoring to one-cell brush mode")
	if more_menu == null or more_menu.get_popup().item_count != 4:
		errors.append("native 3D paint toolbar lost its compact secondary-actions menu")
	if toolbar.visible:
		errors.append("battlefield toolbar remains visible without a Battlefield scene context")
	if brush != null and brush.visible:
		errors.append("inactive Battlefield tool settings still consume viewport header space")
	var line: Array = painter.call("_cells_on_line", Vector2i(0, 0), Vector2i(4, 2))
	if line.size() != 5 or line.front() != Vector2i.ZERO or line.back() != Vector2i(4, 2):
		errors.append("fast 3D brush movement no longer fills a continuous cell line")
	painter.shutdown()
	toolbar.free()


func _test_surface_handoff(field: EmberBattlefieldResource, errors: Array[String]) -> void:
	var surface := SculptModel.make_battlefield_surface(
		field.field_id,
		field.display_name,
		field.width,
		field.height,
		field.elevations,
		field.terrain_kinds,
		field.blocked,
	)
	if surface == null:
		errors.append("battlefield could not seed a visual Surface Resource")
		return
	if surface.size_blocks != Vector3i(field.width, 1, field.height):
		errors.append("battlefield Surface does not map one visual block per semantic cell")
	if surface.normalized_density() != 32 or surface.voxels.is_empty():
		errors.append("battlefield Surface lost its 32-art-voxel authored source")
	var editable := field.duplicate(true) as EmberBattlefieldResource
	editable.visual_surface = null
	var undo := UndoRedo.new()
	var actions := BattlefieldActions.new() as EmberBattlefieldEditorActions
	actions.configure(undo)
	if not actions.assign_visual_surface(editable, surface):
		errors.append("battlefield visual Surface assignment was rejected")
	elif not editable.visual_surface_matches_field():
		errors.append("assigned battlefield visual Surface no longer matches field dimensions")
	else:
		undo.undo()
		if editable.visual_surface != null:
			errors.append("one Ctrl+Z did not detach the battlefield visual Surface")
		undo.redo()
		if editable.visual_surface != surface:
			errors.append("one Ctrl+Shift+Z did not restore the battlefield visual Surface")
	undo.clear_history()
	undo.free()
	var surface_path := "user://battlefield_external_surface_test.tres"
	var field_path := "user://battlefield_external_reference_test.tres"
	if ResourceSaver.save(surface, surface_path, ResourceSaver.FLAG_CHANGE_PATH) != OK:
		errors.append("battlefield Surface could not be saved as an external Resource")
	else:
		surface.take_over_path(surface_path)
		editable.visual_surface = surface
		if ResourceSaver.save(editable, field_path) != OK:
			errors.append("battlefield with external Surface reference could not be saved")
		else:
			var reopened := ResourceLoader.load(
				field_path, "", ResourceLoader.CACHE_MODE_REPLACE
			) as EmberBattlefieldResource
			if (
				reopened == null or reopened.visual_surface == null
				or reopened.visual_surface.resource_path != surface_path
			):
				errors.append("battlefield save embedded a duplicate Surface instead of an external reference")
	for path in [surface_path, field_path]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _test_surface_water_sync(field: EmberBattlefieldResource, errors: Array[String]) -> void:
	var editable := field.duplicate(true) as EmberBattlefieldResource
	editable.terrain_kinds.fill(EmberBattlefieldResource.TerrainKind.NEUTRAL)
	editable.groups.fill("")
	editable.terrain_kinds[1] = EmberBattlefieldResource.TerrainKind.WET
	editable.groups[1] = "old_manual_water"
	var surface := SculptModel.make_battlefield_surface(
		field.field_id,
		field.display_name,
		field.width,
		field.height,
		field.elevations,
		field.terrain_kinds,
		field.blocked,
	)
	_mark_surface_block_water(surface, Vector2i.ZERO)
	editable.visual_surface = surface
	var preview := editable.surface_water_sync_preview(0.25)
	var wet_cells: Array = preview.get("wet_cells", [])
	var changed_cells: Array = preview.get("changed_cells", [])
	if not bool(preview.get("ok", false)) or wet_cells != [Vector2i.ZERO]:
		errors.append("visual water coverage did not resolve to its single battle cell")
		return
	if changed_cells.size() != 2:
		errors.append("water sync preview did not report one added and one stale Wet cell")
	var undo := UndoRedo.new()
	var actions := BattlefieldActions.new() as EmberBattlefieldEditorActions
	actions.configure(undo)
	if not actions.sync_surface_water(editable, 0.25):
		errors.append("water sync action rejected a valid Visual Surface preview")
	else:
		var wet := editable.cell_definition(Vector2i.ZERO)
		var dry := editable.cell_definition(Vector2i(1, 0))
		if "wet" not in wet.get("tags", []) or str(wet.get("group", "")) != "tide":
			errors.append("water sync did not write canonical Wet + tide semantics")
		if "wet" in dry.get("tags", []) or not str(dry.get("group", "")).is_empty():
			errors.append("water sync did not clear a stale dry Wet cell")
		undo.undo()
		if "wet" in editable.cell_definition(Vector2i.ZERO).get("tags", []):
			errors.append("water sync Undo did not restore the dry cell")
		if "wet" not in editable.cell_definition(Vector2i(1, 0)).get("tags", []):
			errors.append("water sync Undo did not restore the prior manual Wet cell")
		undo.redo()
		if "wet" not in editable.cell_definition(Vector2i.ZERO).get("tags", []):
			errors.append("water sync Redo did not restore derived Wet semantics")
	undo.clear_history()
	undo.free()


func _test_surface_height_sync(field: EmberBattlefieldResource, errors: Array[String]) -> void:
	var expected := field.elevations.duplicate()
	var surface := SculptModel.make_battlefield_surface(
		field.field_id,
		field.display_name,
		field.width,
		field.height,
		expected,
		field.terrain_kinds,
		field.blocked,
	)
	# One decorative spike must not raise an entire tactical cell: projection
	# reads the median floor, not the highest art voxel.
	var surface_size := surface.grid_size()
	var spike_cell := Vector2i.ZERO
	var base_top := (
		BattleSurfaceProjection.BASE_TOP_VOXEL
		+ int(expected[0]) * BattleSurfaceProjection.ELEVATION_STEP_VOXELS
	)
	var spike_y := mini(surface_size.y - 1, base_top + 6)
	surface.voxels[SculptModel.index_of(Vector3i(spike_cell.x, spike_y, spike_cell.y), surface_size)] = 2
	var editable := field.duplicate(true) as EmberBattlefieldResource
	var zero_elevations := PackedInt32Array()
	zero_elevations.resize(field.cell_count())
	zero_elevations.fill(0)
	editable.elevations = zero_elevations
	editable.visual_surface = surface
	var preview := editable.surface_height_sync_preview()
	if not bool(preview.get("ok", false)):
		errors.append("visual Surface height preview rejected a valid battlefield")
		return
	if preview.get("elevations", PackedInt32Array()) != expected:
		errors.append("visual Surface median heights did not recover coarse battlefield elevations")
	var undo := UndoRedo.new()
	var actions := BattlefieldActions.new() as EmberBattlefieldEditorActions
	actions.configure(undo)
	if not actions.sync_surface_heights(editable):
		errors.append("height sync action rejected a valid Visual Surface preview")
	else:
		if editable.elevations != expected:
			errors.append("height sync did not write canonical battlefield elevations")
		undo.undo()
		if editable.elevations != zero_elevations:
			errors.append("height sync Undo did not restore prior elevations")
		undo.redo()
		if editable.elevations != expected:
			errors.append("height sync Redo did not restore projected elevations")
	undo.clear_history()
	undo.free()
	var empty_surface := surface.duplicate(true) as EmberVoxelModelResource
	var density := empty_surface.normalized_density()
	for y in surface_size.y:
		for z in density:
			for x in density:
				empty_surface.voxels[
					SculptModel.index_of(Vector3i(x, y, z), surface_size)
				] = 0
	var preserved := field.duplicate(true) as EmberBattlefieldResource
	preserved.elevations[0] = 4
	preserved.visual_surface = empty_surface
	var empty_preview := preserved.surface_height_sync_preview()
	if Vector2i.ZERO not in empty_preview.get("empty_cells", []):
		errors.append("height sync did not diagnose a completely empty battle cell")
	elif int((empty_preview.get("elevations", PackedInt32Array()) as PackedInt32Array)[0]) != 4:
		errors.append("height sync overwrote an empty cell instead of preserving its rule")


func _test_surface_inspector_navigation(field: EmberBattlefieldResource, errors: Array[String]) -> void:
	if field.visual_surface == null:
		errors.append("battlefield has no visual Surface for Inspector navigation test")
		return
	var owner_path: String = SurfaceInspectorPanel.battlefield_path_for(field.visual_surface)
	if owner_path != E2_PATH:
		errors.append("Surface Inspector could not resolve its canonical Battlefield owner")
	var panel := SurfaceInspectorPanel.new()
	panel.setup(field.visual_surface, null, Callable())
	var rules_button := panel.find_child("OpenBattlefieldRulesFromSurface", true, false) as Button
	if rules_button == null or rules_button.disabled:
		errors.append("Surface Inspector lost its direct Battlefield rules button")
	panel.free()


func _test_embedded_surface_externalization(
	field: EmberBattlefieldResource,
	errors: Array[String],
) -> void:
	var parent_path := "user://battlefield_embedded_surface_test.tres"
	var external_path := "user://battlefield_externalized_surface_test.tres"
	var staged := field.duplicate(true) as EmberBattlefieldResource
	var surface := SculptModel.make_battlefield_surface(
		"externalization_fixture",
		"Externalization fixture",
		field.width,
		field.height,
		field.elevations,
		field.terrain_kinds,
		field.blocked,
	)
	staged.field_id = "externalization_fixture"
	staged.visual_surface = surface
	if ResourceSaver.save(staged, parent_path, ResourceSaver.FLAG_CHANGE_PATH) != OK:
		errors.append("could not stage an embedded Surface regression fixture")
		return
	var reopened := ResourceLoader.load(
		parent_path, "", ResourceLoader.CACHE_MODE_REPLACE
	) as EmberBattlefieldResource
	if reopened == null or reopened.visual_surface == null:
		errors.append("embedded Surface regression fixture did not reopen")
		return
	var embedded_path := reopened.visual_surface.resource_path
	if "::" not in embedded_path or SculptModel.is_writable_resource_path(embedded_path):
		errors.append("embedded Surface path was incorrectly accepted as a writable file")
	var canonical := SculptModel.surface_save_path(reopened.visual_surface, embedded_path)
	if canonical != SculptModel.battle_surface_path("externalization_fixture"):
		errors.append("embedded Surface did not resolve its canonical external path")
	if ResourceSaver.save(
		reopened.visual_surface,
		external_path,
		ResourceSaver.FLAG_CHANGE_PATH,
	) != OK:
		errors.append("embedded Surface could not be externalized")
		return
	reopened.visual_surface.take_over_path(external_path)
	if ResourceSaver.save(reopened, parent_path) != OK:
		errors.append("Battlefield owner could not save its external Surface link")
		return
	var linked := ResourceLoader.load(
		parent_path, "", ResourceLoader.CACHE_MODE_REPLACE
	) as EmberBattlefieldResource
	if (
		linked == null or linked.visual_surface == null
		or linked.visual_surface.resource_path != external_path
	):
		errors.append("Battlefield owner re-embedded Surface after externalization")
	for path in [parent_path, external_path]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _mark_surface_block_water(surface: EmberVoxelModelResource, block: Vector2i) -> void:
	var size := surface.grid_size()
	var density := surface.normalized_density()
	var transparency := PackedByteArray()
	transparency.resize(surface.voxels.size())
	transparency.fill(0)
	for z in range(block.y * density, (block.y + 1) * density):
		for x in range(block.x * density, (block.x + 1) * density):
			for y in range(size.y - 1, -1, -1):
				var index := SculptModel.index_of(Vector3i(x, y, z), size)
				if int(surface.voxels[index]) <= 0:
					continue
				transparency[index] = 208
				break
	surface.transparency = transparency


func _test_resize_undo(field: EmberBattlefieldResource, errors: Array[String]) -> void:
	var editable := field.duplicate(true) as EmberBattlefieldResource
	var undo := UndoRedo.new()
	var actions := BattlefieldActions.new() as EmberBattlefieldEditorActions
	actions.configure(undo)
	var before := editable.authoring_snapshot()
	var preview := editable.resize_preview(9, 7, EmberBattlefieldResource.ResizeAnchor.CENTER)
	if not bool(preview.get("ok", false)):
		errors.append("safe resize rejected a valid centered expansion")
		undo.free()
		return
	if int(preview.get("lost_cells", -1)) != 0 or int(preview.get("new_cells", -1)) != 28:
		errors.append("resize preview reported incorrect kept/new cell counts")
	var offset: Vector2i = preview.get("offset", Vector2i.ZERO)
	if offset != Vector2i.ONE:
		errors.append("center resize did not calculate the expected +1,+1 remap")
	if not actions.resize_field(editable, 9, 7, EmberBattlefieldResource.ResizeAnchor.CENTER):
		errors.append("resize action rejected a valid centered expansion")
	else:
		if editable.width != 9 or editable.height != 7:
			errors.append("resize action did not update canonical dimensions")
		if editable.party_deployment_cells[0] != field.party_deployment_cells[0] + Vector2i.ONE:
			errors.append("resize action did not remap party deployment")
		if editable.cell_definition(Vector2i(1, 1)) != field.cell_definition(Vector2i.ZERO):
			errors.append("resize action did not preserve cell data at its remapped coordinate")
		undo.undo()
		if editable.authoring_snapshot() != before:
			errors.append("one Ctrl+Z did not restore dimensions, cells, focus and deployments")
		undo.redo()
		if editable.width != 9 or editable.height != 7:
			errors.append("one Ctrl+Shift+Z did not restore resized field")

	var crop := field.duplicate(true) as EmberBattlefieldResource
	crop.enemy_deployment_cells.append(Vector2i(1, 0))
	var crop_preview := crop.resize_preview(6, 5, EmberBattlefieldResource.ResizeAnchor.TOP_LEFT)
	if not bool(crop_preview.get("ok", false)) or int(crop_preview.get("enemy_lost", 0)) != 1:
		errors.append("resize preview did not report one cropped enemy deployment")
	undo.clear_history()
	undo.free()


func _test_runtime_deployments(field: EmberBattlefieldResource, errors: Array[String]) -> void:
	var state := EmberCombatGrid.initial_state(field)
	var hero_cells: Array[Vector2i] = []
	var enemy_cells: Array[Vector2i] = []
	for raw_id in state.get("units", {}):
		var unit: Dictionary = (state.get("units", {}) as Dictionary).get(raw_id, {})
		if str(unit.get("team", "")) == "hero":
			hero_cells.append(unit.get("cell", Vector2i(-1, -1)))
		else:
			enemy_cells.append(unit.get("cell", Vector2i(-1, -1)))
	if hero_cells != field.party_deployment_cells:
		errors.append("runtime hero placement does not consume canonical party deployment order")
	if enemy_cells != field.enemy_deployment_cells:
		errors.append("runtime enemy placement does not consume canonical enemy deployment order")
