extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Item=preload("res://scripts/ember_world_item_3d.gd")
var errors: Array[String]=[]
var host: Node3D
var state: EmberExploreState
func _init() -> void:
	if not Fixture.prepare(self):quit(2);return
	_run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);push_error(message)
func frames(n: int) -> void:
	for i in n:await physics_frame
func ground(at: Vector3,size: Vector3,angle: float) -> void:
	var body:=StaticBody3D.new();body.position=at;body.rotation.z=deg_to_rad(angle)
	var collider:=CollisionShape3D.new();collider.shape=BoxShape3D.new();collider.shape.size=size;body.add_child(collider)
	var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.mesh.size=size
	var paint:=StandardMaterial3D.new();paint.albedo_color=Color("7a8662");mesh.material_override=paint;body.add_child(mesh);host.add_child(body)
func apple(id: String,at: Vector3) -> RigidBody3D:
	var body:=Item.new();body.item_id="apple";body.pickup_id=id;body.position=at;body.progress_state=state;host.add_child(body)
	return body
func _run() -> void:
	state=root.get_node("EmberExploreProgress");state.persistence_enabled=false;state.world_items.clear()
	host=Node3D.new();host.name="ItemPhysicsFixture";root.add_child(host);current_scene=host
	ground(Vector3(0,-1,0),Vector3(600,2,600),0)
	ground(Vector3(0,15,-60),Vector3(180,2,60),-14)
	ground(Vector3(0,15,60),Vector3(180,2,60),14)
	var right:=apple("slope_right",Vector3(0,30,-60))
	var left:=apple("slope_left",Vector3(0,30,60))
	var flat:=apple("flat_roll",Vector3(0,20,0));flat.queue_release_motion(Vector3(4,0,0),Vector3(0,0,-2))
	var bottle:=Item.new();bottle.item_id="shore_empty_bottle";bottle.pickup_id="legacy_bottle";bottle.position=Vector3(-80,8,0);bottle.progress_state=state;host.add_child(bottle)
	check(bottle.get_node("BodyShape").shape is BoxShape3D and bottle.linear_damp==1.0 and bottle.angular_damp==2.0,"legacy body defaults changed")
	check(right.get_node("BodyShape").shape is ConvexPolygonShape3D and right.physics_material_override.bounce>0.0,"round physical profile missing")
	check(right.get_node("BodyShape").shape==left.get_node("BodyShape").shape,"immutable item shapes were duplicated per body")
	var touched:=false;var bounced:=false;var spun:=false
	var ground_path:=0.0;var previous_center: Vector3=flat.get_node("BodyShape").global_position
	for i in 180:
		await physics_frame
		var current_center: Vector3=flat.get_node("BodyShape").global_position
		if current_center.y<2.8:touched=true
		if touched:ground_path+=Vector2(current_center.x-previous_center.x,current_center.z-previous_center.z).length()
		if touched and flat.linear_velocity.y>2.0:bounced=true
		if touched and flat.angular_velocity.length()>0.3:spun=true
		previous_center=current_center
	check(right.global_position.x>6.0 and left.global_position.x< -6.0,"apples did not roll down opposite slope directions")
	var flat_center: Vector3=flat.get_node("BodyShape").global_position
	check(ground_path>1.0 and ground_path<25.0 and bounced and spun,"flat apple did not bounce/roll naturally")
	print("PHYSICS at3s right=",right.global_position," left=",left.global_position," flat=",flat.global_position," bounce=",bounced)
	print("PHYSICS flat centre=",flat_center," post-contact path=",ground_path)
	await frames(540)
	print("PHYSICS at12s flat=",flat.global_position," velocity=",flat.linear_velocity," spin=",flat.angular_velocity," sleeping=",flat.sleeping)
	check(flat.sleeping or (flat.linear_velocity.length()<0.2 and flat.angular_velocity.length()<0.2),"flat apple did not settle")
	var presentation: Node3D=load("res://prefabs/items/apple.scn").instantiate()
	check(presentation.validation_errors().is_empty(),"apple physical profile invalid")
	var packed:=PackedScene.new();packed.pack(presentation)
	check(ResourceSaver.save(packed,"user://apple-physics-roundtrip.scn")==OK,"physics presentation save failed")
	var reopened: Node3D=load("user://apple-physics-roundtrip.scn").instantiate()
	check(reopened.body_shape is ConvexPolygonShape3D and reopened.body_center==presentation.body_center and reopened.surface.bounce==presentation.surface.bounce and reopened.angular_damping==presentation.angular_damping,"physical profile did not survive scene reopen")
	presentation.body_shape=ConcavePolygonShape3D.new();check(not presentation.validation_errors().is_empty(),"dynamic concave item shape accepted")
	presentation.body_shape=ConvexPolygonShape3D.new();check(not presentation.validation_errors().is_empty(),"empty item hull accepted")
	presentation.body_shape=null;presentation.linear_damping=NAN;check(not presentation.validation_errors().is_empty(),"nonfinite damping accepted")
	presentation.free();reopened.free()
	var loaded:=EmberExploreState.new();loaded.storage_root=state.storage_root
	state.persistence_enabled=true;state.set_world_context("landscape_compact",null,16);check(state.save_slot(0) and loaded.load_slot(0),"physical pose save failed")
	flat.queue_release_motion(Vector3(20,0,0),Vector3.ONE*5)
	state.adopt_loaded_save(loaded);loaded.free();flat.restore_progress();await frames(3)
	check(not flat.get("_release_pending") and flat.get_node("BodyShape").shape is ConvexPolygonShape3D,"load retained stale release impulse or lost collider")
	state.persistence_enabled=false;host.queue_free();await process_frame;await process_frame
	print("PASS world item physics: rounded data profile, opposite slopes, bounce/spin/settle, legacy box defaults, shared shape, validation, scene reopen and saved pose/no stale impulse" if errors.is_empty() else "FAIL world item physics")
	quit(0 if errors.is_empty() else 1)
