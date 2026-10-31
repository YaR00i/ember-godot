extends SceneTree
## One real map, Forward+ captures, editor commands and isolated user:// save.
## Never writes authored terrain, prefabs, materials or the main scene.
var failures: Array[String] = []
var output := "user://world-anomaly-check"
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); printerr("FAIL ",message)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png")) == OK,"capture "+name)


func leaf_coverage(sphere: Node) -> void:
	if DisplayServer.get_name() == "headless": return
	var cells: Dictionary = {}
	var cards: Dictionary = {}
	for binding: Dictionary in sphere._bindings:
		if binding.materials[0].get_shader_parameter("ember_anomaly_grow_cells") == true: cells = binding; break
	for binding: Dictionary in sphere._bindings:
		if binding.source == cells.source and binding.materials.size() == 2: cards = binding; break
	var viewport := SubViewport.new(); viewport.size = Vector2i(256,256); viewport.transparent_bg = true; viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var visual := MeshInstance3D.new(); viewport.add_child(visual)
	var camera := Camera3D.new(); viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 8.0; camera.current = true
	var centre: Vector3 = cells.visual.mesh.get_aabb().get_center()
	camera.position = centre+Vector3(0,0,20); camera.look_at(centre)
	for kind in ["cells","cards"]:
		visual.mesh = cells.visual.mesh if kind == "cells" else sphere.Correspondence.surface_mesh(cards.visual.mesh,1)
		visual.material_override = cells.materials[0] if kind == "cells" else cards.materials[1]
		for state in ["low","outside","inside"]:
			visual.set_instance_shader_parameter("ember_anomaly_sphere",Vector4(0,0,0,100.0 if state != "outside" else 0.0))
			visual.set_instance_shader_parameter("ember_anomaly_band_look",Vector2(0.45,1 if state == "low" else 2))
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var pixels := 0
			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x,y).a > 0.01: pixels += 1
			var visible: bool = state == "inside" if kind == "cells" else state != "inside"
			check(pixels > 100 if visible else pixels == 0,"GPU leaf coverage: %s %s (%d pixels)" % [kind,state,pixels])
	viewport.queue_free()


func settle_grass(sphere: Node, patch: Node) -> void:
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if patch._dirty or patch._rebuilding or not sphere._prepared: continue
		var current := true
		for binding: Dictionary in sphere._bindings:
			if binding.source == patch._visual and binding.scatter != patch._visual.multimesh: current = false
		if current: return
	check(false,"grass edit preparation timeout")

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var began := Time.get_ticks_msec()
	var scene: Node = load("res://scenes/landscape_compact.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	var map: EmberMapLoader = scene.get_node("Map")
	var projection: Node = map.get_node("DerivedCompactWorldTerrain")
	var sphere: Node3D = map.get_node("WorldAnomaly")
	var deadline := Time.get_ticks_msec()+180000
	while (not sphere._prepared or not scene._startup_complete) and Time.get_ticks_msec()<deadline: await process_frame
	check(sphere._prepared and scene._startup_complete,"map and sphere prepare")
	if not sphere._prepared: quit(1); return
	var preparation_ms := Time.get_ticks_msec()-began
	scene._player.set_physics_process(false); scene._party_followers.set_physics_process(false); scene._player.camera_rig.set_process(false)
	var patch: Node = map.get_node("Props/GrassPatch")
	var panel = load("res://addons/ember_import/ember_world_look_panel.gd").new()
	root.add_child(panel); panel.hide()
	var history := UndoRedo.new(); panel.set_target(scene,map,history)
	var original_grass_count: int = patch._visual.multimesh.instance_count
	panel._commit("grass_density",100.0,50.0,false)
	await settle_grass(sphere,patch)
	check(patch._visual.multimesh.instance_count < original_grass_count,"density edit reaches original scatter")
	for binding: Dictionary in sphere._bindings:
		if binding.source == patch._visual: check(binding.visual.multimesh.instance_count == patch._visual.multimesh.instance_count,"local look follows edited scatter")
	history.undo()
	await settle_grass(sphere,patch)
	check(patch._visual.multimesh.instance_count == original_grass_count,"grass Undo restores local coverage")
	await leaf_coverage(sphere)
	map.world_look = 1
	for frame in 5: await process_frame
	for binding: Dictionary in sphere._bindings:
		check(not binding.visual.visible and binding.source.layers == binding.layers,"global look suspends local display")
	map.world_look = 0
	await settle_grass(sphere,patch)
	var grass_scatter: MultiMesh = patch._visual.multimesh
	var rock: Node = map.get_node("Props/PaintedRockGroup")
	var rock_shape: Shape3D = rock.get_node("Collision/Shape").shape
	var tile_shape: Shape3D = projection._tiles[Vector2i(1,2)].get_node("GroundPhysics/Shape").shape
	var floor_before := map.surface_floor_sample(Vector3(72,100,200))
	var source_heights := map.compact_terrain.heights.duplicate()
	var source_water := map.compact_terrain.water_levels.duplicate()
	var revision: int = projection.column_revision()
	var preparations: int = sphere.preparations
	var builds: int = sphere.Correspondence.builds
	var identities: Array = []
	for binding: Dictionary in sphere._bindings:
		identities.append([binding.visual.get_instance_id(),binding.mesh.get_rid(),binding.visual.mesh.get_rid() if binding.visual is MeshInstance3D else binding.visual.multimesh.get_rid()])
	sphere.enabled = false
	await capture("detailed")
	sphere.enabled = true
	var positions: Array[Vector3] = [Vector3(88,32,176),Vector3(128,24,148),Vector3(68,16,208)]
	var longest_input_us := 0
	for look in [1,2]:
		panel._commit("anomaly_look",sphere.inner_look,look,false)
		for point in positions:
			sphere.position = point
			await process_frame
			check(sphere._prepared,"sphere remains ready while moving")
			await capture("look-%d-position-%d" % [look,positions.find(point)])
		# Continuous field input: no preparation, scatter, physics or meshes.
		for frame in 90:
			var start := Time.get_ticks_usec()
			sphere.position = positions[0].lerp(positions[1],float(frame)/89.0)
			sphere.radius_m = 3.6+sin(float(frame)*0.1)*0.5
			sphere.feather_m = 0.45
			sphere._process(0.0)
			longest_input_us = maxi(longest_input_us,Time.get_ticks_usec()-start)
			await process_frame
		check(sphere.preparations == preparations and sphere.Correspondence.builds == builds,"moving/resizing/changing look never prepares geometry")
	for index in identities.size():
		var binding: Dictionary = sphere._bindings[index]
		check(identities[index] == [binding.visual.get_instance_id(),binding.mesh.get_rid(),binding.visual.mesh.get_rid() if binding.visual is MeshInstance3D else binding.visual.multimesh.get_rid()],"prepared instance and geometry remain identical")
	check(patch._visual.multimesh == grass_scatter and projection.column_revision() == revision,"scatter and terrain revision stay unchanged")
	check(rock.get_node("Collision/Shape").shape == rock_shape and projection._tiles[Vector2i(1,2)].get_node("GroundPhysics/Shape").shape == tile_shape,"colliders stay shared")
	check(map.surface_floor_sample(Vector3(72,100,200)) == floor_before,"physical floor stays shared")
	check(map.compact_terrain.heights == source_heights and map.compact_terrain.water_levels == source_water,"authored height and water channels unchanged")
	map.compact_material_gray_preview = true
	for binding: Dictionary in sphere._bindings:
		if binding.source is MultiMeshInstance3D or binding.source == rock.get_node("Mesh"):
			check(binding.materials[0].get_shader_parameter("material_gray_preview") == true,"material authoring reaches local looks")
	map.compact_material_gray_preview = false
	sphere.position = positions[0]; sphere.radius_m = 4.5; sphere.inner_look = 2
	await capture("sphere-final")
	panel._commit("anomaly_radius",4.5,3.0,false)
	history.undo(); check(sphere.radius_m == 4.5,"real-map Undo")
	history.redo(); check(sphere.radius_m == 3.0,"real-map Redo")
	panel._commit("anomaly_radius",3.0,4.5,false)
	# Packing after editor notifications must contain published props and sphere
	# parameters only. No internal carriers, material overrides or scatter data.
	scene.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var packed := PackedScene.new(); check(packed.pack(scene) == OK,"pack actual scene")
	var path := "user://world-anomaly-main-check.tscn"
	check(ResourceSaver.save(packed,path) == OK,"save isolated actual scene")
	var fresh: Node = (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved: Node = fresh.get_node("Map/WorldAnomaly")
	check(saved.position == positions[0] and saved.radius_m == 4.5 and saved.inner_look == 2,"actual scene reopens with sphere")
	check(fresh.get_node("Map/Props/PaintedRockGroup/Mesh").mesh.resource_path == "res://prefabs/voxels/meshes/vox_painted_rock_group_block.res","saved rock uses published Source")
	check(fresh.get_node("Map/Props/PaintedRockGroup/Mesh").layers == 1,"saving restores authored visibility")
	var text := FileAccess.get_file_as_string(path)
	check(text.length() < 20000 and not text.contains("DerivedAnomaly") and not text.contains("ember_anomaly_targets"),"save excludes derived geometry/materials")
	sphere.radius_m = 9.0; check(saved.radius_m == 4.5,"discard keeps saved sphere")
	fresh.free()
	sphere.set_process(false)
	scene.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	var report := {"pass":failures.is_empty(),"failures":failures,"preparation_ms":preparation_ms,"bindings":identities.size(),"preparations_during_motion":sphere.preparations-preparations,"builds_during_motion":sphere.Correspondence.builds-builds,"longest_sphere_update_us":longest_input_us,"renderer":RenderingServer.get_current_rendering_method(),"manual_gate":"mouse/hotkeys, moving boundary and visual/feel acceptance by author"}
	var file := FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t"))
	print("WORLD_ANOMALY ",JSON.stringify(report))
	history.clear_history(); history.free(); panel.free()
	quit(0 if failures.is_empty() else 1)
