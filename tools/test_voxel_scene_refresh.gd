extends SceneTree

const Refresh = preload("res://addons/ember_import/ember_voxel_scene_refresh.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const ProjectionScript = preload("res://scripts/ember_voxel_surface_projection.gd")
const NativeMesher = preload("res://scripts/ember_voxel_native_mesher.gd")
var errors: Array[String] = []
var fixture := "user://ember-tests/scene-refresh-%d-%d" % [Time.get_unix_time_from_system(), OS.get_process_id()]


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)


func _winding(mesh: ArrayMesh, label: String) -> void:
	var bottom_count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for first in range(0, indices.size(), 3):
			var a := indices[first]
			var b := indices[first + 1]
			var c := indices[first + 2]
			var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
			check(cross.dot(normals[a]) < -0.00000001, label + ": triangle winding agrees with outward normal instead of clockwise")
			if normals[a].dot(Vector3.DOWN) > 0.9999: bottom_count += 1
	check(bottom_count > 0, label + ": no bottom triangles")


func _source(id: String) -> EmberVoxelModelResource:
	var source := EmberVoxelModelResource.new()
	source.model_id = id
	source.display_name = id
	source.voxels_per_block = 16
	source.size_blocks = Vector3i.ONE
	source.height_voxels = 2
	source.physical = true
	source.palette = PackedColorArray([Color.TRANSPARENT, Color("98622d"), Color("438dc4")])
	source.voxels.resize(16 * 2 * 16)
	source.voxels.fill(1)
	return source


func _old_prefab(source: EmberVoxelModelResource) -> PackedScene:
	var prop := EmberVoxelPrefab.prepare_resource(source).instantiate() as EmberVoxelProp
	prop.scene_file_path = ""
	var visual := prop.get_node("Mesh") as MeshInstance3D
	visual.mesh = Session._legacy_bottom_mesh(visual.mesh)
	var physics := EmberVoxelPrefab._collision_mesh(source.to_definition().model, 1.0 / source.normalized_density())
	prop.get_node("Collision/Shape").shape = (Session._legacy_bottom_mesh(physics) if physics != null else visual.mesh).create_trimesh_shape()
	var packed := PackedScene.new()
	check(packed.pack(prop) == OK, "old prefab pack")
	prop.free()
	return packed


func _capture(scene: Node3D, suffix: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	if scene.get_node_or_null("CaptureCamera") == null:
		var camera := Camera3D.new()
		camera.name = "CaptureCamera"
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 100
		scene.add_child(camera)
		camera.position = Vector3(100, -55, 80)
		camera.look_at(Vector3(50, 0, 0))
		camera.current = true
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_COLOR
		world.environment.background_color = Color("101923")
		world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world.environment.ambient_light_color = Color.WHITE
		world.environment.ambient_light_energy = 1.0
		scene.add_child(world)
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://voxel-scene-refresh-%s.png" % suffix
	root.get_texture().get_image().save_png(path)
	print("REFRESH_CAPTURE ", ProjectSettings.globalize_path(path))


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var sources := fixture.path_join("sources")
	var prefabs := fixture.path_join("prefabs")
	var source := _source("opaque")
	var glass := _source("transparent")
	glass.transparency.resize(glass.voxels.size())
	glass.transparency.fill(150)
	glass.collision_voxels.resize(glass.voxels.size())
	glass.collision_voxels.fill(0)
	glass.collision_voxels[0] = 1
	var models := [source, glass]
	var before_hashes := {}
	var before_bytes := {}
	var before_uids := {}
	var props: Array[EmberVoxelProp] = []
	for model in models:
		var source_path := sources.path_join(model.model_id + ".tres")
		var prefab_path := prefabs.path_join(model.model_id + ".tscn")
		check(Store.install_prepared_asset(model, _old_prefab(model), source_path, prefab_path).ok, "fixture installs")
		check(Store.install_derived_prefab(_old_prefab(model), prefab_path, "previous-bottom-contract").ok, "old fixture installs")
		before_hashes[model.model_id] = FileAccess.get_sha256(source_path)
		before_bytes[model.model_id] = FileAccess.get_file_as_bytes(prefab_path)
		before_uids[model.model_id] = EmberVoxelPrefab.resource_uid_from_header(prefab_path)
		var packed := load(prefab_path) as PackedScene
		for index in 2:
			var prop := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as EmberVoxelProp
			prop.name = model.model_id + str(index)
			prop.placement_id = prop.name
			scene.add_child(prop)
			prop.owner = scene
			prop.position = Vector3(props.size() * 20, 0, 0)
			prop.rotation.y = 0.15
			prop.get_node("Mesh").layers = 3
			props.append(prop)
	var socket := Node3D.new()
	socket.name = "AuthoredSocket"
	props[0].get_node("Mesh").add_child(socket)
	socket.owner = scene
	var pose := props[0].transform
	var old_mesh: ArrayMesh = props[0].get_node("Mesh").mesh
	var old_shape: Shape3D = props[0].get_node("Collision/Shape").shape
	var old_arrays := old_mesh.surface_get_arrays(0)
	var material_override := StandardMaterial3D.new()
	props[0].get_node("Mesh").set_surface_override_material(0, material_override)
	var saved_scene := PackedScene.new()
	check(saved_scene.pack(scene) == OK, "original scene pack")
	var scene_path := fixture.path_join("scene.tscn")
	check(ResourceSaver.save(saved_scene, scene_path) == OK, "original scene save")
	var map_hash := FileAccess.get_sha256(scene_path)
	var projection := ProjectionScript.new()
	scene.add_child(projection)
	projection.position.x = 90
	projection.configure(source, 16.0, Vector2i.ONE, null)
	while projection.drain_next_chunk(): pass
	var surface_mesh: Mesh = projection._chunks[Vector2i.ZERO].mesh
	await _capture(scene, "before")
	var operation := Refresh.new()
	operation.source_directory = sources
	operation.prefab_directory = prefabs
	var result: Dictionary = await operation.refresh(scene, undo)
	check(result.ok and result.models == 2 and result.instances == 4 and result.surfaces == 1 and result.skipped.is_empty(), "batch result: " + str(result))
	print("REFRESH_TIMING ", result.get("elapsed_usec", 0) / 1000.0, "ms / 2 models, 4 props")
	check(FileAccess.get_sha256(scene_path) == map_hash, "refresh rewrote authored scene")
	check(props[0].transform == pose and props[0].placement_id == "opaque0" and props[0].get_node("Mesh/AuthoredSocket") == socket and socket.owner == scene, "refresh lost placement/authored descendants")
	check(props[0].get_node("Mesh").layers == 3, "refresh lost presentation override")
	check(props[0].get_node("Mesh").get_surface_override_material(0) == material_override, "refresh lost instance surface material override")
	check(props[0].get_node("Mesh").mesh != old_mesh and props[0].get_node("Collision/Shape").shape != old_shape, "open instance retains stale inline mesh/shape")
	check(old_mesh.surface_get_arrays(0) == old_arrays, "refresh mutated old cached mesh snapshot")
	for prop in props: _winding(prop.get_node("Mesh").mesh, prop.name)
	while projection.drain_next_chunk(): pass
	check(projection._chunks[Vector2i.ZERO].mesh != surface_mesh, "same Resource Surface refresh did not rebuild chunks")
	_winding(projection._chunks[Vector2i.ZERO].mesh, "Surface")
	await _capture(scene, "after")
	for model in models:
		check(FileAccess.get_sha256(sources.path_join(model.model_id + ".tres")) == before_hashes[model.model_id], "refresh rewrote canonical source")
		check(EmberVoxelPrefab.resource_uid_from_header(prefabs.path_join(model.model_id + ".tscn")) == before_uids[model.model_id], "refresh changed prefab UID")
	var fresh_mesh: Mesh = props[0].get_node("Mesh").mesh
	undo.undo()
	check(props[0].get_node("Mesh").mesh == old_mesh and props[0].get_node("Collision/Shape").shape == old_shape, "Undo did not restore old geometry")
	for model in models:
		check(FileAccess.get_file_as_bytes(prefabs.path_join(model.model_id + ".tscn")) == before_bytes[model.model_id], "Undo did not restore exact prefab bytes")
	undo.redo()
	check(props[0].get_node("Mesh").mesh == fresh_mesh, "Redo did not restore prepared geometry")
	var current := Refresh.new()
	current.source_directory = sources
	current.prefab_directory = prefabs
	result = await current.refresh(scene, undo)
	check(result.models == 0 and result.instances == 0, "current props were rebuilt unnecessarily")
	var scene_after := PackedScene.new()
	check(scene_after.pack(scene) == OK and ResourceSaver.save(scene_after, scene_path) == OK, "updated scene save")
	var reopened := (ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	_winding(reopened.get_node("opaque0/Mesh").mesh, "reopened instance")
	reopened.free()
	# Non-bottom custom mesh is never silently replaced.
	var damaged := ArrayMesh.new()
	var arrays := old_arrays.duplicate(true)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
	vertices[0].x += 0.05
	arrays[Mesh.ARRAY_VERTEX] = vertices
	damaged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	damaged.surface_set_name(0, old_mesh.surface_get_name(0))
	props[0].get_node("Mesh").mesh = damaged
	var blocked := Refresh.new()
	blocked.source_directory = sources
	blocked.prefab_directory = prefabs
	var untouched_prefab := FileAccess.get_file_as_bytes(prefabs.path_join("opaque.tscn"))
	result = await blocked.refresh(scene, undo, "opaque", false)
	check(result.models == 0 and result.skipped.size() == 1 and props[0].get_node("Mesh").mesh == damaged and FileAccess.get_file_as_bytes(prefabs.path_join("opaque.tscn")) == untouched_prefab, "manual geometry was overwritten")
	props[0].get_node("Mesh").mesh = fresh_mesh
	var changed_material := Session._legacy_bottom_mesh(fresh_mesh)
	changed_material.surface_set_material(0, StandardMaterial3D.new())
	props[0].get_node("Mesh").mesh = changed_material
	result = await blocked.refresh(scene, undo, "opaque", false)
	check(result.models == 0 and result.skipped.size() == 1 and props[0].get_node("Mesh").mesh == changed_material, "custom mesh surface material was overwritten")
	# Indexed storage alone is compatible, but colors, tangents and triangle
	# multiplicity remain part of the strict comparison.
	var Equivalence = load("res://addons/ember_import/ember_voxel_projection_equivalence.gd")
	var indexer := SurfaceTool.new()
	indexer.create_from(old_mesh, 0)
	indexer.index()
	var indexed := indexer.commit()
	indexed.surface_set_name(0, old_mesh.surface_get_name(0))
	indexed.surface_set_material(0, old_mesh.surface_get_material(0))
	check(Equivalence.mesh_scale(indexed, old_mesh, 16) == 1.0, "equivalent vertex indexing rejected")
	var tinted_arrays := indexed.surface_get_arrays(0)
	var tinted_colors: PackedColorArray = tinted_arrays[Mesh.ARRAY_COLOR].duplicate()
	tinted_colors[0] = Color.MAGENTA
	tinted_arrays[Mesh.ARRAY_COLOR] = tinted_colors
	var tinted := ArrayMesh.new()
	tinted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tinted_arrays)
	tinted.surface_set_name(0, old_mesh.surface_get_name(0))
	tinted.surface_set_material(0, old_mesh.surface_get_material(0))
	check(Equivalence.mesh_scale(tinted, old_mesh, 16) == 0.0, "custom indexed vertex color overwritten")
	if NativeMesher.available():
		var native := NativeMesher.new().build_region(source.voxels, source.grid_size(), source.palette, PackedByteArray(), Vector3i.ZERO, source.grid_size(), 1.0 / 16.0, null, null)
		check(not native.is_empty(), "native mesher did not build")
		if not native.is_empty(): _winding(native.mesh, "native")
	# Whole catalog includes objects not placed in any scene, deduplicates IDs,
	# forces current assets, and cancellation is observed between models.
	var library := Refresh.new()
	library.source_directory = sources
	library.prefab_directory = prefabs
	var ids: Array[String] = ["transparent", "opaque", "transparent"]
	var library_old := FileAccess.get_file_as_bytes(prefabs.path_join("opaque.tscn"))
	var rename_calls := [0]
	Store.derived_rename_override = func(temporary: String, destination: String):
		rename_calls[0] += 1
		if rename_calls[0] <= 2: return FAILED
		return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination))
	result = await library.rebuild_library(ids, scene, null, undo)
	Store.derived_rename_override = Callable()
	check(rename_calls[0] == 4, "transient publication did not retry twice then publish both models")
	check(result.rebuilt == 2 and result.total == 2 and not result.cancelled and result.skipped.is_empty(), "whole library outside scene: " + str(result))
	undo.undo()
	check(FileAccess.get_file_as_bytes(prefabs.path_join("opaque.tscn")) == library_old, "catalog asset Undo did not restore bytes")
	undo.redo()
	if OS.get_name() == "Windows":
		var locked_path := prefabs.path_join("transparent.tscn")
		var lock_box := [FileAccess.open(locked_path, FileAccess.READ)]
		var release_at := Time.get_ticks_msec() + 250
		var release_lock := func():
			if Time.get_ticks_msec() >= release_at and not lock_box.is_empty():
				lock_box[0].close()
				lock_box.clear()
		process_frame.connect(release_lock)
		var attempts := [0]
		Store.derived_rename_override = func(temporary: String, destination: String):
			attempts[0] += 1
			return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination))
		var locked_ids: Array[String] = ["transparent"]
		result = await library.rebuild_library(locked_ids, scene, null, undo)
		Store.derived_rename_override = Callable()
		process_frame.disconnect(release_lock)
		if not lock_box.is_empty(): lock_box[0].close()
		check(result.rebuilt == 1 and attempts[0] > 1 and result.skipped.is_empty(), "real Windows read handle did not release/retry successfully: " + str(result))
		print("WINDOWS_READ_LOCK_RETRY ", attempts[0], " attempts")
	var cancelling := Refresh.new()
	cancelling.source_directory = sources
	cancelling.prefab_directory = prefabs
	cancelling.library_progress.connect(func(done: int, _total: int, _id: String):
		if done == 1: cancelling.cancel_library()
	)
	result = await cancelling.rebuild_library(ids, scene, null, undo)
	for connection in cancelling.library_progress.get_connections():
		cancelling.library_progress.disconnect(connection.callable)
	check(result.cancelled and result.completed == 1 and result.rebuilt == 1, "cancel does not stop between catalog models: " + str(result))
	for model in models:
		check(FileAccess.get_sha256(sources.path_join(model.model_id + ".tres")) == before_hashes[model.model_id], "library rebuild changed source")
	var unbuilt := _source("unbuilt")
	check(ResourceSaver.save(unbuilt, sources.path_join("unbuilt.tres")) == OK, "unbuilt source fixture saves")
	var creating := Refresh.new()
	creating.source_directory = sources
	creating.prefab_directory = prefabs
	check(creating.rebuild_catalog_model("unbuilt", null, undo).ok and FileAccess.file_exists(prefabs.path_join("unbuilt.tscn")), "library cannot build an object without a prefab")
	undo.undo()
	check(FileAccess.file_exists(prefabs.path_join("unbuilt.tscn")), "Undo deleted a recoverable new derived asset")
	check(EmberVoxelPrefab.resource_uid_from_header(prefabs.path_join("unbuilt.tscn")) != ResourceUID.INVALID_ID, "never-built prefab UID not assigned")
	var missing_ids: Array[String] = ["missing_refresh_fixture"]
	result = await creating.rebuild_library(missing_ids, scene, null, undo)
	check(result.rebuilt == 0 and result.skipped_ids == missing_ids and "Voxel source" in result.skipped[0], "retry queue does not contain exactly failed IDs")
	undo.clear_history()
	undo.free()
	scene.free()
	for message in errors: push_error(message)
	print("Voxel scene refresh: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size())
	quit(0 if errors.is_empty() else 1)
