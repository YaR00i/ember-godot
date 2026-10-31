extends SceneTree
const Content = preload("res://tools/fixtures/ember_interaction_test_fixture.gd")
var setup: Dictionary
var failures: Array[String] = []
func _init() -> void:
	setup = Content.prepare(self)
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message);printerr("FEEDBACK FAIL ",message)
func frames() -> void:
	for i in 3:await process_frame
func run() -> void:
	if setup.refused or setup.error != OK:quit(2);return
	var state:=root.get_node("EmberExploreProgress") as EmberExploreState
	state.reset_new_game();state.persistence_enabled=false
	var scene=Content.save_map("feedback_fixture",setup.directory).instantiate()
	root.add_child(scene);current_scene=scene
	await frames()
	scene._player.set_physics_process(false);scene._party_followers.set_physics_process(false)
	var focus=scene.get_node("InteractionFocus")
	var tracker=scene.get_node("CanvasLayer/QuestTrackerUI")
	check(not tracker._card.visible and not tracker._toast.visible,"unknown quest has no HUD spoilers")
	var bottle=load("res://prefabs/items/shore_bottle_pickup.tscn").instantiate()
	bottle.map_id=scene.map_id;bottle.position=Vector3(24,4,16);scene.add_child(bottle)
	bottle.freeze=true
	scene._player.position=Vector3(24,4,24)
	await frames()
	check(focus.focused==bottle.get_node("Pickup") and focus._copies.size()>0 and focus._label.text.begins_with("[F]"),"nearest bottle has outline and F prompt")
	var original_mesh:Mesh=focus._copies[0].source.mesh
	check(focus._copies[0].copy.mesh==original_mesh and focus._copies[0].copy.material_override!=focus._copies[0].source.material_override,"outline is a derived mesh copy with its own material")
	scene._inventory_ui.open();await frames()
	check(focus.focused==null and not focus._label.visible,"bag hides interaction focus")
	scene._inventory_ui.close();await frames()
	scene._player.position=Vector3(200,4,200);await frames()
	check(focus.focused==null and focus._copies.is_empty(),"leaving reach clears old outline")
	scene._player.position=Vector3(24,4,24);await frames()
	var old_target_id:int=bottle.get_node("Pickup").get_instance_id()
	check(scene._player.activate_interact(bottle.get_node("Pickup")),"F command still targets the highlighted bottle")
	await frames()
	check((not is_instance_valid(focus.focused) or focus.focused.get_instance_id()!=old_target_id) and focus._copies.all(func(entry):return is_instance_valid(entry.source)),"collected object leaves no ghost outline; next nearby interaction may take focus")
	var keeper=load("res://prefabs/items/shore_keeper.tscn").instantiate()
	keeper.position=Vector3(40,4,32);scene.add_child(keeper)
	scene._player.position=Vector3(40,4,40);await frames()
	check(focus.focused==keeper.get_node("Talk") and focus._copies.size()>0,"NPC uses the same focus route")
	scene._player.activate_interact(keeper.get_node("Talk"));await frames()
	check(focus.focused==null,"dialogue hides interaction focus")
	scene._interaction_ui.close()
	state.set_flag("shore_letter_read",true,false)
	await frames()
	check(tracker._card.visible and "Найти отправителя" in tracker._objective.text and tracker._toast.visible,"reading exposes current objective and a quest update")
	check(not focus._badge.visible or not focus._badge.get_global_rect().intersects(tracker._toast.get_global_rect()),"interaction key does not cover the quest update")
	state.set_flag("shore_sender_met",true,false)
	check("три ракушки" in tracker._objective.text and "Цель обновлена" in tracker._toast_text.text,"next stage replaces HUD objective")
	var flags:=state.flags.duplicate(true)
	var resumed=preload("res://scripts/ember_quest_tracker_ui.gd").new();resumed.progress_state=state;scene.get_node("CanvasLayer").add_child(resumed)
	check("три ракушки" in resumed._objective.text and not resumed._toast.visible,"saved active quest resumes without a false new-quest toast")
	check(state.flags==flags,"HUD is read-only")
	resumed.queue_free()
	for flag in ["shore_shells_delivered","shore_boar_defeated","shore_reward_received"]:state.set_flag(flag,true,false)
	check(not tracker._card.visible and "Задание выполнено" in tracker._toast_text.text,"completion clears active tracker and announces result")
	state.combat_party_locked=true;await frames()
	check(focus.focused==null,"battle lock suppresses world prompts")
	state.combat_party_locked=false
	print("FEEDBACK ","PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	scene.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
