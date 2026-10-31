extends SceneTree
const Content=preload("res://tools/fixtures/ember_interaction_test_fixture.gd")
const Item=preload("res://scripts/ember_world_item_3d.gd")
const Combat=preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid=preload("res://scripts/prototypes/ember_combat_grid.gd")
var setup: Dictionary
var errors: Array[String]=[]
var hud: Control
var state: EmberExploreState
var fragile: RigidBody3D
var sturdy: RigidBody3D
const FRAGILE:="world_item:combat_fragile"
const STURDY:="world_item:combat_sturdy"
func _init() -> void:
	setup=Content.prepare(self);run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);push_error(label)
func frames(n: int) -> void:
	for i in n:await physics_frame
func shot(label: String) -> void:
	var folder:=OS.get_environment("EMBER_CRATE_COMBAT_CAPTURE_DIR")
	if folder.is_empty():return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func crate(parent: Node3D,id: String,at: Vector3,breaks: bool) -> RigidBody3D:
	var body:=Item.new();body.pickup_id=id;body.item_id="quest_crate";body.carryable=true;body.pushable=true;body.breakable=breaks
	body.break_effect=load("res://prefabs/items/quest_crate_break.scn");body.position=at;parent.add_child(body);return body
func turn_at(cell: Vector2i) -> void:
	hud._state.units.protagonist.cell=cell;hud._state.units.protagonist.nextAt=0.0;hud._state.units.shore_boar.nextAt=100.0
	# A lifecycle fixture needs several throws, independently of random criticals
	# and the production boar's small HP pool. Combat balance is not this gate.
	if hud._state.units.shore_boar.maxHp<200:
		hud._state.units.shore_boar.maxHp=200;hud._state.units.shore_boar.hp=200
	hud._state.rngSeed=71
	hud._refresh();
func resolve(command: String,target: String,cell:=Vector2i(-1,-1),choice:="throw") -> Dictionary:
	var snapshot: Dictionary=hud.state_snapshot()
	return Grid.command_preview(snapshot,command,target,snapshot.units.protagonist.cell,Vector2i(-1,-1),cell,choice)
func hit_throw(cell: Vector2i) -> Dictionary:
	for seed in range(1,201):
		hud._state.rngSeed=seed
		var candidate:=resolve(Combat.HELD_THROW_COMMAND,"",cell)
		if candidate.get("ok",false) and candidate.get("hit",false):return candidate
	return {}
func check_miss(snapshot: Dictionary,item_id: String) -> void:
	var trial:=snapshot.duplicate(true)
	var missed: Dictionary={}
	for seed in range(1,201):
		trial.rngSeed=seed
		var candidate:=Grid.command_preview(trial,Combat.HELD_THROW_COMMAND,"",trial.units.protagonist.cell,Vector2i(-1,-1),trial.units.shore_boar.cell)
		if candidate.get("ok",false) and not candidate.get("hit",true):missed=candidate;break
	check(not missed.is_empty(),"no reproducible miss case")
	if missed.is_empty():return
	var after:=Combat.commit(trial,missed)
	check(not after.holds.has("protagonist") and after.units[item_id].has("cell"),"miss kept thrown crate in hand")
	check(after.units.shore_boar.hp==trial.units.shore_boar.hp,"miss damaged enemy")
	check(after.units[item_id].hp==(0 if trial.units[item_id].worldItemBreakable else 1),"miss lost crate durability rule")
func perform(result: Dictionary,label: String) -> void:
	check(result.get("ok",false),label+": "+str(result.get("error","")))
	if not result.get("ok",false):return
	var before_turn: int=hud._state.turn
	print("COMMAND ",label," turn=",before_turn," outcome=",Combat.outcome(hud._state)," held=",hud._state.holds)
	hud._current_preview=result;hud._confirm_action()
	check(hud._state.turn>before_turn,label+": HUD did not commit command")
	await frames(40)
func run() -> void:
	create_timer(85).timeout.connect(func():push_error("crate combat timeout");quit(2))
	if setup.refused or setup.error!=OK:quit(2);return
	state=root.get_node("EmberExploreProgress");state.reset_new_game();state.persistence_enabled=false
	var authored:=Item.new();authored.breakable=true;authored.break_impact_speed=42;authored.throw_damage=11
	var packed:=PackedScene.new();check(packed.pack(authored)==OK,"item pack failed");authored.free()
	check(ResourceSaver.save(packed,"user://crate-properties.scn")==OK,"item scene save failed")
	var reopened=load("user://crate-properties.scn").instantiate()
	check(reopened.breakable and reopened.break_impact_speed==42 and reopened.throw_damage==11,"durability settings lost on reopen");reopened.free()
	state.set_active_hero_ids(["protagonist"],false)
	var scene=Content.save_map("crate_battle_fixture",setup.directory).instantiate();root.add_child(scene);current_scene=scene
	await frames(5);scene._player.set_physics_process(false);scene._party_followers.set_physics_process(false)
	var floor:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(160,2,160);floor.position=Vector3(-264,11,296);floor.add_child(shape);scene.add_child(floor)
	var gentle:=crate(scene,"gentle",Vector3(-290,12.25,275),true)
	await frames(25);check(is_instance_valid(gentle) and state.world_items.gentle.count==1,"resting fragile crate broke")
	gentle.global_position=Vector3(-290,72,275);gentle.sleeping=false
	var drop_sturdy:=crate(scene,"drop_sturdy",Vector3(-280,72,310),false)
	await frames(90)
	check(not is_instance_valid(gentle) and state.world_items.gentle.count==0,"strong ground impact did not break fragile crate")
	check(is_instance_valid(drop_sturdy) and state.world_items.drop_sturdy.count==1,"strong impact broke sturdy crate")
	drop_sturdy.queue_free();await frames(2);state.world_items.drop_sturdy.count=0
	fragile=crate(scene,"combat_fragile",Vector3(-282,12.25,320),true)
	sturdy=crate(scene,"combat_sturdy",Vector3(-264,12.25,264),false)
	await frames(20)
	scene._player.global_position=fragile.global_position+Vector3(0,0,6);scene._player._try_interact();await frames(2)
	check(fragile.is_carried(),"world F failed to take fragile crate")
	state.persistence_enabled=true
	var zone=load("res://prefabs/items/shore_boar_zone.tscn").instantiate();scene.add_child(zone)
	zone.get_node("Boar").set_physics_process(false);state.set_flag("shore_shells_delivered",true,false)
	check(zone.engage("player")==OK,"in-place entry failed: "+zone.last_error)
	if zone.battle==null:quit(1);return
	var deadline:=Time.get_ticks_msec()+6000
	while not zone.presentation_complete and Time.get_ticks_msec()<deadline:await process_frame
	hud=zone.battle.get_node("CombatHUDLayer/CombatHUD")
	if hud._deployment_active:check(hud._confirm_deployment(),"deployment failed")
	await frames(3)
	var snapshot: Dictionary=hud.state_snapshot()
	check(snapshot.holds.get("protagonist","")==FRAGILE and snapshot.units.has(STURDY),"entry lost held/nearby world objects")
	check(fragile.combat_suspended and not fragile.visible and fragile.freeze,"world body was not suspended")
	check(Combat.state_validation_errors(snapshot).is_empty(),"object snapshot invalid: "+str(Combat.state_validation_errors(snapshot)))
	var invalid:=snapshot.duplicate(true);invalid.units[FRAGILE].team="hero"
	check(not Combat.state_validation_errors(invalid).is_empty(),"forged object team accepted")
	check(not Combat.current_unit_id(snapshot).begins_with("world_item:"),"crate received a turn")
	check(Combat.timeline(snapshot,12).all(func(entry):return not str(entry.get("id",entry.get("unitId",""))).begins_with("world_item:")),"crate entered initiative")
	await shot("held-crate")
	turn_at(Vector2i(1,1));hud._state.units.shore_boar.cell=Vector2i(2,1);hud._refresh()
	var before: Dictionary=hud.state_snapshot();var before_hash:=hash(before)
	check_miss(before,FRAGILE)
	var hit:=hit_throw(Vector2i(2,1))
	check(hit.get("ok",false) and hit.get("damage",{}).get("shore_boar",0)>0,"crate throw cannot hit occupied enemy cell")
	check(hash(before)==before_hash and state.world_items.combat_fragile.count==1,"preview mutated persistent item")
	await perform(hit,"fragile throw")
	check(hud._state.units[FRAGILE].hp==0 and hud._state.units.shore_boar.hp<before.units.shore_boar.hp,"fragile throw did not damage/break")
	check(state.world_items.combat_fragile.count==1,"unconfirmed attempt changed world")
	await shot("fragile-throw")
	hud._retry_encounter();await frames(4)
	check(hud._state.units[FRAGILE].hp==1 and hud._state.holds.get("protagonist","")==FRAGILE,"Retry lost original held crate")
	check(hud._state.units.keys().filter(func(id):return str(id)==FRAGILE).size()==1,"Retry duplicated crate")
	turn_at(Vector2i(1,1));hud._state.units.shore_boar.cell=Vector2i(3,2)
	await perform(resolve(Combat.HELD_THROW_COMMAND,"",Vector2i(1,2)),"fragile ground throw")
	check(hud._state.units[FRAGILE].hp==0,"fragile ground throw survived")
	turn_at(Vector2i(1,0));hud._state.units[STURDY].cell=Vector2i(2,0);hud._refresh()
	await perform(resolve("lift_throw",STURDY,Vector2i(-1,-1),"hold"),"lift sturdy")
	check(hud._state.holds.get("protagonist","")==STURDY,"sturdy did not become held")
	turn_at(Vector2i(1,1));hud._state.units.shore_boar.cell=Vector2i(2,1);hud._refresh()
	var hp_before: int=hud._state.units.shore_boar.hp
	check_miss(hud.state_snapshot(),STURDY)
	await perform(hit_throw(Vector2i(2,1)),"sturdy throw")
	check(hud._state.units[STURDY].hp==1 and hud._state.units.shore_boar.hp<hp_before,"sturdy throw did not damage/survive")
	if not hud._state.units[STURDY].has("cell"):quit(1);return
	var landing: Vector2i=hud._state.units[STURDY].cell
	check(landing!=hud._state.units.shore_boar.cell,"sturdy overlaps enemy after impact")
	turn_at(landing+Vector2i.LEFT)
	await perform(resolve("lift_throw",STURDY,Vector2i(-1,-1),"hold"),"repeat lift sturdy")
	check(hud._state.holds.get("protagonist","")==STURDY,"sturdy cannot be reused")
	turn_at(landing+Vector2i.LEFT)
	await perform(resolve(Combat.HELD_LOWER_COMMAND,"protagonist"),"lower sturdy")
	check(hud._state.units[STURDY].hp==1 and not hud._state.holds.has("protagonist"),"gentle lower broke/retained crate")
	await shot("sturdy-return")
	hud._state.units.shore_boar.hp=0
	check(Combat.outcome(hud._state)=="victory","object prevented victory")
	var result: Dictionary=hud.state_snapshot()
	check(EmberCombatTransition.finish(self,"victory",state,result)==OK,"victory return failed")
	await frames(6)
	check(state.world_items.combat_fragile.count==0 and state.world_items.combat_sturdy.count==1,"return lost item destruction/survival")
	check(is_instance_valid(sturdy) and not sturdy.combat_suspended and sturdy.visible,"surviving physical body did not resume")
	check(not state.combat_party_locked,"world remained locked")
	var loaded:=EmberExploreState.new();loaded.storage_root=state.storage_root
	check(loaded.load_autosave() and loaded.world_items.combat_fragile.count==0 and loaded.world_items.combat_sturdy.count==1,"cold autosave lost item outcome");loaded.free()
	state.world_items["drop_crate_gate"]=state.world_items.combat_sturdy.duplicate(true)
	state.apply_combat_result({"units":{"world_item:drop_crate_gate":{"worldItemId":"drop_crate_gate","hp":0}}},false,0,true)
	check(not state.world_items.has("drop_crate_gate"),"destroyed dynamic drop left a tombstone")
	for i in 8:
		if scene._interaction_ui.is_open():scene._interaction_ui.advance()
	scene._player.global_position=sturdy.global_position+Vector3(0,0,6);scene._player._try_interact();await frames(2)
	check(sturdy.is_carried(),"returned sturdy crate cannot be taken with F")
	# A second, explicitly reset fixture attempt finishes while still holding the
	# same item; the world hand connection must resume too, not just ground poses.
	state.set_flag("shore_boar_defeated",false,false)
	check(zone.engage("player")==OK,"held return entry failed")
	deadline=Time.get_ticks_msec()+6000
	while not zone.presentation_complete and Time.get_ticks_msec()<deadline:await process_frame
	hud=zone.battle.get_node("CombatHUDLayer/CombatHUD")
	if hud._deployment_active:check(hud._confirm_deployment(),"held return deployment failed")
	check(hud._state.holds.get("protagonist","")==STURDY,"second entry lost held sturdy crate")
	hud._state.units.shore_boar.hp=0
	check(EmberCombatTransition.finish(self,"victory",state,hud.state_snapshot())==OK,"held return victory failed")
	await frames(6)
	check(is_instance_valid(sturdy) and sturdy.is_carried() and not sturdy.combat_suspended,"victory lost world carrier connection")
	state.persistence_enabled=false;scene.queue_free();await process_frame;await process_frame
	print("CRATE_COMBAT PASS: weak/strong impacts, two durable types, same held identity, object initiative, preview/commit, enemy damage, reuse/lower, Retry, victory/world F and cold save" if errors.is_empty() else "CRATE_COMBAT FAIL")
	quit(0 if errors.is_empty() else 1)
