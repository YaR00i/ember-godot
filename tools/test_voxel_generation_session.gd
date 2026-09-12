extends SceneTree
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Session = preload("res://addons/ember_import/ember_voxel_generation_session.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const Presets = preload("res://addons/ember_import/ember_voxel_generator_presets.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _init() -> void:
	_run.call_deferred()

func settle_panel(panel: Node) -> void:
	for frame in 300:
		await process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "panel work did not settle")

func _run() -> void:
	var studio: Node = load(Session.STUDIO_PATH).instantiate()
	check(studio.get_node("StudioEnvironment").environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "neutral studio uses explicit ambient fill")
	studio.free()
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var panel := GenerationPanel.new()
	root.add_child(panel)
	panel.open_for({"root": scene, "parent": scene, "undo": undo, "world_size": 1.0})
	var starting_version: int = panel.recipe.parameters.generation_version
	var starting_thickness: int = panel.recipe.parameters.branch_thickness
	check(starting_version == 9, "new workshop uses current savanna without upgrading loaded recipes")
	var test_dir := "user://generation_session_%d" % Time.get_ticks_usec()
	panel.session.source_directory = test_dir.path_join("source")
	panel.session.prefab_directory = test_dir.path_join("prefabs")
	panel.session.recipe_directory = test_dir.path_join("recipes")
	panel.presets.directory = test_dir.path_join("presets")
	panel.controls.height.value = 64
	check(panel.recipe.parameters.height == 64, "parameter routed to recipe")
	panel.history.undo()
	check(panel.recipe.parameters.height == 96, "parameter Undo")
	panel.history.redo()
	check(panel.recipe.parameters.height == 64, "parameter Redo")
	panel._change_parameter("generation_version", 1)
	check(not panel.controls.crown_shape.visible and not panel.controls.foliage_amount.get_parent().visible
		and panel.controls.leaf_density.get_parent().visible, "classic shows only applicable leaf controls")
	panel.history.undo()
	check(panel.recipe.parameters.generation_version == starting_version, "classic setting Undo")
	panel._count.value = 2
	panel._seed.value = 77
	panel.generate()
	for frame in 60:
		await process_frame
		if not panel.session.running: break
	check(panel.session.candidates.size() == 2, "two candidates produced sequentially")
	if panel.session.candidates.size() != 2:
		panel.free(); scene.free(); undo.free(); quit(1); return
	var first: Dictionary = panel.session.candidates[0]
	var second: Dictionary = panel.session.candidates[1]
	check(first.seed == 77 and second.seed == 104806, "deterministic seed sequence")
	check(first.creation.recipe.family_id == second.creation.recipe.family_id, "common family")
	check(first.creation.recipe.structure.size() > 0, "frozen editable skeleton")
	check(first.node.owner == null and first.node.get_child(0) is MeshInstance3D, "unowned native preview")
	check(_physics_count(first.node) == 0, "preview has no physics")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK and packed.get_state().get_node_count() == 1, "temporary candidates excluded from map serialization")
	check(first.number == 1 and second.number == 2 and first.node.get_node("CandidateNumber").text == "№ 1", "stable visible candidate numbers")
	var first_id: String = first.creation.source.model_id
	var original_structure: Dictionary = first.creation.recipe.structure.duplicate(true)
	var original_source: Resource = first.creation.source
	var second_source: Resource = second.creation.source
	panel._select_preview(first)
	panel.candidate_controls.branch_thickness.value = 40
	check(first.creation.source == original_source and panel.recipe.parameters.branch_thickness == starting_thickness, "draft edits neither remesh nor change batch")
	panel.history.undo()
	check(panel.candidate_recipe.parameters.branch_thickness == starting_thickness, "candidate draft Undo")
	panel.history.redo()
	check(panel.candidate_recipe.parameters.branch_thickness == 40, "candidate draft Redo")
	panel._select_preview(second)
	check(panel.active_id == first_id, "dirty draft prevents accidental candidate switch")
	panel._select_preview(first)
	check(panel.candidate_recipe.parameters.branch_thickness == 40, "reselecting active candidate preserves draft")
	panel.discard_candidate()
	check(not panel._draft_dirty(), "discard restores current prepared settings")
	panel.history.undo()
	check(panel._draft_dirty(), "discard Undo restores draft")
	panel.history.redo()
	panel._change_candidate_parameter("branch_thickness", 35)
	panel._change_candidate_parameter("foliage_color", Color("c67432"))
	panel.apply_candidate()
	check(first.creation.recipe.parameters.branch_thickness == 35 and first.creation.source.model_id == first_id, "apply revision preserves candidate identity")
	check(first.creation.recipe.structure == original_structure and second.creation.source == second_source, "one-tree edit preserves skeleton and other candidate")
	check(first.creation.source.voxels != original_source.voxels, "branch thickness changes actual voxels")
	check(first.creation.source.palette != original_source.palette and second.creation.source.palette == second_source.palette, "autumn palette changes only selected tree")
	panel.history.undo()
	check(first.creation.source.voxels == original_source.voxels, "applied revision Undo rebuilds exact previous voxels")
	panel.history.redo()
	check(first.creation.recipe.parameters.branch_thickness == 35, "applied revision Redo")
	panel.regenerate_candidate()
	check(first.creation.recipe.structure != original_structure and second.creation.source == second_source, "new skeleton affects only selected candidate")
	panel.history.undo()
	check(first.creation.recipe.structure == original_structure, "new skeleton Undo")
	panel._show_solo()
	check(first.node.visible and not second.node.visible, "solo view isolates selected candidate")
	panel._select_all_previews()
	check(first.node.visible and second.node.visible, "gallery view restores other candidates")
	panel._change_candidate_parameter("foliage_amount", 80)
	var map := Node3D.new()
	root.add_child(map)
	panel.scene_context_changed(map, undo)
	check(panel.suspended and panel._draft_dirty() and is_instance_valid(first.node), "map tab suspends without losing preview or draft")
	panel.undo_local()
	check(panel.candidate_recipe.parameters.foliage_amount == 80, "paused UI history cannot mutate studio draft")
	scene.scene_file_path = Session.STUDIO_PATH
	panel.scene_context_changed(scene, undo)
	check(not panel.suspended and panel._draft_dirty(), "return to studio preserves draft")
	panel.discard_candidate()
	panel._preview_root.free()
	panel.scene_context_changed(scene, undo)
	check(is_instance_valid(first.node) and first.node.get_node("CandidateNumber").text == "№ 1", "closed studio can reconstruct transient gallery")
	map.free()
	panel._choose(first, true)
	panel.history.undo()
	check(not first.chosen, "choice Undo")
	panel.history.redo()
	check(first.chosen, "choice Redo")
	panel.save_chosen()
	await settle_panel(panel)
	check(first.saved and not second.saved and scene.get_child_count() == 1, "only chosen saved, no placement")
	var source_path := panel.session.source_directory.path_join(first.creation.source.model_id + ".tres")
	var loaded := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	check(loaded != null and loaded.voxels == first.creation.source.voxels, "preview source equals published source")
	var recipe_path: String = first.creation.recipe_path(first.creation.source.model_id, panel.session.recipe_directory)
	var stored := ResourceLoader.load(recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var rebuilt := Generator.build(stored, Color.WHITE, {}, "Roundtrip") if stored != null else {"error": "missing"}
	check(not rebuilt.has("error") and rebuilt.geometry.voxels == first.creation.source.voxels and rebuilt.geometry.palette == first.creation.source.palette, "save/reopen skeleton reproduces exact voxels and palette")
	undo.undo()
	check(not first.saved and not FileAccess.file_exists(source_path), "asset-only Undo")
	var published_source: Resource = first.creation.source
	panel._change_candidate_parameter("branch_thickness", 90)
	check(first.creation.source == published_source and not panel._draft_dirty(), "publication history locks preview against local edits after file Undo")
	undo.redo()
	check(first.saved and FileAccess.file_exists(source_path), "asset-only Redo")
	var borrowed := first.creation.packed.instantiate() as EmberVoxelProp
	scene.add_child(borrowed)
	borrowed.owner = scene
	check(first.creation._library_used(), "placed instance protects asset from history removal")
	borrowed.free()
	panel._choose(second, true)
	panel.save_chosen()
	await settle_panel(panel)
	var entries: Array[Dictionary] = [{"id": first.creation.source.model_id, "title": "Tree", "ready": true},
		{"id": second.creation.source.model_id, "title": "Tree", "ready": true}]
	var groups: Array[Dictionary] = first.creation.grouped_entries(entries, panel.session.recipe_directory)
	check(groups.size() == 1 and groups[0].variations.size() == 2, "chosen variants share one library card")
	undo.undo()
	check(not second.saved and first.saved, "Undo by candidate does not affect another saved variant")
	var frozen := Session.preset_recipe(first.creation.recipe, "Осень")
	check(frozen.structure.is_empty() and frozen.family_id.is_empty(), "preset strips skeleton and identity")
	var preset_path := panel.presets.save_preset(first.creation.recipe, "Осень")
	check(not preset_path.is_empty() and panel.presets.list_presets(Generator.LARGE_TREE).size() == 1, "preset save/reopen")
	check(panel.presets.save_preset(first.creation.recipe, "Осень").is_empty(), "duplicate preset does not overwrite")
	panel._choose(second, true)
	var old_preview: Node = second.node
	var unused_creation: WeakRef = weakref(second.creation)
	panel._show_solo()
	panel.generate()
	check(panel.session.candidates.has(first) and panel.session.candidates.has(second) and not is_instance_valid(old_preview), "all history retained while old preview released")
	check(first.creation.packed == null and second.creation.packed == null and second.creation.source.voxels.is_empty(), "archive retains recipe/identity but no source geometry or mesh")
	check(panel.active_id.is_empty() and not panel.solo and panel.session.preview_ids.is_empty(), "new batch resets working view independently of favorites")
	panel.cancel()
	check(not panel.session.running and panel.session.candidates.size() == 2, "cancel preserves all prior records")
	panel._title.text = "Другое семейство"
	panel.generate()
	panel._build_next()
	check(panel.session.candidates.size() == 3 and first.number == 1 and second.number == 2 and panel.session.candidates[2].number == 3,
		"all numbers stay stable across new families")
	panel.cancel()
	var third: Dictionary = panel.session.candidates[2]
	var third_id: String = third.creation.source.model_id
	var third_voxels: PackedByteArray = third.creation.source.voxels.duplicate()
	var third_palette: PackedColorArray = third.creation.source.palette.duplicate()
	panel._select_preview(first)
	check(first.creation.packed != null and panel.session.preview_ids.size() == 1 and first.creation.source.voxels == loaded.voxels, "saved archive restores canonical source")
	panel._compare_candidate(third, true)
	await settle_panel(panel)
	check(panel.session.preview_ids.size() == 2 and third.creation.source.voxels == third_voxels, "cross-batch comparison restores exact voxels")
	panel._compare_candidate(first, false)
	panel._select_preview(third)
	panel._change_candidate_parameter("foliage_color", Color("d06020"))
	panel.apply_candidate()
	panel.history.undo()
	check(third.creation.source.voxels == third_voxels and third.creation.source.palette == third_palette, "restored archive edit Undo is exact")
	panel._choose(third, true)
	panel._count.value = 4
	panel.generate()
	await settle_panel(panel)
	check(panel.session.candidates.size() == 7 and panel.session.preview_ids.size() == 4 and third.chosen, "favorites do not limit next four-candidate batch")
	check(third.creation.packed == null and third.creation.recipe.seed == third.seed, "edited archived recipe survives another batch without geometry")
	panel._history_filter_code = third.batch + 1
	panel._rebuild_candidates()
	check(panel._candidates.get_child_count() == 1, "batch filter")
	panel._history_filter_code = 1
	panel._rebuild_candidates()
	check(panel._candidates.get_child_count() == 3, "favorites filter includes saved and archived choices")
	panel.save_chosen()
	await settle_panel(panel)
	check(second.saved and third.saved and third.creation.packed == null, "sequential archive save releases non-viewed geometry")
	var third_stored := ResourceLoader.load(panel.session.source_directory.path_join(third_id + ".tres"), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	check(third_stored != null and third_stored.voxels == third_voxels and third_stored.palette == third_palette, "archive saved source equals restored edited snapshot")
	undo.undo()
	check(not third.saved and second.saved, "archived publication Undo updates history record")
	undo.redo()
	check(third.saved, "archived publication Redo updates history record")
	panel._select_preview(third)
	var tall_preview := Generator.default_recipe(Generator.LARGE_TREE)
	tall_preview.parameters.height = 256
	panel._apply_recipe(tall_preview)
	panel.generate()
	await settle_panel(panel)
	check(panel.session.preview_ids.size() == 2, "tall generation working set remains two")
	panel._compare_candidate(first, true)
	check(panel.session.preview_ids.size() == 2 and panel._pending_previews.is_empty(), "comparison rejects over-limit without losing archive")
	var mixed_candidate: Dictionary = panel.session.candidates[6]
	var previous_batch: int = mixed_candidate.batch
	mixed_candidate.batch = panel.session.batch_number
	panel._show_last_batch()
	await settle_panel(panel)
	check(panel.session.preview_ids.size() == 2 and panel.session.candidates.size() == 9, "mixed-height latest batch retains all nine history records and respects two-model limit")
	mixed_candidate.batch = previous_batch
	var tall := Generator.default_recipe(Generator.LARGE_TREE)
	tall.parameters.height = 256
	check(Generator.candidate_limit(tall) == 2, "large exact previews have memory limit")
	panel.close_session()
	check(scene.get_child_count() == 0, "close discards all temporary nodes")
	second = {}
	panel.free()
	scene.free()
	undo.clear_history()
	undo.free()
	await process_frame
	check(unused_creation.get_ref() == null, "discarded candidate released: no signal/history mesh retention")
	print("Voxel generation session: ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func _physics_count(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children(): count += _physics_count(child)
	return count
