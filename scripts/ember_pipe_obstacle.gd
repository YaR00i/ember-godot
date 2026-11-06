@tool
extends Marker3D
## Put a mesh, a collision body or an instanced obstacle under this marker.

@export_range(1, 32) var segment := 1
@export_range(0.0, 1.0, 0.01) var segment_offset := 0.5
@export_range(-180.0, 180.0, 1.0) var wall_angle := 0.0
