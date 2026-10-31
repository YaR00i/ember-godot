extends SceneTree
const Content = preload("res://tools/fixtures/ember_interaction_test_fixture.gd")
const Body = preload("res://scripts/ember_world_item_3d.gd")
const Records = preload("res://scripts/ember_world_items.gd")
const ItemEditor = preload("res://addons/ember_import/ember_item_editor.gd")
const ItemStore = preload("res://addons/ember_import/ember_item_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
var setup: Dictionary
var failures: Array[String] = []
func _init() -> void:
	setup = Content.prepare(self)
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); printerr("WORLD_ITEM FAIL ",label)
func run() -> void:
	if setup.refused or setup.error != OK: quit(2); return
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.reset_new_game()
	state.persistence_enabled = true
	var packed := Content.save_map("world_item_fixture",setup.directory)
	var scene := packed.instantiate()
	# Synthetic unlabelled props are placeholders, not external mesh imports.
	for prop in scene.find_children("*", "EmberVoxelProp", true, false):
		if prop.model_id.is_empty(): prop.set_meta("ember_external_source", false)
	root.add_child(scene)
	current_scene = scene
	for frame in 5: await process_frame
	scene._player.set_physics_process(false)
	var bottle = load("res://prefabs/items/shore_bottle_pickup.tscn").instantiate()
	bottle.map_id = scene.map_id
	bottle.position = Vector3(24,8,16)
	scene.add_child(bottle)
	await process_frame
	state.world_items = {}
	scene._refresh_world_items()
	check(state.world_items.has("shore_message_bottle") and not bottle.is_queued_for_deletion(),"authored pickup registers after startup selects the save context")
	check(bottle.get_node("Pickup").is_in_group("ember_interact"),"pickup uses the real F route")
	var visual_id:int=bottle.get_node("ItemVisual").get_instance_id()
	check(scene._player.activate_interact(bottle.get_node("Pickup")),"player can activate the bottle")
	bottle.take(scene._player)
	var effects:=get_nodes_in_group("ember_item_pickup_effects")
	check(effects.size()==1,"repeated pickup cannot create a second grant or flight effect")
	await process_frame
	check(int(state.inventory.get("shore_sealed_bottle",0)) == 1,"pickup adds exactly one bottle")
	if effects.size()==1:
		var effect=effects[0]
		check(effect._pivot.get_child(0).get_instance_id()==visual_id,"pickup reuses the object's actual visual")
		var initial:Vector3=effect._start
		await create_timer(0.25).timeout
		check(effect._pivot.global_position.y>initial.y+3.0,"item visibly rises toward the collector's head")
		scene._player.position+=Vector3(4,0,0)
		await create_timer(0.29).timeout
		var head:Vector3=scene._player.get_node("Status").global_position+Vector3.UP*3
		check(effect._collapsing and effect._pivot.global_position.distance_to(head)<0.1,"collapse follows the moving collector above the head")
		check(effect._pivot.scale.x<1 and effect._pivot.scale.x>0,"item contracts before disappearing")
		var saved:=EmberExploreState.new();saved.storage_root=state.storage_root
		check(saved.load_autosave() and saved.inventory.get("shore_sealed_bottle",0)==1 and saved.world_items.shore_message_bottle.count==0,"ownership is saved while cosmetic flight is still active")
		saved.free()
		await create_timer(0.25).timeout
		check(not is_instance_valid(effect),"finished effect removes itself without a physical item")
	check(not state.pickup_world_item("shore_message_bottle",false).ok,"second pickup cannot duplicate the bottle")
	var reentered = load("res://prefabs/items/shore_bottle_pickup.tscn").instantiate()
	reentered.map_id = scene.map_id
	scene.add_child(reentered)
	await process_frame
	check(not is_instance_valid(reentered),"collected authored bottle does not reappear on reentry")
	var result := state.drop_inventory_item("shore_sealed_bottle",scene.map_id,Vector3(24,14,16),false)
	check(result.ok and not state.inventory.has("shore_sealed_bottle"),"drop transfers ownership to world")
	var id := str(result.get("id",""))
	for frame in 70: await physics_frame
	var bodies := get_nodes_in_group("ember_world_item_bodies")
	check(bodies.size() == 1,"one dropped physical body exists")
	if bodies.size() == 1:
		check(bodies[0].global_position.y < 14.0 and bodies[0].global_position.y > -20.0,"drop falls and meets the fixture terrain")
	check(state.save_slot(1),"dropped item saves")
	var reopened := EmberExploreState.new()
	reopened.storage_root = state.storage_root
	check(reopened.load_slot(1),"dropped item reopens")
	check(reopened.world_items.size() == state.world_items.size() and state.world_items.keys().all(func(key): return reopened.world_items.has(key)) and reopened.inventory == state.inventory,"world/inventory survive reopen together")
	check(Records.vector(reopened.world_items[id].position).distance_to(Records.vector(state.world_items[id].position)) < 0.01,"saved drop position survives float serialization")
	state.adopt_loaded_save(reopened)
	check(state.pickup_world_item(id,false).ok,"dropped bottle can be picked up after restore")
	await process_frame
	var bag: EmberInventoryUi = scene._inventory_ui
	bag.open()
	check(bag.select_item("shore_sealed_bottle"),"bottle is selectable in the actual bag")
	bag.get_node("Backdrop").find_child("InventoryUseItem",true,false).emit_signal("pressed")
	check(not state.inventory.has("shore_sealed_bottle") and state.inventory.get("shore_empty_bottle",0) == 1 and state.inventory.get("shore_message_letter",0) == 1,"open atomically replaces bottle with bottle and letter")
	check(bag.select_item("shore_message_letter"),"letter is selectable")
	bag.confirm()
	check(not bag.is_open() and scene._interaction_ui.is_open(),"reading routes through the existing dialogue UI")
	for step in 8:
		if not scene._interaction_ui.is_open(): break
		scene._interaction_ui.advance()
	check(state.flags.get("shore_letter_read",false) and EmberQuestCatalog.projection(EmberQuestCatalog.definition("shore_message"),state.flags).status == "active","reading advances the real quest flags")
	check(state.inventory.get("shore_message_letter",0) == 1,"reading does not consume the letter")
	var journal: EmberQuestJournalUi = scene._quest_journal_ui
	journal.open()
	check(journal.find_child("QuestProgressSource",true,false) == null,"player journal hides save internals")
	check(journal.find_child("ResetQuestProgress_shore_message",true,false) == null,"player journal has no destructive test reset")
	check(journal.find_child("QuestObjective_deliver_shells",true,false) == null,"player journal does not reveal locked future objectives")
	journal.close()
	var diagnostic := EmberQuestJournalUi.new()
	diagnostic.show_debug_progress = true
	diagnostic.progress_state = state
	root.add_child(diagnostic);diagnostic.open()
	check(diagnostic.find_child("QuestProgressSource",true,false) != null,"explicit diagnostic journal retains its progress controls")
	diagnostic.queue_free()
	await test_keeper(scene,state)
	state.inventory["shore_sealed_bottle"] = 1
	state.inventory["shore_empty_bottle"] = 20
	var before := state.inventory.duplicate(true)
	check(not state.open_container("shore_sealed_bottle",false).ok and state.inventory == before,"full contents stack leaves the sealed bottle intact")
	check(state.save_slot(1) and reopened.load_slot(1) and reopened.flags.get("shore_letter_read",false),"quest progress survives save/load")
	var old := state.capture_save()
	old.erase("worldItems")
	reopened._apply_v2_payload(old,false)
	check(reopened.world_items.is_empty() and reopened.inventory == state.inventory,"old v2 save remains readable")
	check(Records.normalize({"bad":{"itemId":"coin","count":1,"mapId":"x","position":[NAN,0,0],"rotation":[0,0,0]}}).is_empty(),"nonfinite world coordinates are rejected")
	for item in ["shore_sealed_bottle","shore_empty_bottle","shore_message_letter"]:
		check(ItemStore.validation_errors(ItemStore.document(item)).is_empty(),"item validates: "+item)
	var editor := ItemEditor.new()
	editor.setup("shore_sealed_bottle","shore_sealed_bottle")
	root.add_child(editor)
	var document := editor._document()
	check(document.get("openContents",{}) == {"shore_empty_bottle":1,"shore_message_letter":1},"editor preserves contents")
	check(str(document.get("worldScene","")).ends_with("sealed_bottle.tscn"),"editor preserves drop visual")
	var undo := UndoRedo.new()
	var session := Session.new()
	session.configure(undo)
	check(session.create("item","world_item_editor_fixture","Контейнер",load("res://content/items/shore_sealed_bottle.tres")),"item draft creates through existing session")
	session.set_value("definition",document)
	check(session.has_changes(),"contents draft is tracked")
	session.undo(); session.redo()
	check(session.draft.definition.get("openContents",{}) == document.openContents,"draft Undo/Redo retains contents")
	session.discard()
	check(not session.has_changes(),"draft discard restores the baseline")
	check(session.create("item","world_item_editor_fixture","Контейнер",load("res://content/items/shore_sealed_bottle.tres")),"draft can be reopened after discard")
	# Native publication is restricted to the already-guarded disposable project.
	var published := document.duplicate(true)
	published.id = "world_item_editor_fixture"
	session.set_value("definition",published)
	check(session.save(),"item contents publish through existing Save: "+session.last_error)
	var saved := ResourceLoader.load(session.path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberItemResource
	check(saved != null and saved.definition.openContents == document.openContents,"item contents survive fresh load")
	undo.undo()
	check(not FileAccess.file_exists(session.path),"publication Undo removes only new fixture")
	undo.redo()
	check(FileAccess.file_exists(session.path),"publication Redo restores fixture")
	editor.queue_free()
	undo.free()
	reopened.free()
	Content.verify_sources(setup,failures)
	print("WORLD_ITEM ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func finish_dialogue(ui: EmberInteractionUi) -> void:
	for step in 12:
		if not ui.is_open(): break
		ui.advance()

func test_keeper(scene: Node, state: EmberExploreState) -> void:
	var keeper = load("res://prefabs/items/shore_keeper.tscn").instantiate()
	scene.add_child(keeper)
	var talk: EmberInteract = keeper.get_node("Talk")
	var ui: EmberInteractionUi = scene._interaction_ui
	var shells := []
	for index in 3:
		var shell = load("res://prefabs/items/shore_shell_pickup.tscn").instantiate()
		shell.pickup_id = "shore_shell_"+str(index+1)
		shell.map_id = scene.map_id
		shell.position = Vector3(20+index*6,8,20)
		scene.add_child(shell)
		shells.append(shell)
	await process_frame
	check(shells.all(func(shell):return not shell.visible and not shell.get_node("Pickup").is_in_group("ember_interact")),"shells stay hidden before accepting the task")
	scene._refresh_world_items()
	var before_acceptance: Dictionary = state.capture_save()
	scene._player.activate_interact(talk)
	ui.advance(); ui.choose(1); ui.advance()
	check(not state.flags.get("shore_sender_met",false),"declining does not accept the task")
	scene._player.activate_interact(talk)
	ui.advance(); ui.choose(0); ui.advance()
	finish_dialogue(ui)
	check(state.flags.get("shore_sender_met",false) and shells.all(func(shell):return shell.visible),"accepting the request reveals all three shells")
	scene._player.activate_interact(talk)
	check(not state.flags.get("shore_shells_delivered",false),"zero shells cannot finish delivery")
	finish_dialogue(ui)
	for index in 2: scene._player.activate_interact(shells[index].get_node("Pickup"))
	scene._player.activate_interact(talk)
	finish_dialogue(ui)
	check(state.inventory.get("shore_shell",0) == 2 and not state.flags.get("shore_shells_delivered",false),"insufficient delivery neither consumes items nor advances the quest")
	scene._player.activate_interact(shells[2].get_node("Pickup"))
	scene._player.activate_interact(talk)
	# The flag is set before showing thanks; closing that text must not lose the hand-in.
	check(state.inventory.get("shore_shell",0) == 0 and state.flags.get("shore_shells_delivered",false),"three shells exchange atomically and advance to boar stage")
	ui.close()
	scene._player.activate_interact(talk)
	check(talk.routed_script_id(state.flags) == "shore_keeper_boar","next dialogue requests the boar")
	finish_dialogue(ui)
	# Reward endpoint fixture only: this does not exercise or claim a real battle.
	check(state.apply_authored_flag("shore_boar_defeated",true,false).get("allowed",false),"boar objective unlocks only after shell delivery")
	state.grant_item("shore_boar_hide",1,false)
	var coins := int(state.inventory.get("coin",0))
	scene._player.activate_interact(talk)
	finish_dialogue(ui)
	check(state.inventory.get("shore_boar_hide",0) == 0 and state.inventory.get("coin",0) == coins+10,"reward endpoint exchanges hide for ten coins")
	scene._player.activate_interact(talk); finish_dialogue(ui)
	check(state.inventory.get("coin",0) == coins+10,"completed quest cannot award twice")
	var bag: EmberInventoryUi = scene._inventory_ui
	bag.open();bag.select_item("shore_message_letter");bag.confirm();finish_dialogue(ui)
	check(EmberQuestCatalog.projection(EmberQuestCatalog.definition("shore_message"),state.flags).status == "done","rereading does not regress the completed quest")
	var completed: Dictionary = state.capture_save()
	state._apply_v2_payload(before_acceptance,false)
	await process_frame
	var restored_shells := get_nodes_in_group("ember_world_item_bodies").filter(func(body):return body.item_id == "shore_shell")
	check(restored_shells.size() == 3 and restored_shells.all(func(body):return not body.visible),"same-scene Load restores authored availability after bodies were collected")
	state._apply_v2_payload(completed,false)
	await process_frame
	var old_world: Dictionary = completed.duplicate(true)
	old_world.erase("worldItems")
	old_world.flags = {}
	state._apply_v2_payload(old_world,false)
	await process_frame
	var fresh_bottles := get_nodes_in_group("ember_world_item_bodies").filter(func(body):return body.item_id == "shore_sealed_bottle")
	check(fresh_bottles.size() == 1,"same-scene old save initializes missing authored placements")
	state._apply_v2_payload(completed,false)
	await process_frame
	var editor := preload("res://addons/ember_import/ember_action_chain_editor.gd").new()
	editor.setup("shore_deliver_shells","shore_deliver_shells")
	root.add_child(editor)
	check(editor._document().steps[0].get("costs",{}) == {"shore_shell":3},"authoring picker retains three-shell cost")
	check(preload("res://addons/ember_import/ember_action_script_store.gd").validation_errors(editor._document()).is_empty(),"exchange action validates in existing authoring")
	editor.queue_free()
	keeper.queue_free()
	await process_frame
