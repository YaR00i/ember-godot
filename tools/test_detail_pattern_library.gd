extends "res://tools/test_detail_brush.gd"
const Bake = preload("res://scripts/ember_detail_pattern_bake.gd")
const SOURCE = "res://content/editor/voxel_stamps/vox_stamp_104392975.tres"
var cold_results: Array[Dictionary] = []

func request_cold(preset: Resource) -> void:
	cold_results.append(await Bake.prepare(preset,map))

func run() -> void:
	output = "user://ember-tests/detail-pattern-library"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
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

	await frames(2)
	var choice: OptionButton = brush.controls.kind
	var selection := -1
	for i in choice.item_count:
		if choice.get_item_metadata(i) == SOURCE: selection = i
	check(selection >= 2 and not choice.is_item_disabled(selection), "saved rock offered by existing library")
	var unsupported := 0
	for row in Bake.choices():
		if not row.supported:
			unsupported += 1
			check(not row.reason.is_empty(), "unsupported library entry explains its limit")
	check(unsupported > 0, "unsupported sources are not presented as ready")
	var canonical: Resource = load(SOURCE)
	var old_generated_key: String = canonical.generated_variants_key
	var old_generated_count: int = canonical.generated_variants.size()
	for i in 5: request_cold(canonical)
	var cold_deadline := Time.get_ticks_msec() + 10000
	while cold_results.size() < 5 and Time.get_ticks_msec() < cold_deadline: await process_frame
	check(cold_results.size() == 5 and Bake.builds == 1, "five cold waiters share one completed bake")
	for result in cold_results: check(result.has("variants") and result.variants.size() == 5, "every cold waiter receives prepared forms")
	choice.select(selection); await brush.select_kind(selection)
	check(canonical.generated_variants_key == old_generated_key and canonical.generated_variants.size() == old_generated_count, "worker leaves canonical source cache untouched")
	check(brush._pattern_ready and brush._pattern_count == 5, "library selection prepares five forms")
	var scaled: Resource = brush.pattern_preset.duplicate(true)
	scaled.geometry = brush.pattern_preset.geometry.duplicate_model()
	scaled.geometry.voxels_per_block = 16; scaled.geometry.size_blocks = Vector3i(2,1,2)
	check(not Bake.key(scaled).is_empty(), "scaled source remains valid")
	check(Bake.key(scaled) != Bake.key(brush.pattern_preset), "density change invalidates geometry cache")
	var builds: int = Bake.builds
	var data: Dictionary = Bake.cached(brush.pattern_preset)
	var hashes := {}
	for entry: Dictionary in data.variants:
		hashes[entry.source_hash] = true
		check(entry.meshes.size() == 3, "three prepared looks per form")
		for mesh: ArrayMesh in entry.meshes: check(mesh.get_surface_count() == 1, "each form has visible surface")
	check(hashes.size() == 5, "five distinct generated forms")
	var count_items: int = brush.controls.variant.item_count
	check(count_items == 6, "panel offers all five mixed or each separately")
	brush.controls.radius_m.value = 0.9; brush.controls.density_per_m2.value = 30; brush.controls.size_value.value = 0.65
	await frames(2)
	check(is_equal_approx(brush.size_value,0.65), "native size control reaches brush")
	brush._append(Vector3(80,0,88)); await settle()
	check(count(2) > 0, "library preview visible")
	for patch in patches(): check(patch.owner == null and patch.density_cells.is_empty(), "preview does not author density")
	brush.cancel_stroke(); check(patches().is_empty(), "Cancel removes all five preview variants")
	brush._append(Vector3(80,0,88)); check(brush.commit_stroke() > 0, "mixed stroke committed")
	await settle(); var mixed_count := count(2); var committed := snapshot()
	check(patches().size() == 5 and mixed_count > 0, "one tile contains five forms")
	var occupied := {}; var generations := {}; var positions := {}
	for patch in patches():
		check(patch.detail_mixed and patch.detail_preset.resource_path == SOURCE, "canonical source reference and mixed mode")
		check(patch.validation_errors().is_empty() and is_equal_approx(patch.tuft_size,0.65), "library patch validates and retains chosen size")
		generations[patch.name] = patch.detail_generations
		var list := PackedVector2Array()
		for i in patch._visual.multimesh.instance_count:
			var pos: Vector3 = patch._visual.multimesh.get_instance_transform(i).origin
			var xz := Vector2(pos.x,pos.z)
			check(not occupied.has(xz), "mixed variants never duplicate a candidate")
			occupied[xz] = true; list.append(xz)
		positions[patch.name] = list
		var palette: PackedColorArray = data.variants[patch.detail_variant].palette
		var lookup: Image = patch._visual.material_override.get_shader_parameter("palette_color_lookup").get_image()
		for color_slot in palette.size(): check(lookup.get_pixel(color_slot,0).is_equal_approx(palette[color_slot]), "renderer binds exact source palette")
	# Fixed form with the same mask produces the same population as all mixed forms.
	var probe: Node = patches()[0]
	probe.detail_mixed = false; probe._dirty = true; await settle()
	check(probe._visual.multimesh.instance_count == mixed_count, "mix does not multiply intended density by five")
	probe.detail_mixed = true; probe._dirty = true; await settle()
	for patch in patches(): generations[patch.name] = patch.detail_generations
	history.undo(); check(patches().is_empty(), "one Undo removes the whole mixed stroke")
	history.redo(); await settle(); check(snapshot() == committed and count(2) == mixed_count, "Redo restores exact mixed stroke")
	brush.controls.variant.select(4); brush.controls.variant.item_selected.emit(4)
	brush._append(Vector3(88,0,92)); brush.commit_stroke(); await settle()
	var fixed_nodes := 0
	for patch in patches():
		if not patch.detail_mixed: fixed_nodes += 1; check(patch.detail_variant == 3, "fixed selection uses chosen variant")
	check(fixed_nodes == 1, "fixed form does not create five layers")
	history.undo(); await settle(); check(snapshot() == committed, "fixed stroke Undo preserves mixed layer")
	brush.controls.variant.select(0); brush.controls.variant.item_selected.emit(0)
	brush.controls.erase.button_pressed = true
	brush._append(Vector3(80,0,88)); brush.commit_stroke(); await settle(); check(count(2) == 0, "erase clears selected mixed set")
	history.undo(); await settle(); check(snapshot() == committed and count(2) == mixed_count, "erase Undo restores all forms")
	brush.controls.erase.button_pressed = false
	for patch in patches(): generations[patch.name] = patch.detail_generations
	for look in [0,1,2,0]:
		map.world_look = look; await settle()
		check(count(2) == mixed_count, "look keeps population " + str(look))
		for patch in patches():
			check(patch.detail_generations == generations[patch.name], "look reuses placement cache")
			check(patch._visual.visible == (look != 2), "small library stones omitted in voxel look")
			var list := PackedVector2Array()
			for i in patch._visual.multimesh.instance_count:
				var pos: Vector3 = patch._visual.multimesh.get_instance_transform(i).origin
				list.append(Vector2(pos.x,pos.z))
			check(list == positions[patch.name], "look retains XZ placement")
	check(Bake.builds == builds, "hover strokes and looks reuse prepared source")
	var invalid := preload("res://scripts/ember_grass_patch.gd").new()
	invalid.detail_kind = 2; invalid.detail_preset = brush.pattern_preset; invalid.detail_variant = 5
	check(not invalid.validation_errors().is_empty(), "out of range source variant rejected"); invalid.free()
	var packed := PackedScene.new(); check(packed.pack(scene) == OK, "pack source references")
	var path := output.path_join("roundtrip.tscn")
	check(ResourceSaver.save(packed,path) == OK, "save temporary copy")
	var reopened: Node = (ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for patch in patches():
		var other: Node = reopened.get_node("Map/Props/" + str(patch.name))
		check(other.density_cells == patch.density_cells and other.detail_variant == patch.detail_variant and other.detail_mixed, "reopen exact mask and variant")
		check(other.detail_preset.resource_path == SOURCE and other.validation_errors().is_empty(), "reopen canonical valid source")
	reopened.free()
	brush._append(Vector3(90,0,100)); brush.commit_stroke()
	var discarded: Node = (ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for key in committed: check(discarded.get_node("Map/Props/" + key).density_cells == committed[key][0], "discard preserves saved source layer")
	discarded.free(); history.undo()
	check(source == projection.document and revision == projection.column_revision() and terrain.same_terrain_data(original), "pattern painting leaves terrain unchanged")
	print("PATTERN_LIBRARY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"variants":hashes.size(),"instances":mixed_count,"bakes":Bake.builds}))
	brush.deactivate(); history.clear_history(); history.free(); quit(0 if errors.is_empty() else 1)

