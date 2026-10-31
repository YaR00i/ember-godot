extends SceneTree
## Focused native checks; only temporary scene copies are saved.
const Brush = preload("res://addons/ember_import/ember_detail_brush.gd")
const Detail = preload("res://scripts/ember_detail_scatter.gd")
const PluginScript = preload("res://addons/ember_import/plugin.gd")
var errors: Array[String] = []
var scene: Node3D
var map: EmberMapLoader
var brush: Node
var history := UndoRedo.new()
var output := "user://ember-tests/detail-brush"

func _init() -> void:
	preload("res://tools/fixtures/ember_exploration_test_fixture.gd").prepare(self, "user://ember-tests/detail-brush-session-" + str(OS.get_process_id()))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label); printerr("DETAIL_FAIL ", label)

func frames(n: int) -> void:
	for i in n: await process_frame

func patches() -> Array[Node]:
	var result: Array[Node] = []
	for node in map.get_node("Props").get_children():
		if node.get_script() == preload("res://scripts/ember_grass_patch.gd") and node.painted_only: result.append(node)
	return result

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		var pending := false
		for node in patches(): pending = pending or node._dirty or node._rebuilding
		if not pending: await frames(3); return
		await process_frame
	check(false, "painted patches settle")

func count(kind: int) -> int:
	var total := 0
	for node in patches():
		if node.detail_kind == kind and node._visual != null and node._visual.multimesh != null: total += node._visual.multimesh.instance_count
	return total

func snapshot() -> Dictionary:
	var result := {}
	for node in patches(): result[str(node.name)] = [node.density_cells.duplicate(), node.scatter_seed, node.tuft_size]
	return result

func capture(label: String) -> void:
	await frames(16); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	if DisplayServer.get_name() == "headless": printerr("Native Forward+ required"); quit(2); return
	DisplayServer.window_set_size(Vector2i(1440,900))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	check(not Detail.validation_errors({Vector2i(16,0):2.0}).is_empty(), "invalid mask cell rejected")
	check(not Detail.validation_errors({Vector2i.ZERO:NAN}).is_empty(), "NaN density rejected")
	# Controlled 8x8m fixture, with grass/sand and a wet edge; no authored map dependency.
	var terrain := EmberTerrainPilotResource.new(); terrain.width = 128; terrain.depth = 128
	terrain.palette = PackedColorArray([Color.TRANSPARENT,Color("6c963b"),Color("cdb482")])
	terrain.palette_surface_roles = PackedStringArray(["","grass","sand"])
	terrain.palette_material_ids = PackedStringArray(["","cartoon_grass","cartoon_sand"])
	var cells := terrain.width * terrain.depth
	terrain.heights.resize(cells); terrain.heights.fill(4)
	terrain.top_materials.resize(cells); terrain.base_materials.resize(cells); terrain.base_materials.fill(1)
	terrain.cap_depths.resize(cells); terrain.cap_depths.fill(1)
	terrain.water_levels.resize(cells); terrain.water_materials.resize(cells)
	for z in terrain.depth:
		for x in terrain.width:
			var i := x + z * terrain.width; terrain.top_materials[i] = 1 if x < 64 else 2
			if x >= 112: terrain.water_levels[i] = 6; terrain.water_materials[i] = 2
	check(terrain.validation_errors().is_empty(),"controlled fixture validates")
	var original := terrain.working_copy()
	scene = Node3D.new(); scene.name = "DetailFixture"
	map = EmberMapLoader.new(); map.name = "Map"; map.compact_terrain = terrain; map.compact_ground_style = 1; map.world_look = 0
	scene.add_child(map); map.owner = scene
	var props := Node3D.new(); props.name = "Props"; map.add_child(props); props.owner = scene
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45,-35,0); scene.add_child(sun)
	root.add_child(scene); current_scene = scene
	var deadline := Time.get_ticks_msec() + 30000
	while map._visual_surface_projection == null or map._visual_surface_projection.pending_tile_count() > 0:
		if Time.get_ticks_msec() > deadline: check(false,"fixture startup timeout"); break
		await process_frame
	var projection: Node = map._visual_surface_projection
	var revision: int = projection.column_revision()
	var source: Resource = projection.document
	brush = Brush.new(); root.add_child(brush); check(brush.activate_details(scene,map,history), "activate density brush")
	var panel: Control = brush.build_panel()
	var canvas := CanvasLayer.new(); root.add_child(canvas)
	var backing := PanelContainer.new(); backing.position = Vector2(1030,16); backing.size = Vector2(390,860); canvas.add_child(backing)
	var background := StyleBoxFlat.new(); background.bg_color = Color(0.07,0.085,0.10,0.98); background.content_margin_left = 12; background.content_margin_right = 12; backing.add_theme_stylebox_override("panel",background)
	var scroll := ScrollContainer.new(); backing.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.add_child(panel)
	panel.theme = preload("res://addons/ember_import/ember_voxel_workshop_theme.gd").build(ThemeDB.get_default_theme())
	check(brush.controls.has("kind") and brush.controls.has("density_per_m2") and brush.controls.has("size_value"), "native panel exposes kind and brush controls")
	brush.controls.radius_m.value = 0.6; brush.controls.density_per_m2.value = 80.0
	brush._append(Vector3(16,0,32)); await settle()
	check(not patches().is_empty() and count(0) > 0, "grass preview visible")
	for patch in patches(): check(patch.owner == null, "new preview patch not authored")
	brush.cancel_stroke(); check(patches().is_empty(), "Cancel removes unsaved preview")
	brush._append(Vector3(16,0,32)); brush._append(Vector3(20,0,32)); check(brush.commit_stroke() > 0, "grass stroke committed")
	await settle(); var grass_count := count(0); var committed := snapshot()
	check(grass_count > 0, "committed grass visible")
	history.undo(); check(patches().is_empty(), "one Undo removes whole stroke")
	history.redo(); await settle(); check(snapshot() == committed and count(0) == grass_count, "Redo exact cells and scatter")
	brush.controls.kind.select(1); brush.controls.kind.item_selected.emit(1)
	brush.controls.density_per_m2.value = 12; brush.controls.radius_m.value = 0.8
	brush._append(Vector3(120,0,72)); check(brush._drafts.is_empty(), "water click does not create a hidden density layer")
	brush._append(Vector3(80,0,72)); check(brush.commit_stroke() > 0, "pebble stroke committed")
	await settle(); check(count(1) > 0, "pebbles visible on sand")
	var before_erase := snapshot(); brush.controls.erase.button_pressed = true; brush.controls.radius_m.value = 0.35
	brush._append(Vector3(80,0,72)); brush.commit_stroke(); await settle()
	check(snapshot() != before_erase, "eraser changes painted density")
	history.undo(); await settle(); check(snapshot() == before_erase, "eraser Undo restores density")
	brush.controls.erase.button_pressed = false; committed = snapshot()
	var counts := [count(0), count(1)]
	var xz := {}
	var generations := {}
	for patch in patches(): generations[patch.name] = patch.detail_generations
	var camera := Camera3D.new(); scene.add_child(camera); camera.far = 1600; camera.fov = 55
	camera.look_at_from_position(Vector3(55,24,119),Vector3(80,4,72)); camera.make_current()
	for look in [0,1,2,0]:
		map.world_look = look; await settle()
		check(snapshot() == committed and [count(0),count(1)] == counts, "world look preserves density and instance count " + str(look))
		for patch in patches():
			check(patch.validation_errors().is_empty(), "saved detail patch validates")
			if patch.detail_kind == 1: check(patch._visual.visible == (look != 2), "small pebbles omitted in voxel look")
			check(patch.detail_generations == generations[patch.name], "world switch reuses prepared scatter " + str(patch.name))
			var positions := PackedVector2Array()
			for i in patch._visual.multimesh.instance_count:
				var point: Vector3 = patch._visual.multimesh.get_instance_transform(i).origin; positions.append(Vector2(point.x,point.z))
			if look == 0 and not xz.has(patch.name): xz[patch.name] = positions
			else: check(xz[patch.name] == positions, "look keeps XZ placement " + str(patch.name))
		await capture("look-" + str(look))
	check(source == projection.document and revision == projection.column_revision(), "detail painting does not rebuild or change terrain")
	brush.controls.density_per_m2.value = 90
	var input_point: Vector3 = projection.floor_surface_sample(Vector3(80,0,72)).position
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.position = camera.unproject_position(input_point); event.pressed = true
	check(brush.forward_input(camera,event) == EditorPlugin.AFTER_GUI_INPUT_STOP, "3D pointer press routed to detail brush")
	check(not brush._drafts.is_empty(), "3D pointer creates a real density preview")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	brush.forward_input(camera,escape)
	check(not brush.active and snapshot() == committed, "Esc cancels 3D pointer preview")
	brush.activate_details(scene,map,history)
	brush.controls.density_per_m2.value = 12
	var packed := PackedScene.new(); check(packed.pack(scene) == OK, "pack authoring result")
	check(ResourceSaver.save(packed,output.path_join("roundtrip.tscn")) == OK, "save temporary scene")
	var fresh: Node = (ResourceLoader.load(output.path_join("roundtrip.tscn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for patch in patches():
		var reopened: Node = fresh.get_node("Map/Props/" + str(patch.name))
		check(reopened.density_cells == patch.density_cells and reopened.validation_errors().is_empty(), "fresh reopen density and validation")
		check(reopened.scatter_seed == patch.scatter_seed and reopened.detail_kind == patch.detail_kind, "fresh reopen pattern and seed")
	fresh.free()
	brush._append(Vector3(90,0,100)); check(brush.commit_stroke() > 0, "unsaved discard fixture actually changes density")
	var discarded: Node = (ResourceLoader.load(output.path_join("roundtrip.tscn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for key in committed: check(discarded.get_node("Map/Props/" + key).density_cells == committed[key][0], "discard keeps saved density")
	discarded.free(); history.undo()
	check(terrain.same_terrain_data(original), "fixture terrain data unchanged by detail authoring")
	print("DETAIL_BRUSH ", JSON.stringify({"pass":errors.is_empty(),"errors":errors,"grass":counts[0],"pebbles":counts[1],"patches":patches().size(),"output":ProjectSettings.globalize_path(output)}))
	brush.deactivate(); history.clear_history(); history.free(); quit(0 if errors.is_empty() else 1)
