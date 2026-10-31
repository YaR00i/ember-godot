@tool
extends Node3D
## Single boolean circuit owner. Scene nodes store bindings, flags store lever positions.
@export var circuit_id := ""
@export var links: Array[Dictionary] = []
var progress_state: EmberExploreState
var values: Dictionary = {}
var diagnostics: Array[String] = []
var timer_remaining: Dictionary = {}
var _components: Array[Node] = []
var _document: Dictionary = {}
var _frames := 0
const Model = preload("res://scripts/ember_mechanism_graph.gd")
const Component = preload("res://scripts/ember_mechanism_component.gd")
const Geometry = preload("res://scripts/ember_mechanism_role_geometry.gd")
func components() -> Array[Node]:
	var result: Array[Node] = []
	for child in get_children():
		if child.get_script() == Component: result.append(child)
	return result
func component(id: String) -> Node:
	for child in components():
		if child.component_id == id: return child
	return null
func snapshot() -> Dictionary:
	var nodes: Array[Dictionary] = []
	for child in components():
		var row := {"id": child.component_id, "kind": child.kind, "label": child.label, "target": "", "crate": "", "clearance": "", "position": child.get_meta("graph_position", Vector2.ZERO), "offset": child.open_offset, "seconds": child.move_seconds, "settle": child.settle_seconds}
		for pair in [["target", child.target_path], ["crate", child.crate_path], ["clearance", child.clearance_path]]:
			var target: Node = child.binding(pair[1])
			row[pair[0]] = str(get_path_to(target)) if target else (str(child.name).path_join(str(pair[1])).simplify_path() if not pair[1].is_empty() else "")
		row["hold_seconds"] = child.hold_seconds
		row["required_weight"] = child.required_weight
		row["character_weight"] = child.character_weight
		if child.has_meta("mechanism_world_position"): row["world_position"] = child.get_meta("mechanism_world_position")
		nodes.append(row)
	return {"nodes": nodes, "links": links.duplicate(true)}
func binding_scene() -> Node:
	if owner != null: return owner
	var scene: Node = self
	while scene.get_parent() != null and (not is_inside_tree() or scene.get_parent() != get_tree().root): scene = scene.get_parent()
	return scene
func owns_target(target: Node) -> bool:
	if target == null or target == self: return false
	var scene := binding_scene()
	if target == scene or not scene.is_ancestor_of(target): return false
	var parent := target.get_parent()
	while parent != null and parent != scene:
		if parent != self and parent.has_method("toggle_lever"): return false
		parent = parent.get_parent()
	return not target.has_method("toggle_lever")
func document_errors(document: Dictionary) -> Array[String]:
	var result := Model.errors(document)
	if not circuit_id.is_empty() and is_inside_tree():
		var scene: Node = self
		while scene.get_parent() != null and scene.get_parent() != get_tree().root: scene = scene.get_parent()
		for other in scene.find_children("*", "Node3D", true, false):
			if other != self and other.has_method("toggle_lever") and str(other.get("circuit_id")) == circuit_id:
				result.append("У наборов одинаковый ID. Удали ручную копию и создай независимый набор кнопкой редактора.")
				break
	var writers := {}
	for row in document.get("nodes", []):
		var kind := str(row.get("kind", ""))
		var path := str(row.get("target", ""))
		var target := get_node_or_null(NodePath(path)) if not path.is_empty() else null
		if kind == "plate":
			var shape := target.get_node_or_null("Shape") as CollisionShape3D if target is Area3D else null
			if shape == null or not shape.shape is BoxShape3D: result.append("Для плиты выбери Area3D с BoxShape3D в дочернем Shape.")
		if kind == "plate":
			var crate_path := str(row.get("crate", ""))
			var crate := get_node_or_null(NodePath(crate_path)) if not crate_path.is_empty() else null
			if not crate_path.is_empty() and (not crate is RigidBody3D or crate.get("pickup_id") == null): result.append("Для выбранного ящика нужен переносной world-item объект.")
		if kind == "lever" and not target is Node3D: result.append("Выбери объект рычага на карте.")
		if kind == "lamp" and not (target is MeshInstance3D or target is Light3D): result.append("Для лампы выбери меш или источник света.")
		if kind == "door":
			var helper := Geometry.helper_for(target, str(row.id)) if target is Node3D else null
			if not target is AnimatableBody3D and (helper == null or not helper.get_node_or_null("Body") is AnimatableBody3D): result.append("Двери нужно AnimatableBody3D или автоматически созданное тело.")
			var clear_path := str(row.get("clearance", ""))
			var clearance := get_node_or_null(NodePath(clear_path)) as Area3D if not clear_path.is_empty() else null
			var shape := clearance.get_node_or_null("Shape") as CollisionShape3D if clearance else null
			if shape == null or not shape.shape is BoxShape3D: result.append("Для двери нужна зона безопасности с BoxShape3D в дочернем Shape.")
			if clearance != null and clearance.get_parent().has_meta("mechanism_role_id") and clearance.get_parent().get_parent() != target:
				result.append("Для смены объекта автоматической двери сними роль и назначь её заново.")
		if target is Node3D: target = Geometry.object_for(target)
		if kind in ["door", "lamp", "lever", "plate"] and target != null and not owns_target(target): result.append("Выбери объект этой сцены, вне другого набора механизма.")
		if kind in ["door", "lamp", "lever", "plate"] and target != null and is_inside_tree():
			for other in binding_scene().find_children("*", "Node3D", true, false):
				if other == self or not other.has_method("snapshot") or not other.has_method("toggle_lever"): continue
				for existing in other.snapshot().nodes:
					if str(existing.get("target", "")).is_empty(): continue
					if Geometry.object_for(other.get_node_or_null(NodePath(str(existing.target))) as Node3D) == target:
						result.append("Этот объект уже имеет роль в другом механизме.")
						break
		if kind in ["door", "lamp", "lever", "plate"] and not path.is_empty():
			var key = target.get_instance_id() if target != null else path
			if writers.has(key): result.append("Один объект нельзя назначить двум компонентам одновременно.")
			writers[key] = true
	return result
func _ready() -> void:
	set_physics_process(not Engine.is_editor_hint())
	if Engine.is_editor_hint(): return
	if progress_state == null: progress_state = get_node_or_null("/root/EmberExploreProgress")
	rebuild()
func release_runtime() -> void:
	for child in _components:
		if is_instance_valid(child): child.release()
	_components.clear()
func rebuild() -> void:
	release_runtime()
	timer_remaining.clear()
	_components = components()
	_document = snapshot()
	diagnostics = document_errors(_document)
	_frames = 0
	for child in _components: child.prepare()
func _exit_tree() -> void:
	if not Engine.is_editor_hint(): release_runtime()
	request_ready()
func _physics_process(delta: float) -> void:
	if progress_state != null and progress_state.restore_enabled and progress_state.has_pending_spawn_restore():
		_frames = 0
		return # Never arm persistent memory from an outgoing/not-yet-restored world.
	_frames += 1
	if _frames < 3: return
	for child in _components:
		if is_instance_valid(child) and child.kind in ["plate", "lever", "door", "lamp"] and not is_instance_valid(child._target):
			diagnostics = ["Объект компонента исчез. Перепривяжи объект или загрузи набор заново."]
	for child in _components:
		if is_instance_valid(child) and child.kind == "plate" and not child.crate_path.is_empty() and child.binding(child.crate_path) == null:
			diagnostics = ["Ящик плиты исчез. Перепривяжи объект или загрузи набор заново."]
	var inputs := {}
	var memory := {}
	for child in _components:
		if not is_instance_valid(child): continue
		inputs[child.component_id] = child.sense(delta, progress_state, circuit_id)
		if child.kind == "latch":
			if progress_state == null: diagnostics = ["Недоступно состояние сохранения фиксации сигнала."]
			else: memory[child.component_id] = bool(progress_state.flags.get(latch_flag_key(child.component_id), false))
	var next := Model.advance(_document, inputs, timer_remaining, delta, memory) if diagnostics.is_empty() else {"values": {}, "timers": {}, "latches": {}}
	values = next.values; timer_remaining = next.timers
	var updates := {}
	for id in next.latches:
		if bool(memory.get(id, false)) != bool(next.latches[id]): updates[latch_flag_key(str(id))] = bool(next.latches[id])
	if not updates.is_empty() and progress_state != null: progress_state.set_flags_batch(updates)
	for child in _components:
		if is_instance_valid(child): child.apply(bool(values.get(child.component_id, false)), delta)
func latch_flag_key(id: String) -> String:
	return "mechanism_latch_%s_%s" % [circuit_id, id]

func toggle_lever(id: String) -> String:
	var child := component(id)
	if child == null or child.kind != "lever" or progress_state == null or circuit_id.is_empty() or not diagnostics.is_empty(): return "Рычаг недоступен"
	var key := "mechanism_%s_%s" % [circuit_id, id]
	progress_state.set_flag(key, not bool(progress_state.flags.get(key, false)))
	return "Рычаг включён" if progress_state.flags[key] else "Рычаг выключен"
func status() -> String:
	if not diagnostics.is_empty(): return diagnostics[0]
	for child in _components:
		if child.kind == "door" and child.blocked and not child.value: return "Проход занят · дверь ждёт"
	var parts: Array[String] = []
	for child in _components:
		if child.kind == "door": parts.append(child.label + ": " + ("открыта" if child.openness > 0.99 else "закрыта" if child.openness < 0.01 else "движется"))
		elif child.kind == "lamp": parts.append(child.label + ": " + ("включена" if child.value else "выключена"))
		elif child.kind == "latch": parts.append(child.label + ": " + ("зафиксирован" if child.value else "сброшен"))
		elif child.kind == "hold" and float(timer_remaining.get(child.component_id, 0.0)) > 0:
			parts.append(child.label + ": %.1fс" % float(timer_remaining[child.component_id]))
	return " · ".join(parts)
# Compatibility accessors for the first playable trial and its checks.
var pressed: bool:
	get: return bool(values.get("plate", false))
var blocked: bool:
	get: return component("door").blocked if component("door") else false
var openness: float:
	get: return component("door").openness if component("door") else 0.0
var _closed: Vector3:
	get: return component("door")._closed if component("door") else Vector3.ZERO

static func make_component(row: Dictionary) -> Node:
	var child := Component.new()
	child.name = "Component_" + str(row.id)
	child.component_id = str(row.id)
	child.label = str(row.label)
	child.kind = str(row.kind)
	for pair in [["target_path", "target"], ["crate_path", "crate"], ["clearance_path", "clearance"]]:
		var path := str(row.get(pair[1], ""))
		child.set(pair[0], NodePath("../" + path) if not path.is_empty() else NodePath(""))
	child.open_offset = row.get("offset", Vector3(0, 40, 0))
	child.move_seconds = float(row.get("seconds", 0.6))
	child.settle_seconds = float(row.get("settle", 0.35))
	child.hold_seconds = float(row.get("hold_seconds", 3.0))
	child.required_weight = float(row.get("required_weight", 0.0))
	child.character_weight = float(row.get("character_weight", 1.0))
	child.set_meta("graph_position", row.get("position", Vector2.ZERO))
	if row.has("world_position"): child.set_meta("mechanism_world_position", row.world_position)
	return child
