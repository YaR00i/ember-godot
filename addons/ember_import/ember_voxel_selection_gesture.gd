@tool
extends RefCounted
## Incremental screen rectangle query; transient, no source writes.
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
var indices := PackedInt32Array()
var done := false
var error := ""
var cursor := 0
var source: EmberVoxelModelResource
var camera: Camera3D
var rectangle: Rect2
var viewport_scale := Vector2.ONE
var through := false
var region := Rect2i()
var height := -1

func step(budget := 128) -> void:
	if done:
		return
	var size := source.grid_size()
	var density := float(source.normalized_density())
	for iteration in budget:
		if cursor >= source.voxels.size():
			done = true
			return
		var index := cursor
		cursor += 1
		if source.voxels[index] == 0:
			continue
		var cell := Selection.cell_of(index,size)
		if not Fragment._allowed(cell,source,region,height):
			continue
		var center := (Vector3(cell)+Vector3.ONE*0.5)/density
		if camera.is_position_behind(center):
			continue
		var point := camera.unproject_position(center)
		if not rectangle.has_point(point/viewport_scale):
			continue
		if not through:
			var hit := Model.pick(source,camera.project_ray_origin(point),camera.project_ray_normal(point),height)
			if hit.get("hit",Model.INVALID_CELL) != cell:
				continue
		indices.append(index)
		if indices.size() > Selection.LIMIT:
			error = "Больше %d вокселей. Уменьшите рамку." % Selection.LIMIT
			indices.clear()
			done = true
			return
