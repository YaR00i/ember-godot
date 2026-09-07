class_name EmberVoxelProp
extends Node3D
## Instance of a voxel PackedScene on an authored map.

const WaterContact := preload("res://scripts/ember_water_contact_3d.gd")

@export var model_id := ""
@export var placement_id := ""
@export_storage var voxels_per_block := 16
@export_storage var block_world_size := 16.0
@export_group("Вода")
@export var water_contact_enabled := false
@export_range(0.05, 1.5, 0.01) var water_contact_radius_blocks := 0.30
@export_group("")


func _ready() -> void:
	if not water_contact_enabled:
		return
	var contact: Node3D = WaterContact.new()
	contact.name = "WaterContact"
	contact.set("radius_blocks", water_contact_radius_blocks)
	add_child(contact)


func configure_voxel_scale(density: int, world_size: float) -> void:
	voxels_per_block = 32 if density == 32 else 16
	block_world_size = maxf(0.01, world_size)
	_apply_voxel_scale()


func _apply_voxel_scale() -> void:
	for child_name in ["Mesh", "ShadowBody"]:
		var visual := get_node_or_null(child_name) as MeshInstance3D
		if visual:
			_apply_scaled_node(visual)
	var shape := get_node_or_null("Collision/Shape") as CollisionShape3D
	if shape:
		_apply_scaled_node(shape)
	var omni := get_node_or_null("Omni") as OmniLight3D
	if omni:
		_apply_scaled_node(omni)
		var range_blocks := float(omni.get_meta("ember_range_blocks", 0.0))
		if range_blocks > 0.0:
			omni.omni_range = range_blocks * block_world_size


func _apply_scaled_node(node: Node3D) -> void:
	var base_position: Vector3 = node.get_meta("ember_block_position", node.position / maxf(0.01, block_world_size))
	node.set_meta("ember_block_position", base_position)
	node.position = base_position * block_world_size
	node.scale = Vector3.ONE * block_world_size
