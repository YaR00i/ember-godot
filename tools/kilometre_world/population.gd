extends Node3D
## Optional moving population for the kilometre field test. Physics and skin
## animation take their real game paths. No quest or combat state is written.
const Hoshi = preload("res://scripts/ember_hoshi_visual.gd")
const Boar = preload("res://prefabs/items/shore_boar_visual.tscn")
var active := false
var revision := 0

class Walker extends CharacterBody3D:
	var home: Vector3
	var phase: float
	var boar: Node3D
	var legs: Array[Node3D]=[]

	func _physics_process(dt: float) -> void:
		phase+=dt
		var destination:=home+Vector3(cos(phase*0.6),0,sin(phase*0.6))*1.8
		var desired:=destination-global_position
		desired.y=0
		desired=desired.limit_length(1.35)
		velocity.x=desired.x
		velocity.z=desired.z
		velocity.y=0.0 if is_on_floor() else velocity.y-9.8*dt
		move_and_slide()
		if boar!=null:
			boar.rotation.y=atan2(-velocity.x,-velocity.z)
			for i in legs.size():legs[i].rotation.x=sin(phase*6.+PI*(i%2))*0.25

func populate(world,enabled: bool) -> void:
	revision+=1
	var token:=revision
	active=enabled
	for body in get_children():
		remove_child(body)
		body.queue_free()
	if not enabled:return
	var camera: Camera3D=world.rig._cam
	var forward:=-camera.global_basis.z
	forward.y=0
	forward=forward.normalized()
	var right:=forward.cross(Vector3.UP)
	var origin: Vector3=world.actor.global_position
	if not await Hoshi.prepare_resources(self) or token!=revision:return
	for i in 12:
		var point:=origin+forward*(5.+3.*floori(i/4.))+right*((i%4-1.5)*3.)
		point.y=world.terrain.data.get_surface_height(point)
		if not is_finite(point.y) or point.y<float(world.spec.water_y)+0.25:continue
		var body:=Walker.new()
		body.home=point
		body.phase=i*0.76
		body.position=point+Vector3.UP*0.08
		body.collision_layer=0
		body.collision_mask=1|4
		var hit:=CollisionShape3D.new()
		var capsule:=CapsuleShape3D.new()
		capsule.height=1.10 if i>=8 else 1.55
		capsule.radius=0.28
		hit.shape=capsule
		hit.position.y=capsule.height*0.5
		body.add_child(hit)
		add_child(body)
		if i<8:
			var visual:=Hoshi.new()
			body.add_child(visual)
			if not visual.setup(body,1.0):push_error("QA NPC visual failed to initialize")
		else:
			body.boar=Boar.instantiate()
			body.add_child(body.boar)
			for key in ["LegFL","LegFR","LegBR","LegBL"]:body.legs.append(body.boar.get_node(key))
		await get_tree().process_frame
		if revision!=token:return

func follow(point: Vector3) -> void:
	for body: Walker in get_children():
		var near:=point.distance_squared_to(body.home)<50.*50.
		if near!=body.visible:
			body.visible=near
			body.process_mode=Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED
