@tool
extends "res://scripts/ember_mechanism_circuit.gd"
## Compatibility envelope for old scene files. Applying the graph converts it in one Undo.
@export_node_path("RigidBody3D") var crate_path := NodePath("Crate")
@export_node_path("Area3D") var plate_path := NodePath("Plate")
@export_node_path("AnimatableBody3D") var gate_path := NodePath("Gate")
@export_node_path("Area3D") var clearance_path := NodePath("Clearance")
@export var open_offset := Vector3(0, 40, 0)
@export var settle_seconds := 0.35
@export var move_seconds := 0.6
func _legacy_document() -> Dictionary:
	return {"nodes": [
		{"id": "plate", "kind": "plate", "label": "Плита", "target": str(plate_path), "crate": str(crate_path), "position": Vector2(40, 40), "settle": settle_seconds},
		{"id": "door", "kind": "door", "label": "Дверь", "target": str(gate_path), "clearance": str(clearance_path), "offset": open_offset, "seconds": move_seconds, "position": Vector2(420, 40)}
	], "links": [{"from": "plate", "to": "door", "port": 0}]}
func snapshot() -> Dictionary:
	return _legacy_document() if components().is_empty() else super.snapshot()
func _ready() -> void:
	if not Engine.is_editor_hint() and components().is_empty():
		if circuit_id.is_empty():
			var crate := get_node_or_null(crate_path)
			circuit_id = "legacy_" + str(crate.get("pickup_id")) if crate else "legacy_" + str(get_instance_id())
		var document := _legacy_document()
		for row in document.nodes: add_child(make_component(row))
		links.assign(document.links)
	super._ready()
