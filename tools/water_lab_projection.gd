extends Node3D
## Lightweight Water Lab adapter for the same water-surface sampling contract
## used by authored voxel surfaces. It keeps the lab independent of map data.

var field_center := Vector2.ZERO
var field_size := Vector2.ONE
var minimum_water_x := -INF
var surface_height := 0.0
var block_world_size := 1.0


func _ready() -> void:
	add_to_group(&"ember_water_surface_projection")


func configure(
	center: Vector2,
	size: Vector2,
	water_min_x: float,
	height: float,
	block_size: float,
) -> void:
	field_center = center
	field_size = size
	minimum_water_x = water_min_x
	surface_height = height
	block_world_size = maxf(block_size, 0.001)


func water_surface_sample(global_point: Vector3) -> Dictionary:
	var half := field_size * 0.5
	var wet := (
		global_point.x >= maxf(field_center.x - half.x, minimum_water_x)
		and global_point.x <= field_center.x + half.x
		and global_point.z >= field_center.y - half.y
		and global_point.z <= field_center.y + half.y
	)
	return {
		"wet": wet,
		"position": Vector3(global_point.x, surface_height, global_point.z),
		"block_world_size": block_world_size,
	}


func water_revision() -> int:
	return 0
