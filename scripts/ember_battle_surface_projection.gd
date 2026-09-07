@tool
class_name EmberBattleSurfaceProjection
extends RefCounted
## Pure art-Surface -> coarse battle-height projection. The visual Resource is
## only a suggestion source; an editor action remains the sole semantic writer.

const SurfaceMesher := preload("res://scripts/ember_voxel_surface_mesher.gd")

const BASE_TOP_VOXEL := 3
const ELEVATION_STEP_VOXELS := 14
const MAX_BATTLE_ELEVATION := 16
const UNEVEN_SPREAD_VOXELS := 7
const SAMPLES_PER_CELL_AXIS := 8


static func height_preview(
	surface: EmberVoxelModelResource,
	width: int,
	height: int,
	current_elevations: PackedInt32Array,
) -> Dictionary:
	if surface == null:
		return {"ok": false, "error": "У поля не назначена Visual Surface."}
	if width <= 0 or height <= 0 or current_elevations.size() != width * height:
		return {"ok": false, "error": "Сначала исправьте массив высот Battlefield Resource."}
	if surface.size_blocks.x != width or surface.size_blocks.z != height:
		return {
			"ok": false,
			"error": "Размер Visual Surface не совпадает с полем %dx%d." % [width, height],
		}
	var size := surface.grid_size()
	if surface.voxels.size() != size.x * size.y * size.z:
		return {"ok": false, "error": "Voxel-данные Visual Surface повреждены."}
	var density := surface.normalized_density()
	var sample_axis := mini(SAMPLES_PER_CELL_AXIS, density)
	var projected := current_elevations.duplicate()
	var median_tops := PackedInt32Array()
	median_tops.resize(width * height)
	median_tops.fill(-1)
	var changed_cells: Array[Vector2i] = []
	var uneven_cells: Array[Vector2i] = []
	var empty_cells: Array[Vector2i] = []
	for battle_z in height:
		for battle_x in width:
			var tops: Array[int] = []
			for sample_z in sample_axis:
				for sample_x in sample_axis:
					# Even cell-centre samples keep Inspector refresh bounded on a
					# 64x64 arena while still rejecting sparse decorative spikes.
					var local_x := clampi(
						floori((float(sample_x) + 0.5) * float(density) / float(sample_axis)),
						0,
						density - 1,
					)
					var local_z := clampi(
						floori((float(sample_z) + 0.5) * float(density) / float(sample_axis)),
						0,
						density - 1,
					)
					var top := SurfaceMesher.solid_height_at(
						surface,
						Vector2i(battle_x * density + local_x, battle_z * density + local_z),
					)
					if top >= 0:
						tops.append(top)
			var cell := Vector2i(battle_x, battle_z)
			var index := battle_z * width + battle_x
			if tops.is_empty():
				empty_cells.append(cell)
				continue
			tops.sort()
			var median := tops[(tops.size() - 1) / 2]
			median_tops[index] = median
			var low := tops[floori(float(tops.size() - 1) * 0.10)]
			var high := tops[ceili(float(tops.size() - 1) * 0.90)]
			if high - low > UNEVEN_SPREAD_VOXELS:
				uneven_cells.append(cell)
			var elevation := clampi(
				roundi(float(median - BASE_TOP_VOXEL) / float(ELEVATION_STEP_VOXELS)),
				0,
				MAX_BATTLE_ELEVATION,
			)
			projected[index] = elevation
			if elevation != int(current_elevations[index]):
				changed_cells.append(cell)
	return {
		"ok": true,
		"elevations": projected,
		"median_top_voxels": median_tops,
		"changed_cells": changed_cells,
		"uneven_cells": uneven_cells,
		"empty_cells": empty_cells,
		"base_top_voxel": BASE_TOP_VOXEL,
		"step_voxels": ELEVATION_STEP_VOXELS,
		"samples_per_cell": sample_axis * sample_axis,
	}
