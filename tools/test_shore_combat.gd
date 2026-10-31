extends SceneTree
const Content = preload("res://tools/fixtures/ember_interaction_test_fixture.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Field = preload("res://scripts/ember_field_encounter.gd")
var setup: Dictionary
var failures: Array[String] = []
func _init() -> void:
	setup=Content.prepare(self)
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label);printerr("SHORE_COMBAT FAIL ",label)
func run() -> void:
	create_timer(45).timeout.connect(func():printerr("SHORE_COMBAT timeout");quit(2))
	if setup.refused or setup.error != OK: quit(2);return
	var state:=root.get_node("EmberExploreProgress") as EmberExploreState
	state.reset_new_game()
	state.persistence_enabled=true
	state.set_active_hero_ids(["protagonist","mira"],false)
	var encounter:=EmberEncounterCatalog.definition("shore_boar")
	check(encounter!=null,"encounter catalog includes boar")
	check(encounter.validation_errors().is_empty(),"boar encounter valid: "+str(encounter.validation_errors()))
	check(not Combat.initial_state().units.has("shore_boar"),"catalog addition does not alter baseline roster")
	var initial:=encounter.initial_state({},71,["protagonist","mira"])
	check(initial.units.size()==3 and initial.units.has("shore_boar"),"explicit encounter roster")
	var a:=Field.with_initiative(initial,"player")
	var b:=Field.with_initiative(initial,"rear")
	var c:=Field.with_initiative(initial,"enemy")
	check(b.units.shore_boar.nextAt-initial.units.shore_boar.nextAt==2*(a.units.shore_boar.nextAt-initial.units.shore_boar.nextAt),"rear doubles initial timeline advantage")
	check(Combat.current_unit_id(c)=="shore_boar","enemy contact grants first initiative")
	check(Grid.focus_definition(initial).is_empty(),"ordinary field has no invisible magic focus")
	var scene=Content.save_map("shore_battle_fixture",setup.directory).instantiate()
	root.add_child(scene);current_scene=scene
	for i in 5:await process_frame
	scene._player.set_physics_process(false)
	scene._party_followers.set_physics_process(false)
	# One existing physical floor; the battle adapter must never add another.
	var floor:=StaticBody3D.new();var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(96,2,96);shape.shape=box;floor.position=Vector3(-264,11,296);floor.add_child(shape);scene.add_child(floor)
	var zone=load("res://prefabs/items/shore_boar_zone.tscn").instantiate()
	scene.add_child(zone)
	zone.get_node("Boar").set_physics_process(false)
	state.set_flag("shore_shells_delivered",true,false)
	scene._player.global_position=Vector3(-248,12,336)
	scene._party_followers.reset_to_leader()
	zone.get_node("Boar").visible=true
	for i in 3:await physics_frame
	var original_scene:=scene.get_instance_id()
	var original_map:=scene.get_node("Map").get_instance_id()
	check(zone.engage("enemy")==OK,"start real combat shell in place: "+zone.last_error)
	if zone.battle==null: quit(1);return
	check(zone.battle.get_node("CombatHUDLayer/CombatHUD").entry_transition_active,"battle input is locked while entry cover is active")
	var start_at:Vector3=scene._player.global_position
	check(scene._player.visible and zone._entry_cover.color.a==0,"entry leaves the same world actors visible, without black cover")
	var mid_deadline:=Time.get_ticks_msec()+350
	while Time.get_ticks_msec()<mid_deadline:await process_frame
	check(scene._player.global_position.y>start_at.y+2 and scene._player.global_position.distance_to(start_at)>3,"leader visibly hops from the exploration position")
	var entry_deadline := Time.get_ticks_msec()+5000
	while not zone.presentation_complete and Time.get_ticks_msec()<entry_deadline:await process_frame
	check(zone.presentation_complete,"entry effect completes before interaction")
	var hud=zone.battle.get_node("CombatHUDLayer/CombatHUD")
	check(not hud.entry_transition_active,"battle input unlocks after camera settles")
	var arena=zone.battle.get_node("Arena")
	check(current_scene.get_instance_id()==original_scene and scene.get_node("Map").get_instance_id()==original_map,"world/map instances survive battle entry")
	check(state.combat_party_locked,"party locked during combat")
	check(zone.get_node("Boar").visible and zone.get_node("Boar").process_mode==Node.PROCESS_MODE_DISABLED,"same field enemy remains visible with its controller frozen")
	check(zone._world_actors.size()==3 and zone._world_actors.protagonist==scene._player,"leader, follower and enemy retain their world identities")
	check(not hud._fade_overlay.visible,"continuous entry has no opaque Lab fade overlay")
	check(not arena.get_node("CombatGridMap").visible and arena.get_node("CombatGridMap").collision_layer==0,"battle projection adds no floor")
	check(is_equal_approx(arena.global_basis.get_scale().x*1.2,16.0),"cell is one world metre")
	check(arena.get_node_or_null("WorldEnvironment")==null,"world lighting retained")
	check(arena.get_node("CombatActors3D/CombatUnit_shore_boar").get_child_count()>0,"boar projected through common actor renderer")
	var landing:Vector3=arena._unit_roots.protagonist.to_global(Vector3(0,-0.36,0))
	check(scene._player.global_position.distance_to(landing)<0.1,"leader lands on the authoritative deployment cell")
	if hud._deployment_active: check(hud._confirm_deployment(),"confirm existing party deployment")
	for i in 3:await process_frame
	var picked:Vector2i=arena.pick_cell_at(arena.screen_position_for_cell(Vector2i(2,2)))
	check(picked==Vector2i(2,2),"translated/scaled world camera and picking agree: "+str(picked))
	check(int(hud.state_snapshot().turn)>1 and Combat.unit_definition(hud.state_snapshot(),Combat.current_unit_id(hud.state_snapshot())).team=="hero","enemy initiative executes before accepting hero commands")
	var persistent_party:=state.party.duplicate(true)
	var before_seed:int=hud.state_snapshot().rngSeed
	# A failed attempt is a lifecycle fixture, separate from the legal winning
	# attempt below. Retry must discard it and keep this world and initiative.
	for unit in hud._state.units.values():
		if unit.team=="hero":unit.hp=0
	hud._refresh()
	check(Combat.outcome(hud.state_snapshot())=="defeat" and state.party==persistent_party,"in-place defeat does not commit party damage")
	hud._retry_encounter()
	check(Combat.outcome(hud.state_snapshot())=="active" and hud.state_snapshot().rngSeed!=before_seed and not hud._deployment_active,"Retry rebuilds the same in-place encounter without reopening deployment")
	check(state.party==persistent_party and not state.flags.get("shore_boar_defeated",false),"Retry grants no result or loot")
	# Use actual action previews/commit/AI through the existing HUD. No HP edits,
	# console victory or quest result injection substitutes for the encounter.
	for turn in 40:
		var snapshot: Dictionary=hud.state_snapshot()
		if Combat.outcome(snapshot)!="active":break
		var actor:=Combat.unit_definition(snapshot,Combat.current_unit_id(snapshot))
		if actor.team=="enemy":
			hud._advance_enemy_turns();hud._refresh();continue
		var resolved: Dictionary={}
		for command in actor.get("actions",[]):
			var candidate:=Grid.approach_command_preview(snapshot,str(command),"shore_boar")
			if candidate.get("ok",false) and str(command)!="defend":resolved=candidate;break
		if resolved.is_empty():resolved=Grid.command_preview(snapshot,"defend",str(actor.id),actor.get("cell",Vector2i.ZERO))
		check(resolved.get("ok",false),"legal hero action "+str(actor.id))
		if not resolved.get("ok",false):break
		hud._current_preview=resolved
		hud._confirm_action()
		await process_frame
	check(Combat.outcome(hud.state_snapshot())=="victory","real resolver and AI reach victory")
	var coins:=int(state.inventory.get("coin",0))
	var final:Dictionary=hud.state_snapshot()
	check(EmberCombatTransition.finish(self,"victory",state,final)==OK,"commit real outcome")
	check(EmberCombatTransition.finish(self,"victory",state,final)!=OK,"duplicate victory rejected")
	for i in 5:await process_frame
	check(current_scene.get_instance_id()==original_scene and scene.get_node("Map").get_instance_id()==original_map,"return keeps actual world/map")
	check(not state.combat_party_locked and scene._player.visible and scene.get_node("CanvasLayer").visible,"exploration restored")
	check(state.flags.get("shore_boar_defeated",false) and state.inventory.get("shore_boar_hide",0)==1,"victory supplies one real skin")
	var loaded:=EmberExploreState.new();loaded.storage_root=state.storage_root
	check(loaded.load_autosave() and loaded.inventory.get("shore_boar_hide",0)==1 and loaded.flags.get("shore_boar_defeated",false),"loot survives immediate load before acknowledging receipt")
	loaded.free()
	for i in 8:
		if scene._interaction_ui.is_open():scene._interaction_ui.advance()
	check(state.inventory.get("shore_boar_hide",0)==1,"receipt cannot duplicate loot")
	scene._interaction_ui.activate_script("shore_receive_reward")
	for i in 8:
		if scene._interaction_ui.is_open():scene._interaction_ui.advance()
	check(state.inventory.get("shore_boar_hide",0)==0 and state.inventory.get("coin",0)==coins+10 and state.flags.get("shore_reward_received",false),"real combat result reaches mission reward")
	await test_group_entry(scene,zone,state)
	print("SHORE_COMBAT ","PASS" if failures.is_empty() else "FAIL", " failures=",failures.size()," turns=",final.get("turn",0))
	scene.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)

func test_group_entry(scene: Node, zone: Node, state: EmberExploreState) -> void:
	# Guarded disposable native encounter only: four heroes and two instances of
	# one enemy template exercise identity mapping and the no-deployment route.
	state.reset_new_game()
	state.set_active_hero_ids(["protagonist","mira","orik","sena"],false)
	var encounter:=EmberEncounterCatalog.definition("shore_boar").duplicate(true) as EmberEncounterResource
	encounter.encounter_id="hop_group_fixture"
	encounter.victory_flag_id="hop_group_won"
	encounter.enemy_unit_ids=PackedStringArray(["shore_boar","shore_boar"])
	encounter.battlefield.enemy_deployment_cells.append(Vector2i(4,3))
	check(encounter.validation_errors().is_empty(),"group fixture uses valid existing encounter schema")
	check(ResourceSaver.save(encounter,"res://content/combat/encounters/hop_group_fixture.tres")==OK,"group encounter published only in guarded disposable project")
	zone.encounter_id=encounter.encounter_id
	var second:=zone.get_node("Boar").duplicate() as CharacterBody3D
	second.name="SecondBoar"
	second.combat_unit_id="shore_boar__instance_2"
	zone.add_child(second)
	second.set_physics_process(false)
	second.global_position=Vector3(-236,12,316)
	second.visible=true
	zone.get_node("Boar").visible=true
	scene._player.global_position=Vector3(-248,12,336)
	scene._party_followers.reset_to_leader()
	var party_before:=state.party.duplicate(true)
	check(zone.engage("enemy")==OK,"full group enters the same-world encounter")
	var deadline:=Time.get_ticks_msec()+350
	while Time.get_ticks_msec()<deadline:await process_frame
	var hud=zone.battle.get_node("CombatHUDLayer/CombatHUD")
	check(hud.state_snapshot().turn==1,"enemy initiative waits for landing even without pre-battle deployment")
	deadline=Time.get_ticks_msec()+4000
	while not zone.presentation_complete and Time.get_ticks_msec()<deadline:await process_frame
	check(zone.presentation_complete and zone._world_actors.size()==6,"all four heroes and both enemies land")
	check(zone._world_actors.shore_boar__instance_2==second,"duplicate enemy template keeps its own world identity")
	check(int(hud.state_snapshot().turn)>1,"first enemy actions start after landing")
	check(state.party==party_before and not state.flags.get("hop_group_won",false),"entry and first combat actions do not prematurely commit progress")
	EmberCombatTransition.abandon_active_encounter()
	zone.finish_in_place()
	await frames_after_group()
	check(not state.combat_party_locked and scene._player.visible,"abandon restores exploration controls")

func frames_after_group() -> void:
	for i in 3:await process_frame
