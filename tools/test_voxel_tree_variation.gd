extends SceneTree
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const Presets = preload("res://addons/ember_import/ember_voxel_generator_presets.gd")
var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func fingerprint(lines: Array) -> Array:
	# Heights, branch counts and connectivity are invariant under global yaw.
	var result := []
	for line: Dictionary in lines:
		result.append([line.start.y, line.finish.y, line.start.distance_to(line.finish), line.branch, line.t0, line.t1])
	return result

func _run() -> void:
	_test_oak_composition()
	_test_oak_laterals()
	var directory := "user://tree_variation_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for kind in [0, 1, 2, 3, 4]:
		var recipe: Resource = Generator.creation_presets(Generator.LARGE_TREE)[kind].recipe.duplicate(true)
		var old_version: int = [9, 8, 5, 7, 10][kind]
		check(recipe.parameters.generation_version == Generator.LargeTreeProvider.LATEST_VERSIONS[kind], "latest preset opts into structural variation")
		for height in [64, 128, 256]:
			var signatures := {}
			var counts := {}
			for seed in [17, 371, 391, 104746, 209475, 314204]:
				recipe.seed = seed
				recipe.parameters.height = height
				recipe.parameters.foliage_amount = 0
				var start := Time.get_ticks_usec()
				var built := Generator.build(recipe, Color.WHITE, {}, "Varied")
				check(not built.has("error"), "new varied scaffold builds within budget")
				if built.has("error"): continue
				check(built.geometry.validation_errors().is_empty() and Generator.LargeTreeProvider.structure_errors(built.structure).is_empty(), "new source and frozen structure validate")
				signatures[hash(fingerprint(built.structure.lines))] = true
				counts[built.structure.lines.size()] = true
				if seed != 391: continue
				print("Tree variation type%d height%d: %.2f ms / %d lines" % [kind, height, (Time.get_ticks_usec() - start) / 1000.0, built.structure.lines.size()])
				var frozen := recipe.duplicate(true)
				frozen.structure = built.structure.duplicate(true)
				check(Generator.build(frozen, Color.WHITE, {}, "Frozen").geometry.voxels == built.geometry.voxels, "fresh/frozen exact scaffold")
				var path := directory.path_join("tree_%d_%d.tres" % [kind, height])
				check(ResourceSaver.save(frozen, path) == OK, "new recipe saves")
				var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
				check(Generator.build(reopened, Color.WHITE, {}, "Reopen").geometry.voxels == built.geometry.voxels, "new recipe text roundtrip exact")
				var zero := recipe.duplicate(true)
				zero.parameters.structure_diversity = 0
				var reference := zero.duplicate(true)
				reference.parameters.generation_version = old_version
				var zero_result := Generator.build(zero, Color.WHITE, {}, "Zero")
				var old_result := Generator.build(reference, Color.WHITE, {}, "Legacy")
				check(zero_result.geometry.voxels == old_result.geometry.voxels and zero_result.structure.lines == old_result.structure.lines, "zero diversity reproduces previous scaffold exactly")
				frozen.parameters.structure_diversity = 100
				check(Generator.build(frozen, Color.WHITE, {}, "Still frozen").geometry.voxels == built.geometry.voxels, "diversity cannot silently replace a frozen skeleton")
			check(signatures.size() == 6 and counts.size() >= 3, "seeds differ structurally, even after ignoring rotation")
		var extreme := recipe.duplicate(true)
		extreme.parameters.merge({"structure_diversity":100,"height":256,"foliage_amount":100,"trunk_width":24,"branchiness":100,"branch_thickness":100,"cluster_size":180,"canopy_cohesion":100,"crown_spread":85}, true)
		for extreme_seed in [17, 371, 391]:
			extreme.seed = extreme_seed
			for style in ([0, 1] if kind == 1 else [0]):
				extreme.parameters.foliage_style = style
				check(not Generator.build(extreme, Color.WHITE, {}, "Extreme").has("error"), "maximal varied tree and pixel foliage remain bounded")
		for direction in [1, 2, 3]:
			var directed := recipe.duplicate(true)
			directed.parameters.branch_direction = direction
			directed.parameters.structure_diversity = 100
			check(not Generator.build(directed, Color.WHITE, {}, "Directed").has("error"), "direction override stays bounded on varied scaffold")
		recipe.parameters.height = 96
		recipe.parameters.foliage_amount = 100
		if kind == 1: recipe.parameters.foliage_style = 1
		var full := Generator.build(recipe, Color.WHITE, {}, "Dressed")
		check(not full.has("error"), "new structure supports existing foliage")
		var bare_recipe := recipe.duplicate(true)
		bare_recipe.parameters.foliage_amount = 0
		var bare := Generator.build(bare_recipe, Color.WHITE, {}, "Bare")
		check(bare.structure.lines == full.structure.lines and bare.structure.groups == full.structure.groups, "fresh leaf amount does not affect scaffold or support plan")
		var frozen_full := recipe.duplicate(true)
		frozen_full.structure = full.structure.duplicate(true)
		check(Generator.build(frozen_full, Color.WHITE, {}, "Dressed frozen").geometry.voxels == full.geometry.voxels, "existing foliage fresh/frozen exact on new scaffold")
		var store := Presets.new()
		store.directory = directory.path_join("presets")
		var preset_path := store.save_preset(frozen_full, "Varied%d" % kind)
		var preset := ResourceLoader.load(preset_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
		check(preset != null and preset.structure.is_empty() and preset.parameters.structure_diversity == 65, "preset retains diversity without frozen structure")
		var panel := GenerationPanel.new()
		root.add_child(panel)
		panel.open_for({"world_size":1.0}, recipe)
		check(panel.controls.structure_diversity.get_parent().visible, "diversity visible in creation settings")
		panel.controls.structure_diversity.value = 100
		panel.undo_local()
		check(panel.recipe.parameters.structure_diversity == 65, "diversity draft Undo")
		panel.redo_local()
		check(panel.recipe.parameters.structure_diversity == 100, "diversity draft Redo")
		check(not Generator.editing_fields(frozen_full).any(func(field): return field.key == "structure_diversity"), "frozen editing does not expose structural regeneration as dressing")
		panel.close_session()
		panel.queue_free()
	print("Voxel tree variation: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func _test_oak_composition() -> void:
	var profiles := {}
	var trunks := {}
	for seed in [17, 371, 391, 104746, 209475, 314204]:
		var recipe: Resource = Generator.creation_presets(Generator.LARGE_TREE)[1].recipe.duplicate(true)
		recipe.seed = seed
		recipe.parameters.merge({"height":96,"trunk_width":8,"crown_spread":80,"branchiness":62,"structure_diversity":100,"foliage_style":1,"foliage_detail":55,"foliage_pattern_strength":25,"foliage_along":85}, true)
		var old := recipe.duplicate(true)
		old.parameters.generation_version = 11
		var legacy := Generator.build(old, Color.WHITE, {}, "Saved v11")
		check(legacy.structure.parameters.generation_version == 11, "saved v11 stays on its original algorithm")
		var result := Generator.build(recipe, Color.WHITE, {}, "Composition")
		check(not result.has("error"), "reported settings build composed oak")
		if result.has("error"): continue
		var lines: Array = result.structure.lines
		var root_point: Vector3 = lines[4].finish
		trunks[root_point.y] = true
		var continuations := lines.filter(func(line): return line.branch and line.start == root_point and line.finish.y > root_point.y)
		check(continuations.size() == 2, "trunk transitions into two real tapered leaders")
		for leader in continuations: check(leader.r1 < leader.r0, "leader tapers instead of exposing a capped pole")
		var branches := []
		for line in lines:
			if line.branch and line.t0 == 0.0 and line.start != root_point: branches.append(snappedf(line.start.y,1.0))
		profiles[hash(branches)] = true
		check(branches != legacy.structure.lines.filter(func(line): return line.branch and line.t0 == 0.0).map(func(line): return snappedf(line.start.y,1.0)), "composition replaces fixed ascending branch ladder")
		var bare := recipe.duplicate(true)
		bare.parameters.foliage_amount = 0
		check(Generator.build(bare, Color.WHITE, {}, "Bare").structure.lines == lines, "central leaders are physical structure, not foliage filler")
		var grid: Vector3i = result.geometry.grid_size()
		var bias: Vector2i = result.pivot_bias
		var central_leaves := 0
		for y in range(ceili(root_point.y + 3), mini(grid.y, ceili(root_point.y + 20))):
			for z in range(-4,5):
				for x in range(-4,5):
					var column := Vector2i(roundi(root_point.x) + x + grid.x / 2 + bias.x, roundi(root_point.z) + z + grid.z / 2 + bias.y)
					if column.x < 0 or column.y < 0 or column.x >= grid.x or column.y >= grid.z: continue
					var tone: int = result.geometry.voxels[column.x + grid.x * (column.y + grid.z * y)]
					if tone in [4,5,6]: central_leaves += 1
		check(central_leaves > 50, "inner supported foliage breaks the systematic empty centre")
	check(profiles.size() >= 5 and trunks.size() >= 4, "reported settings produce visibly different fork-height compositions")

func _test_oak_laterals() -> void:
	var provider = Generator.LargeTreeProvider
	for branchiness in [0,62,100]:
		var plans: Array = provider.TreeVariation.oak_laterals(17,100,branchiness,6)
		check(plans.all(func(shoots): return shoots.size() == 1 + roundi(float(branchiness) / 50.0)), "branchiness controls bounded lateral count")
	var profiles := {}
	for seed in [17,371,391,104746,209475,314204]:
		var recipe: Resource = Generator.creation_presets(Generator.LARGE_TREE)[1].recipe.duplicate(true)
		recipe.seed = seed
		recipe.parameters.merge({"height":96,"trunk_width":8,"crown_spread":80,"structure_diversity":100,"foliage_style":1,"foliage_along":85}, true)
		var before := recipe.duplicate(true)
		before.parameters.generation_version = 16
		var old := Generator.build(before, Color.WHITE, {}, "Saved16")
		var result := Generator.build(recipe, Color.WHITE, {}, "Laterals")
		check(not result.has("error"), "reported lateral oak builds")
		if result.has("error"): continue
		var primary = func(line): return not line.branch or line.t0 == 0.0
		check(result.structure.lines.filter(primary) == old.structure.lines.filter(primary), "secondary upgrade preserves exact primary composition16")
		var starts: Array = result.structure.lines.filter(func(line): return line.t0 == 0.40)
		check(starts.size() >= 8 and starts.all(func(line): return line.physical and line.branch and Vector2(line.finish.x-line.start.x,line.finish.z-line.start.z).length() > absf(line.finish.y-line.start.y)), "physical secondary branches reach sideways rather than towards the top")
		for line in starts:
			var supports: Array = result.structure.lines.filter(func(parent): return parent.t0 == 0.35)
			check(supports.any(func(parent): return Geometry3D.get_closest_point_to_segment(line.start,parent.start,parent.finish).distance_to(line.start) < 0.30), "secondary branch anchors on the main limb")
		profiles[hash(starts)] = true
		var frozen := before.duplicate(true)
		frozen.structure = old.structure.duplicate(true)
		frozen.parameters.generation_version = 17
		check(Generator.build(frozen,Color.WHITE,{},"Still16").geometry.voxels == old.geometry.voxels, "saved frozen16 never silently gains lateral branches")
	check(profiles.size() == 6, "secondary placement differs across seeds")
