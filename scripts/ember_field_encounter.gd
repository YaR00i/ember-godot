extends Node3D
## Presentation host for the existing combat shell. The world keeps its floor;
## CombatTransition and ExploreState retain all results, loot and saves.

@export var encounter_id := "shore_boar"
@export var field_corner := Vector3(-304, 12, 256)
@export var unit_visual_scenes: Dictionary = {}

var battle: Node3D
var _held: Array[Dictionary] = []
var _camera: Camera3D
var _initiative := "player"
var last_error := ""
var presentation_complete := false
var _entry_layer: CanvasLayer
var _entry_cover: ColorRect
var _world_actors: Dictionary = {}
var _bindings_ready := false
var _entry_running := false
var _entry_camera: Camera3D
var _camera_from := Transform3D.IDENTITY
var _camera_fov_from := 45.0
var _entry_weight := 0.0
var _arena: EmberCombatGrid3DWorld
var _hud: Control
var _combat_scene: PackedScene
var _world_items: Dictionary={}
var _item_return: Dictionary={}

func _ready() -> void:
	# Load the existing shell during world preparation, before first contact.
	_combat_scene = load(EmberCombatTransition.COMBAT_SCENE) as PackedScene

static func with_initiative(state: Dictionary, advantage: String) -> Dictionary:
	var result := state.duplicate(true)
	var delayed_team := "hero" if advantage == "enemy" else "enemy"
	var delay := 40.0 if advantage == "rear" else 20.0
	for unit in result.get("units", {}).values():
		if str(unit.get("team", "")) == delayed_team:
			unit["nextAt"] = float(unit.get("nextAt", 0.0)) + delay
	result.log.append({"enemy":"Кабан напал первым: преимущество противника.", "rear":"Удар со спины: двойное преимущество группы.", "player":"Первый удар: преимущество группы."}.get(advantage, "Первый удар: преимущество группы."))
	return result

func engage(advantage := "player") -> Error:
	_initiative = advantage
	return EmberCombatTransition.change_scene(get_tree(), encounter_id, _progress(), self)

func _progress() -> EmberExploreState:
	return get_node_or_null("/root/EmberExploreProgress") as EmberExploreState

func begin_in_place(encounter: EmberEncounterResource) -> Error:
	var world := get_tree().current_scene
	if world == null or not world.get("_player") is EmberPlayer or battle != null:
		return ERR_UNAVAILABLE
	var heights: Array[float] = []
	for z in encounter.battlefield.height:
		for x in encounter.battlefield.width:
			var at := field_corner + Vector3(x*16+8, 0, z*16+8)
			var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*48, at-Vector3.UP*48, 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or hit.normal.dot(Vector3.UP) < 0.98:
				last_error = "На участке боя нет ровной опоры."
				return ERR_INVALID_DATA
			heights.append(hit.position.y)
	if heights.max() - heights.min() > 2.0:
		last_error = "Участок боя изменился: нужна ровная площадка."
		return ERR_INVALID_DATA
	var ground: float = (heights.max() + heights.min()) * 0.5
	_camera = get_viewport().get_camera_3d()
	_world_actors = world.get("_party_followers").combat_world_actors()
	var leader := world.get("_player") as EmberPlayer
	_world_actors[leader.controlled_hero_id] = leader
	for enemy in get_tree().get_nodes_in_group("ember_field_enemies"):
		if not is_ancestor_of(enemy): continue
		var unit_id := str(enemy.get("combat_unit_id"))
		if not unit_id.is_empty() and unit_id != "<null>": _world_actors[unit_id] = enemy
	var roster := Array(encounter.party_unit_ids) + Array(encounter.enemy_unit_ids)
	for unit_id in _world_actors.keys():
		if unit_id not in roster and unit_id not in encounter.enemy_instances().map(func(entry):return entry.id): _world_actors.erase(unit_id)
	var item_snapshot:=_capture_world_items(encounter)
	var held_nodes: Array = [world.get("_player"), world.get("_party_followers"), world.get_node_or_null("CanvasLayer"), world.get("_player").camera_rig]
	held_nodes.append_array(get_tree().get_nodes_in_group("ember_field_enemies"))
	for node in held_nodes:
		if not is_instance_valid(node): continue
		_held.append({"node":node, "mode":node.process_mode, "visible":node.get("visible")})
		node.process_mode = Node.PROCESS_MODE_DISABLED
	battle = _combat_scene.instantiate() as Node3D
	battle.name = "WorldBattle"
	battle.process_mode = Node.PROCESS_MODE_ALWAYS
	var hud := battle.get_node("CombatHUDLayer/CombatHUD")
	_hud = hud
	hud.request_fullscreen = false
	hud.entry_transition_active = true
	var scale_factor := 16.0 / 1.2
	var label_offsets := {}
	for unit_id in _world_actors:
		var actor: Node3D = _world_actors[unit_id]
		var label := actor.get_node_or_null("Status") as Node3D
		if label == null: label = actor.get_node_or_null("Prompt") as Node3D
		if label != null: label_offsets[unit_id] = label.position.y/scale_factor-0.36
	hud.in_place_context = {"initiative":_initiative, "unitVisuals":unit_visual_scenes,
		"worldItems":item_snapshot,
		"continuousEntry":true,"worldActorIds":_world_actors.keys(),"labelOffsets":label_offsets,
		"transform":Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_factor),Vector3(field_corner.x,ground-0.32*scale_factor,field_corner.z))}
	for path in ["Arena/WorldEnvironment", "Arena/CombatKeyLight"]:
		var node := battle.get_node_or_null(path)
		if node != null: node.free()
	(battle.get_node("Arena/CameraRig/CombatCamera3D") as Camera3D).current = false
	presentation_complete = false
	_entry_layer = CanvasLayer.new()
	_entry_layer.layer = 100
	_entry_layer.name = "BattleEntryTransition"
	add_child(_entry_layer)
	_entry_cover = ColorRect.new()
	# Transparent input shield only. The world stays visible during the hops.
	_entry_cover.color = Color(0,0,0,0)
	_entry_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_entry_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_entry_layer.add_child(_entry_cover)
	_camera_from = _camera.global_transform
	_camera_fov_from = _camera.fov
	_entry_camera = Camera3D.new()
	_entry_camera.name = "BattleEntryCamera"
	_entry_camera.fov = _camera.fov
	_entry_camera.near = _camera.near
	_entry_camera.far = _camera.far
	_entry_camera.cull_mask = _camera.cull_mask
	add_child(_entry_camera)
	_entry_camera.global_transform = _camera_from
	_entry_camera.make_current()
	_entry_running = true
	process_priority = 100
	hud.presentation_ready.connect(_jump_to_formation, CONNECT_ONE_SHOT)
	_install_visible_battle.call_deferred()
	return OK

func _install_visible_battle() -> void:
	for entry in _held:
		if is_instance_valid(entry.node) and entry.node is CanvasLayer: entry.node.visible = false
	battle.get_node("CombatHUDLayer").visible = false
	get_tree().current_scene.add_child(battle)

func _jump_to_formation() -> void:
	_arena = battle.get_node("Arena") as EmberCombatGrid3DWorld
	for unit_id in _world_actors:
		var actor: Node3D = _world_actors[unit_id]
		for path in ["Status","Prompt"]:
			var label := actor.get_node_or_null(path) as Node3D
			if label != null:
				_held.append({"node":label,"mode":label.process_mode,"visible":label.visible})
				label.hide()
	_entry_weight = 0
	_impact_ring(get_tree().current_scene.get("_player").global_position)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self,"_entry_weight",1.0,0.85)
	var index := 0
	for unit_id in _world_actors:
		var actor := _world_actors[unit_id] as Node3D
		var projected := _arena._unit_roots.get(unit_id) as Node3D
		if projected == null: continue
		var destination := projected.to_global(Vector3(0,-0.36,0))
		var local_destination: Vector3 = actor.get_parent().to_local(destination)
		# Reuse the renderer's existing arc math, with a host-bound Tween so
		# frozen exploration controllers cannot pause their presentation.
		tween.tween_method(_arena._set_arc_position.bind(actor,actor.position,local_destination,8.0),0.0,1.0,0.58).set_delay(0.06+index*0.025)
		index += 1
	await tween.finished
	_entry_running = false
	_bindings_ready = true
	_sync_world_actors()
	_arena.get_node("CameraRig/CombatCamera3D").make_current()
	_entry_camera.queue_free()
	for actor in _world_actors.values():
		if actor.visible: _impact_ring(actor.global_position)
	battle.get_node("CombatHUDLayer").visible = true
	if is_instance_valid(_entry_layer): _entry_layer.queue_free()
	_hud.finish_world_entry()
	presentation_complete = true

func _process(_dt: float) -> void:
	if _entry_running and is_instance_valid(_entry_camera):
		if is_instance_valid(_arena):
			var camera := _arena.get_node("CameraRig/CombatCamera3D") as Camera3D
			var rotation := _camera_from.basis.orthonormalized().get_rotation_quaternion().slerp(camera.global_basis.orthonormalized().get_rotation_quaternion(),_entry_weight)
			_entry_camera.global_transform = Transform3D(Basis(rotation),_camera_from.origin.lerp(camera.global_position,_entry_weight))
			_entry_camera.fov = lerpf(_camera_fov_from,camera.fov,_entry_weight)
		_entry_camera.make_current()
	elif _bindings_ready: _sync_world_actors()

func _sync_world_actors() -> void:
	if not is_instance_valid(_arena): return
	for unit_id in _world_actors:
		var actor := _world_actors[unit_id] as Node3D
		if not is_instance_valid(actor): continue
		var projected := _arena._unit_roots.get(unit_id) as Node3D
		actor.visible = projected != null
		if projected != null: actor.global_position = projected.to_global(Vector3(0,-0.36,0))

func _impact_ring(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 4.6
	mesh.outer_radius = 5.0
	mesh.rings = 24
	mesh.ring_segments = 6
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1,0.9,0.64,0.7)
	ring.material_override = material
	add_child(ring)
	ring.global_position = at + Vector3.UP*0.3
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring,"scale",Vector3(2.2,0.1,2.2),0.25)
	tween.tween_property(material,"albedo_color:a",0.0,0.25)
	tween.chain().tween_callback(ring.queue_free)

func prepare_return(combat_state: Dictionary) -> void:
	var world := get_tree().current_scene
	var player := world.get("_player") as EmberPlayer
	var unit: Dictionary = combat_state.get("units", {}).get(player.controlled_hero_id, {})
	if unit.is_empty(): return
	var arena := battle.get_node("Arena") as EmberCombatGrid3DWorld
	player.global_position = arena.to_global(arena._world_position(unit.get("cell",Vector2i.ZERO),0.06)) + Vector3.UP*0.1
	player.velocity = Vector3.ZERO
	_item_return.clear()
	for id in _world_items:
		var item: Dictionary=combat_state.get("units",{}).get(id,{})
		if item.is_empty():continue
		var carrier:=preload("res://scripts/prototypes/ember_combat_prototype.gd").carrier_id_for(combat_state,id)
		var at: Vector3=_world_items[id].position
		if not carrier.is_empty() and _world_actors.has(carrier):at=_world_actors[carrier].global_position
		elif item.has("cell"):at=arena.to_global(arena._world_position(item.cell,0.06))
		item["worldItemPosition"]=[at.x,at.y,at.z]
		_item_return[id]={"position":at,"carrier":carrier}

func finish_in_place() -> void:
	_bindings_ready = false
	_arena = null
	if is_instance_valid(battle): battle.queue_free()
	battle = null
	for entry in _held:
		if not is_instance_valid(entry.node): continue
		entry.node.process_mode = entry.mode
		if entry.node is Node3D or entry.node is CanvasLayer: entry.node.visible = entry.visible
	_held.clear()
	for id in _world_items:
		var entry: Dictionary=_world_items[id]
		var body: Node3D=entry.body
		if not is_instance_valid(body) or body.is_queued_for_deletion():continue
		if int(_progress().world_items.get(body.pickup_id,{}).get("count",0))<=0:continue
		var returned: Dictionary=_item_return.get(id,{"position":entry.position,"carrier":entry.carrier})
		body.resume_after_combat(returned.position,_world_actors.get(returned.carrier) as Node3D)
	_world_items.clear();_item_return.clear()
	if is_instance_valid(_camera): _camera.make_current()
	var world := get_tree().current_scene
	if world.has_method("_resume_combat_return_action"): world._resume_combat_return_action()

func _capture_world_items(encounter: EmberEncounterResource) -> Dictionary:
	var snapshot:={"units":{},"holds":{}}
	var initial:=encounter.initial_state({},1,_progress().active_hero_ids)
	var occupied: Array=[]
	for unit: Dictionary in initial.units.values():occupied.append(unit.get("cell",Vector2i(-1,-1)))
	for body in get_tree().get_nodes_in_group("ember_world_item_bodies"):
		# First bridge covers carryable single-cell loads. Push-only scenery keeps
		# its authored Battlefield semantics until the separate push/plate slice.
		if body.is_queued_for_deletion() or body.progress_state!=_progress() or not body.is_item_available() or not body.carryable or body.visual_size>16.0:continue
		if int(_progress().world_items.get(body.pickup_id,{}).get("count",0))<=0:continue
		var carrier:=""
		if body.is_carried():
			var actor: Node3D=body.get("_carrier").get_ref()
			for actor_id in _world_actors:
				if _world_actors[actor_id]==actor:carrier=actor_id;break
		var local: Vector3=(body.global_position-field_corner)/16.0
		var cell:=Vector2i(floori(local.x),floori(local.z))
		if carrier.is_empty() and (cell.x<0 or cell.y<0 or cell.x>=encounter.battlefield.width or cell.y>=encounter.battlefield.height or cell in occupied):continue
		var value:=preload("res://scripts/ember_combat_world_items.gd").unit(body,cell)
		var id: String=value.id
		snapshot.units[id]=value
		if not carrier.is_empty():snapshot.holds[carrier]=id
		else:occupied.append(cell)
		_world_items[id]={"body":body,"position":body.global_position,"carrier":carrier}
		body.suspend_for_combat()
	return snapshot
