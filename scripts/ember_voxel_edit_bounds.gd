extends RefCounted
## Editor-only upper cut plane. Height is a count: 1 exposes voxel Y=0.
## X/Z strides stay unchanged, so preview and picking share the original bytes.

static func visible_size(size: Vector3i, height := -1) -> Vector3i:
	return Vector3i(size.x, size.y if height < 0 else clampi(height, 0, size.y), size.z)


static func contains_index(index: int, size: Vector3i, height := -1) -> bool:
	var visible := visible_size(size, height)
	return index >= 0 and index < visible.x * visible.y * visible.z
