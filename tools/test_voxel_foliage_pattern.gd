extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const Presets = preload("res://addons/ember_import/ember_voxel_generator_presets.gd")
const ContextPanel = preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func positions(built: Dictionary, physical := false) -> Dictionary:
	var source: EmberVoxelModelResource = built.geometry
	var grid := source.grid_size()
	var bias: Vector2i = built.pivot_bias
	var result := {}
	for index in source.voxels.size():
		var tone: int = source.voxels[index]
		if tone == 0 or (not physical and tone >= 4 and tone <= 6): continue
		if physical and source.collision_voxels[index] == 0: continue
		var cell := Vector3i(index % grid.x - grid.x / 2 - bias.x, index / (grid.x * grid.z), (index / grid.x) % grid.z - grid.z / 2 - bias.y)
		result[cell] = 1 if physical else tone
	return result

func _run() -> void:
	var oak: Resource = Generator.creation_presets(Generator.LARGE_TREE)[1].recipe.duplicate(true)
	check(oak.parameters.foliage_style == 0, "existing oak preset does not silently change style")
	oak.parameters.generation_version = 8 # Existing trial foliage and custom-v1 upgrade gates.
	var directory := "user://foliage_pattern_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_test_clouds(oak, directory)
	if OS.get_cmdline_user_args().has("--clouds-only"):
		print("Voxel foliage clouds: ", "PASS" if failures == 0 else "FAIL")
		quit(0 if failures == 0 else 1)
		return
	_test_shoots(oak, directory)
	var pattern := Generator.LargeTreeProvider.FoliagePattern
	var cells := {}
	for y in 16:
		for z in 16:
			for x in 16: cells[Vector3i(x - 8, y - 8, z - 8)] = 5
	var reversed := {}
	var keys := cells.keys()
	keys.reverse()
	for cell in keys: reversed[cell] = 5
	var paint_settings: Dictionary = oak.parameters.duplicate()
	paint_settings.foliage_style = 1
	pattern.colorize(cells, {}, paint_settings, 391)
	pattern.colorize(reversed, {}, paint_settings, 391)
	check(cells == reversed, "surface pattern is independent of insertion/overlap order")
	check(cells.values().has(4) and cells.values().has(5) and cells.values().has(6), "surface pattern has recesses, leaf bodies and accents")
	for height in [64, 96, 128, 256]:
		for seed in [17, 391]:
			var recipe := oak.duplicate(true)
			recipe.parameters.height = height
			recipe.seed = seed
			var old := Generator.build(recipe, Color.WHITE, {}, "Old")
			var missing := recipe.duplicate(true)
			missing.parameters.erase("foliage_style")
			missing.parameters.erase("foliage_detail")
			var compatible := Generator.build(missing, Color.WHITE, {}, "Compatible")
			check(compatible.geometry.voxels == old.geometry.voxels, "missing foliage fields preserve exact old geometry")
			recipe.parameters.foliage_style = 1
			var start := Time.get_ticks_usec()
			var fresh := Generator.build(recipe, Color.WHITE, {}, "Pixel")
			print("Pixel foliage %d / seed %d: %.2f ms" % [height, seed, (Time.get_ticks_usec() - start) / 1000.0])
			check(not fresh.has("error"), "pixel crown stays within bounds")
			if fresh.has("error"): continue
			check(fresh.geometry.validation_errors().is_empty(), "pixel source validates")
			check(fresh.structure.lines == old.structure.lines and fresh.structure.groups == old.structure.groups, "new dressing keeps exact scaffold and crown supports")
			check(positions(fresh) == positions(old) and positions(fresh, true) == positions(old, true), "new foliage preserves every bark voxel and physical collision")
			check(hash(fresh.geometry.voxels) != hash(old.geometry.voxels), "pixel style changes real crown geometry")
			check(fresh.occupied != old.occupied, "new style changes occupancy, not only palette indices")
			recipe.structure = fresh.structure.duplicate(true)
			var frozen := Generator.build(recipe, Color.WHITE, {}, "Frozen")
			check(frozen.geometry.voxels == fresh.geometry.voxels and frozen.geometry.collision_voxels == fresh.geometry.collision_voxels, "pixel fresh/frozen exact")
			var path := directory.path_join("oak_%d_%d.tres" % [height, seed])
			check(ResourceSaver.save(recipe, path) == OK, "pixel recipe saves")
			var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			var rebuilt := Generator.build(reopened, Color.WHITE, {}, "Reopen")
			check(reopened.parameters.foliage_style == 1 and reopened.parameters.foliage_detail == 55 and rebuilt.geometry.voxels == fresh.geometry.voxels, "pixel recipe text roundtrip exact")
			for amount in [0, 35, 100]:
				var changed := recipe.duplicate(true)
				changed.parameters.foliage_amount = amount
				var result := Generator.build(changed, Color.WHITE, {}, "Amount")
				check(not result.has("error") and positions(result) == positions(fresh) and positions(result, true) == positions(fresh, true), "foliage amount edits leave wood and collision intact")
				if amount == 0:
					check(result.geometry.voxels.count(4) + result.geometry.voxels.count(5) + result.geometry.voxels.count(6) == 0, "zero foliage leaves bare scaffold")
			if height == 96 and seed == 391:
				var legacy_pattern := recipe.duplicate(true)
				legacy_pattern.parameters.erase("foliage_pattern_version")
				legacy_pattern.parameters.erase("foliage_pattern_strength")
				var legacy_missing := Generator.build(legacy_pattern, Color.WHITE, {}, "First pattern")
				legacy_pattern.parameters.foliage_pattern_version = 1
				check(Generator.build(legacy_pattern, Color.WHITE, {}, "First pattern").geometry.voxels == legacy_missing.geometry.voxels, "missing pattern revision preserves first prototype exactly")
				legacy_pattern.parameters.foliage_detail = 85
				var custom_legacy := Generator.build(legacy_pattern, Color.WHITE, {}, "Custom first pattern")
				var upgrade_panel := ContextPanel.new()
				root.add_child(upgrade_panel)
				upgrade_panel.recipe_directory = directory
				check(ResourceSaver.save(legacy_pattern, directory.path_join(custom_legacy.geometry.model_id + ".tres")) == OK and upgrade_panel.open_source(custom_legacy.geometry), "contextual panel loads saved revision1 without migration")
				check(not upgrade_panel.controls.has("foliage_pattern_strength"), "legacy pattern does not expose new strength")
				upgrade_panel.controls.foliage_style.item_selected.emit(1)
				check(upgrade_panel.recipe.parameters.foliage_pattern_version == 2 and upgrade_panel.controls.has("foliage_pattern_strength"), "explicit same-style selection upgrades pattern revision")
				var upgraded := Generator.build(upgrade_panel.recipe, Color.WHITE, {}, "Upgrade")
				var before: PackedByteArray = custom_legacy.geometry.voxels.duplicate()
				var after: PackedByteArray = upgraded.geometry.voxels.duplicate()
				for i in before.size(): before[i] = mini(before[i], 1)
				for i in after.size(): after[i] = mini(after[i], 1)
				check(upgrade_panel.recipe.parameters.foliage_geometry_detail == 85 and before == after and custom_legacy.geometry.collision_voxels == upgraded.geometry.collision_voxels, "pattern upgrade preserves custom v1 crown occupancy exactly")
				upgrade_panel.undo_parameters()
				check(upgrade_panel.recipe.parameters.foliage_pattern_version == 1 and not upgrade_panel.controls.has("foliage_pattern_strength"), "pattern upgrade Undo restores revision1 and fields")
				upgrade_panel.queue_free()
				for strength in [0, 20, 65, 100]:
					var changed := recipe.duplicate(true)
					changed.parameters.foliage_pattern_strength = strength
					var result := Generator.build(changed, Color.WHITE, {}, "Strength")
					check(result.geometry.voxels == fresh.geometry.voxels and result.geometry.collision_voxels == fresh.geometry.collision_voxels, "pattern strength is palette-only and preserves occupancy/collision")
					if strength == 0: check(result.geometry.palette[4] == result.geometry.palette[5] and result.geometry.palette[6] == result.geometry.palette[5], "zero strength disables visible pattern")
				var contextual := ContextPanel.new()
				root.add_child(contextual)
				contextual.recipe_directory = directory
				var old_recipe := oak.duplicate(true)
				old_recipe.seed = seed
				old_recipe.structure = old.structure.duplicate(true)
				var old_path := directory.path_join(old.geometry.model_id + ".tres")
				check(ResourceSaver.save(old_recipe, old_path) == OK and contextual.open_source(old.geometry), "contextual panel opens saved old oak")
				check(contextual.controls.has("foliage_style") and not contextual.controls.has("foliage_detail"), "saved oak initially hides new detail")
				contextual.controls.foliage_style.item_selected.emit(1)
				check(contextual.controls.has("foliage_detail") and contextual.recipe.parameters.foliage_style == 1, "contextual style change rebuilds conditional descriptors")
				contextual.controls.foliage_detail.value = 85
				contextual.undo_parameters()
				contextual.undo_parameters()
				check(not contextual.controls.has("foliage_detail") and contextual.recipe.parameters.foliage_style == 0, "contextual Undo removes dependent field")
				contextual.redo_parameters()
				check(contextual.controls.has("foliage_detail"), "contextual Redo restores dependent field")
				contextual.discard()
				check(contextual.recipe.parameters.foliage_style == 0 and old.geometry.voxels == compatible.geometry.voxels, "contextual Discard does not touch canonical source")
				contextual.queue_free()
				var preset_store := Presets.new()
				preset_store.directory = directory.path_join("presets")
				var preset_path := preset_store.save_preset(recipe, "Pixel oak")
				var preset := ResourceLoader.load(preset_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
				check(preset != null and preset.structure.is_empty() and preset.parameters.foliage_style == 1 and preset.parameters.foliage_detail == 55, "reusable preset stores foliage controls without frozen scaffold")
				var source: EmberVoxelModelResource = fresh.geometry
				var grid := source.grid_size()
				var isolated := 0
				for index in source.voxels.size():
					if source.voxels[index] < 4 or source.voxels[index] > 6: continue
					var cell := Vector3i(index % grid.x, index / (grid.x * grid.z), (index / grid.x) % grid.z)
					var joined := false
					for offset in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
						var neighbor: Vector3i = cell + offset
						if neighbor.x < 0 or neighbor.y < 0 or neighbor.z < 0 or neighbor.x >= grid.x or neighbor.y >= grid.y or neighbor.z >= grid.z: continue
						if source.voxels[(neighbor.y * grid.z + neighbor.z) * grid.x + neighbor.x] != 0: joined = true; break
					if not joined: isolated += 1
				check(isolated == 0, "grouped contours do not produce isolated voxel confetti")
				var hashes := []
				for detail in [0, 55, 100]:
					var changed := recipe.duplicate(true)
					changed.parameters.foliage_detail = detail
					var result := Generator.build(changed, Color.WHITE, {}, "Detail")
					hashes.append(hash(result.geometry.voxels))
					check(positions(result) == positions(fresh), "detail edits keep wood")
					check(result.occupied == fresh.occupied and result.geometry.collision_voxels == fresh.geometry.collision_voxels, "revision2 pattern detail does not reshape the crown")
				check(hashes[0] != hashes[1] and hashes[1] != hashes[2], "detail generates distinct grouped contours")
				var autumn := recipe.duplicate(true)
				autumn.parameters.foliage_color = Color("c67432")
				check(Generator.build(autumn, Color.WHITE, {}, "Autumn").geometry.voxels == fresh.geometry.voxels, "season only changes palette")
	var extreme := oak.duplicate(true)
	extreme.parameters.merge({"foliage_style": 1, "foliage_detail": 100, "height": 256, "trunk_width": 24, "branch_thickness": 100, "branchiness": 100, "cluster_size": 180, "canopy_cohesion": 100, "crown_spread": 85}, true)
	check(not Generator.build(extreme, Color.WHITE, {}, "Extreme").has("error"), "maximal pixel crown stays within storage budget")
	var panel := GenerationPanel.new()
	root.add_child(panel)
	panel.open_for({"world_size": 1.0}, oak)
	check(panel.controls.foliage_style.visible and not panel.controls.foliage_detail.get_parent().visible, "oak offers old/new style and hides irrelevant detail")
	panel.controls.foliage_style.item_selected.emit(1)
	check(panel.recipe.parameters.foliage_style == 1 and panel.controls.foliage_detail.get_parent().visible, "native creation style choice reveals detail")
	panel.undo_local()
	check(panel.recipe.parameters.foliage_style == 0, "recipe-only style draft Undo")
	panel.redo_local()
	check(panel.recipe.parameters.foliage_style == 1, "recipe-only style draft Redo")
	var old_draft := panel.recipe.duplicate(true)
	old_draft.parameters.foliage_pattern_version = 1
	panel._apply_recipe(old_draft)
	panel.controls.foliage_style.item_selected.emit(1)
	check(panel.recipe.parameters.foliage_pattern_version == 2 and panel.controls.foliage_pattern_strength.get_parent().visible, "creation same-style selection upgrades legacy pattern")
	panel.undo_local()
	check(panel.recipe.parameters.foliage_pattern_version == 1, "creation pattern revision upgrade Undo")
	panel.close_session()
	panel.queue_free()
	for index in [0, 2, 3, 4]:
		var other: Resource = Generator.creation_presets(Generator.LARGE_TREE)[index].recipe.duplicate(true)
		other.parameters.height = 64
		var before := Generator.build(other, Color.WHITE, {}, "Other")
		other.parameters.foliage_style = 1
		var after := Generator.build(other, Color.WHITE, {}, "Other")
		check(before.structure.lines == after.structure.lines and before.structure.groups == after.structure.groups, "shared pixel dressing preserves species scaffold and crown supports")
		check(before.geometry.voxels != after.geometry.voxels, "every species accepts pixel dressing")
	print("Voxel foliage pattern: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func _test_clouds(oak: Resource, directory: String) -> void:
	for revision in [8, 11]:
		for height in [64, 96, 128, 256]:
			for seed in [17, 391]:
				var recipe := oak.duplicate(true)
				recipe.parameters.merge({"generation_version": revision, "height": height, "foliage_style": 3}, true)
				recipe.seed = seed
				var previous := recipe.duplicate(true)
				previous.parameters.foliage_style = 1
				var reference := Generator.build(previous, Color.WHITE, {}, "Pixel")
				var start := Time.get_ticks_usec()
				var built := Generator.build(recipe, Color.WHITE, {}, "Clouds")
				check(not built.has("error"), "clouds build within storage budget")
				if built.has("error"): continue
				print("Foliage clouds v%d height%d seed%d: %.2f ms / occupied%d" % [revision, height, seed, (Time.get_ticks_usec() - start) / 1000.0, built.occupied])
				check(built.geometry.validation_errors().is_empty(), "cloud source validates")
				check(built.structure.lines == reference.structure.lines and built.structure.groups == reference.structure.groups, "clouds share exact pixel scaffold/supports")
				check(positions(built) == positions(reference) and positions(built, true) == positions(reference, true), "clouds preserve bark and collision")
				recipe.structure = built.structure.duplicate(true)
				check(Generator.build(recipe, Color.WHITE, {}, "Frozen").geometry.voxels == built.geometry.voxels, "cloud fresh/frozen exact")
				if seed != 391 or height != 96: continue
				var path := directory.path_join("cloud%d.tres" % revision)
				check(ResourceSaver.save(recipe, path) == OK, "cloud recipe saves")
				var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
				check(reopened.parameters.foliage_leaf_accents == 35 and Generator.build(reopened, Color.WHITE, {}, "Reopen").geometry.voxels == built.geometry.voxels, "cloud recipe text roundtrip exact")
				for amount in [0, 35]:
					var changed := recipe.duplicate(true)
					changed.parameters.foliage_amount = amount
					var edited := Generator.build(changed, Color.WHITE, {}, "Amount")
					check(not edited.has("error") and positions(edited, true) == positions(built, true), "cloud amount preserves physical wood")
					if amount == 0: check(edited.geometry.voxels.count(4) + edited.geometry.voxels.count(5) + edited.geometry.voxels.count(6) == 0, "cloud amount zero is bare")
				var context := ContextPanel.new()
				root.add_child(context)
				context.recipe_directory = directory
				check(ResourceSaver.save(recipe, directory.path_join(built.geometry.model_id + ".tres")) == OK and context.open_source(built.geometry), "contextual opens clouds")
				check(context.controls.has("foliage_leaf_accents") and context.controls.has("foliage_leaf_size") and context.controls.has("foliage_detail") and context.controls.has("foliage_pattern_strength"), "caps expose geometry and shared pattern controls")
				var occupancy: PackedByteArray = built.geometry.voxels.duplicate()
				for index in occupancy.size(): occupancy[index] = mini(occupancy[index], 1)
				for detail in [15, 85]:
					var changed := recipe.duplicate(true)
					changed.parameters.foliage_detail = detail
					var edited := Generator.build(changed, Color.WHITE, {}, "Pattern size")
					var mask: PackedByteArray = edited.geometry.voxels.duplicate()
					for index in mask.size(): mask[index] = mini(mask[index], 1)
					check(mask == occupancy and edited.geometry.voxels != built.geometry.voxels and edited.structure == built.structure, "pattern scale changes colors but never cap occupancy/supports")
				for strength in [0, 20, 100]:
					var changed := recipe.duplicate(true)
					changed.parameters.foliage_pattern_strength = strength
					var edited := Generator.build(changed, Color.WHITE, {}, "Contrast")
					check(edited.geometry.voxels == built.geometry.voxels and edited.geometry.palette != built.geometry.palette, "cap contrast changes palette only")
				context.controls.foliage_leaf_accents.value = 80
				context.undo_parameters()
				check(context.recipe.parameters.foliage_leaf_accents == 35, "cloud accent Undo")
				context.redo_parameters()
				check(context.recipe.parameters.foliage_leaf_accents == 80, "cloud accent Redo")
				context.discard()
				context.queue_free()
	var settings: Dictionary = oak.parameters.duplicate(true)
	settings.foliage_leaf_accents = 0
	var body := {}
	Generator.LargeTreeProvider.FoliagePattern.paint_clouds(body, {}, Vector3(0, 24, 0), Vector3(12, 8, 12), settings, 391)
	settings.foliage_leaf_accents = 100
	var dressed := {}
	Generator.LargeTreeProvider.FoliagePattern.paint_clouds(dressed, {}, Vector3(0, 24, 0), Vector3(12, 8, 12), settings, 391)
	check(dressed.size() > body.size() and body.keys().all(func(cell): return dressed.has(cell)), "accents only add geometry to unchanged cloud body")
	var legacy := oak.duplicate(true)
	legacy.seed = 391
	legacy.parameters.merge({"height":96,"foliage_style":3,"foliage_cloud_version":1}, true)
	var first := Generator.build(legacy, Color.WHITE, {}, "Original clouds")
	check(first.occupied == 94068, "revision1 exact first trial occupancy golden")
	var missing := legacy.duplicate(true)
	missing.parameters.erase("foliage_cloud_version")
	check(Generator.build(missing, Color.WHITE, {}, "Missing cloud version").geometry.voxels == first.geometry.voxels, "missing cloud revision preserves original trial")
	var context := ContextPanel.new()
	root.add_child(context)
	context.recipe_directory = directory
	legacy.structure = first.structure.duplicate(true)
	ResourceSaver.save(legacy, directory.path_join(first.geometry.model_id + ".tres"))
	check(context.open_source(first.geometry) and not context.controls.has("foliage_pattern_strength"), "old cloud recipe does not silently expose new pattern")
	context.controls.foliage_style.item_selected.emit(3)
	check(context.recipe.parameters.foliage_cloud_version == 2 and context.controls.has("foliage_pattern_strength"), "explicit same-style selection upgrades clouds")
	context.undo_parameters()
	check(context.recipe.parameters.foliage_cloud_version == 1 and Generator.build(context.recipe, Color.WHITE, {}, "Upgrade Undo").geometry.voxels == first.geometry.voxels, "cloud revision upgrade Undo exact old geometry")
	context.queue_free()
	var panel := GenerationPanel.new()
	root.add_child(panel)
	panel.open_for({"world_size": 1.0}, oak)
	panel.controls.foliage_style.item_selected.emit(3)
	check(panel.recipe.parameters.foliage_style == 3 and panel.controls.foliage_leaf_accents.get_parent().visible and panel.controls.foliage_detail.get_parent().visible and panel.controls.foliage_pattern_strength.get_parent().visible, "cap creation pattern controls visible")
	panel.undo_local()
	check(panel.recipe.parameters.foliage_style == 0, "cloud style Undo")
	panel.redo_local()
	var store := Presets.new()
	store.directory = directory.path_join("cloud_presets")
	var preset_path := store.save_preset(panel.recipe, "Clouds")
	var preset := ResourceLoader.load(preset_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	check(preset != null and preset.structure.is_empty() and preset.parameters.foliage_style == 3 and preset.parameters.foliage_leaf_accents == 35, "reusable cloud preset")
	var old_draft := panel.recipe.duplicate(true)
	old_draft.parameters.foliage_cloud_version = 1
	panel._apply_recipe(old_draft)
	check(not panel.controls.foliage_detail.get_parent().visible, "creation retains original cloud controls")
	panel.controls.foliage_style.item_selected.emit(3)
	check(panel.recipe.parameters.foliage_cloud_version == 2 and panel.controls.foliage_detail.get_parent().visible, "creation same-style selection upgrades caps")
	panel.undo_local()
	check(panel.recipe.parameters.foliage_cloud_version == 1 and not panel.controls.foliage_detail.get_parent().visible, "creation cloud upgrade Undo")
	panel.redo_local()
	check(panel.recipe.parameters.foliage_cloud_version == 2, "creation cloud upgrade Redo")
	for size in [3, 12]:
		var extreme := panel.recipe.duplicate(true)
		extreme.parameters.merge({"height":256,"foliage_leaf_size":size,"foliage_leaf_accents":100,"cluster_size":180,"canopy_cohesion":100,"crown_spread":85,"trunk_width":24,"branch_thickness":100,"branchiness":100}, true)
		for seed in [17, 371, 391]:
			extreme.seed = seed
			check(not Generator.build(extreme, Color.WHITE, {}, "Extreme clouds").has("error"), "extreme clouds stay bounded")
	panel.close_session()
	panel.queue_free()


func _test_shoots(oak: Resource, directory: String) -> void:
	for height in [64, 96, 128, 256]:
		var recipe := oak.duplicate(true)
		recipe.seed = 391
		recipe.parameters.height = height
		var old := Generator.build(recipe, Color.WHITE, {}, "Old")
		recipe.parameters.foliage_style = 2
		var start := Time.get_ticks_usec()
		var fresh := Generator.build(recipe, Color.WHITE, {}, "Shoots")
		check(not fresh.has("error"), "leaf shoots stay within tree budgets")
		if fresh.has("error"): continue
		print("Leaf shoots %d: %.2f ms / occupied %d (old %d)" % [height, (Time.get_ticks_usec() - start) / 1000.0, fresh.occupied, old.occupied])
		check(fresh.geometry.validation_errors().is_empty(), "shoot source validates")
		check(fresh.structure.lines == old.structure.lines and fresh.structure.groups == old.structure.groups, "shoots preserve frozen scaffold")
		check(positions(fresh) == positions(old) and positions(fresh, true) == positions(old, true), "shoots preserve exact bark and collision")
		recipe.structure = fresh.structure.duplicate(true)
		check(Generator.build(recipe, Color.WHITE, {}, "Frozen").geometry.voxels == fresh.geometry.voxels, "shoot fresh/frozen exact")
		var path := directory.path_join("shoot_%d.tres" % height)
		check(ResourceSaver.save(recipe, path) == OK, "shoot recipe saves")
		var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
		check(Generator.build(reopened, Color.WHITE, {}, "Reopen").geometry.voxels == fresh.geometry.voxels, "shoot text roundtrip exact")
		if height != 96: continue
		var panel := GenerationPanel.new()
		root.add_child(panel)
		panel.open_for({"world_size": 1.0}, oak)
		panel.controls.foliage_style.item_selected.emit(2)
		check(panel.controls.foliage_leaf_size.get_parent().visible and not panel.controls.foliage_detail.get_parent().visible, "shoot UI exposes only leaf size")
		panel.undo_local()
		check(panel.recipe.parameters.foliage_style == 0, "shoot style Undo")
		panel.redo_local()
		check(panel.recipe.parameters.foliage_style == 2, "shoot style Redo")
		panel.close_session()
		panel.queue_free()
		for size in [3, 8, 12]:
			var changed := recipe.duplicate(true)
			changed.parameters.foliage_leaf_size = size
			var result := Generator.build(changed, Color.WHITE, {}, "Size")
			check(not result.has("error") and positions(result, true) == positions(fresh, true), "leaf size leaves physical scaffold intact")
			check(result.geometry.voxels != fresh.geometry.voxels, "leaf size changes actual leaf geometry")
		var bare := recipe.duplicate(true)
		bare.parameters.foliage_amount = 0
		var bare_result := Generator.build(bare, Color.WHITE, {}, "Bare")
		check(bare_result.geometry.voxels.count(4) + bare_result.geometry.voxels.count(5) + bare_result.geometry.voxels.count(6) == 0, "shoot amount zero removes all leaf dressing")
		var autumn := recipe.duplicate(true)
		autumn.parameters.foliage_color = Color("c67432")
		check(Generator.build(autumn, Color.WHITE, {}, "Autumn").geometry.voxels == fresh.geometry.voxels, "shoot season changes palette only")
