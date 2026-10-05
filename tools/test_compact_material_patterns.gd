extends SceneTree
## Shared pattern validation, dialog discard/undo/save, shader image refresh.

const Pattern = preload("res://scripts/ember_compact_terrain_pattern.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Dialog = preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors: Array[String] = []
	for role in ["soil", "grass", "sand", "stone"]:
		var source := Materials.load_compact_terrain_pattern(role)
		if source == null or not source.validation_errors().is_empty():
			errors.append("missing or invalid %s pattern" % role)
			continue
		var image := source.to_image()
		if image == null or image.get_size() != Vector2i(16, 16):
			errors.append("%s did not create an exact 16x16 tile" % role)
		var candidate := Materials.load_compact_terrain_variant(role + "_relief")
		if candidate == null or not candidate.validation_errors().is_empty() or candidate.side_pixels.size() != 256:
			errors.append("missing or invalid %s relief variant" % role)
	var invalid := Pattern.new()
	invalid.role_id = "grass"
	invalid.pixels.resize(256)
	invalid.pixels[4] = 3
	if invalid.validation_errors().is_empty():
		errors.append("invalid tone index passed validation")
	invalid.pixels[4] = 0
	invalid.side_pixels = PackedByteArray([0])
	if invalid.validation_errors().is_empty(): errors.append("invalid side size passed validation")
	invalid.side_pixels.resize(256)
	invalid.side_pixels[4] = 3
	if invalid.validation_errors().is_empty(): errors.append("invalid side tone passed validation")
	invalid.side_pixels = PackedByteArray()
	if invalid.face_pixels(true) != invalid.pixels: errors.append("legacy sides did not fall back to top")
	invalid.gloss = 1.1
	if invalid.validation_errors().is_empty():
		errors.append("invalid gloss passed validation")
	var source := Materials.load_compact_terrain_pattern("grass")
	if source == null:
		printerr("FAIL compact material patterns: source missing")
		quit(1)
		return
	var fixture := Pattern.new()
	fixture.role_id = source.role_id
	fixture.base_color = source.base_color
	fixture.light_color = source.light_color
	fixture.shadow_color = source.shadow_color
	fixture.pixels = source.pixels.duplicate()
	var path := "user://compact-material-pattern-test.tres"
	if ResourceSaver.save(fixture, path) != OK:
		errors.append("fixture did not save")
	else:
		var dialog := Dialog.new()
		root.add_child(dialog)
		dialog.pattern_path_override = path
		if not dialog.open_role("grass"):
			errors.append("dialog did not open saved pattern")
		else:
			# A side stroke must undo to the empty legacy fallback, even after a face switch.
			var original_top := dialog._draft.pixels.duplicate()
			dialog._select_face(1)
			dialog._grid.current_tone = 2
			dialog._grid.stroke_started.emit()
			dialog._grid.paint_at(Vector2(12.5, 12.5), 2)
			dialog._grid.stroke_finished.emit()
			if dialog._draft.side_pixels.size() != 256 or dialog._draft.pixels != original_top:
				errors.append("side stroke modified the top or did not create side artwork")
			dialog._select_face(0)
			dialog.undo_edit()
			if not dialog._draft.side_pixels.is_empty(): errors.append("side undo lost legacy fallback")
			dialog.redo_edit()
			if dialog._draft.side_pixels.size() != 256: errors.append("side redo failed across face switch")
			dialog.undo_edit()
			(dialog._finish_sliders["gloss"] as HSlider).value = 0.45
			if not is_equal_approx(dialog._draft.gloss, 0.45):
				errors.append("finish slider did not update draft")
			dialog.undo_edit()
			if not is_zero_approx(dialog._draft.gloss):
				errors.append("finish slider undo failed")
			dialog.redo_edit()
			if not is_equal_approx(dialog._draft.gloss, 0.45):
				errors.append("finish slider redo failed")
			dialog.undo_edit()
			var pixel := 0
			while pixel < 256 and fixture.pixels[pixel] == 1:
				pixel += 1
			if pixel >= 256:
				errors.append("fixture has no paintable base pixel")
			else:
				dialog._grid.current_tone = 1
				dialog._grid.stroke_started.emit()
				dialog._grid.paint_at(Vector2((pixel % 16 + 0.5) * 25, (pixel / 16 + 0.5) * 25), 1)
				dialog._grid.stroke_finished.emit()
				if dialog._draft.pixels[pixel] != 1:
					errors.append("paint did not change draft pixel")
				dialog.undo_edit()
				if dialog._draft.pixels[pixel] != fixture.pixels[pixel]:
					errors.append("pattern pixel undo failed")
					dialog.redo_edit()
					if dialog._draft.pixels[pixel] != 1:
						errors.append("pattern pixel redo failed")
					dialog.undo_edit()
					var grid_size: Vector2 = dialog._grid.size
					var side := minf(grid_size.x / 16.0, grid_size.y / 16.0)
					var origin := (grid_size - Vector2.ONE * side * 16.0) * 0.5
					var down := InputEventMouseButton.new()
					down.button_index = MOUSE_BUTTON_LEFT
					down.pressed = true
					down.position = origin + Vector2(0.5, 0.5) * side
					dialog._grid._gui_input(down)
					var drag := InputEventMouseMotion.new()
					drag.position = origin + Vector2(1.5, 0.5) * side
					dialog._grid._gui_input(drag)
					var up := InputEventMouseButton.new()
					up.button_index = MOUSE_BUTTON_LEFT
					up.pressed = false
					up.position = drag.position
					dialog._grid._gui_input(up)
					if dialog._draft.pixels[0] != 1 or dialog._draft.pixels[1] != 1:
						errors.append("drag stroke did not paint both cells")
					dialog.undo_edit()
					if dialog._draft.pixels[0] != fixture.pixels[0] or dialog._draft.pixels[1] != fixture.pixels[1]:
						errors.append("drag stroke undo was not atomic")
			dialog.hide()
			var discarded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Pattern
			if discarded == null or discarded.pixels != fixture.pixels or not is_zero_approx(discarded.gloss):
				errors.append("closing dialog wrote an unsaved draft")
			if not dialog.open_role("grass"):
				errors.append("dialog failed to reopen after discard")
			else:
				var png := "user://compact-material-roundtrip.png"
				dialog._file_import = false
				dialog._on_file_selected(png)
				var exported := Image.new()
				if exported.load(png) != OK or exported.get_size() != Vector2i(16, 16):
					errors.append("PNG export did not produce 16x16 image")
				else:
					exported.set_pixel(0, 0, fixture.light_color)
					exported.save_png(png)
					dialog._file_import = true
					dialog._on_file_selected(png)
					if dialog._draft.pixels[0] != 1:
						errors.append("PNG import did not update draft")
					dialog.undo_edit()
					if dialog._draft.pixels[0] != fixture.pixels[0]:
						errors.append("PNG import undo failed")
				var next_color := Color("97b765")
				dialog._tones[0].color_changed.emit(next_color)
				if dialog._draft.base_color != next_color:
					errors.append("tone did not update draft")
				(dialog._finish_sliders["gloss"] as HSlider).value = 0.55
				(dialog._finish_sliders["sheen"] as HSlider).value = 0.35
				(dialog._finish_sliders["pixel_relief"] as HSlider).value = 0.12
				dialog._select_face(1)
				var sides := dialog._draft.pixels.duplicate()
				sides[0] = 2
				dialog._set_pixels(sides, true)
				dialog._file_import = false
				dialog._on_file_selected("user://compact-material-sides.png")
				var side_image := Image.load_from_file("user://compact-material-sides.png")
				if side_image == null or side_image.get_pixel(0, 0).to_html(false) != dialog._draft.shadow_color.to_html(false):
					errors.append("side PNG export used top artwork")
				dialog._save()
				var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Pattern
				if reopened == null or reopened.base_color != next_color:
					errors.append("tone save/reopen failed")
				elif not is_equal_approx(reopened.gloss, 0.55) or not is_equal_approx(reopened.sheen, 0.35) or not is_equal_approx(reopened.pixel_relief, 0.12):
					errors.append("finish save/reopen failed")
				if reopened == null or reopened.side_pixels != sides: errors.append("side save/reopen failed")
				var material := Materials.compact_terrain_material()
				Materials.set_compact_terrain_roles(material, PackedStringArray(["", "grass"]))
				var atlas := material.get_shader_parameter("pattern_atlas") as Texture2D
				if atlas == null or atlas.get_size() != Vector2(16, 4096):
					errors.append("shader material did not receive 16x256 atlas")
				var finish := material.get_shader_parameter("finish_lookup") as Texture2D
				if finish == null or finish.get_size() != Vector2(256, 1):
					errors.append("shader material did not receive finish lookup")
				else:
					var actual := finish.get_image().get_pixel(1, 0)
					if absf(actual.r - source.gloss) > 0.005 or absf(actual.g - source.sheen) > 0.005 or absf(actual.b * 0.3 - source.pixel_relief) > 0.005:
						errors.append("finish lookup differs from saved material")
				if atlas != null:
					var atlas_pixel := atlas.get_image().get_pixel(0, 16)
					var expected_height: float = [0.5, 1.0, 0.0][source.pixels[0]]
					if absf(atlas_pixel.a - expected_height) > 0.005:
						errors.append("pattern tone did not create relief height")
				Materials.set_compact_terrain_roles(material, PackedStringArray(["", "stone"]), PackedStringArray(["", "stone_relief"]))
				var side_atlas := material.get_shader_parameter("side_pattern_atlas") as Texture2D
				var lookup := material.get_shader_parameter("role_lookup") as Texture2D
				var stone := Materials.load_compact_terrain_variant("stone_relief")
				if side_atlas == null or side_atlas.get_size() != Vector2(16, 4096) or lookup.get_image().get_pixel(1, 0).g <= 0.0:
					errors.append("side artwork was not bound or flagged")
				elif side_atlas.get_image().get_pixel(4, 20).to_html(false) != stone.to_image(true).get_pixel(4, 4).to_html(false):
					errors.append("side atlas differs from saved artwork")
				if dialog.open_role("grass"):
					var created: Array = []
					dialog.variant_directory_override = "user://"
					dialog.pattern_created.connect(func(id: String, role: String): created.append([id, role]))
					var new_id := "grass_fixture_%d" % Time.get_ticks_usec()
					dialog._name_input.text = new_id
					dialog._create_variant()
					var variant := ResourceLoader.load("user://%s.tres" % new_id, "", ResourceLoader.CACHE_MODE_IGNORE) as Pattern
					if variant == null or variant.role_id != "grass" or created != [[new_id, "grass"]]:
						errors.append("named variant creation did not save and emit")
					else:
						dialog._name_input.text = new_id
						dialog._create_variant()
						if created.size() != 1:
							errors.append("duplicate variant name was accepted")
		dialog.queue_free()
		await process_frame
	if errors.is_empty():
		print("COMPACT_MATERIAL_PATTERNS validation=ok drag=ok undo_redo=ok discard=ok png=ok create_variant=ok save_reopen=ok atlas=ok finish=ok side_faces=ok legacy_fallback=ok")
		quit()
	else:
		for error in errors:
			printerr("FAIL compact material patterns: ", error)
		quit(1)
