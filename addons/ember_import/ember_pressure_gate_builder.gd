@tool
extends RefCounted

static func box(parent: Node3D, name: String, at: Vector3, size: Vector3, color: Color, solid := false) -> Node3D:
	var node: Node3D = StaticBody3D.new() if solid else Node3D.new()
	node.name = name
	node.position = at
	parent.add_child(node)
	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	node.add_child(mesh)
	if solid:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = BoxShape3D.new()
		shape.shape.size = size
		node.add_child(shape)
	return node

static func area(parent: Node3D, name: String, at: Vector3, size: Vector3, mask: int) -> Area3D:
	var node := Area3D.new()
	node.name = name
	node.collision_layer = 0
	node.collision_mask = mask
	parent.add_child(node)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.position = at
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	node.add_child(shape)
	return node

static func build(map_id := "landscape_compact") -> Node3D:
	var kit := preload("res://scripts/ember_mechanism_circuit.gd").new() as Node3D
	kit.name = "Mechanism"
	kit.circuit_id = "circuit_" + Crypto.new().generate_random_bytes(8).hex_encode()
	box(kit, "Floor", Vector3(0, -2, 0), Vector3(160, 4, 160), Color("596774"), true)
	for side in [-1, 1]:
		box(kit, "Side%d" % (side + 1), Vector3(side * 78, 24, 0), Vector3(4, 48, 160), Color("8295a3"), true)
		box(kit, "Partition%d" % (side + 1), Vector3(side * 46, 24, -20), Vector3(64, 48, 4), Color("8295a3"), true)
		box(kit, "End%d" % (side + 1), Vector3(0, 4 if side == 1 else 24, side * 78), Vector3(160, 8 if side == 1 else 48, 4), Color("8295a3"), true)
	var gate := AnimatableBody3D.new()
	gate.name = "Gate"
	gate.position = Vector3(0, 18, -20)
	kit.add_child(gate)
	box(gate, "Leaf", Vector3.ZERO, Vector3(28, 36, 4), Color("7e665b"))
	var gate_shape := CollisionShape3D.new()
	gate_shape.name = "Shape"
	gate_shape.shape = BoxShape3D.new()
	gate_shape.shape.size = Vector3(28, 36, 4)
	gate.add_child(gate_shape)
	var plate := area(kit, "Plate", Vector3(0, 14, 0), Vector3(30, 28, 30), 4)
	plate.position = Vector3(-40, 0, 0)
	var top := box(plate, "Top", Vector3(0, 0.4, 0), Vector3(28, 0.8, 28), Color("c79746"), true)
	# Runtime visual reference stays on the plate root; collision belongs to Top.
	var visual := top.get_node("Visual")
	top.remove_child(visual)
	plate.add_child(visual)
	visual.position.y = 0.4
	area(kit, "Clearance", Vector3(0, 20, -20), Vector3(26, 36, 12), 1 | 2 | 4)
	var crate := preload("res://scripts/ember_world_item_3d.gd").new()
	crate.name = "Crate"
	crate.item_id = "quest_crate"
	crate.pickup_id = "mechanism_crate_" + Crypto.new().generate_random_bytes(8).hex_encode()
	crate.carryable = true
	crate.map_id = map_id
	crate.position = Vector3(-40, 0.15, 30)
	kit.add_child(crate)
	item_visual(crate, "quest_crate", true)
	var reward := preload("res://scripts/ember_world_item_3d.gd").new()
	reward.name = "Find"
	reward.item_id = "shore_shell"
	reward.pickup_id = "mechanism_find_" + Crypto.new().generate_random_bytes(8).hex_encode()
	reward.map_id = map_id
	reward.position = Vector3(0, 0.15, -55)
	kit.add_child(reward)
	item_visual(reward, "shore_shell", false)
	var circuit := preload("res://scripts/ember_mechanism_circuit.gd")
	for row in [
		{"id": "plate", "kind": "plate", "label": "Плита", "target": "Plate", "crate": "Crate", "position": Vector2(40, 40)},
		{"id": "door", "kind": "door", "label": "Дверь", "target": "Gate", "clearance": "Clearance", "position": Vector2(420, 40)}
	]: kit.add_child(circuit.make_component(row))
	kit.links.assign([{"from": "plate", "to": "door", "port": 0}])
	return kit

static func item_visual(body: RigidBody3D, item_id: String, collider: bool) -> void:
	var item := EmberItemCatalog.definition(item_id)
	var visual := (load(str(item.get("worldScene", ""))) as PackedScene).instantiate() as Node3D
	visual.name = "ItemVisual"
	visual.scale = Vector3.ONE * 16.0
	body.add_child(visual)
	if collider:
		var shape := CollisionShape3D.new()
		shape.name = "BodyShape"
		shape.position.y = 8.0
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3.ONE * 16.0
		body.add_child(shape)

static func build_workshop(map_id := "landscape_compact") -> Node3D:
	var kit := build(map_id)
	var second_plate := area(kit, "PlateB", Vector3(0, 14, 0), Vector3(30, 28, 30), 4)
	second_plate.position = Vector3(40, 0, 0)
	var top := box(second_plate, "Top", Vector3(0, 0.4, 0), Vector3(28, 0.8, 28), Color("c79746"), true)
	var visual := top.get_node("Visual")
	top.remove_child(visual)
	second_plate.add_child(visual)
	visual.position.y = 0.4
	var crate := preload("res://scripts/ember_world_item_3d.gd").new()
	crate.name = "CrateB"
	crate.item_id = "quest_crate"
	crate.pickup_id = "mechanism_crate_" + Crypto.new().generate_random_bytes(8).hex_encode()
	crate.carryable = true
	crate.map_id = map_id
	crate.position = Vector3(40, 0.15, 30)
	kit.add_child(crate)
	item_visual(crate, "quest_crate", true)
	box(kit, "LeverA", Vector3(-22, 5, 48), Vector3(8, 10, 8), Color("d28054"))
	box(kit, "LeverB", Vector3(22, 5, 48), Vector3(8, 10, 8), Color("d28054"))
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	lamp.mesh = SphereMesh.new()
	lamp.mesh.radius = 5.0
	lamp.mesh.height = 10.0
	lamp.position = Vector3(0, 16, 0)
	kit.add_child(lamp)
	var circuit := preload("res://scripts/ember_mechanism_circuit.gd")
	kit.get_node("Component_plate").label = "Левая плита"
	kit.get_node("Component_plate").set_meta("graph_position", Vector2(40, 40))
	kit.get_node("Component_door").set_meta("graph_position", Vector2(650, 100))
	for row in [
		{"id": "plate_b", "kind": "plate", "label": "Правая плита", "target": "PlateB", "crate": "CrateB", "position": Vector2(40, 220)},
		{"id": "both", "kind": "all", "label": "Обе плиты", "position": Vector2(350, 100)},
		{"id": "lever_a", "kind": "lever", "label": "Левый рычаг", "target": "LeverA", "position": Vector2(40, 430)},
		{"id": "lever_b", "kind": "lever", "label": "Правый рычаг", "target": "LeverB", "position": Vector2(40, 600)},
		{"id": "either", "kind": "any", "label": "Любой рычаг", "position": Vector2(350, 490)},
		{"id": "lamp", "kind": "lamp", "label": "Лампа", "target": "Lamp", "position": Vector2(650, 490)}
	]: kit.add_child(circuit.make_component(row))
	kit.links.assign([
		{"from": "plate", "to": "both", "port": 0}, {"from": "plate_b", "to": "both", "port": 1}, {"from": "both", "to": "door", "port": 0},
		{"from": "lever_a", "to": "either", "port": 0}, {"from": "lever_b", "to": "either", "port": 1}, {"from": "either", "to": "lamp", "port": 0}
	])
	return kit
