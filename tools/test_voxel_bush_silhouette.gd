extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
var errors: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)

func build(recipe: Resource) -> EmberVoxelModelResource:
	var result := Generator.build(recipe, Color.WHITE, {}, "Базовый куст")
	check(not result.has("error"), "basic build")
	return result.get("geometry")

func connected(source: EmberVoxelModelResource) -> bool:
	var grid := source.grid_size()
	var first := -1
	for index in source.voxels.size():
		if source.voxels[index] != 0:
			first = index
			break
	if first < 0: return false
	var queue: Array[int] = [first]
	var seen := {first: true}
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var cell := Vector3i(index % grid.x, index / (grid.x * grid.z), (index / grid.x) % grid.z)
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
			var next: Vector3i = cell + direction
			if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= grid.x or next.y >= grid.y or next.z >= grid.z: continue
			var key := Model.index_of(next, grid)
			if source.voxels[key] != 0 and not seen.has(key):
				seen[key] = true
				queue.append(key)
	return seen.size() == source.voxels.size() - source.voxels.count(0)

func leaf_slice(source: EmberVoxelModelResource, y: int) -> int:
	var grid := source.grid_size()
	var result := 0
	for value in source.voxels.slice(y * grid.x * grid.z, (y + 1) * grid.x * grid.z):
		if value >= 4: result += 1
	return result

func _run() -> void:
	var presets := Generator.creation_presets(Generator.BUSH)
	check(presets[0].recipe.parameters.generation_version == 5 and presets[0].recipe.parameters.foliage_style == 3, "cloud base opts in explicitly")
	var limits := Generator.normalized_parameters(Generator.BUSH, {"generation_version": 5, "base_height": 999, "stem_count": 0})
	check(limits.base_height == 32 and limits.stem_count == 1, "new base and branch limits")
	for version in [2, 3, 4]:
		var old := Generator.normalized_parameters(Generator.BUSH, {"generation_version": version})
		check(not old.has("base_height"), "old recipes do not acquire new base parameter")
	check(presets[1].recipe.parameters.generation_version == 6 and presets[2].recipe.parameters.generation_version == 6, "other forms explicitly opt in cloud profiles")
	for seed in [0, 73, 391]:
		var recipe: Resource = presets[0].recipe.duplicate(true)
		recipe.parameters.generation_version = 3
		recipe.parameters.foliage_pattern_strength = 0
		recipe.parameters.height = 24
		recipe.seed = seed
		var source := build(recipe)
		check(source != null and source.validation_errors().is_empty() and connected(source), "valid connected base seed " + str(seed))
		check(source.palette[4] == source.palette[5] and source.palette[5] == source.palette[6], "one authored foliage colour")
		check(leaf_slice(source, 3) > leaf_slice(source, 16), "broad low foundation, not pointed bottom")
		var old: Resource = recipe.duplicate(true)
		old.parameters.generation_version = 2
		var previous := build(old)
		check(source.voxels != previous.voxels, "base silhouette differs from old crown")
		var reopened: Resource = old.duplicate(true)
		reopened.parameters = Generator.normalized_parameters(Generator.BUSH, old.parameters)
		check(reopened.parameters.generation_version == 2 and build(reopened).voxels == previous.voxels, "saved v2 does not silently upgrade")
	for seed in [0, 73, 391, 17, 99]:
		for style in [1, 3]:
			var recipe: Resource = presets[0].recipe.duplicate(true)
			recipe.parameters.generation_version = 4
			recipe.seed = seed
			recipe.parameters.foliage_style = style
			var source := build(recipe)
			check(source != null and source.validation_errors().is_empty() and connected(source), "shoot connected seed/style " + str(seed) + "/" + str(style))
			check(source.voxels.count(1) > 30, "real ground shoots and petioles")
			var previous: Resource = recipe.duplicate(true)
			previous.parameters.generation_version = 3
			check(source.voxels != build(previous).voxels, "shoots replace domes")
			var roundtrip: Resource = recipe.duplicate(true)
			roundtrip.parameters = Generator.normalized_parameters(Generator.BUSH, recipe.parameters)
			check(source.voxels == build(roundtrip).voxels, "normalized shoots reproduce source")
	for seed in [0, 73, 391, 17, 99]:
		for style in [1, 3]:
			var recipe: Resource = presets[0].recipe.duplicate(true)
			recipe.seed = seed
			recipe.parameters.foliage_style = style
			var source := build(recipe)
			check(source.validation_errors().is_empty() and connected(source), "clouds connected")
			var raised: Resource = recipe.duplicate(true)
			raised.parameters.base_height = 18
			var lifted := build(raised)
			var shift := int(raised.parameters.base_height) - int(recipe.parameters.base_height)
			var grid := source.grid_size()
			for index in source.voxels.size():
				if source.voxels[index] < 4: continue
				var cell := Vector3i(index % grid.x, index / (grid.x * grid.z), (index / grid.x) % grid.z)
				check(lifted.voxels[Model.index_of(cell + Vector3i.UP * shift, lifted.grid_size())] >= 1, "base height translates clouds without stretching")
			check(connected(lifted), "raised clouds connected")
			for count in [1, 12]:
				raised.parameters.stem_count = count
				check(connected(build(raised)), "branch count extremes connected")
	for entry in presets.slice(1):
		var maximum: Resource = entry.recipe.duplicate(true)
		maximum.parameters.merge({"height": 96, "spread_radius": 30, "density": 32, "base_height": 32, "stem_count": 12}, true)
		var large := build(maximum)
		check(large.voxels.size() <= 524288 and large.validation_errors().is_empty() and connected(large), "profile maximum storage and geometry")
		for seed in [0, 73, 391]:
			for style in [1, 3]:
				var recipe: Resource = entry.recipe.duplicate(true)
				recipe.seed = seed
				recipe.parameters.foliage_style = style
				var source := build(recipe)
				check(source.validation_errors().is_empty() and connected(source), "new profiles valid and connected")
				var roundtrip: Resource = recipe.duplicate(true)
				roundtrip.parameters = Generator.normalized_parameters(Generator.BUSH, recipe.parameters)
				check(build(roundtrip).voxels == source.voxels, "profile exact normalized roundtrip")
				var previous: Resource = recipe.duplicate(true)
				previous.parameters.generation_version = 2
				check(source.voxels != build(previous).voxels, "new profile differs from v2")
				for count in [1, 12]:
					for floor_height in [0, 32]:
						roundtrip.parameters.merge({"stem_count": count, "base_height": floor_height}, true)
						check(connected(build(roundtrip)), "profile branch/base extremes")
	for version in [1, 2, 3, 4, 5, 6]:
		var settings := Generator.normalized_parameters(Generator.BUSH, {"generation_version": version})
		check(int(settings.get("generation_version", 1)) == version, "normalization preserves old version")
	for message in errors: push_error(message)
	print("test_voxel_bush_silhouette: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size(), " errors")
	quit(0 if errors.is_empty() else 1)
