@tool
extends RefCounted
## Session-local derived geometry only. Y slabs preserve the original y/z/x
## face order, so old prefabs, exact parity and collider layout remain valid.
var _key: Array = []
var _parts: Array[Dictionary] = []
var rebuilt := 0
var reused := 0

func build(model: Dictionary, voxel_size: float) -> ArrayMesh:
	var size := VoxMesher.ember_grid_size(model)
	var voxels := PackedByteArray(model.get("voxels", []))
	var transparency := PackedByteArray(model.get("transparency", []))
	var colors := VoxMesher._model_colors(model)
	var plane := size.x * size.z
	var height := maxi(1, mini(8, 65536 / maxi(1, plane)))
	var key: Array = [size, voxel_size, colors, height]
	if key != _key:
		_parts.clear()
		_key = key
	rebuilt = 0
	reused = 0
	var dirty: Array[int] = []
	for y in range(0, size.y, height):
		var index := y / height
		var end := mini(size.y, y + height)
		var lower := maxi(0, y - 1) * plane
		var upper := mini(size.y, end + 1) * plane
		var occupancy := voxels.slice(lower, upper)
		var alpha := transparency.slice(lower, upper) if not transparency.is_empty() else PackedByteArray()
		if index >= _parts.size():
			_parts.append({})
		if _parts[index].get("voxels") != occupancy or _parts[index].get("alpha") != alpha:
			_parts[index] = {"voxels": occupancy, "alpha": alpha, "y": y, "height": end-y}
			dirty.append(index)
		else:
			reused += 1
	if not dirty.is_empty():
		var filled := PackedByteArray()
		var indices := PackedInt32Array()
		filled.resize(voxels.size())
		indices.resize(voxels.size())
		for index in voxels.size():
			indices[index] = voxels[index]
			filled[index] = 1 if voxels[index] > 0 else 0
		for index in dirty:
			var part := _parts[index]
			part.mesh = VoxMesher._build_culled(size.x,size.y,size.z,filled,indices,colors,transparency,voxel_size,Vector3i(0,part.y,0),Vector3i(size.x,part.height,size.z))
			rebuilt += 1
	# Always assemble fresh arrays. Published/runtime mesh mutations cannot poison
	# cached pieces or weaken the independent source-vs-instance safety check.
	var mesh := ArrayMesh.new()
	for channel in ["opaque", "transparent"]:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var palette := PackedColorArray()
		var indices := PackedInt32Array()
		for part in _parts:
			var piece: ArrayMesh = part.mesh
			for surface in piece.get_surface_count():
				if piece.surface_get_name(surface) != channel:
					continue
				var arrays := piece.surface_get_arrays(surface)
				var offset := vertices.size()
				vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
				normals.append_array(arrays[Mesh.ARRAY_NORMAL])
				palette.append_array(arrays[Mesh.ARRAY_COLOR])
				for index in arrays[Mesh.ARRAY_INDEX]:
					indices.append(index + offset)
		VoxMesher._append_array_mesh_surface(mesh,vertices,normals,palette,indices,channel)
	return mesh
