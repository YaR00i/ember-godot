extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Model = preload("res://scripts/ember_mechanism_graph.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const Workshop = preload("res://addons/ember_import/ember_mechanism_workspace.gd")
const Circuit = preload("res://scripts/ember_mechanism_circuit.gd")
const Legacy = preload("res://scripts/ember_pressure_gate.gd")
const WorldWires = preload("res://addons/ember_import/ember_mechanism_world_wires.gd")
const MechanismInspector = preload("res://addons/ember_import/ember_mechanism_inspector.gd")
func _initialize() -> void:
	if not Fixture.prepare(self): quit(2); return
	_run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func _run() -> void:
	root.size = Vector2i(1280, 800)
	await process_frame
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false
	state.reset_new_game()
	state.world_items.clear()
	state.inventory.clear()
	var scene := Node3D.new()
	scene.name = "CircuitFixture"
	root.add_child(scene)
	current_scene = scene
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	var kit := actions.create_pressure_gate(scene, Vector3.ZERO, true)
	assert(kit != null and kit.get_script() == Circuit)
	var copy := actions.create_pressure_gate(scene, Vector3(350, 0, 0), true)
	assert(copy.circuit_id != kit.circuit_id)
	copy.circuit_id = kit.circuit_id
	copy.rebuild()
	assert(not copy.diagnostics.is_empty() and copy.toggle_lever("lever_a") == "Рычаг недоступен")
	for body in copy.get_children():
		if body is RigidBody3D: state.world_items.erase(str(body.get("pickup_id")))
	history.undo()
	history.clear_history()
	if is_instance_valid(copy): copy.free()
	var original: Dictionary = kit.snapshot()
	assert(original.nodes.size() == 8 and original.links.size() == 6 and kit.document_errors(original).is_empty())
	# The 3D view uses actual projected sockets and the same scene commands/history.
	var wires := WorldWires.new(); root.add_child(wires)
	wires.setup(actions, Callable(), Callable()); wires.set_scene(scene)
	wires._toggle.button_pressed = true
	var camera := Camera3D.new(); scene.add_child(camera)
	camera.position = Vector3(210, 180, 270); camera.look_at(Vector3(0, 15, 0))
	var sockets: Array[Dictionary] = wires.ports(camera)
	assert(sockets.size() == 12)
	var lamp_socket := {}; var output_socket := {}
	for socket in sockets:
		assert(wires._hit(sockets, socket.at).id == socket.id)
		if socket.id == "lamp": lamp_socket = socket
		if socket.id == "either" and socket.output: output_socket = socket
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	click.position = lamp_socket.at; click.shift_pressed = true
	assert(wires.forward_input(camera, click) == EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert(kit.links.size() == 5)
	history.undo(); assert(kit.links.size() == 6)
	history.redo(); assert(kit.links.size() == 5)
	click.shift_pressed = false; click.position = output_socket.at; wires.forward_input(camera, click)
	click.position = lamp_socket.at; wires.forward_input(camera, click)
	assert(kit.links.size() == 6)
	wires.use_port(output_socket); wires.use_port(lamp_socket)
	assert(kit.links.size() == 6 and not wires._draft.is_empty()) # occupied input rejected
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	wires.forward_input(camera, escape); assert(wires._draft.is_empty())
	click.position = Vector2(-100, -100)
	assert(wires.forward_input(camera, click) == EditorPlugin.AFTER_GUI_INPUT_PASS) # ordinary selection stays available
	wires.use_port(output_socket); wires._toggle.button_pressed = false; assert(wires._draft.is_empty())
	wires.set_scene(null); assert(not wires.active and wires.circuit() == null)
	wires.free(); camera.free()
	var empty_zone := Area3D.new(); empty_zone.name = "EmptyZone"; kit.add_child(empty_zone)
	var wrong_zone := original.duplicate(true)
	for row in wrong_zone.nodes:
		if row.kind == "door": row.clearance = "EmptyZone"
	assert(not kit.document_errors(wrong_zone).is_empty())
	empty_zone.free()
	# Pure truth tables and invalid topology, with explicit disconnected NOT semantics.
	for a in [false, true]:
		for b in [false, true]:
			var result := Model.evaluate(original, {"plate": a, "plate_b": b, "lever_a": a, "lever_b": b})
			assert(result.door == (a and b) and result.lamp == (a or b))
	var invalid := original.duplicate(true)
	invalid.links.append(invalid.links[0].duplicate())
	assert(not Model.errors(invalid).is_empty())
	invalid = {"nodes": [{"id": "a", "kind": "not", "label": "A"}, {"id": "b", "kind": "not", "label": "B"}], "links": [{"from": "a", "to": "b", "port": 0}, {"from": "b", "to": "a", "port": 0}]}
	assert(not Model.errors(invalid).is_empty() and Model.evaluate(invalid, {}).is_empty())
	invalid.links = []
	assert(not Model.evaluate(invalid, {}).a)
	await frames(60)
	assert(not kit.values.door and not kit.values.lamp)
	var crate: RigidBody3D = kit.get_node("Crate")
	crate.global_position = Vector3(-40, 0.95, 0)
	crate.linear_velocity = Vector3.ZERO
	await frames(70)
	assert(kit.values.plate and not kit.values.door)
	var other: RigidBody3D = kit.get_node("CrateB")
	other.global_position = Vector3(40, 0.95, 0)
	other.linear_velocity = Vector3.ZERO
	await frames(90)
	assert(kit.values.plate_b and kit.values.door and kit.component("door").openness > 0.99)
	# Actual F-style lever adapter, persisted as one flag, never an inventory/quest copy.
	state.storage_root = "user://ember-tests/mechanism-circuit-%d" % OS.get_process_id()
	state.persistence_enabled = true
	crate.capture_progress(); other.capture_progress()
	var saved: Array[String] = []
	state.saved.connect(func(path: String): saved.append(path))
	kit.get_node("LeverA/MechanismLeverInput").activate_from(null)
	await frames(3)
	assert(kit.values.lever_a and kit.values.lamp and saved.size() == 1)
	var restored := EmberExploreState.new()
	restored.persistence_enabled = false
	restored.restore_enabled = false
	restored.storage_root = state.storage_root
	assert(restored.load_autosave())
	assert(restored.flags.get("mechanism_%s_lever_a" % kit.circuit_id, false))
	# Native GraphEdit signals route through one scene mutation and history.
	var window := Workshop.new()
	root.add_child(window)
	var current := {"yes": true}
	window.setup(scene, actions, func(): return current.yes)
	window._graph.disconnection_request.emit(&"either", 0, &"lamp", 0)
	await frames(3)
	assert(not kit.values.lamp)
	window._undo(false)
	await frames(3)
	assert(kit.values.lamp)
	window._undo(true)
	await frames(3)
	assert(not kit.values.lamp)
	window._undo(false)
	var before: Dictionary = kit.snapshot()
	window._graph.connection_request.emit(&"lever_a", 0, &"lamp", 0)
	assert(kit.snapshot() == before and "провод" in window._message.text)
	# Add a real logic component through the UI and rewire it to the lamp.
	for i in window._kind.item_count:
		if str(window._kind.get_item_metadata(i)) == "not": window._kind.select(i)
	window._fill_bindings()
	window._name.text = "Инвертор рычага"
	window._add_component()
	var logic_id := str(window._document.nodes[-1].id)
	assert(kit.component(logic_id) != null)
	window.connect_wire(&"lever_a", 0, StringName(logic_id), 0)
	window.disconnect_wire(&"either", 0, &"lamp", 0)
	window.connect_wire(StringName(logic_id), 0, &"lamp", 0)
	await frames(3)
	assert(not kit.values.lamp)
	kit.toggle_lever("lever_a")
	await frames(3)
	assert(kit.values.lamp)
	var stable_doc: Dictionary = kit.snapshot()
	var door_component: Node = kit.component("door")
	var physical_time: int = kit._frames
	var moved := stable_doc.duplicate(true)
	moved.nodes[0].position += Vector2(35, 20)
	assert(actions.apply_mechanism_document(kit, moved).ok)
	assert(kit.component("door") == door_component and kit._frames == physical_time)
	# Refuse a cycle and a stale window without mutating the authored scene.
	before = kit.snapshot()
	invalid = before.duplicate(true)
	invalid.links.append({"from": logic_id, "to": logic_id, "port": 0})
	assert(not actions.apply_mechanism_document(kit, invalid).ok and kit.snapshot() == before)
	current.yes = false
	window.disconnect_wire(StringName(logic_id), 0, &"lamp", 0)
	assert(kit.snapshot() == before)
	current.yes = true
	# Save/reopen source, discard unsaved wiring, reload lever/world-item save separately.
	kit.release_runtime()
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "user://mechanism-circuit-source.tscn") == OK)
	kit.rebuild()
	window.disconnect_wire(StringName(logic_id), 0, &"lamp", 0)
	var reopened := (ResourceLoader.load("user://mechanism-circuit-source.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var loaded: Node3D = reopened.get_node(NodePath(str(kit.name)))
	assert(loaded.snapshot().nodes.size() == 9 and loaded.links.size() == 7)
	assert(loaded.get_node("LeverA").get_node_or_null("MechanismLeverInput") == null)
	assert(loaded.component(logic_id).get_meta("graph_position") is Vector2)
	window.free()
	history.clear_history()
	scene.free()
	assert(restored.load_autosave())
	loaded.progress_state = restored
	for child in loaded.get_children():
		if child is RigidBody3D: child.progress_state = restored
	root.add_child(reopened)
	current_scene = reopened
	await frames(90)
	assert(not loaded.values.lever_a and loaded.values.lamp and loaded.values.door)
	# A physically bound component cannot be driven by two controllers in one circuit.
	invalid = loaded.snapshot()
	var duplicate: Dictionary = invalid.nodes[-1].duplicate(true)
	duplicate.id = "lamp_duplicate"; duplicate.kind = "lamp"; duplicate.target = "Lamp"
	invalid.nodes.append(duplicate)
	assert(not loaded.document_errors(invalid).is_empty())
	loaded.get_node("Lamp").free()
	await frames(3)
	assert(not loaded.diagnostics.is_empty() and loaded.values.is_empty())
	reopened.free()
	restored.free()
	# Existing serialized pressure-gate envelope is evaluated by the common engine,
	# and the first graph edit converts it with Undo/Redo and preserved references.
	var old_scene := Node3D.new(); old_scene.name = "LegacyFixture"
	root.add_child(old_scene); current_scene = old_scene
	var legacy := preload("res://addons/ember_import/ember_pressure_gate_builder.gd").build()
	for child in legacy.components(): legacy.remove_child(child); child.free()
	legacy.set_script(Legacy)
	old_scene.add_child(legacy)
	await frames(4)
	assert(legacy.components().size() == 2)
	assert(actions.apply_mechanism_document(legacy, legacy.snapshot()).ok)
	assert(legacy.get_script() == Circuit and legacy.components().size() == 2)
	history.undo()
	assert(legacy.get_script() == Legacy and legacy.plate_path == NodePath("Plate"))
	history.redo()
	assert(legacy.get_script() == Circuit and legacy.document_errors(legacy.snapshot()).is_empty())
	history.clear_history(); history.free()
	old_scene.free()
	var stage: Node3D = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(stage); current_scene = stage
	await process_frame
	stage.start_mechanism_trial()
	stage.open_mechanism_graph()
	await process_frame
	var actor: EmberPlayer = stage._mechanism.get_node("TrialPlayer")
	assert(not actor.is_physics_processing())
	stage._mechanism.get_node("MechanismWindow").hide()
	await process_frame
	assert(actor.is_physics_processing())
	stage.stop_mechanism_trial()
	stage.queue_free()
	await process_frame
	assert(await _test_object_roles())
	assert(await _test_generated_roles())
	assert(await _test_hold_gate())
	assert(await _test_latch_gate())
	assert(await _test_mechanism_inspector())
	print("PASS mechanism circuits: AND/OR/NOT, physical plates, lever save/load, Graph wiring/add/undo/redo/reject, metadata-only move, source reopen/discard and legacy conversion; ordinary object role assignment")
	quit()

func _test_object_roles() -> bool:
	var authored := Node3D.new(); authored.name = "OrdinaryObjectFixture"; root.add_child(authored)
	var group := Node3D.new(); group.name = "Decoration"; authored.add_child(group); group.owner = authored
	group.position = Vector3(100, 7, -20)
	var handle := MeshInstance3D.new(); handle.name = "OrdinaryHandle"; handle.mesh = BoxMesh.new()
	group.add_child(handle); handle.owner = authored; handle.position = Vector3(-18, 3, 0)
	var light := OmniLight3D.new(); light.name = "OrdinaryLight"
	group.add_child(light); light.owner = authored; light.position = Vector3(18, 8, 0)
	var before := handle.global_transform
	var history := UndoRedo.new(); var actions := Actions.new(); actions.configure(history)
	var result := actions.assign_mechanism_role(authored, handle, "lever")
	assert(result.ok)
	var circuit: Node3D = result.circuit
	var source_id := str(result.id)
	assert(circuit.get_parent() == authored and circuit.components().size() == 1)
	assert(handle.get_parent() == group and handle.global_transform == before and handle.get_script() == null)
	history.undo(); assert(not circuit.is_inside_tree() and handle.is_inside_tree() and handle.global_transform == before)
	history.redo(); assert(circuit.is_inside_tree() and handle.global_transform == before)
	var state := EmberExploreState.new(); state.persistence_enabled = false; state.restore_enabled = false
	root.add_child(state); circuit.progress_state = state; circuit.rebuild()
	assert(not actions.assign_mechanism_role(authored, handle, "lever").ok)
	assert(not actions.assign_mechanism_role(authored, group, "lamp", circuit).ok)
	result = actions.assign_mechanism_role(authored, light, "lamp", circuit)
	assert(result.ok and circuit.components().size() == 2)
	var receiver_id := str(result.id)
	assert(not actions.assign_mechanism_role(authored, light, "lever", circuit).ok)
	var doc: Dictionary = circuit.snapshot()
	doc.links.append({"from": source_id, "to": receiver_id, "port": 0})
	assert(actions.apply_mechanism_document(circuit, doc).ok)
	await frames(4)
	assert(not light.visible)
	assert(handle.get_node("MechanismLeverInput").activate().contains("включён"))
	await frames(2); assert(light.visible)
	var other_result := actions.assign_mechanism_role(authored, group, "lever")
	assert(other_result.ok)
	var other: Node3D = other_result.circuit
	var conflict: Dictionary = other.snapshot()
	conflict.nodes[0].target = str(other.get_path_to(handle))
	assert(not other.document_errors(conflict).is_empty())
	history.undo(); assert(not other.is_inside_tree())
	var packed := PackedScene.new(); assert(packed.pack(authored) == OK)
	assert(ResourceSaver.save(packed, "user://ordinary_roles.tscn") == OK)
	var loaded: Node3D = load("user://ordinary_roles.tscn").instantiate()
	var reopened: Node3D = loaded.get_node(NodePath(str(circuit.name)))
	assert(reopened.links.size() == 1 and reopened.document_errors(reopened.snapshot()).is_empty())
	assert(loaded.get_node("Decoration/OrdinaryHandle").get_node_or_null("MechanismLeverInput") == null)
	# An unsaved disconnection is discarded when reopening the saved source.
	var disconnected: Dictionary = circuit.snapshot(); disconnected.links.clear()
	assert(actions.apply_mechanism_document(circuit, disconnected).ok)
	assert(circuit.links.is_empty() and reopened.links.size() == 1)
	history.undo(); assert(circuit.links.size() == 1)
	# Variable text must scroll inside a bounded form, never enlarge its Window.
	var form := WorldWires.new(); root.add_child(form)
	form.setup(actions, Callable(), Callable()); form.set_scene(authored); form.open_role_dialog(handle)
	form._role_message.text = "Длинное название предмета и сообщение ошибки. ".repeat(250)
	for i in 4: await process_frame
	assert(form._role_dialog.size.y <= 600 and form._role_dialog.size.x <= 900)
	var scroll := form._role_dialog.get_node("RoleScroll") as ScrollContainer
	assert(scroll.get_v_scroll_bar().visible)
	assert(not scroll.is_ancestor_of(form._role_dialog.get_ok_button()))
	assert(form._role_dialog.get_ok_button().get_global_rect().end.y <= form._role_dialog.size.y)
	form.free()
	loaded.free(); history.clear_history(); history.free()
	authored.free(); state.free()
	return true

func _test_hold_gate() -> bool:
	var document := {"nodes": [
		{"id": "source", "kind": "lever", "label": "Вход"},
		{"id": "delay", "kind": "hold", "label": "Задержка", "hold_seconds": 1.0},
		{"id": "light", "kind": "lamp", "label": "Выход"}],
		"links": [{"from": "source", "to": "delay", "port": 0}, {"from": "delay", "to": "light", "port": 0}]}
	var step := Model.advance(document, {}, {}, 0.1)
	assert(not step.values.light) # no startup pulse
	step = Model.advance(document, {"source": true}, step.timers, 0.1)
	assert(step.values.light and is_equal_approx(step.timers.delay, 1.0))
	var remaining: Dictionary = step.timers.duplicate()
	for i in 9: step = Model.advance(document, {}, step.timers, 0.1)
	assert(step.values.light)
	step = Model.advance(document, {"source": true}, step.timers, 0.1)
	assert(is_equal_approx(step.timers.delay, 1.0)) # retrigger refreshes duration
	step = Model.advance(document, {}, step.timers, 0.0)
	assert(step.values.light and is_equal_approx(step.timers.delay, 1.0))
	for i in 10: step = Model.advance(document, {}, step.timers, 0.1)
	assert(not step.values.light and step.timers.delay == 0)
	assert(not Model.advance(document, {}, remaining, 1.0).values.light) # frame partition
	var disconnected := document.duplicate(true); disconnected.links.remove_at(0)
	assert(not Model.advance(disconnected, {}, remaining, 0.0).values.light)
	for duration in [-1.0, 0.0, NAN, INF, 121.0]:
		var bad := document.duplicate(true); bad.nodes[1].hold_seconds = duration
		assert(not Model.errors(bad).is_empty())
	var scene := Node3D.new(); scene.name = "HoldFixture"; root.add_child(scene)
	var handle := Node3D.new(); handle.name = "Handle"; scene.add_child(handle); handle.owner = scene
	var light := OmniLight3D.new(); light.name = "Light"; scene.add_child(light); light.owner = scene
	var history := UndoRedo.new(); var actions := Actions.new(); actions.configure(history)
	var assigned := actions.assign_mechanism_role(scene, handle, "lever")
	var circuit: Node3D = assigned.circuit; var source_id := str(assigned.id)
	var state := EmberExploreState.new(); state.persistence_enabled = false; state.restore_enabled = false
	root.add_child(state); circuit.progress_state = state
	assigned = actions.assign_mechanism_role(scene, light, "lamp", circuit)
	var receiver := str(assigned.id)
	var doc: Dictionary = circuit.snapshot()
	doc.nodes.append({"id": "delay", "kind": "hold", "label": "Успеть пройти", "hold_seconds": 0.3})
	doc.links.append({"from": source_id, "to": "delay", "port": 0}); doc.links.append({"from": "delay", "to": receiver, "port": 0})
	assert(actions.apply_mechanism_document(circuit, doc).ok)
	history.undo(); assert(circuit.component("delay") == null)
	history.redo(); assert(is_equal_approx(circuit.component("delay").hold_seconds, 0.3))
	await frames(4); assert(not light.visible)
	circuit.toggle_lever(source_id); await frames(2); assert(light.visible)
	circuit.toggle_lever(source_id); await frames(4); assert(light.visible)
	var before: Dictionary = circuit.timer_remaining.duplicate()
	var moved: Dictionary = circuit.snapshot(); moved.nodes[2].position = Vector2(800, 200)
	assert(actions.apply_mechanism_document(circuit, moved).ok and circuit.timer_remaining == before)
	circuit.set_physics_process(false); await frames(22)
	assert(circuit.timer_remaining == before and light.visible)
	circuit.set_physics_process(true); await frames(22); assert(not light.visible)
	var window := Workshop.new(); root.add_child(window); window.setup(scene, actions)
	window.focus_component(circuit, "delay")
	assert(window._hold.visible and is_equal_approx(window._hold.value, 0.3) and not window._target.visible)
	window._hold.value = 0.7; window._apply_fields()
	assert(is_equal_approx(circuit.component("delay").hold_seconds, 0.7))
	history.undo(); assert(is_equal_approx(circuit.component("delay").hold_seconds, 0.3))
	var packed := PackedScene.new(); assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "user://hold_mechanism.tscn") == OK)
	var reopened: Node3D = load("user://hold_mechanism.tscn").instantiate()
	var saved: Node3D = reopened.get_node(NodePath(str(circuit.name)))
	assert(is_equal_approx(saved.component("delay").hold_seconds, 0.3) and saved.timer_remaining.is_empty())
	assert(saved.document_errors(saved.snapshot()).is_empty())
	window.free(); reopened.free(); history.clear_history(); history.free(); scene.free(); state.free()
	print("PASS hold gate: duration/retrigger/idle/disconnect/frame partition, runtime pause/layout, properties/Undo and source reopen without countdown")
	return true

func _test_latch_gate() -> bool:
	var doc := {"nodes": [
		{"id": "set", "kind": "lever", "label": "Включить"},
		{"id": "reset", "kind": "lever", "label": "Сброс"},
		{"id": "memory", "kind": "latch", "label": "Замок"},
		{"id": "light", "kind": "lamp", "label": "Дверь"}],
		"links": [{"from": "set", "to": "memory", "port": 0}, {"from": "reset", "to": "memory", "port": 1}, {"from": "memory", "to": "light", "port": 0}]}
	for previous in [false, true]:
		for set_on in [false, true]:
			for reset_on in [false, true]:
				var next := Model.advance(doc, {"set": set_on, "reset": reset_on}, {}, 0.1, {"memory": previous})
				assert(next.values.light == (false if reset_on else set_on or previous))
	var unplugged := doc.duplicate(true); unplugged.links.remove_at(1); unplugged.links.remove_at(0)
	assert(Model.advance(unplugged, {}, {}, 0, {"memory": true}).values.light)
	var loop := doc.duplicate(true); loop.links.append({"from": "memory", "to": "memory", "port": 0})
	assert(not Model.errors(loop).is_empty())
	var scene := Node3D.new(); scene.name = "LatchFixture"; root.add_child(scene)
	var set_object := Node3D.new(); set_object.name = "Set"; scene.add_child(set_object); set_object.owner = scene
	var reset_object := Node3D.new(); reset_object.name = "Reset"; scene.add_child(reset_object); reset_object.owner = scene
	var light := OmniLight3D.new(); light.name = "Light"; scene.add_child(light); light.owner = scene
	var history := UndoRedo.new(); var actions := Actions.new(); actions.configure(history)
	var assigned := actions.assign_mechanism_role(scene, set_object, "lever")
	var circuit: Node3D = assigned.circuit; var set_id := str(assigned.id)
	assigned = actions.assign_mechanism_role(scene, reset_object, "lever", circuit)
	var reset_id := str(assigned.id)
	assigned = actions.assign_mechanism_role(scene, light, "lamp", circuit)
	var receiver := str(assigned.id)
	var state := EmberExploreState.new(); state.restore_enabled = false; state.persistence_enabled = false
	state.storage_root = "user://ember-tests/latch-%d" % OS.get_process_id()
	root.add_child(state); state.reset_new_game(); circuit.progress_state = state
	var definition: Dictionary = circuit.snapshot()
	definition.nodes.append({"id": "memory", "kind": "latch", "label": "Замок"})
	definition.nodes.append({"id": "cascade", "kind": "latch", "label": "Второй замок"})
	definition.links = [{"from": set_id, "to": "memory", "port": 0}, {"from": reset_id, "to": "memory", "port": 1},
		{"from": "memory", "to": "cascade", "port": 0}, {"from": reset_id, "to": "cascade", "port": 1}, {"from": "cascade", "to": receiver, "port": 0}]
	assert(actions.apply_mechanism_document(circuit, definition).ok)
	await frames(4); assert(not light.visible)
	# Sources change without their separate autosaves; count only latch transactions.
	state.flags["mechanism_%s_%s" % [circuit.circuit_id, set_id]] = true
	var saves: Array[String] = []; var notifications: Array[Dictionary] = []
	state.saved.connect(func(path): saves.append(path))
	state.progress_changed.connect(func(): notifications.append(state.flags.duplicate()))
	state.persistence_enabled = true
	state.restore_enabled = true; state._restore_pending = true
	await frames(4); assert(saves.is_empty() and not light.visible)
	state._restore_pending = false
	await frames(3)
	var first_key: String = circuit.latch_flag_key("memory"); var second_key: String = circuit.latch_flag_key("cascade")
	assert(light.visible and saves.size() == 1 and notifications.size() == 1)
	assert(notifications[0][first_key] and notifications[0][second_key]) # no partially committed observer state
	await frames(20); assert(saves.size() == 1)
	state.flags["mechanism_%s_%s" % [circuit.circuit_id, set_id]] = false
	await frames(3); assert(light.visible and saves.size() == 1)
	var restored := EmberExploreState.new(); restored.persistence_enabled = false; restored.restore_enabled = false
	restored.storage_root = state.storage_root
	assert(restored.load_autosave() and restored.flags[first_key] and restored.flags[second_key])
	# Current live set input is off; saved source input is irrelevant to the held state.
	restored.flags["mechanism_%s_%s" % [circuit.circuit_id, set_id]] = false
	circuit.progress_state = restored; circuit.rebuild(); await frames(4)
	assert(light.visible)
	var before: Dictionary = restored.flags.duplicate()
	assert(not restored.set_flags_batch({"valid": true, "bad": Vector3.ZERO}))
	assert(restored.flags == before)
	circuit.progress_state = state; circuit.rebuild()
	state.flags["mechanism_%s_%s" % [circuit.circuit_id, reset_id]] = true
	await frames(4)
	assert(not light.visible and not state.flags[first_key] and not state.flags[second_key] and saves.size() == 2)
	await frames(20); assert(saves.size() == 2)
	assert(restored.load_autosave() and not restored.flags[first_key])
	state.flags["mechanism_%s_%s" % [circuit.circuit_id, reset_id]] = false
	state.flags["mechanism_%s_%s" % [circuit.circuit_id, set_id]] = true
	await frames(2); assert(light.visible and saves.size() == 3)
	var window := Workshop.new(); root.add_child(window); window.setup(scene, actions); window.focus_component(circuit, "memory")
	assert(window._graph.get_node("memory/Signal0/Input").text == "Включить")
	assert(window._graph.get_node("memory/Signal1/Input").text == "Сброс")
	var layout: Dictionary = circuit.snapshot(); layout.nodes[3].position = Vector2(600, 100)
	assert(actions.apply_mechanism_document(circuit, layout).ok)
	assert(state.flags[first_key])
	history.undo(); history.redo(); await frames(3)
	assert(light.visible and saves.size() == 3)
	var packed := PackedScene.new(); assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "user://latch_source.tscn") == OK)
	var reopened: Node3D = load("user://latch_source.tscn").instantiate()
	var loaded: Node3D = reopened.get_node(NodePath(str(circuit.name)))
	assert(loaded.component("memory").kind == "latch" and loaded.document_errors(loaded.snapshot()).is_empty())
	# New component IDs never inherit an old saved latch flag.
	assert(circuit.latch_flag_key("new_memory") != first_key)
	window.free(); reopened.free(); history.clear_history(); history.free(); scene.free(); state.free(); restored.free()
	print("PASS latch: truth table/reset priority, cascade atomic flags and single autosave, hold/reload/reset, unchanged-frame no writes, validation, named ports/Undo/source reopen")
	return true

func _test_mechanism_inspector() -> bool:
	var scene := Node3D.new(); scene.name = "InspectorFixture"; root.add_child(scene)
	var plate := MeshInstance3D.new(); plate.name = "Plate"; plate.mesh = BoxMesh.new(); plate.mesh.size = Vector3(24,2,24)
	scene.add_child(plate); plate.owner = scene
	var door := MeshInstance3D.new(); door.name = "Door"; door.mesh = BoxMesh.new(); door.mesh.size = Vector3(24,32,4)
	scene.add_child(door); door.owner = scene; door.position = Vector3(60,16,0)
	var selected := {"node": plate}; var current := {"valid": true}
	var history := UndoRedo.new(); var actions := Actions.new(); actions.configure(history)
	var window := Workshop.new(); root.add_child(window); window.setup(scene, actions, func(): return current.valid)
	var wires := WorldWires.new(); root.add_child(wires)
	wires.setup(actions, Callable(), Callable()); wires.use_inspector_mode(); wires.set_scene(scene)
	var panel := MechanismInspector.new(); root.add_child(panel)
	panel.setup(scene, actions, window, wires, func(): return selected.node)
	wires._toggle.button_pressed = true
	assert(panel._palette.visible and not panel._fields.visible)
	panel._roles.plate.pressed.emit()
	var circuit: Node3D = wires.circuit(); var source := str(window._selected)
	assert(circuit.component(source).kind == "plate" and panel._fields.visible and not window._kind.visible)
	selected.node = door; panel.select_native_object(); assert(panel._palette.visible)
	panel._roles.door.pressed.emit(); var receiver := str(window._selected)
	assert(circuit.component(receiver).kind == "door" and window._lift.visible and not window._target.visible)
	wires.use_port({"id": source, "output": true, "port": 0})
	wires.use_port({"id": receiver, "output": false, "port": 0})
	assert(circuit.links.size() == 1 and window._selected == receiver)
	var custom: Dictionary = circuit.snapshot()
	for row in custom.nodes:
		if row.id == receiver: row.offset = Vector3(40,0,0); row.seconds = 5.0
	assert(actions.apply_mechanism_document(circuit, custom).ok)
	assert(window._lift.value == 0 and window._seconds.value == 5)
	window._name.text = "Переименованная дверь"; window._apply_fields()
	assert(circuit.component(receiver).open_offset == Vector3(40,0,0) and circuit.component(receiver).move_seconds == 5)
	window._undo(false); window._undo(false)
	window._lift.value = 42; window._apply_fields()
	assert(circuit.component(receiver).open_offset.y == 42)
	window._undo(false); assert(circuit.component(receiver).open_offset.y == 36)
	var camera := Camera3D.new(); scene.add_child(camera)
	camera.position = Vector3(80,80,160); camera.look_at(Vector3(20,0,0)); wires._camera = camera
	wires.use_port({"id": source, "output": true, "port": 0})
	var before_add: Dictionary = circuit.snapshot()
	assert(wires.open_logic_menu(camera, Vector2(300,180)))
	assert(wires._logic_popup.item_count == 5)
	wires._logic_popup.hide(); await process_frame
	assert(circuit.snapshot() == before_add and wires._draft.is_empty())
	wires.use_port({"id": source, "output": true, "port": 0})
	assert(wires.open_logic_menu(camera, Vector2(300,180)))
	wires._logic_popup.hide(); wires._logic_popup.id_pressed.emit(3)
	var inserted := str(window._selected)
	assert(circuit.component(inserted).kind == "hold" and wires._draft == inserted)
	assert(circuit.links.size() == 2 and circuit.links.back().from == source and circuit.links.back().to == inserted)
	var inserted_at: Vector3 = circuit.component(inserted).get_meta("mechanism_world_position")
	window._undo(false); assert(circuit.snapshot() == before_add)
	window._undo(true); assert(circuit.component(inserted).get_meta("mechanism_world_position") == inserted_at)
	window._hold.value = 7; window._apply_fields()
	assert(circuit.component(inserted).get_meta("mechanism_world_position") == inserted_at)
	var placed: Dictionary = circuit.snapshot(); var stable_component: Node = circuit.component(inserted)
	for row in placed.nodes:
		if row.id == inserted: row.world_position += Vector3(5,0,0)
	assert(actions.apply_mechanism_document(circuit, placed).ok and circuit.component(inserted) == stable_component)
	var invalid_placement: Dictionary = circuit.snapshot()
	for row in invalid_placement.nodes:
		if row.id == inserted: row.world_position = Vector3(NAN,0,0)
	assert(not actions.apply_mechanism_document(circuit, invalid_placement).ok)
	var packed := PackedScene.new(); assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "user://wire-add-mechanism.tscn") == OK)
	var restored := (ResourceLoader.load("user://wire-add-mechanism.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	assert(restored.get_node(NodePath(str(circuit.name))).snapshot() == circuit.snapshot()); restored.free()
	var before_drag: Dictionary = circuit.snapshot(); var version := history.get_version()
	var output := {}
	for point in wires.ports(camera):
		if point.id == inserted and point.output: output = point
	assert(not output.is_empty())
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	press.position = output.at - Vector2(74,0)
	assert(wires.forward_input(camera, press) == EditorPlugin.AFTER_GUI_INPUT_STOP)
	var motion := InputEventMouseMotion.new(); motion.position = press.position + Vector2(80,-40); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	assert(wires.forward_input(camera, motion) == EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert(circuit.snapshot() == before_drag and history.get_version() == version)
	var preview := Vector2.ZERO
	for point in wires.ports(camera):
		if point.id == inserted and point.output: preview = point.at
	assert(preview.is_equal_approx(output.at + Vector2(80,-40)))
	var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.position = motion.position
	wires.forward_input(camera, release)
	assert(circuit.snapshot() != before_drag and circuit.component(inserted) == stable_component)
	for point in wires.ports(camera):
		if point.id == inserted and point.output: assert(point.at.is_equal_approx(preview))
	var after_drag: Dictionary = circuit.snapshot()
	assert(packed.pack(scene) == OK and ResourceSaver.save(packed, "user://wire-drag-mechanism.tscn") == OK)
	var reopened_drag := (ResourceLoader.load("user://wire-drag-mechanism.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	assert(reopened_drag.get_node(NodePath(str(circuit.name))).snapshot() == after_drag); reopened_drag.free()
	history.undo(); assert(circuit.snapshot() == before_drag)
	history.redo(); assert(circuit.snapshot() == after_drag)
	history.undo(); version = history.get_version()
	wires.forward_input(camera, press); wires.forward_input(camera, release)
	assert(circuit.snapshot() == before_drag and history.get_version() == version)
	wires.forward_input(camera, press); wires.forward_input(camera, motion)
	var escape := InputEventKey.new(); escape.pressed = true; escape.keycode = KEY_ESCAPE
	wires.forward_input(camera, escape); wires.forward_input(camera, release)
	assert(circuit.snapshot() == before_drag and history.get_version() == version)
	wires.forward_input(camera, press); wires.forward_input(camera, motion); wires.set_ports_visible(false)
	assert(wires._drag_id.is_empty() and circuit.snapshot() == before_drag)
	wires.set_ports_visible(true)
	var spare: String = window.add_logic("not")
	wires.use_port({"id": inserted, "output": false, "port": 0}, true)
	wires.use_port({"id": spare, "output": true, "port": 0})
	assert(str(wires._feedback["%s:0" % inserted]).is_empty())
	assert("круг" in str(wires._feedback["%s:0" % spare]))
	assert("уже есть" in str(wires._feedback["%s:0" % receiver]))
	var before_reject: Dictionary = circuit.snapshot()
	wires.use_port({"id": spare, "output": false, "port": 0})
	assert(circuit.snapshot() == before_reject and wires._draft == spare)
	for point in wires.ports(camera):
		if point.id == inserted and not point.output: press.position = point.at
	assert(wires.forward_input(camera, press) == EditorPlugin.AFTER_GUI_INPUT_STOP)
	release.position = press.position
	assert(wires.forward_input(camera, release) == EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert(circuit.links.back().from == spare and circuit.links.back().to == inserted)
	history.undo(); assert(circuit.snapshot() == before_reject)
	history.undo(); history.undo(); assert(circuit.snapshot() == before_drag)
	print("PASS3D gestures: drag preview=commit, one Undo/Redo/save/reopen, click/Esc/hidden-ports no mutation, identity retained, valid/occupied/cycle feedback and rejection")
	window._undo(false); window._undo(false); window._undo(false)
	assert(circuit.snapshot() == before_add)
	wires.use_port({"id": source, "output": true, "port": 0})
	assert(wires.open_logic_menu(camera, Vector2(300,180)))
	wires.set_ports_visible(false)
	assert(not wires._logic_popup.visible and wires._pending_source.is_empty() and circuit.snapshot() == before_add)
	wires.set_ports_visible(true)
	panel._logic_menu.get_popup().id_pressed.emit(3)
	assert(panel._logic_picker.item_count == 1 and circuit.component(window._selected).kind == "hold" and window._hold.visible)
	selected.node = door; panel.select_native_object()
	window._remove_button.pressed.emit()
	assert(circuit.component(receiver) == null and door.is_inside_tree() and panel._palette.visible)
	window._undo(false); assert(circuit.component(receiver) != null and panel._fields.visible)
	wires.set_ports_visible(false); assert(not wires.active and wires.is_editing())
	wires.set_ports_visible(true); assert(wires.active)
	var other := MeshInstance3D.new(); other.name = "Independent"; other.mesh = BoxMesh.new(); scene.add_child(other); other.owner = scene
	selected.node = other; panel.select_native_object(); panel._new_circuit.button_pressed = true
	panel._roles.lever.pressed.emit(); assert(wires.circuit() != circuit)
	for i in wires._picker.item_count:
		if wires._picker.get_item_metadata(i).get_ref() == circuit:
			wires._picker.select(i); wires._picker.item_selected.emit(i); break
	assert(window.root_circuit() == circuit and panel._logic_picker.item_count == 1)
	var before: Dictionary = circuit.snapshot(); current.valid = false
	panel.assign_role("lamp"); assert(circuit.snapshot() == before)
	panel.find_child("MechanismPorts", true, false).button_pressed = false
	panel.release_view(); panel.free(); window.free()
	current.valid = true
	var reopened_window := Workshop.new(); root.add_child(reopened_window); reopened_window.setup(scene, actions)
	var reopened_panel := MechanismInspector.new(); root.add_child(reopened_panel)
	reopened_panel.setup(scene, actions, reopened_window, wires, func(): return selected.node)
	assert(not reopened_panel.find_child("MechanismPorts", true, false).button_pressed and not wires.active and wires.is_editing())
	for i in wires._picker.item_count:
		if wires._picker.get_item_metadata(i).get_ref() == circuit:
			wires._picker.select(i); wires._picker.item_selected.emit(i); break
	assert(reopened_window.root_circuit() == circuit)
	reopened_panel.release_view(); reopened_panel.free(); reopened_window.free()
	wires.set_scene(null); assert(not wires.is_editing() and wires.circuit() == null)
	wires.free(); history.clear_history(); history.free(); scene.free()
	print("PASS mechanism inspector: role palette, shared conditional properties, compact wire focus, add logic, edit/remove/Undo, mode toggle, stale scene and picker cleanup")
	return true

func _test_generated_roles() -> bool:
	var scene := Node3D.new(); scene.name = "AutomaticRoleFixture"; root.add_child(scene)
	var decoration := Node3D.new(); decoration.name = "Decoration"; scene.add_child(decoration); decoration.owner = scene
	var plate := MeshInstance3D.new(); plate.name = "OrdinaryPlate"; plate.mesh = BoxMesh.new(); plate.mesh.size = Vector3(24, 2, 24)
	decoration.add_child(plate); plate.owner = scene; plate.position.y = 1
	var door := MeshInstance3D.new(); door.name = "OrdinaryDoor"; door.mesh = BoxMesh.new(); door.mesh.size = Vector3(24, 32, 4)
	decoration.add_child(door); door.owner = scene; door.position = Vector3(0, 16, -40)
	var old_body := StaticBody3D.new(); old_body.name = "OriginalCollision"; door.add_child(old_body); old_body.owner = scene
	var old_shape := CollisionShape3D.new(); old_shape.shape = BoxShape3D.new(); old_shape.shape.size = door.mesh.size
	old_body.add_child(old_shape); old_shape.owner = scene
	var original := door.transform
	var history := UndoRedo.new(); var actions := Actions.new(); actions.configure(history)
	var result := actions.assign_mechanism_role(scene, plate, "plate")
	assert(result.ok)
	var transient := MeshInstance3D.new(); transient.mesh = BoxMesh.new(); scene.add_child(transient)
	assert(not actions.assign_mechanism_role(scene, transient, "door").ok)
	transient.free()
	var circuit: Node3D = result.circuit
	var plate_id := str(result.id)
	assert(circuit.document_errors(circuit.snapshot()).is_empty())
	history.undo(); assert(plate.get_child_count() == 0 and plate.get_parent() == decoration)
	history.redo(); assert(plate.get_child_count() == 1)
	result = actions.assign_mechanism_role(scene, door, "door", circuit)
	assert(result.ok)
	var door_id := str(result.id)
	await frames(2); assert(old_shape.disabled)
	history.undo(); await frames(2)
	assert(door.get_child_count() == 1 and door.transform == original and not old_shape.disabled)
	history.redo(); await frames(2)
	assert(circuit.document_errors(circuit.snapshot()).is_empty())
	assert(not actions.assign_mechanism_role(scene, plate, "lever", circuit).ok)
	var document: Dictionary = circuit.snapshot(); document.links.append({"from": plate_id, "to": door_id, "port": 0})
	assert(actions.apply_mechanism_document(circuit, document).ok)
	await frames(50)
	assert(circuit.component(door_id).openness < 0.01)
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 16, -60), Vector3(0, 16, -20), 1)
	assert(not scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	var actor := CharacterBody3D.new(); actor.collision_layer = 2
	var actor_shape := CollisionShape3D.new(); actor_shape.shape = BoxShape3D.new(); actor_shape.shape.size = Vector3(4, 10, 4)
	actor.add_child(actor_shape); scene.add_child(actor); actor.position = Vector3(0, 7, 0)
	await frames(65)
	assert(circuit.values[plate_id] and circuit.component(door_id).openness > 0.99)
	assert(scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	actor.position = Vector3(0, 7, -40)
	await frames(50)
	assert(not circuit.values[plate_id] and circuit.component(door_id).blocked and circuit.component(door_id).openness > 0.99)
	actor.position.x = 100; await frames(50)
	assert(circuit.component(door_id).openness < 0.01)
	actor.free()
	var weight := RigidBody3D.new(); weight.collision_layer = 4
	var weight_shape := CollisionShape3D.new(); weight_shape.shape = BoxShape3D.new(); weight_shape.shape.size = Vector3(6, 6, 6)
	weight.add_child(weight_shape); scene.add_child(weight); weight.position = Vector3(0, 5, 0)
	await frames(65)
	assert(circuit.values[plate_id] and circuit.component(door_id).openness > 0.99)
	weight.position.x = 100; await frames(60)
	assert(not circuit.values[plate_id] and circuit.component(door_id).openness < 0.01)
	weight.free()
	# End-to-end timed passage, using the actual generated plate and moving door.
	var timed: Dictionary = circuit.snapshot()
	timed.nodes.append({"id": "delay", "kind": "hold", "label": "Время пройти", "hold_seconds": 0.3})
	timed.links = [{"from": plate_id, "to": "delay", "port": 0}, {"from": "delay", "to": door_id, "port": 0}]
	assert(actions.apply_mechanism_document(circuit, timed).ok)
	var walker := CharacterBody3D.new(); walker.collision_layer = 2
	var walker_shape := CollisionShape3D.new(); walker_shape.shape = BoxShape3D.new(); walker_shape.shape.size = Vector3(4, 10, 4)
	walker.add_child(walker_shape); scene.add_child(walker); walker.position = Vector3(0, 7, 0)
	await frames(65); assert(circuit.component(door_id).openness > 0.99)
	walker.position.x = 100; await frames(6)
	assert(not circuit.values[plate_id] and circuit.values.delay and circuit.component(door_id).openness > 0.99)
	await frames(55); assert(not circuit.values.delay and circuit.component(door_id).openness < 0.01)
	walker.free()
	var removed: Dictionary = circuit.snapshot()
	for i in range(removed.nodes.size() - 1, -1, -1):
		if removed.nodes[i].id == door_id: removed.nodes.remove_at(i)
	removed.links.clear()
	assert(actions.apply_mechanism_document(circuit, removed).ok)
	await frames(2); assert(door.get_child_count() == 1 and not old_shape.disabled)
	history.undo(); await frames(2)
	assert(door.get_child_count() == 2 and old_shape.disabled)
	circuit.release_runtime(); await frames(2)
	var packed := PackedScene.new(); assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "user://automatic_mechanism_roles.tscn") == OK)
	var loaded: Node = load("user://automatic_mechanism_roles.tscn").instantiate()
	var saved: Node3D = loaded.get_node(NodePath(str(circuit.name)))
	assert(saved.components().size() == 3 and saved.links.size() == 2 and saved.document_errors(saved.snapshot()).is_empty())
	assert(loaded.get_node("Decoration/OrdinaryDoor").position == original.origin)
	loaded.free(); history.clear_history(); history.free(); scene.free()
	print("PASS automatic plate/door: helpers, undo/redo/removal, original collision restore, actor pressure, occupied passage, physical ray and source reopen")
	return true
