class_name EmberVoxelNativeMesher
extends RefCounted
## Optional Voxel Tools adapter shared by editor and runtime projections.
## EmberVoxelModelResource remains the only writable owner; the native buffer
## and mesh are transient derived data, with the exact GDScript mesher as fallback.

const CHANNEL_COLOR := 2
const COLOR_MESHER_PALETTE := 1

var _mesher: Object
var _palette: Object
var _palette_source := PackedColorArray()


static func available() -> bool:
	return (
		ClassDB.class_exists("VoxelBuffer")
		and ClassDB.class_exists("VoxelColorPalette")
		and ClassDB.class_exists("VoxelMesherCubes")
	)


func _init() -> void:
	if not available():
		return
	_mesher = ClassDB.instantiate("VoxelMesherCubes")
	_palette = ClassDB.instantiate("VoxelColorPalette")
	_mesher.set("color_mode", COLOR_MESHER_PALETTE)
	_mesher.set("palette", _palette)
	_mesher.set("greedy_meshing_enabled", true)


func build_region(
	voxels: PackedByteArray,
	global_size: Vector3i,
	colors: PackedColorArray,
	transparency: PackedByteArray,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size: float,
	opaque_material: Material,
	transparent_material: Material,
	visible_height := -1,
) -> Dictionary:
	if _mesher == null or _palette == null:
		return {}
	var expected := global_size.x * global_size.y * global_size.z
	if expected < 1 or voxels.size() != expected:
		return {}
	global_size = preload("res://scripts/ember_voxel_edit_bounds.gd").visible_size(
		global_size, visible_height
	)
	var start := Vector3i(
		clampi(region_min.x, 0, global_size.x),
		clampi(region_min.y, 0, global_size.y),
		clampi(region_min.z, 0, global_size.z),
	)
	var end := Vector3i(
		clampi(start.x + region_size.x, start.x, global_size.x),
		clampi(start.y + region_size.y, start.y, global_size.y),
		clampi(start.z + region_size.z, start.z, global_size.z),
	)
	if start == end:
		return {}
	_sync_palette(colors)
	_mesher.set("opaque_material", opaque_material)
	_mesher.set("transparent_material", transparent_material)
	var lower_padding := maxi(1, int(_mesher.call("get_maximum_padding")))
	var upper_padding := maxi(1, int(_mesher.call("get_minimum_padding")))
	var content_size := end - start
	var buffer_size := content_size + Vector3i.ONE * (lower_padding + upper_padding)
	var native_colors := PackedByteArray()
	native_colors.resize(buffer_size.x * buffer_size.y * buffer_size.z)
	native_colors.fill(0)
	# Voxel Tools stores channels in ZXY order (Y is contiguous). Ember keeps
	# X + Z*sx + Y*sx*sz, so this is the only format projection in the adapter.
	for local_z in buffer_size.z:
		for local_x in buffer_size.x:
			for local_y in buffer_size.y:
				var global_cell := start + Vector3i(
					local_x - lower_padding,
					local_y - lower_padding,
					local_z - lower_padding,
				)
				if (
					global_cell.x < 0 or global_cell.y < 0 or global_cell.z < 0
					or global_cell.x >= global_size.x
					or global_cell.y >= global_size.y
					or global_cell.z >= global_size.z
				):
					continue
				var source_index := VoxMesher.cell_index(
					global_cell.x, global_cell.y, global_cell.z, global_size.x, global_size.z
				)
				if source_index < transparency.size() and transparency[source_index] > 0:
					# Native palettes attach alpha to a palette entry, while Ember can
					# vary transparency per cell. Preserve correctness via the fallback.
					return {}
				var native_index := (
					local_y
					+ local_x * buffer_size.y
					+ local_z * buffer_size.x * buffer_size.y
				)
				native_colors[native_index] = voxels[source_index]
	var buffer: Object = ClassDB.instantiate("VoxelBuffer")
	buffer.call("create", buffer_size.x, buffer_size.y, buffer_size.z)
	buffer.call("set_channel_from_byte_array", CHANNEL_COLOR, native_colors)
	var mesh := _mesher.call(
		"build_mesh", buffer, [opaque_material, transparent_material], {}
	) as Mesh
	if mesh == null:
		return {}
	return {
		"mesh": mesh,
		"position": Vector3(start) * voxel_size,
		"scale": Vector3.ONE * voxel_size,
	}


func _sync_palette(source: PackedColorArray) -> void:
	if source == _palette_source:
		return
	var native_colors := PackedColorArray()
	native_colors.resize(256)
	native_colors.fill(Color(0.55, 0.52, 0.48, 1.0))
	native_colors[0] = Color(0, 0, 0, 0)
	for index in mini(source.size(), 256):
		if index > 0:
			native_colors[index] = source[index]
	_palette.set("colors", native_colors)
	_palette_source = source.duplicate()
