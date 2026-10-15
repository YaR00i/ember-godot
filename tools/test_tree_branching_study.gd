extends SceneTree
const Fixture = preload("res://scripts/prototypes/ember_tree_branching_fixture.gd")
const Provider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Layout = preload("res://addons/ember_import/ember_tree_branch_layout.gd")
const Recipe = preload("res://addons/ember_import/ember_voxel_generator_recipe.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Restored = preload("res://scripts/prototypes/ember_smooth_tree_material_fixture.gd")
var errors: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var old := Restored.new().build()
	check(old.source_sha256 == "7394d61bdfc6754f001a9bde18263817633f36becc6711f0d3e1df55f4334a26", "saved oak17 bytes unchanged")
	check(Provider.LATEST_VERSIONS[1] == 17 and Provider.normalize({"generation_version": 22, "tree_type": 1}).generation_version == 17, "opt-in18/19 do not upgrade presets or invalid versions")
	var built := Fixture.build()
	var again := Fixture.build()
	check(built.source.validation_errors().is_empty(), "canonical voxel Source18")
	check(Provider.structure_errors(built.structure).is_empty(), "valid bounded hierarchy")
	check(built.structure.lines.size() <= 128 and built.layout.size() == 48, "current support budget")
	check(built.source.voxels == again.source.voxels and built.cards.mesh.surface_get_arrays(0) == again.cards.mesh.surface_get_arrays(0), "seed reproduces Source, cards, UV and normals")
	for seed in [0, 1, 7, 31, 197, 74019]:
		var plan := Layout.plan(Provider.normalize(built.parameters), seed)
		for branch: Dictionary in plan:
			check(branch.radius > branch.tip_radius and branch.tip_radius > 0, "all branches progressively taper")
			if branch.parent >= 0:
				var parent: Dictionary = plan[branch.parent]
				check(branch.path[0].distance_to(Layout.sample(parent.path, branch.attachment)) < 0.0001, "child starts on actual parent")
				check(branch.radius < Layout.radius(parent, branch.attachment), "child thinner than parent at attachment")
	var damaged: Dictionary = built.structure.duplicate(true)
	damaged.lines[8].parent_id = 99
	check(not Provider.structure_errors(damaged).is_empty(), "reject broken hierarchy")
	damaged = built.structure.duplicate(true); damaged.lines[0].branch_id = -1
	check(not Provider.structure_errors(damaged).is_empty(), "reject negative branch index without invalid array access")
	var recipe := Recipe.new(); recipe.generator_id = "large_tree"; recipe.seed = 7
	recipe.parameters = built.parameters; recipe.structure = built.structure
	check(ResourceSaver.save(recipe, "user://branching-recipe.tres") == OK and ResourceSaver.save(built.source, "user://branching-source.tres") == OK, "private fixture save")
	var reopened: Resource = ResourceLoader.load("user://branching-source.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var reopened_recipe: Resource = ResourceLoader.load("user://branching-recipe.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.voxels == built.source.voxels and reopened.palette == built.source.palette, "Source reopen exact")
	check(Provider.structure_errors(reopened_recipe.structure).is_empty(), "recipe reopen hierarchy")
	check(Generator.validation_errors(reopened_recipe).is_empty(), "existing recipe router accepts explicit LAB18")
	var rebuilt := Generator.build(reopened_recipe, Color.WHITE, {}, "Reopened", "branching_oak_lab")
	check(not rebuilt.has("error") and rebuilt.geometry.voxels == built.source.voxels and rebuilt.geometry.collision_voxels == built.source.collision_voxels, "existing recipe rebuild preserves thin tips and Source")
	var arrays: Array = built.cards.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in built.cards.roots.size():
		var root: Dictionary = built.cards.roots[i]
		var index: int = i * 4
		# Sprite stem UV(.125,.93) must land on a real branch, not a cloud center.
		var texture_root := vertices[index] + (vertices[index + 1] - vertices[index]) * 0.125 + (vertices[index + 3] - vertices[index]) * 0.07
		check(texture_root.distance_to(root.point) < 0.0001, "sprite root attached to twig")
		var branch: Dictionary = built.layout[root.branch]
		var offset := Vector3(built.pivot_bias.x, 0, built.pivot_bias.y)
		check(root.point.distance_to((Fixture.point_at(branch, root.t) + offset) / 16.0) < 0.0001, "leaf support owned by shared scaffold")
	check(built.cards.cards == 366 and built.cards.triangles == 732, "bounded batched canopy")
	print("TREE_BRANCHING_TEST ", "PASS" if errors.is_empty() else errors, " supports=", built.structure.lines.size(), " cards=", built.cards.cards)
	quit(0 if errors.is_empty() else 1)
