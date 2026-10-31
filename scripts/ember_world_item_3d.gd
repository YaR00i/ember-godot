extends RigidBody3D
## Physical presentation of one ExploreState.world_items record, never a save owner.

const Records = preload("res://scripts/ember_world_items.gd")
const Interact = preload("res://scripts/ember_world_item_interact.gd")
const PickupEffect = preload("res://scripts/ember_item_pickup_effect.gd")
const Presentation = preload("res://scripts/ember_item_presentation.gd")
@export var pickup_id := ""
@export var item_id := ""
@export var map_id := "landscape_compact"
@export var authored_pickup := true
@export var available_flag_id := ""
@export var carryable := false
@export var breakable := false
@export var break_effect: PackedScene
@export_range(1.0,200.0,1.0) var break_impact_speed := 36.0
@export_range(1,100,1) var throw_damage := 8
@export var pushable := false
@export_range(0.05, 1000.0, 0.05) var item_mass := 0.25
@export_range(1.0, 128.0, 1.0) var visual_size := 16.0
## Zero disables the quest tether. Distance is in world units from authored origin.
@export_range(0.0, 4096.0, 16.0) var return_radius := 0.0
@export var start_quest_id := ""
var _carrier: WeakRef
var progress_state: EmberExploreState
var display_name := "Предмет"
var _waiting_for_world := true
var _authored_transform := Transform3D.IDENTITY
var _release_pending := false
var combat_suspended := false
var _impact_queued := false
var _release_velocity := Vector3.ZERO
var _release_spin := Vector3.ZERO

func _ready() -> void:
	_authored_transform = global_transform
	freeze = true
	gravity_scale = 16.0
	mass = item_mass
	linear_damp = 1.0
	angular_damp = 2.0
	collision_layer = 4
	collision_mask = 1 | 4
	continuous_cd = true
	max_contacts_reported=8 if breakable else 0
	if progress_state == null: progress_state = get_node_or_null("/root/EmberExploreProgress")
	if progress_state == null or pickup_id.is_empty(): return
	var item := EmberItemCatalog.definition(item_id)
	display_name = str(item.get("nameRu",item_id))
	var path := str(item.get("worldScene",""))
	if path.is_empty(): return
	var packed := load(path) as PackedScene
	if packed == null: return
	var visual := get_node_or_null("ItemVisual") as Node3D
	if visual == null:
		visual = packed.instantiate() as Node3D
		visual.name = "ItemVisual"
		add_child(visual)
	visual.scale = Vector3.ONE * visual_size
	var bounds := AABB()
	var first := true
	var meshes := visual.find_children("*","MeshInstance3D",true,false)
	if visual is MeshInstance3D: meshes.append(visual)
	for mesh in meshes:
		if mesh.mesh == null: continue
		var box: AABB = (global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var collider := CollisionShape3D.new()
	collider.name = "BodyShape"
	var shape := BoxShape3D.new()
	shape.size = bounds.size.max(Vector3.ONE*0.3)
	collider.shape = shape
	collider.position = bounds.get_center()
	if visual is Presentation:
		var errors: Array[String]=visual.validation_errors()
		if errors.is_empty():
			linear_damp=visual.linear_damping; angular_damp=visual.angular_damping
			physics_material_override=visual.surface
			if visual.body_shape!=null:
				collider.shape=visual.scaled_body_shape(visual_size)
				collider.position=visual.body_center*visual_size
		else:push_warning("Invalid item presentation physics: "+str(errors))
	if has_node("BodyShape"): collider.free()
	else: add_child(collider)
	var interact := Interact.new()
	interact.kind = "custom"
	interact.name = "Pickup"
	var reach := CollisionShape3D.new()
	reach.name = "Shape"
	var sphere := SphereShape3D.new()
	sphere.radius = 4.0
	reach.shape = sphere
	reach.position = bounds.get_center()
	interact.add_child(reach)
	add_child(interact)
	add_to_group("ember_world_item_bodies")
	refresh_availability()
	var ancestor := get_parent()
	while ancestor != null:
		# WorldCanvas selects its save context after child _ready. Its existing
		# exploration setup registers authored items once that context is final.
		if authored_pickup and ancestor.has_method("_startup_status"): return
		ancestor = ancestor.get_parent()
	register_authored_item()
	restore_progress()

func register_authored_item() -> void:
	if authored_pickup: progress_state.ensure_authored_item(pickup_id,item_id,map_id,_authored_transform)

func placement_settings() -> Dictionary:
	return {"transform":_authored_transform,"availableFlagId":available_flag_id,"itemId":item_id,"carryable":carryable,"startQuestId":start_quest_id,"pushable":pushable,"itemMass":item_mass,"visualSize":visual_size,"returnRadius":return_radius,"breakable":breakable,"breakEffect":break_effect,"breakImpactSpeed":break_impact_speed,"throwDamage":throw_damage}

func restore_progress() -> void:
	if progress_state == null: return
	_release_pending=false
	_clear_carrier()
	if carryable:
		freeze = false
		collision_layer = 4
		collision_mask = 1 | 4
	var row: Dictionary = progress_state.world_items.get(pickup_id,{})
	if int(row.get("count",0)) <= 0:
		queue_free()
		return
	global_position = Records.vector(row.position)
	global_rotation = Records.vector(row.rotation)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if return_radius > 0.0 and global_position.distance_to(_authored_transform.origin) > return_radius:
		recover_from_void()

func capture_progress() -> void:
	if combat_suspended:return
	if progress_state == null or not progress_state.world_items.has(pickup_id): return
	var row: Dictionary = progress_state.world_items[pickup_id]
	if int(row.get("count",0)) <= 0: return
	row.position = Records.packed(global_position)
	row.rotation = Records.packed(global_rotation)

func is_item_available() -> bool:
	return available_flag_id.is_empty() or (progress_state != null and progress_state.flags.get(available_flag_id,false) == true)

func refresh_availability() -> void:
	if combat_suspended:return
	visible = is_item_available()
	collision_layer = 4 if visible and not is_carried() else 0
	if not visible: freeze = true
	elif not is_carried() and not _waiting_for_world: freeze = false
	if has_node("Pickup"): get_node("Pickup").refresh_runtime_binding()

func _physics_process(_delta: float) -> void:
	if combat_suspended:return
	if not is_item_available(): return
	if not _waiting_for_world and return_radius > 0.0 and global_position.distance_to(_authored_transform.origin) > return_radius:
		recover_from_void()
		return
	if is_carried():
		var actor := _carrier.get_ref() as Node3D
		global_position = actor.global_position + _carry_direction(actor) * 20.0 + Vector3.UP * 8.0
		capture_progress()
		return
	if _carrier != null:
		_clear_carrier()
		freeze = false
		collision_layer = 4
		collision_mask = 1 | 4
	if _waiting_for_world:
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("_startup_status") and not scene.get("_startup_complete"): return
		_waiting_for_world = false
		freeze = false
	if _release_pending and not freeze:
		_release_pending=false; sleeping=false
		apply_central_impulse(_release_velocity*mass)
		angular_velocity+=_release_spin
	if sleeping: capture_progress()

func queue_release_motion(velocity: Vector3,spin: Vector3) -> void:
	if not velocity.is_finite() or not spin.is_finite() or is_carried() or not is_item_available():return
	# Gated authored pickups thaw on their first available physics tick.
	_release_velocity=velocity; _release_spin=spin; _release_pending=true

func take(actor: Node3D = null) -> String:
	if combat_suspended:return "Предмет участвует в бою"
	if carryable:
		_release_pending=false
		return _toggle_carry(actor)
	if pushable: return "Этот ящик можно только толкать"
	if progress_state == null: return "Предмет недоступен"
	var result := progress_state.pickup_world_item(pickup_id)
	if not result.ok: return "Нет места в стопке" if result.reason == "stack_full" else "Предмет уже подобран"
	# Disable the prompt immediately, before deferred deletion or another F press.
	get_node("Pickup").remove_from_group("ember_interact")
	var visual := get_node_or_null("ItemVisual") as Node3D
	if is_instance_valid(actor) and visual != null:
		var effect := PickupEffect.new()
		effect.name = "ItemPickupEffect"
		get_tree().current_scene.add_child(effect)
		effect.play(visual,actor)
	queue_free()
	return "Получено: %s ×%d" % [result.nameRu,result.count]

func receive_world_hit(_actor: Node3D, direction: Vector3) -> bool:
	if not breakable or is_carried() or not is_item_available() or progress_state == null: return false
	var pose := global_transform
	if not progress_state.destroy_world_item(pickup_id): return false
	_clear_carrier()
	collision_layer = 0; collision_mask = 0; freeze = true
	visible = false
	if has_node("Pickup"): get_node("Pickup").remove_from_group("ember_interact")
	if break_effect != null:
		var effect := break_effect.instantiate() as Node3D
		get_tree().current_scene.add_child(effect)
		effect.play(pose, visual_size, direction)
	queue_free()
	return true

func push_from(direction: Vector3, speed: float) -> void:
	if not pushable or is_carried() or freeze or not is_item_available(): return
	var forward := Vector3(direction.x, 0, direction.z).normalized()
	if forward.is_zero_approx(): return
	# Sustained contact uses a force, not a frame-dependent repeated impulse.
	var along := linear_velocity.dot(forward)
	if along < speed: apply_central_force(forward * minf(500.0, (speed - along) * 20.0))

func throw_from(actor: Node3D) -> String:
	if actor == null or not carryable or not is_carried() or _carrier.get_ref() != actor:
		return "Сначала возьми ящик"
	var body_shape := get_node("BodyShape") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body_shape.shape
	query.transform = global_transform * body_shape.transform
	query.collision_mask = 1 | 4
	query.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	var wall := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 12.0, query.transform.origin, 1 | 4)
	wall.exclude = [get_rid()]
	if not space.intersect_ray(wall).is_empty() or not space.intersect_shape(query, 1).is_empty():
		return "Нет места для броска"
	var direction := _carry_direction(actor)
	_clear_carrier()
	collision_layer = 4
	collision_mask = 1 | 4
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	apply_central_impulse((direction * 64.0 + Vector3.UP * 32.0) * mass)
	capture_progress()
	progress_state.save_autosave()
	return "Брошено: " + display_name

func recover_from_void() -> void:
	if combat_suspended:return
	if progress_state == null or int(progress_state.world_items.get(pickup_id, {}).get("count", 0)) <= 0: return
	_release_pending=false
	_clear_carrier()
	global_transform = _authored_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = not is_item_available()
	collision_layer = 4 if is_item_available() else 0
	collision_mask = 1 | 4
	sleeping = false
	capture_progress()
	progress_state.save_autosave()

func is_carried() -> bool:
	return _carrier != null and is_instance_valid(_carrier.get_ref())

func _carry_direction(actor: Node3D) -> Vector3:
	return actor.interaction_forward() if actor.has_method("interaction_forward") else -actor.global_basis.z

func _clear_carrier() -> void:
	if is_carried():
		var actor := _carrier.get_ref() as Node3D
		if actor.has_meta("ember_carried_item"):
			var held: WeakRef = actor.get_meta("ember_carried_item")
			if held.get_ref() == self:
				actor.remove_meta("ember_carried_item")
	_carrier = null

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not breakable or combat_suspended or freeze or _impact_queued or progress_state==null or progress_state.combat_party_locked:return
	for i in state.get_contact_count():
		if state.get_contact_impulse(i).length()/maxf(mass,0.05)>=break_impact_speed:
			_impact_queued=true
			_break_on_impact.call_deferred(-state.get_contact_local_normal(i))
			break

func _break_on_impact(direction: Vector3) -> void:
	_impact_queued=false
	if not is_queued_for_deletion() and not combat_suspended:receive_world_hit(null,direction)

func suspend_for_combat() -> void:
	capture_progress()
	combat_suspended=true;_release_pending=false
	_clear_carrier();freeze=true;visible=false;collision_layer=0;collision_mask=0
	linear_velocity=Vector3.ZERO;angular_velocity=Vector3.ZERO
	if has_node("Pickup"):get_node("Pickup").remove_from_group("ember_interact")

func resume_after_combat(at: Vector3,carrier: Node3D=null) -> void:
	combat_suspended=false;_impact_queued=false
	global_position=at
	linear_velocity=Vector3.ZERO;angular_velocity=Vector3.ZERO
	if carrier!=null:
		_carrier=weakref(carrier);carrier.set_meta("ember_carried_item",weakref(self))
		freeze=true;visible=true;collision_layer=0;collision_mask=0
	else:refresh_availability()
	capture_progress()

func _toggle_carry(actor: Node3D) -> String:
	if actor == null or progress_state == null:
		return "Предмет недоступен"
	if int(progress_state.world_items.get(pickup_id, {}).get("count", 0)) <= 0:
		return "Предмет уже отсутствует в мире"
	if is_carried():
		if _carrier.get_ref() != actor:
			return "Предмет уже несут"
		var at := actor.global_position + _carry_direction(actor) * 24.0
		var space := get_world_3d().direct_space_state
		var wall := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 12.0, at + Vector3.UP * 12.0, 1)
		var floor_query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 40.0, at + Vector3.DOWN * 128.0, 1)
		var floor_hit := space.intersect_ray(floor_query)
		if not space.intersect_ray(wall).is_empty() or floor_hit.is_empty() or (floor_hit.normal as Vector3).y < 0.7:
			return "Здесь нет места для ящика"
		at.y = (floor_hit.position as Vector3).y + 0.15
		var body_shape := get_node("BodyShape") as CollisionShape3D
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body_shape.shape
		query.transform = Transform3D(Basis.IDENTITY, at) * body_shape.transform
		query.collision_mask = 1 | 4
		query.exclude = [get_rid()]
		query.margin = 0.01
		if not space.intersect_shape(query, 1).is_empty():
			return "Место занято"
		_clear_carrier()
		global_transform = Transform3D(Basis.IDENTITY, at)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		collision_layer = 4
		collision_mask = 1 | 4
		freeze = false
		sleeping = false
		capture_progress()
		progress_state.save_autosave()
		return "Поставлено: " + display_name
	if actor.has_meta("ember_carried_item"):
		var held: WeakRef = actor.get_meta("ember_carried_item")
		if is_instance_valid(held.get_ref()):
			return "Сначала поставьте предмет"
	_carrier = weakref(actor)
	actor.set_meta("ember_carried_item", weakref(self))
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if not start_quest_id.is_empty():
		var quest := EmberQuestCatalog.definition(start_quest_id)
		if EmberQuestCatalog.projection(quest, progress_state.flags).get("status", "") == "available":
			progress_state.apply_authored_flag(str(quest.get("statusFlagId", "")), "active")
	return "В руках: %s · F — поставить" % display_name

func _exit_tree() -> void:
	_clear_carrier()
