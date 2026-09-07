extends SceneTree
const Palette = preload("res://addons/ember_import/ember_voxel_palette_model.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const TEMP_PATH := "user://ember_palette_test.tres"
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_remapping()
	root.size = Vector2i(1280, 720)
	var resource := _fixture()
	var original := resource.voxels.duplicate()
	var colors := resource.palette.duplicate()
	var water := resource.surface_fill_palette.duplicate()
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null, undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(resource, TEMP_PATH)
	for frame in 4:
		await process_frame
	var panel: VBoxContainer = workspace.get("_palette_panel")
	var toolbar: OptionButton = workspace.get("_palette")
	var tint: OptionButton = workspace.get("_surface_fill_tint")
	(panel.find_child("PaletteColor_3", true, false) as Button).pressed.emit()
	_check(toolbar.selected == 2, "swatch did not select paint color")
	_check(not workspace.has_unsaved_changes(), "selecting a color dirtied content")
	panel.call("_open_dialog", "set")
	var picker: ColorPicker = panel.get("_picker")
	var dialog: ConfirmationDialog = panel.get("_dialog")
	picker.color = Color.MAGENTA
	_check(resource.palette == colors, "ColorPicker drag modified source before confirmation")
	dialog.canceled.emit()
	dialog.hide()
	_check(resource.palette == colors and not undo.has_undo(), "cancel wrote an Undo action")
	panel.call("_open_dialog", "set")
	picker.color = Color(0.6, 0.3, 0.8, 0.4)
	dialog.hide()
	dialog.confirmed.emit()
	_check(resource.palette[3].is_equal_approx(Color(0.6, 0.3, 0.8, 1)), "set color did not sanitize alpha")
	_check(resource.voxels == original and resource.surface_fill_palette == water, "set changed geometry or water references")
	undo.undo()
	_check(resource.palette == colors and not undo.has_undo(), "set was not one undoable action")
	undo.redo()
	_check(toolbar.selected == 2, "Undo/Redo reset active paint color")
	workspace.call("_apply_palette_operation", resource, {"kind": "add", "color": Color.PINK})
	_check(resource.palette.size() == 5 and toolbar.selected == 3, "add did not select new color")
	undo.undo()
	_check(resource.palette.size() == 4 and toolbar.selected < toolbar.item_count, "add Undo left invalid selection")
	undo.redo()
	workspace.call("_select_palette_color", 1)
	tint.select(3)
	workspace.call("_apply_palette_operation", resource, {"kind": "merge", "index": 1, "target": 3})
	_check(resource.palette.size() == 4 and tint.selected == 2 and toolbar.selected == 1, "merge lost selected water/paint identity")
	_check(resource.surface_fill_palette[0] == 2 and resource.surface_fill_palette[2] == 2, "water was not remapped")
	_check(resource.voxels[0] == 2 and resource.voxels[original.size() - 1] == 2, "merge missed hidden voxel")
	var merged := resource.voxels.duplicate()
	undo.undo()
	_check(resource.voxels == original and resource.surface_fill_palette == water and resource.palette.size() == 5, "merge Undo did not restore all channels")
	_check(tint.selected == 3 and toolbar.selected == 2, "Undo did not preserve selected color identity")
	undo.redo()
	_check(resource.voxels == merged, "merge Redo differed")
	_check(tint.selected == 2 and toolbar.selected == 1, "Redo did not preserve selected color identity")
	_check(bool(workspace.call("_save")), "palette save failed")
	var reopened := ResourceLoader.load(TEMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(reopened != null and reopened.palette == resource.palette and reopened.voxels == merged and reopened.surface_fill_palette == resource.surface_fill_palette, "round trip lost palette references")
	# Eyedropper uses canonical color, not lit screen pixels, and never paints.
	workspace.call("_fit_camera_to_surface")
	for frame in 4:
		await process_frame
	var camera: Camera3D = workspace.get("_camera")
	var viewport: SubViewport = workspace.get("_viewport")
	var container: SubViewportContainer = workspace.get("_viewport_container")
	var position := camera.unproject_position(Vector3(0.3, 0.125, 0.3)) * container.size / Vector2(viewport.size)
	var hit: Dictionary = workspace.call("_pick_at", position)
	_check(hit.has("hit"), "test eyedropper ray missed fixture")
	workspace.call("_toggle_color_pick")
	workspace.call("_pick_palette_color", Vector2(-1000, -1000))
	_check(bool(workspace.get("_picking_color")), "empty click disarmed picker")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = position
	workspace.call("_on_viewport_input", click)
	_check(not bool(workspace.get("_picking_color")) and not bool(workspace.get("_stroke_active")), "picker started brush or remained armed")
	if hit.has("hit"):
		_check(toolbar.selected + 1 == resource.voxels[Model.index_of(hit["hit"], resource.grid_size())], "picker returned wrong palette index")
	_check(resource.voxels == merged and not workspace.has_unsaved_changes(), "eyedropper changed source")
	workspace.call("_toggle_color_pick")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	workspace.call("_input", escape)
	_check(not bool(workspace.get("_picking_color")), "Esc did not cancel picker")
	var slice: CheckButton = workspace.find_child("EnableHeightSlice", true, false)
	var height: SpinBox = workspace.find_child("HeightSliceLevel", true, false)
	slice.button_pressed = true
	height.value = 1
	position = camera.unproject_position(Vector3(0.3, 0.0625, 0.3)) * container.size / Vector2(viewport.size)
	workspace.call("_toggle_color_pick")
	workspace.call("_pick_palette_color", position)
	_check(toolbar.selected == 1, "eyedropper did not sample hidden layer exposed by slice")
	slice.button_pressed = false
	# A stale dialog must not act on shifted palette indices after Undo.
	panel.call("_open_dialog", "set")
	undo.undo()
	picker.color = Color.BLACK
	dialog.confirmed.emit()
	_check(resource.palette.size() == 5 and resource.palette[1] != Color.BLACK, "stale dialog wrote after Undo")
	workspace.discard_changes()
	_check(panel.get("_colors") == resource.palette and not workspace.has_unsaved_changes(), "discard did not refresh palette UI")
	# Ramp dialog previews ordinary colors, commits once, remaps every reference
	# without changing resolved voxel/water appearance, and survives save/reopen.
	workspace.call("_select_palette_color", 2)
	var ramp_palette_before := resource.palette.duplicate()
	var ramp_voxel_colors_before := _resolved_colors(resource.voxels, resource.palette)
	var ramp_water_colors_before := _resolved_colors(resource.surface_fill_palette, resource.palette)
	panel.call("_open_dialog", "ramp")
	var ramp_preview: HBoxContainer = panel.get("_ramp_preview")
	_check(ramp_preview.get_child_count() == 5, "ramp dialog did not preview five colors")
	_check(resource.palette == ramp_palette_before, "ramp preview mutated source before confirmation")
	dialog.canceled.emit()
	dialog.hide()
	_check(resource.palette == ramp_palette_before, "cancelled ramp changed palette")
	panel.call("_open_dialog", "ramp")
	dialog.hide()
	dialog.confirmed.emit()
	_check(resource.palette.size() == ramp_palette_before.size() + 4, "ramp commit did not insert four colors")
	_check(_resolved_colors(resource.voxels, resource.palette) == ramp_voxel_colors_before, "ramp changed resolved voxel colors")
	_check(_resolved_colors(resource.surface_fill_palette, resource.palette) == ramp_water_colors_before, "ramp changed resolved water tint")
	_check(toolbar.selected + 1 == 4 and tint.selected == 4, "ramp did not preserve active paint/water base color")
	undo.undo()
	_check(resource.palette == ramp_palette_before, "ramp Undo failed")
	undo.redo()
	_check(resource.palette.size() == ramp_palette_before.size() + 4, "ramp Redo failed")
	_check(bool(workspace.call("_save")), "ramp save failed")
	reopened = ResourceLoader.load(TEMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(reopened != null and reopened.palette == resource.palette and reopened.voxels == resource.voxels, "ramp save/reopen lost palette or references")
	panel.call("_open_dialog", "set")
	workspace.hide()
	_check(not dialog.visible, "hidden workspace retained an editing dialog")
	workspace.show()
	if "--visual" in OS.get_cmdline_user_args():
		for frame in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ember_palette_test.png")
		panel.call("_open_dialog", "ramp")
		for frame in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var logical_height := root.get_visible_rect().size.y
		_check(dialog.size.y <= logical_height and dialog.position.y >= 0 and dialog.position.y + dialog.size.y <= logical_height, "palette dialog extends outside viewport")
		root.get_texture().get_image().save_png("user://ember_palette_dialog_test.png")
		print("VISUAL: ", ProjectSettings.globalize_path("user://ember_palette_test.png"))
	var full := _fixture()
	full.palette.resize(256)
	panel.call("sync", full, 255)
	_check((panel.get("_grid") as GridContainer).get_child_count() == 255 and (panel.get("_add") as Button).disabled and (panel.get("_ramp") as Button).disabled, "full palette UI did not enforce capacity")
	panel.call("_open_dialog", "set")
	panel.call("sync", resource, 1)
	dialog.confirmed.emit()
	_check(full.palette.size() == 256 and not workspace.has_unsaved_changes(), "resource switch retained pending operation")
	workspace.free()
	undo.clear_history()
	undo.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	for error in errors:
		printerr(error)
	if errors.is_empty():
		print("PASS palette: remapping, water, ramps, capacity, global edits, Undo/Redo, dialogs, eyedropper, save/discard")
	quit(0 if errors.is_empty() else 1)


func _test_remapping() -> void:
	var resource := _fixture()
	resource.voxels = PackedByteArray([0, 1, 2, 3])
	resource.surface_fill_palette = PackedByteArray([0, 3, 1, 2])
	for pair in [Vector2i(1, 3), Vector2i(3, 1), Vector2i(2, 1)]:
		var plan := Palette.plan(resource, {"kind": "merge", "index": pair.x, "target": pair.y})
		var props: Dictionary = plan["properties"]
		for name in ["voxels", "surface_fill_palette"]:
			var before: PackedByteArray = resource.get(name)
			var after: PackedByteArray = props[name]
			for i in before.size():
				var expected: int = pair.y if before[i] == pair.x else int(before[i])
				_check(after[i] == expected - (1 if expected > pair.x else 0), "remap direction failed")
		_check(not props.has("transparency") and resource.voxels == PackedByteArray([0, 1, 2, 3]), "planning mutated unrelated/source data")
	for operation in [{"kind": "set", "index": 0}, {"kind": "merge", "index": 1, "target": 0}, {"kind": "merge", "index": 1, "target": 1}]:
		_check(Palette.plan(resource, operation).has("error"), "reserved/invalid palette operation accepted")
	resource.palette.resize(255)
	_check(Palette.plan(resource, {"kind": "add"})["properties"]["palette"].size() == 256, "last palette slot rejected")
	resource.palette.resize(256)
	_check(Palette.plan(resource, {"kind": "add"}).has("error"), "palette overflow accepted")
	resource.palette.resize(2)
	_check(Palette.plan(resource, {"kind": "merge", "index": 1, "target": 1}).has("error"), "last color removed")
	resource.palette.resize(4)
	resource.surface_fill_palette[0] = 255
	_check(Palette.plan(resource, {"kind": "merge", "index": 1, "target": 2}).has("error"), "dangling water reference accepted")
	_test_ramps()


func _test_ramps() -> void:
	var base := Color("4a8c68")
	for steps in [3, 5, 7]:
		var ramp := Palette.build_ramp(base, steps, 1)
		_check(ramp.size() == steps and ramp[steps / 2] == base, "ramp lost requested size/base")
		_check(ramp[0].v < base.v and ramp[-1].v > base.v, "ramp is not ordered shadow to light")
		for color in ramp:
			_check(is_equal_approx(color.a, 1.0), "ramp produced transparent swatch")
	var resource := _fixture()
	resource.voxels = PackedByteArray([0, 1, 2, 3])
	resource.surface_fill_palette = PackedByteArray([0, 3, 1, 2])
	var ramp := Palette.build_ramp(resource.palette[2], 5, 1)
	var result := Palette.plan(resource, {"kind": "ramp", "index": 2, "colors": ramp})
	var properties: Dictionary = result.get("properties", {})
	_check(not properties.is_empty() and properties.palette.size() == 8, "ramp plan did not insert four swatches")
	_check(properties.palette[4] == resource.palette[2] and result.selected == 4, "ramp center lost source color/index")
	_check(properties.voxels == PackedByteArray([0, 1, 4, 7]), "ramp did not remap voxel references")
	_check(properties.surface_fill_palette == PackedByteArray([0, 7, 1, 4]), "ramp did not remap water references")
	_check(resource.voxels == PackedByteArray([0, 1, 2, 3]), "ramp planning mutated source")
	resource.palette.resize(254)
	_check(Palette.plan(resource, {"kind": "ramp", "index": 1, "colors": ramp}).has("error"), "ramp overflow accepted")


func _fixture() -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "palette_test"
	resource.display_name = "Палитра · тест"
	resource.height_voxels = 3
	resource.palette = PackedColorArray([Color.TRANSPARENT, Color(0.3, 0.6, 0.4), Color(0.8, 0.5, 0.3), Color(0.2, 0.5, 0.8)])
	var size := resource.grid_size()
	resource.voxels.resize(size.x * size.y * size.z)
	for i in resource.voxels.size():
		resource.voxels[i] = 1 if i < size.x * size.z else 2
	resource.voxels[resource.voxels.size() - 1] = 1
	resource.surface_fill_levels.resize(size.x * size.z)
	resource.surface_fill_levels.fill(3)
	resource.surface_fill_materials.resize(size.x * size.z)
	resource.surface_fill_materials.fill(1)
	resource.surface_fill_palette.resize(size.x * size.z)
	resource.surface_fill_palette[0] = 1
	resource.surface_fill_palette[2] = 3
	return resource


func _resolved_colors(channel: PackedByteArray, palette: PackedColorArray) -> PackedColorArray:
	var result := PackedColorArray()
	for value in channel:
		result.append(palette[int(value)] if int(value) < palette.size() else Color.MAGENTA)
	return result


func _check(condition: bool, message: String) -> void:
	if not condition and message not in errors:
		errors.append(message)
