extends SceneTree
## Composed authoring/runtime gate. Runs only in the disposable mixed fixture.
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")
const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const DialogueStore = preload("res://addons/ember_import/ember_dialogue_store.gd")
const ID := "harbor_cargo"
var errors: Array[String] = []

func _init() -> void:
	if not Fixture.prepare(self):
		quit(2)
		return
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func frames(count := 10) -> void:
	for index in count:
		await physics_frame
	await process_frame

func finish(ui: EmberInteractionUi) -> void:
	for index in 20:
		if not ui.is_open():
			break
		ui.advance()

func dialogue(id: String, text: String) -> void:
	check(DialogueStore.write_graph_document({"id": id, "nameRu": "Смотритель · Груз у берега", "startStepId": "line", "steps": [
		{"id": "line", "type": "dialogue", "textRu": text, "next": "end"}, {"id": "end", "type": "end"},
	]}) == OK, "dialogue write failed")

func _run() -> void:
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false
	state.flags.clear()
	state.world_items.clear()
	var quest := {"id": ID, "titleRu": "Груз у берега", "summaryRu": "Помочь смотрителю перенести ящик на отмеченную площадку.", "statusFlagId": "harbor_cargo_status", "showWhenAvailable": false, "objectives": []}
	var ids := ["meet", "visit", "place", "reward"]
	var texts := ["Поговорить со смотрителем у берега", "Найти ящик дальше по берегу", "Поставить ящик на золотую площадку", "Вернуться к смотрителю за наградой"]
	for index in ids.size():
		quest.objectives.append({"id": ids[index], "textRu": texts[index], "flagId": "harbor_cargo_" + ids[index], "progressMode": "flag", "requiresObjectiveIds": [] if index == 0 else [ids[index - 1]]})
	check(QuestStore.validation_errors(quest).is_empty(), "quest invalid")
	dialogue("harbor_cargo_intro", "Поможешь с грузом? Чуть дальше по берегу стоит деревянный ящик. Найди его, возьми по F и поставь повторным F на золотую площадку за ним. Потом вернись ко мне — получишь 3 монеты.")
	dialogue("harbor_cargo_reminder", "Ящик стоит дальше по берегу. Возьми его по F и отнеси на золотую площадку. Поставь повторным F и дай ему остановиться.")
	dialogue("harbor_cargo_thanks", "Всё на месте! Спасибо за помощь. Вот обещанные 3 монеты.")
	dialogue("harbor_cargo_done", "Спасибо! С грузом мы уже разобрались.")
	var authored := Node3D.new()
	authored.name = "HarborCargoQuest"
	# The same authoring commands used by Graph; no alternate runtime controller.
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	var npc := actions.create_quest_conversation(authored, Vector3(112, 6, 280), "Смотритель грузов", QuestStore.event_token(ID, "objective", "meet"), "harbor_cargo_intro", quest)
	check(npc != null, "NPC creation failed")
	if npc == null:
		quit(1)
		return
	npc.name = "CargoKeeper"
	var giver := npc.get_node("Talk") as EmberInteract
	var routes: Dictionary = giver.get("objective_scripts").duplicate()
	var intro := ActionStore.document(str(routes.meet))
	intro.id = "harbor_cargo_accept"
	routes.meet = intro.id
	intro.steps.insert(1, {"type": "set_flag", "flag": quest.statusFlagId, "value": "active"})
	check(ActionStore.write_document(intro) == OK, "start chain write failed")
	var reach := actions.create_quest_reach_zone(authored, Vector3(112, 11, 328), "visit", quest)
	var placement := actions.create_quest_object_placement(authored, Vector3(112, 7.15, 328), Vector3(112, 6, 376), "place", quest)
	check(reach != null and placement != null, "reach/crate authoring failed")
	if reach == null or placement == null:
		quit(1)
		return
	placement.name = "CargoPlacement"
	var crate = placement.get_node("Crate")
	crate.pickup_id = "harbor_cargo_crate"
	placement.get_node("TargetZone").target_pickup_id = "harbor_cargo_crate"
	# Reminders route to a dialogue without advancing the world objectives.
	check(ActionStore.write_document({"id": "harbor_cargo_wait", "nameRu": "Груз: напомнить", "steps": [{"type": "talk", "dialogueId": "harbor_cargo_reminder"}]}) == OK, "reminder write failed")
	routes.visit = "harbor_cargo_wait"
	routes.place = "harbor_cargo_wait"
	check(actions.bind_quest_conversation(npc, QuestStore.event_token(ID, "objective", "reward"), "harbor_cargo_thanks", authored, quest), "reward binding failed")
	routes.reward = (giver.get("objective_scripts") as Dictionary).reward
	var reward := ActionStore.document(str(routes.reward))
	reward.id = "harbor_cargo_reward"
	routes.reward = reward.id
	reward.steps.insert(1, {"type": "exchange_items", "costs": {}, "rewards": {"coin": 3}})
	reward.steps.append({"type": "set_flag", "flag": quest.statusFlagId, "value": "done"})
	check(ActionStore.write_document(reward) == OK, "reward write failed")
	check(ActionStore.write_document({"id": "harbor_cargo_complete", "nameRu": "Груз: уже завершено", "steps": [{"type": "talk", "dialogueId": "harbor_cargo_done"}]}) == OK, "done write failed")
	giver.set("objective_scripts", routes)
	giver.set("completed_script_id", "harbor_cargo_complete")
	var packed := PackedScene.new()
	check(packed.pack(authored) == OK, "authored scene pack failed")
	var export_dir := OS.get_environment("EMBER_ERRAND_EXPORT")
	if not export_dir.is_empty():
		check(ResourceSaver.save(packed, export_dir.path_join("harbor_cargo_quest.tscn")) == OK, "export failed")
		for directory in ["quests", "action_scripts", "dialogues"]:
			DirAccess.make_dir_recursive_absolute(export_dir.path_join(directory))
			for file in DirAccess.get_files_at("res://content/" + directory):
				if file.begins_with("harbor_cargo"):
					check(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://content/" + directory + "/" + file), export_dir.path_join(directory).path_join(file)) == OK, "resource export failed")
	history.clear_history()
	history.free()
	authored.free()
	# Test the saved composition, rather than its construction objects.
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(240, 2, 480)
	floor_body.position = Vector3(112, 5, 328)
	floor_body.add_child(shape)
	scene.add_child(floor_body)
	var instance := packed.instantiate() as Node3D
	scene.add_child(instance)
	giver = instance.get_node("CargoKeeper/Talk")
	crate = instance.get_node("CargoPlacement/Crate")
	var zone := instance.get_node("CargoPlacement/TargetZone") as Area3D
	var ui := EmberInteractionUi.new()
	ui.economy_state = state
	root.add_child(ui)
	var player := EmberPlayer.new()
	player.progress_state = state
	player.interaction_ui = ui
	player.position = Vector3(112, 6, 280)
	scene.add_child(player)
	player.set_physics_process(false)
	await frames()
	ui.activate(giver)
	ui.close()
	check(not state.flags.get("harbor_cargo_meet", false), "cancelled introduction advanced quest")
	ui.activate(giver)
	finish(ui)
	check(state.flags.get("harbor_cargo_meet", false) and state.flags.get("harbor_cargo_status", "") == "active", "intro did not start quest")
	ui.activate(giver)
	finish(ui)
	check(not state.flags.get("harbor_cargo_visit", false), "reminder bypassed travel")
	player.position = Vector3(112, 6, 320)
	await frames()
	check(state.flags.get("harbor_cargo_visit", false), "real entry did not advance quest")
	check(player.activate_interact(crate.get_node("Pickup")) and crate.is_carried(), "F did not lift crate")
	player.position = Vector3(112, 6, 352)
	player.set("_interaction_forward", Vector3(0, 0, 1))
	await frames()
	check(player.activate_interact(crate.get_node("Pickup")) and not crate.is_carried(), "F did not put crate down")
	await frames(65)
	check(state.flags.get("harbor_cargo_place", false), "placed crate did not advance quest")
	state.persistence_enabled = true
	state.set_world_context("landscape_compact", player, 16.0)
	check(state.save_slot(1), "mid-quest save failed")
	var cold := EmberExploreState.new()
	root.add_child(cold)
	check(cold.load_slot(1) and cold.flags.get("harbor_cargo_place", false) and not cold.flags.get("harbor_cargo_reward", false), "cold load lost stage")
	check(giver.routed_script_id(cold.flags) == str(routes.reward), "cold-loaded NPC routes to wrong stage")
	cold.free()
	state.persistence_enabled = false
	var before := int(state.inventory.get("coin", 0))
	ui.activate(giver)
	ui.close()
	check(int(state.inventory.get("coin", 0)) == before and not state.flags.get("harbor_cargo_reward", false), "cancelled reward gave coins")
	ui.activate(giver)
	finish(ui)
	check(int(state.inventory.get("coin", 0)) == before + 3 and state.flags.get("harbor_cargo_status", "") == "done", "reward did not commit exactly 3 coins")
	ui.activate(giver)
	finish(ui)
	check(int(state.inventory.get("coin", 0)) == before + 3, "repeat conversation duplicated reward")
	check(EmberQuestCatalog.projection(EmberQuestCatalog.definition(ID), state.flags).get("status", "") == "done", "catalog does not show completed quest")
	ui.queue_free()
	scene.queue_free()
	await process_frame
	Fixture.verify_sources(errors)
	if errors.is_empty():
		print("PASS harbor errand: authoring composition/reopen, cancel, intro/reminder, real entry, F carry/place, cold save/load, reward exactly once")
		quit(0)
	else:
		for error in errors:
			printerr("FAIL ", error)
		quit(1)
