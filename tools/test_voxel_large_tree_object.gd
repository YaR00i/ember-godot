extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const SculptActions = preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")
const ObjectSession = preload("res://addons/ember_import/ember_voxel_object_session.gd")

var failures := 0


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var builds := {}
	for height in [64, 128, 256]:
		var recipe := Generator.default_recipe(Generator.LARGE_TREE)
		recipe.seed = 371
		recipe.parameters.height = height
		recipe.parameters.density = 16
		var started := Time.get_ticks_usec()
		var built := Generator.build(recipe, Color.WHITE, {}, "Дерево %d" % height)
		var elapsed := Time.get_ticks_usec() - started
		print("Large tree %d vox: %.2f ms" % [height, float(elapsed) / 1000.0])
		check(not built.has("error"), "large tree %d build" % height)
		if built.has("error"):
			continue
		var source: EmberVoxelModelResource = built.geometry
		builds[height] = source
		check(source.height_voxels == height, "large tree %d honest height" % height)
		var validation := source.validation_errors()
		check(validation.is_empty(), "large tree %d canonical source: %s" % [height, validation])
		check(source.tags.has("large_tree") and not source.tags.has("stamp"), "large tree is an object")
		check(source.voxels.count(0) < source.voxels.size(), "large tree %d visible voxels" % height)
		check(_layer_count(source, height - 1) > 0, "large tree %d reaches requested height" % height)
		check(source.collision_voxels.size() == source.voxels.size(), "large tree %d collision channel" % height)
		check(source.collision_voxels.count(1) > 0, "large tree %d trunk collision" % height)
		check(source.collision_voxels.count(0) > source.collision_voxels.count(1), "large tree %d leaves do not collide" % height)
		check(source.to_definition().model.collisionVoxels.size() == source.voxels.size(), "large tree collision serialization")
		if height == 256:
			var boundary_started := Time.get_ticks_usec()
			var boundary_packed := EmberVoxelPrefab.prepare_resource(source)
			print("Large tree 256 prefab: %.2f ms" % (float(Time.get_ticks_usec() - boundary_started) / 1000.0))
			check(boundary_packed != null, "large tree 256 exact prefab")
	check(builds.size() == 3, "all boundary sizes generated")
	if not builds.has(64):
		_finish()
		return
	var deterministic_recipe := Generator.default_recipe(Generator.LARGE_TREE)
	deterministic_recipe.seed = 371
	deterministic_recipe.parameters.height = 64
	var repeated := Generator.build(deterministic_recipe, Color.WHITE, {}, "Дерево 64")
	check(not repeated.has("error") and repeated.geometry.voxels == builds[64].voxels, "large tree seed determinism")
	var packed := EmberVoxelPrefab.prepare_resource(builds[64])
	check(packed != null, "large tree exact prefab")
	if packed != null:
		var prop := packed.instantiate() as EmberVoxelProp
		var visual := prop.get_node_or_null("Mesh") as MeshInstance3D
		var collision := prop.get_node_or_null("Collision/Shape") as CollisionShape3D
		check(visual != null and visual.mesh != null, "large tree visual mesh")
		check(collision != null and collision.shape != null, "large tree physical trunk")
		if collision != null and collision.shape is ConcavePolygonShape3D and visual != null:
			check(collision.shape.get_faces().size() < _mesh_face_vertices(visual.mesh), "collision excludes foliage")
		prop.free()
	_test_sculpt_collision(builds[64])
	_test_shapes()
	await _creation_roundtrip()
	_finish()


func _test_shapes() -> void:
	var provider := preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
	var legacy := Generator.default_recipe(Generator.LARGE_TREE)
	legacy.parameters = {"height": 64}
	var old := Generator.build(legacy, Color.WHITE, {}, "Legacy")
	check(old.parameters.generation_version == 1, "missing recipe version must retain classic")
	legacy.parameters["generation_version"] = 1
	legacy.parameters["branch_thickness"] = 100
	var old_again := Generator.build(legacy, Color.WHITE, {}, "Legacy")
	check(old.geometry.voxels == old_again.geometry.voxels, "new controls changed classic recipe")
	var recipe := Generator.default_recipe(Generator.LARGE_TREE)
	recipe.parameters.height = 64
	var base := Generator.build(recipe, Color.WHITE, {}, "Sculpted")
	check(base.parameters.generation_version == 2, "new recipe must default to sculpted")
	var size: Vector3i = base.geometry.grid_size()
	var top_wood := 0
	for z in size.z:
		for x in size.x:
			var value := int(base.geometry.voxels[VoxMesher.cell_index(x, 63, z, size.x, size.z)])
			if value > 0 and value < 4:
				top_wood += 1
	check(top_wood == 0, "top foliage headroom contains a clipped wooden spike")
	check(_connected_count(base.geometry) == base.geometry.voxels.size() - base.geometry.voxels.count(0), "sculpted tree has detached voxels")
	for field in ["branch_thickness", "branch_taper", "branch_curve", "branch_start", "cluster_size", "cluster_flatten", "canopy_cohesion", "root_flare", "crown_shape"]:
		var changed := recipe.duplicate(true)
		changed.parameters[field] = 1 if field == "crown_shape" else (65 if field == "cluster_size" else 0)
		var built := Generator.build(changed, Color.WHITE, {}, "Changed")
		check(not built.has("error"), "shape control build " + field)
		if not built.has("error"):
			check(built.geometry.voxels != base.geometry.voxels, "shape control has no effect " + field)
	var extreme := provider.defaults()
	recipe.parameters.crown_shape = 2
	var tiered := Generator.build(recipe, Color.WHITE, {}, "Tiered")
	check(not tiered.has("error") and tiered.geometry.voxels != base.geometry.voxels, "tiered crown is distinct")
	extreme.merge({"height": 256, "trunk_width": 24, "crown_spread": 85, "cluster_size": 180, "canopy_cohesion": 100}, true)
	var boundary := provider.build(extreme, 52, Color.WHITE, {}, "Boundary")
	check(not boundary.has("error"), "sculpted extreme respects storage envelope")
	if not boundary.has("error"):
		check(boundary.geometry.validation_errors().is_empty(), "extreme source validation")


func _connected_count(source: EmberVoxelModelResource) -> int:
	var size := source.grid_size()
	var plane := size.x * size.z
	var first := -1
	for index in source.voxels.size():
		if source.voxels[index] != 0:
			first = index
			break
	if first < 0:
		return 0
	var queue := PackedInt32Array([first])
	var seen := {first: true}
	var cursor := 0
	while cursor < queue.size():
		var index := queue[cursor]
		cursor += 1
		var neighbors := [index - plane, index + plane]
		if index % size.x > 0:
			neighbors.append(index - 1)
		if index % size.x < size.x - 1:
			neighbors.append(index + 1)
		if index % plane >= size.x:
			neighbors.append(index - size.x)
		if index % plane < plane - size.x:
			neighbors.append(index + size.x)
		for neighbor in neighbors:
			if neighbor >= 0 and neighbor < source.voxels.size() and source.voxels[neighbor] != 0 and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return seen.size()


func _creation_roundtrip() -> void:
	var directory := "user://voxel_large_tree_%d" % Time.get_ticks_usec()
	var creation := Creation.new()
	creation.source_directory = directory.path_join("models")
	creation.prefab_directory = directory.path_join("prefabs")
	creation.recipe_directory = directory.path_join("recipes")
	creation.world_size = 16.0
	var settings := Generator.normalized_parameters(Generator.LARGE_TREE, {"height": 64})
	settings.generation_version = 2
	check(creation.prepare(settings, 913, "Большой дуб"), "large tree creation prepare")
	if creation.source == null:
		return
	var root_node := Node3D.new()
	root.add_child(root_node)
	var props := Node3D.new()
	props.name = "Props"
	root_node.add_child(props)
	props.owner = root_node
	var undo := UndoRedo.new()
	var prop := creation.commit(root_node, props, undo, Vector3(2, 0, 3))
	check(prop != null and prop.get_parent() == props, "large tree create and place")
	var model_id := creation.source.model_id
	var source_path := creation.source_directory.path_join(model_id + ".tres")
	var prefab_path := creation.prefab_directory.path_join(model_id + ".tscn")
	var recipe_path := Creation.recipe_path(model_id, creation.recipe_directory)
	check(FileAccess.file_exists(source_path) and FileAccess.file_exists(prefab_path), "large tree source and prefab save")
	check(FileAccess.file_exists(recipe_path), "large tree companion recipe save")
	var reopened := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	var recipe := Creation.load_recipe(model_id, creation.recipe_directory)
	check(reopened != null and reopened.collision_voxels == creation.source.collision_voxels, "large tree save/reopen")
	check(recipe != null and recipe.generator_id == Generator.LARGE_TREE and recipe.seed == 913, "large tree recipe reopen")
	check(recipe.parameters.generation_version == 2 and recipe.parameters.branch_thickness == settings.branch_thickness, "shape recipe controls survive save/reopen")
	var edit := ObjectSession.new()
	edit.source_directory = creation.source_directory
	edit.prefab_directory = creation.prefab_directory
	check(edit.open(prop, root_node, undo, true), "large tree reopens in ordinary Object Canvas session")
	if edit.draft != null:
		check(edit.draft.to_definition().model == reopened.to_definition().model, "large tree Canvas draft matches saved source")
	undo.undo()
	check(prop.get_parent() == null, "large tree placement Undo")
	undo.redo()
	check(prop.get_parent() == props, "large tree placement Redo")
	root_node.free()
	undo.clear_history()
	undo.free()


func _mesh_face_vertices(mesh: ArrayMesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		count += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	return count


func _layer_count(source: EmberVoxelModelResource, y: int) -> int:
	var size := source.grid_size()
	var count := 0
	for z in size.z:
		for x in size.x:
			if source.voxels[VoxMesher.cell_index(x, y, z, size.x, size.z)] != 0:
				count += 1
	return count


func _test_sculpt_collision(source: EmberVoxelModelResource) -> void:
	var editable := source.duplicate(true) as EmberVoxelModelResource
	var empty := editable.voxels.find(0)
	var solid := editable.collision_voxels.find(1)
	var undo := UndoRedo.new()
	var actions := SculptActions.new()
	actions.configure(undo)
	var add_change := {}
	add_change[empty] = {"before": 0, "after": 1}
	check(actions.apply_stroke(editable, add_change), "tree Canvas add stroke")
	check(editable.voxels[empty] == 1 and editable.collision_voxels[empty] == 1, "new hand-sculpted voxel is physical")
	undo.undo()
	check(editable.voxels[empty] == 0 and editable.collision_voxels[empty] == 0, "tree collision add Undo")
	undo.redo()
	check(editable.voxels[empty] == 1 and editable.collision_voxels[empty] == 1, "tree collision add Redo")
	var remove_change := {}
	remove_change[solid] = {"before": int(editable.voxels[solid]), "after": 0}
	check(actions.apply_stroke(editable, remove_change), "tree Canvas remove stroke")
	check(editable.voxels[solid] == 0 and editable.collision_voxels[solid] == 0, "removed trunk clears collision")
	undo.undo()
	check(editable.voxels[solid] != 0 and editable.collision_voxels[solid] == 1, "tree collision remove Undo")
	undo.clear_history()
	undo.free()


func _finish() -> void:
	print("Voxel large tree object: ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
