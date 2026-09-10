@tool
extends RefCounted
## Pure bounded shape authoring. Source schema and meshing remain unchanged.
const KINDS := ["empty", "block", "cylinder", "sphere"]
const WARNING_CELLS := 131072
const MAX_CELLS := 524288

static func build(kind: String, dimensions: Vector3i, density: int, color: Color, model_id: String, title: String) -> Dictionary:
	if kind not in KINDS or density not in [16, 32]:
		return {"ok": false, "error": "Неизвестная форма или плотность."}
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.z < 1 or dimensions.y > 8 * density:
		return {"ok": false, "error": "Размеры должны быть положительными; высота не более %d vox." % (8 * density)}
	if dimensions.x > 256 or dimensions.z > 256:
		return {"ok": false, "error": "Ширина и глубина формы ограничены 256 vox."}
	if (kind == "sphere" and (dimensions.x != dimensions.y or dimensions.x != dimensions.z)) or (kind == "cylinder" and dimensions.x != dimensions.z):
		return {"ok": false, "error": "Сфера: один диаметр XYZ. Цилиндр: одинаковый диаметр XZ."}
	var grid := Vector3i(ceili(float(dimensions.x) / density) * density, dimensions.y, ceili(float(dimensions.z) / density) * density)
	if grid.x * grid.y * grid.z > MAX_CELLS:
		return {"ok": false, "error": "Сетка хранения превышает 524 288 ячеек. Уменьшите размеры. Разрезание на секции пока не реализовано."}
	var source := EmberVoxelModelResource.new()
	source.model_id = model_id
	source.display_name = title
	source.voxels_per_block = density
	source.size_blocks = Vector3i(grid.x / density, ceili(float(grid.y) / density), grid.z / density)
	source.height_voxels = dimensions.y
	source.palette = PackedColorArray([Color.TRANSPARENT, Color(color, 1.0)])
	source.voxels.resize(grid.x * grid.y * grid.z)
	var origin := Vector3i((grid.x - dimensions.x) / 2, 0, (grid.z - dimensions.z) / 2)
	var center := Vector3(dimensions - Vector3i.ONE) * 0.5
	# Cell-centre sampling: every integer diameter, including 1/2, reaches
	# the advertised extents while remaining symmetric about its centre.
	var radius := float(dimensions.x) * 0.5
	if kind != "empty":
		for y in dimensions.y:
			for z in dimensions.z:
				for x in dimensions.x:
					var delta := Vector3(x, y, z) - center
					var occupied := kind == "block"
					if kind == "cylinder":
						occupied = delta.x * delta.x + delta.z * delta.z <= radius * radius
					elif kind == "sphere":
						occupied = delta.length_squared() <= radius * radius
					if occupied:
						source.voxels[VoxMesher.cell_index(x + origin.x, y, z + origin.z, grid.x, grid.z)] = 1
	return {"ok": true, "source": source, "grid": grid, "dimensions": dimensions, "origin": origin, "error": ""}
