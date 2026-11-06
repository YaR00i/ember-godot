extends SceneTree
const Recipe = preload("res://scripts/ember_craft_recipe_resource.gd")
const StationScene = preload("res://prefabs/items/crafting_workbench.tscn")
const CookingScene = preload("res://prefabs/items/cooking_station.tscn")
var errors: Array[String] = []
var state: EmberExploreState
var output := ""

func _init() -> void:
	if not FileAccess.file_exists("res://.interaction-test-sandbox"):
		printerr("REFUSED: use tools/run_crafting_tests.py disposable project"); quit(2); return
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("CHECK FAIL ", message)

func _run() -> void:
	state = root.get_node("EmberExploreProgress")
	state.persistence_enabled = false; state.restore_enabled = false
	output = "user://ember-tests/crafting-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	state.storage_root = output.path_join("saves"); state.legacy_storage_root = output.path_join("legacy")
	state.set_meta("world_canvas_storage_root", state.storage_root)
	state.reset_new_game()
	var recipe: Resource = load("res://content/recipes/chapter1_practice_assembly.tres")
	var cook: Resource = load("res://content/recipes/chapter1_practice_drink.tres")
	check(recipe.validation_errors(EmberItemCatalog.definitions()).is_empty(), "valid authored recipe rejected")
	var invalid := recipe.duplicate(true)
	invalid.ingredients = {}
	check(not state.craft_recipe(invalid).ok, "empty costs allowed")
	invalid.ingredients = {"herb": 1.5}
	check(not state.craft_recipe(invalid).ok, "fractional recipe count allowed")
	invalid.ingredients = {"not_an_item": 1}
	check(not state.craft_recipe(invalid).ok, "unknown ingredient allowed")
	invalid.ingredients = {"herb": 0}
	check(not state.craft_recipe(invalid).ok, "zero ingredient allowed")
	var edited := recipe.duplicate(true)
	edited.title = "Edited recipe"
	var recipe_path := output.path_join("recipe.tres")
	check(ResourceSaver.save(edited, recipe_path) == OK, "recipe save failed")
	var reopened = ResourceLoader.load(recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.ingredients == recipe.ingredients and reopened.title == "Edited recipe", "recipe reopen lost fields")
	edited.title = "Unsaved"
	check(ResourceLoader.load(recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE).title == "Edited recipe", "discard leaked resource draft")
	state.inventory = {"herb": 4}
	var before := state.inventory.duplicate(true)
	check(state.preview_recipe(recipe).ok and state.inventory == before, "preview mutated inventory")
	check(state.craft_recipe(recipe).ok, "first craft failed")
	check(state.inventory == {"herb": 2, "revival_spark": 1}, "cost/result not atomic")
	check(state.craft_recipe(recipe).ok and state.inventory == {"revival_spark": 2}, "second paid batch failed")
	before = state.inventory.duplicate(true)
	check(not state.craft_recipe(recipe).ok and state.inventory == before, "missing costs granted result")
	var cap: int = EmberItemCatalog.definition("revival_spark").get("stackMax", 99)
	state.inventory = {"herb": 2, "revival_spark": cap}
	before = state.inventory.duplicate(true)
	check(state.craft_recipe(recipe).reason == "stack_full" and state.inventory == before, "overflow consumed ingredients")
	var overlap := recipe.duplicate(true)
	overlap.ingredients = {"apple": 1}; overlap.results = {"apple": 1}
	state.inventory = {"apple": int(EmberItemCatalog.definition("apple").get("stackMax", 99))}
	before = state.inventory.duplicate(true)
	check(state.craft_recipe(overlap).ok and state.inventory == before, "overlap incorrectly overflowed")
	state.inventory = {"herb": 2}
	state.combat_party_locked = true
	check(state.craft_recipe(recipe).reason == "locked" and state.inventory == {"herb": 2}, "combat lock bypassed")
	state.combat_party_locked = false

	var scene := Node3D.new(); scene.name = "CraftingFixture"; root.add_child(scene); current_scene = scene
	var layer := CanvasLayer.new(); scene.add_child(layer)
	var ui := EmberInteractionUi.new(); ui.economy_state = state; layer.add_child(ui)
	var player := EmberPlayer.new(); player.name = "Player"; player.progress_state = state; player.interaction_ui = ui
	scene.add_child(player); player.set_physics_process(false)
	var bench := StationScene.instantiate() as Node3D
	bench.position = Vector3(0, 0, -20); scene.add_child(bench)
	var interaction := bench.get_node("Interaction") as EmberInteract
	check(interaction.validation_errors().is_empty(), "workbench invalid")
	state.inventory = {}
	check(player.activate_interact(interaction) and ui.view_state().mode == "craft", "real F route failed")
	check(ui.blocks_movement() and ui.get("_craft_create").disabled, "missing-cost UI not blocked")
	before = state.inventory.duplicate(true); ui.close()
	check(state.inventory == before, "cancel spent items")
	state.inventory = {"herb": 2}
	player.activate_interact(interaction)
	# A previously ready screen must recheck after inventory changes elsewhere.
	state.inventory = {}
	ui.advance()
	check(state.inventory.is_empty(), "stale UI created free result")
	state.inventory = {"herb": 2}
	state.economy_changed.emit()
	check(not ui.get("_craft_create").disabled, "live ingredient refresh failed")
	ui.get("_craft_create").pressed.emit()
	check(state.inventory == {"revival_spark": 1}, "mouse create failed")
	ui.advance()
	check(state.inventory == {"revival_spark": 1}, "repeat click duplicated result")
	ui.close()
	var history := UndoRedo.new()
	var old := bench.position
	var moved := old + Vector3(20, 0, 0)
	var local_at := interaction.position
	history.create_action("Move workstation")
	history.add_do_property(bench, "position", moved); history.add_undo_property(bench, "position", old); history.commit_action()
	check(interaction.global_position == moved + local_at, "interaction detached after move")
	history.undo(); check(bench.position == old, "station undo failed")
	history.redo(); check(bench.position == moved, "station redo failed")
	var saved := PackedScene.new(); check(saved.pack(bench) == OK, "station pack failed")
	var station_path := output.path_join("station.tscn")
	check(ResourceSaver.save(saved, station_path) == OK, "station save failed")
	var restored = (ResourceLoader.load(station_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(restored.position == moved and restored.get_node("Interaction").recipes[0].recipe_id == recipe.recipe_id, "station reopen lost binding")
	restored.free()
	# Offer a second recipe on the same station to verify selection, without new economy rules.
	var second := recipe.duplicate(true); second.recipe_id = "test_second"; second.title = "Second"; second.ingredients = {"herb": 1}
	interaction.recipes.append(second)
	state.inventory = {"herb": 1}
	player.activate_interact(interaction)
	ui.call("_move_craft_selection", 1)
	check(ui.view_state().craftIndex == 1, "recipe selection failed")
	ui.advance(); check(state.inventory == {"revival_spark": 1}, "selected recipe ignored")
	ui.close()
	var kitchen := CookingScene.instantiate() as Node3D; scene.add_child(kitchen)
	var cooking := kitchen.get_node("Interaction") as EmberInteract
	state.inventory = {"apple": 1, "herb": 1}
	check(player.activate_interact(cooking) and ui.get("_craft_create").text == "Приготовить", "kitchen uses wrong UI")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("crafting-ui.png"))
	ui.advance()
	check(state.inventory == {"qingxin_tea": 1}, "cooking didn't use shared transaction")
	ui.close()
	# A station cannot offer a recipe assigned to a different workstation type.
	cooking.recipes.assign([recipe])
	check(not cooking.validation_errors().is_empty(), "wrong station type accepted")
	check(ui.open_crafting(cooking) != "" and not ui.is_open(), "wrong type opened UI")
	cooking.recipes.assign([cook])
	state.inventory = {"apple": 1, "herb": 1}
	player.activate_interact(cooking)
	kitchen.queue_free(); await process_frame
	ui.advance(); check(state.inventory == {"apple": 1, "herb": 1} and not ui.is_open(), "deleted station still crafted")
	state.inventory = {"qingxin_tea": 1}
	state.persistence_enabled = true
	check(state.save_slot(1), "craft save failed")
	state.inventory.clear()
	check(state.load_slot(1) and state.inventory == {"qingxin_tea": 1}, "craft cold load lost result")
	state.persistence_enabled = false; state.restore_enabled = false
	var fresh := EmberExploreState.new()
	fresh.name = "ColdRecipeState"
	fresh.storage_root = state.storage_root; fresh.legacy_storage_root = state.legacy_storage_root
	fresh.persistence_enabled = false; fresh.restore_enabled = false
	root.add_child(fresh)
	check(fresh.load_slot(1) and fresh.inventory == {"qingxin_tea": 1}, "fresh owner lost crafted result")
	fresh.queue_free()
	# Saved chapter maps expose the same prefab bindings; no dynamic special-case spawn.
	for suffix in ["home", "estate"]:
		var map = (load("res://scenes/chapter1_" + suffix + ".tscn") as PackedScene).instantiate()
		check(map.find_child("CookingStation" if suffix == "home" else "CraftingWorkbench", true, false) != null, "saved map lacks station " + suffix)
		map.free()
	scene.queue_free(); current_scene = null
	history.free()
	await process_frame
	# Native integration in the saved home, through the real exploration UI/player.
	check(change_scene_to_file("res://scenes/chapter1_home.tscn") == OK, "home start failed")
	for frame in 600:
		await process_frame
		if current_scene != null and current_scene.get("_startup_complete") == true: break
	check(current_scene != null and current_scene.get("_startup_complete") == true, "home didn't become ready")
	if current_scene != null and current_scene.get("_startup_complete") == true:
		var live_player := current_scene.get_node("Player") as EmberPlayer
		var live_station := current_scene.get_node("Map/Props/CookingStation/Interaction") as EmberInteract
		state.inventory = {"herb": 1, "apple": 1}
		live_player.global_position = live_station.global_position + Vector3(0, 0, 12)
		check(live_player.activate_interact(live_station), "saved station F route rejected")
		check(live_player.interaction_ui.view_state().mode == "craft", "saved scene didn't open recipe panel")
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("home-cooking.png"))
		live_player.interaction_ui.advance()
		check(state.inventory == {"qingxin_tea": 1}, "live scene craft failed")
		live_player.interaction_ui.close()
	current_scene.queue_free(); current_scene = null
	await process_frame
	if not errors.is_empty(): printerr("CRAFTING FAIL ", errors); quit(1); return
	print("CRAFTING PASS: validation/atomic preview+commit/overflow/lock/stale UI/selection/workbench+cooking/move+undo+save+reopen/cold load")
	print("EVIDENCE ", ProjectSettings.globalize_path(output))
	quit(0)
