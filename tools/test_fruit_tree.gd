extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const LeafGate=preload("res://tools/test_leaf_pile.gd")
const FLAG:="fruit_tree_apple_dropped"
const PICKUP:="fruit_tree_apple"
var host: Node3D
var state: EmberExploreState
var errors: Array[String]=[]
func _init() -> void:
	if not Fixture.prepare(self):quit(2);return
	_run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);push_error(message)
func frames(n: int) -> void:
	for i in n:await physics_frame
func pickup() -> Node3D:
	for node in get_nodes_in_group("ember_world_item_bodies"):
		if host.is_ancestor_of(node) and node.pickup_id==PICKUP and not node.is_queued_for_deletion():return node
	return null
func restore(slot: int) -> void:
	var loaded:=EmberExploreState.new();loaded.storage_root=state.storage_root
	check(loaded.load_slot(slot),"fruit cold load failed");state.adopt_loaded_save(loaded);loaded.free();await frames(5)
func shot(label: String) -> void:
	var output:=OS.get_environment("EMBER_FRUIT_CAPTURE_DIR")
	if output.is_empty():return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func _run() -> void:
	state=root.get_node("EmberExploreProgress");state.persistence_enabled=false;state.flags.clear();state.world_items.clear()
	host=LeafGate.Host.new();var map:=LeafGate.StubMap.new();map.name="Map";host.add_child(map)
	var canvas:=CanvasLayer.new();canvas.name="CanvasLayer";host.add_child(canvas);var hud:=Label.new();hud.name="Gate";canvas.add_child(hud)
	root.add_child(host);current_scene=host
	var floor_body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(480,2,480);shape.position.y=-1;floor_body.add_child(shape);host.add_child(floor_body)
	var tree: Area3D=load("res://prefabs/items/fruit_tree.scn").instantiate()
	tree.get_node("Tree/Mesh").set_instance_shader_parameter("tree_hit_sway",Vector4.ONE)
	host.add_child(tree)
	state.progress_changed.connect(host._refresh_world_items);host._refresh_world_items()
	var control: Node3D=load("res://prefabs/voxels/vox_painted_oak.tscn").instantiate();control.position.x=128;host.add_child(control)
	var mesh: MeshInstance3D=tree.get_node("Tree/Mesh");var control_mesh: MeshInstance3D=control.get_node("Mesh")
	var original_mesh:=mesh.mesh;var original_shape: Shape3D=tree.get_node("Tree/Collision/Shape").shape
	var leaf_material:=mesh.mesh.surface_get_material(1) as ShaderMaterial
	var player:=EmberPlayer.new();player.progress_state=state;player.position=Vector3(0,0.1,28);host.add_child(player);player.set_physics_process(false)
	var ui:=EmberInventoryUi.new();ui.progress_state=state;root.add_child(ui);player.inventory_ui=ui
	var camera:=Camera3D.new();host.add_child(camera);camera.position=Vector3(120,95,170);camera.look_at(Vector3(16,42,0));camera.current=true;camera.fov=43
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-30,0);sun.shadow_enabled=true;host.add_child(sun)
	var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color(0.52,0.65,0.75);world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=0.4;host.add_child(world)
	var floor_visual:=MeshInstance3D.new();floor_visual.mesh=BoxMesh.new();floor_visual.mesh.size=Vector3(480,2,480);floor_visual.position.y=-1;var paint:=StandardMaterial3D.new();paint.albedo_color=Color("657b43");floor_visual.material_override=paint;host.add_child(floor_visual)
	await frames(30)
	check(mesh.get_instance_shader_parameter("tree_hit_sway")==Vector4.ZERO,"saved cosmetic sway was not cleared at startup")
	check(mesh.get_property_list().any(func(property):return property.name=="instance_shader_parameters/tree_hit_sway"),"accepted tree does not expose crown sway")
	await process_frame;await RenderingServer.frame_post_draw
	var still_pixels: PackedByteArray=root.get_texture().get_image().get_data()
	tree.set("_direction",Vector2(0,1));tree.call("_shake_step",0.1)
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_data()!=still_pixels,"crown shader parameter had no rendered effect")
	tree.call("_finish_shake")
	var initial:=int(state.inventory.get("apple",0))
	check(pickup()!=null and not pickup().visible and pickup().freeze and tree.get_node("HangingFruit").visible,"fruit not hanging before strike")
	state.persistence_enabled=true;state.set_world_context("landscape_compact",player,16);check(state.save_slot(0),"hanging save failed")
	ui.open();check(not player.world_strike(),"inventory allowed tree hit");ui.close()
	var wall:=StaticBody3D.new();wall.position=Vector3(0,14,16);var wall_shape:=CollisionShape3D.new();wall_shape.shape=BoxShape3D.new();wall_shape.shape.size=Vector3(40,28,2);wall.add_child(wall_shape);host.add_child(wall)
	await frames(3);player.set("_next_world_strike_ms",0);check(not player.world_strike() and not state.flags.get(FLAG,false),"hit through wall dropped fruit")
	wall.queue_free();await frames(3)
	state.combat_party_locked=true;check(not tree.receive_world_hit(player,Vector3.FORWARD),"combat handoff dropped fruit");state.combat_party_locked=false
	await shot("tree-before")
	var writes: Array[int]=[0];var on_save:=func(_path):writes[0]+=1
	state.saved.connect(on_save);player.set("_next_world_strike_ms",0)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;Input.parse_input_event(event)
	await process_frame;await frames(6);event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(event)
	check(state.flags.get(FLAG,false) and not tree.get_node("HangingFruit").visible and pickup()!=null and pickup().visible and not pickup().freeze,"native tree strike did not release apple")
	check(writes[0]==1 and int(state.inventory.get("apple",0))==initial,"strike duplicated save or granted instant apple")
	check(pickup().get_node("BodyShape").shape is ConvexPolygonShape3D and pickup().physics_material_override!=null,"apple lost rounded physical profile")
	check(pickup().angular_velocity.length()>0.2 and Vector2(pickup().linear_velocity.x,pickup().linear_velocity.z).length()>0.5,"released apple had no physical spin/impulse")
	var sway: Variant=mesh.get_instance_shader_parameter("tree_hit_sway")
	check(sway is Vector4 and Vector2(sway.x,sway.y).length()>0.001,"crown did not sway")
	var other_sway: Variant=control_mesh.get_instance_shader_parameter("tree_hit_sway")
	check(other_sway==null or other_sway==Vector4.ZERO,"hit moved another tree")
	check(mesh.mesh==original_mesh and tree.get_node("Tree/Collision/Shape").shape==original_shape,"hit rebuilt tree or collision")
	await shot("tree-hit")
	var apple_id:=pickup().get_instance_id()
	var spin_before: Vector3=pickup().angular_velocity
	check(tree.receive_world_hit(player,Vector3.FORWARD) and writes[0]==1 and pickup().get_instance_id()==apple_id,"repeat tree hit duplicated fruit")
	check(pickup().angular_velocity==spin_before and not pickup().get("_release_pending"),"repeat hit kicked already fallen fruit")
	await frames(100)
	check(pickup()!=null and pickup().global_position.y<6.0,"apple stuck on branches instead of falling to ground")
	check(mesh.get_instance_shader_parameter("tree_hit_sway")==Vector4.ZERO,"crown did not settle")
	check(mesh.mesh==original_mesh and tree.get_node("Tree/Collision/Shape").shape==original_shape,"settling changed tree geometry")
	state.saved.disconnect(on_save);check(state.save_slot(1),"fallen save failed")
	await shot("tree-fallen")
	if not OS.get_environment("EMBER_FRUIT_CAPTURE_DIR").is_empty():
		var camera_pose:=camera.global_transform
		var model: MeshInstance3D=pickup().get_node("ItemVisual/Mesh")
		var target: Vector3=model.global_transform*model.mesh.get_aabb().get_center()
		camera.position=target+Vector3(8,5,10);camera.look_at(target);camera.fov=35
		await shot("apple-after-drop")
		camera.global_transform=camera_pose;camera.fov=43
	var center: Vector3=pickup().get_node("Pickup/Shape").global_position
	player.position=Vector3(center.x,0.1,center.z+5);player._try_interact();await frames(3)
	check(pickup()==null and int(state.inventory.get("apple",0))==initial+1,"F did not collect exactly one apple")
	check(state.save_slot(2),"collected save failed")
	await restore(0);check(tree.get_node("HangingFruit").visible and pickup()!=null and not pickup().visible and pickup().freeze,"hanging cold restore")
	await restore(1);check(not tree.get_node("HangingFruit").visible and pickup()!=null and pickup().visible,"fallen cold restore")
	await restore(2);check(not tree.get_node("HangingFruit").visible and pickup()==null and int(state.inventory.get("apple",0))==initial+1,"collected cold restore duplicated apple")
	check(tree.receive_world_hit(player,Vector3.FORWARD) and pickup()==null,"hit after collection regrew apple")
	var authored: Node3D=load("res://prefabs/items/fruit_tree.scn").instantiate();var packed:=PackedScene.new();packed.pack(authored);authored.free()
	check(ResourceSaver.save(packed,"user://fruit-tree-roundtrip.scn")==OK,"fruit tree scene save")
	var reopened: Node3D=load("user://fruit-tree-roundtrip.scn").instantiate()
	check(reopened.dropped_flag_id==reopened.get_node("ApplePickup").available_flag_id and reopened.get_node("ApplePickup").pickup_id==PICKUP,"fruit bindings lost on reopen");reopened.free()
	var icon: Dictionary=EmberItemCatalog.icon_definitions().get("apple",{})
	check(icon.get("rows",[]).size()==16 and icon.get("rows",[]).all(func(row):return row.length()==16),"apple inventory icon invalid")
	if not OS.get_environment("EMBER_FRUIT_CAPTURE_DIR").is_empty():
		var preview: Node3D=load("res://prefabs/items/apple.scn").instantiate();preview.position=Vector3(70,-0.25,30);preview.scale=Vector3.ONE*16;host.add_child(preview)
		camera.position=Vector3(75,6.5,40);camera.look_at(Vector3(70,2.2,30));camera.fov=35;await frames(3);await shot("apple-model")
	state.persistence_enabled=false;state.progress_changed.disconnect(host._refresh_world_items);ui.queue_free();host.queue_free();await process_frame;await process_frame
	print("PASS fruit tree: native strike/UI/wall/combat guards, instance crown sway/no remesh or shared-tree motion, falling apple/F, repeat guards, three cold saves, scene/icon roundtrip" if errors.is_empty() else "FAIL fruit tree")
	quit(0 if errors.is_empty() else 1)
