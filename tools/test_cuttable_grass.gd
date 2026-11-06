extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const LeafGate = preload("res://tools/test_leaf_pile.gd")
const FLAG := "cuttable_grass_revealed"
const PICKUP := "cut_grass_herb"
var host: Node3D
var state: EmberExploreState
var errors: Array[String]=[]
func _init() -> void:
	if not Fixture.prepare(self): quit(2); return
	_run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: errors.append(message); push_error(message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func pickup() -> Node3D:
	for node in get_nodes_in_group("ember_world_item_bodies"):
		if host.is_ancestor_of(node) and node.pickup_id==PICKUP and not node.is_queued_for_deletion():return node
	return null
func restore(slot: int) -> void:
	var loaded := EmberExploreState.new(); loaded.storage_root=state.storage_root
	check(loaded.load_slot(slot),"cold load failed"); state.adopt_loaded_save(loaded); loaded.free(); await frames(5)
func shot(label: String) -> void:
	var output := OS.get_environment("EMBER_GRASS_CAPTURE_DIR")
	if output.is_empty():return
	check(DirAccess.make_dir_recursive_absolute(output)==OK,"capture directory unavailable")
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK,"capture failed "+label)
func _run() -> void:
	state=root.get_node("EmberExploreProgress"); state.persistence_enabled=false; state.flags.clear(); state.world_items.clear()
	host=LeafGate.Host.new(); var map:=LeafGate.StubMap.new(); map.name="Map"; host.add_child(map)
	var canvas:=CanvasLayer.new(); canvas.name="CanvasLayer"; host.add_child(canvas)
	var hud:=Label.new(); hud.name="Gate"; canvas.add_child(hud)
	root.add_child(host); current_scene=host
	var floor_body:=StaticBody3D.new(); var floor_shape:=CollisionShape3D.new(); floor_shape.shape=BoxShape3D.new(); floor_shape.shape.size=Vector3(240,2,240); floor_shape.position.y=-1; floor_body.add_child(floor_shape); host.add_child(floor_body)
	var grass: Area3D=load("res://prefabs/items/cuttable_grass.scn").instantiate(); host.add_child(grass)
	state.progress_changed.connect(host._refresh_world_items); host._refresh_world_items()
	var player:=EmberPlayer.new(); player.progress_state=state; player.position=Vector3(0,0.1,28); host.add_child(player); player.set_physics_process(false)
	var ui:=EmberInventoryUi.new(); ui.progress_state=state; root.add_child(ui); player.inventory_ui=ui
	if not OS.get_environment("EMBER_GRASS_CAPTURE_DIR").is_empty():
		var camera:=Camera3D.new(); host.add_child(camera); camera.position=Vector3(52,45,68); camera.look_at(Vector3(0,8,0)); camera.fov=43; camera.current=true
		var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-55,-30,0); sun.shadow_enabled=true; host.add_child(sun)
		var world:=WorldEnvironment.new(); world.environment=Environment.new(); world.environment.background_mode=Environment.BG_COLOR; world.environment.background_color=Color(0.52,0.65,0.75); world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; world.environment.ambient_light_color=Color.WHITE; world.environment.ambient_light_energy=0.4; host.add_child(world)
		var ground:=MeshInstance3D.new(); ground.mesh=BoxMesh.new(); ground.mesh.size=Vector3(240,2,240); ground.position.y=-1; var paint:=StandardMaterial3D.new(); paint.albedo_color=Color("657b43"); ground.material_override=paint; host.add_child(ground)
	await frames(30)
	var foliage: ShaderMaterial=grass.get_node("PileVisual").material_override
	check(grass.get_node("PileVisual").mesh.surface_get_array_index_len(0)==72,"high grass misses three simple contour tufts")
	check(grass.get_node("PileVisual").cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"high grass shadows disabled")
	check(foliage.get_shader_parameter("flower_tint")==Color.WHITE,"harvest grass adds a separate dark tint")
	check(foliage.shader.has_meta("ember_feature_base"),"harvest grass misses existing compiled feature program")
	check(grass.get_node("CutStubble").material_override==foliage,"stubble lost shared meadow material")
	var initial:=int(state.inventory.get("herb",0))
	check(pickup()!=null and not pickup().visible and pickup().freeze,"herb exposed before cutting")
	check(not grass.get_node("CutStubble").visible and grass.get_node("PileVisual").visible,"uncut visuals wrong")
	player.position=Vector3(0,0.1,0); await frames(5)
	check(not state.flags.get(FLAG,false),"walking cut grass")
	player.position=Vector3(0,0.1,28); await frames(4)
	state.persistence_enabled=true; state.set_world_context("landscape_compact",player,16)
	check(state.save_slot(0),"uncut save failed")
	ui.open(); check(not player.world_strike(),"inventory allowed cutting"); ui.close()
	var wall:=StaticBody3D.new(); wall.position=Vector3(0,14,18); var wall_shape:=CollisionShape3D.new(); wall_shape.shape=BoxShape3D.new(); wall_shape.shape.size=Vector3(40,28,2); wall.add_child(wall_shape); host.add_child(wall)
	await frames(3); player.set("_next_world_strike_ms",0)
	check(not player.world_strike() and not state.flags.get(FLAG,false),"cut through wall")
	wall.queue_free(); await frames(3)
	state.combat_party_locked=true; check(not grass.receive_world_hit(player,Vector3.FORWARD),"combat cut grass"); state.combat_party_locked=false
	await shot("grass-before")
	var writes: Array[int]=[0]; var on_save:=func(_path):writes[0]+=1
	state.saved.connect(on_save)
	player.set("_next_world_strike_ms",0)
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; Input.parse_input_event(event)
	await process_frame; await frames(6)
	event=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; Input.parse_input_event(event)
	check(state.flags.get(FLAG,false) and not grass.get_node("PileVisual").visible and grass.get_node("CutStubble").visible,"native LMB did not leave cut stubble")
	check(pickup()!=null and pickup().visible and not pickup().freeze,"cut did not expose physical herb")
	check(writes[0]==1 and int(state.inventory.get("herb",0))==initial,"cut gave instant loot or duplicate save")
	check(not grass.receive_world_hit(player,Vector3.FORWARD) and writes[0]==1,"repeat cut duplicated reveal")
	check(player.get("_action_message").contains("Трава"),"grass used leaf/crate feedback")
	var effects:=get_nodes_in_group("ember_world_break_effects")
	check(effects.size()==1 and effects[0].get("_leaf_parts").size()==64 and effects[0].get_child_count()==4,"individual grass blades missing")
	check(effects[0].get_child(0).material_override.shader.has_meta("ember_feature_base"),"cut wisps miss existing compiled feature program")
	check(effects[0].lifetime<0.8 and effects[0].get("_leaf_floor").is_empty(),"grass wisps use slow ground-fragment motion")
	var first_blade: Transform3D=effects[0].get_child(0).multimesh.get_instance_transform(0)
	check(first_blade.origin.distance_to(effects[0].leaf_transforms[0].origin)>0.01,"grass blades did not drift in the wind")
	await shot("grass-cutting")
	await frames(22)
	var late_blade: Transform3D=effects[0].get_child(0).multimesh.get_instance_transform(0)
	var shrink: float=late_blade.basis.get_scale().length()/effects[0].leaf_transforms[0].basis.get_scale().length()
	check(shrink>0.0 and shrink<0.95,"grass blades popped out rather than fading near end")
	await shot("grass-wisps-late")
	state.saved.disconnect(on_save); check(state.save_slot(1),"cut save failed")
	await frames(80); check(get_nodes_in_group("ember_world_break_effects").is_empty(),"cut fragments leaked")
	await shot("grass-revealed")
	var center: Vector3=pickup().get_node("Pickup/Shape").global_position
	player.position=Vector3(center.x,0.1,center.z+5); player._try_interact(); await frames(3)
	check(pickup()==null and int(state.inventory.get("herb",0))==initial+1,"F did not collect one herb")
	check(state.save_slot(2),"collected save failed")
	await restore(0); check(grass.get_node("PileVisual").visible and not grass.get_node("CutStubble").visible and pickup()!=null and not pickup().visible,"uncut cold restore")
	await restore(1); check(not grass.get_node("PileVisual").visible and grass.get_node("CutStubble").visible and pickup()!=null and pickup().visible and not pickup().freeze,"cut cold restore")
	await restore(2); check(pickup()==null and grass.get_node("CutStubble").visible and int(state.inventory.get("herb",0))==initial+1,"collected cold restore duplicated herb")
	var authored: Node3D=load("res://prefabs/items/cuttable_grass.scn").instantiate()
	var source_scene:=PackedScene.new(); check(source_scene.pack(authored)==OK,"grass scene pack")
	check(ResourceSaver.save(source_scene,"user://cuttable-grass-roundtrip.scn")==OK,"grass scene save")
	authored.free()
	var reopened: Node3D=load("user://cuttable-grass-roundtrip.scn").instantiate()
	check(reopened.revealed_flag_id==reopened.get_node("HiddenPickup").available_flag_id and reopened.get_node("HiddenPickup").pickup_id==PICKUP,"scene reopen lost cover/pickup binding")
	check(reopened.collision_mask==0 and not reopened.monitoring,"scene reopen enabled trampling")
	check(absf(reopened.get_node("CutStubble").mesh.get_aabb().end.y-4.2)<0.001,"cut stubble no longer meets blade cut plane")
	var fragments: Node3D=reopened.scatter_effect.instantiate()
	var blade_count := 0
	for batch: MultiMeshInstance3D in fragments.get_children():
		blade_count += batch.multimesh.instance_count
		var bounds: AABB=batch.multimesh.mesh.get_aabb()
		check(batch.multimesh.mesh.surface_get_array_index_len(0)==9,"cut blade exceeds three triangles")
		check(bounds.size.y>maxf(bounds.size.x,bounds.size.z)*1.2,"grass wisps still contain wide clump cards")
	check(blade_count==64 and fragments.leaf_transforms.size()==64,"saved scatter lost individual blade poses")
	check(fragments.find_children("*","PhysicsBody3D",true,false).is_empty(),"cosmetic blades created physics bodies")
	fragments.free(); reopened.free()
	state.persistence_enabled=false; state.progress_changed.disconnect(host._refresh_world_items)
	ui.queue_free(); host.queue_free(); await process_frame; await process_frame
	print("PASS cuttable grass: walking/UI/wall/combat guards, native LMB/stubble/64 short blade wisps, one reveal, herb F, three cold saves, scene roundtrip and cleanup" if errors.is_empty() else "FAIL cuttable grass")
	quit(0 if errors.is_empty() else 1)
