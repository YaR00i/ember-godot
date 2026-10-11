@tool
extends RefCounted
## Storage/math leaf for the existing terrain Resource. Section payloads use
## that same Resource's column channels; no scene, renderer or editing state.

const CELLS := 384 # 24 game blocks, 16 columns per block.
const MAX_AXIS := 22 # Bounded 528 m envelope; increase only with measured gates.
const CHANNELS := ["heights", "top_materials", "base_materials", "cap_depths", "water_levels", "water_materials"]


static func has_cell(source, x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= source.width or z >= source.depth: return false
	if not source.is_sectioned(): return true
	var part = source.sections.get(Vector2i(x / CELLS, z / CELLS))
	return part != null and x % CELLS < part.width and z % CELLS < part.depth


static func read(source, channel: String, index: int) -> int:
	if index < 0 or source.width <= 0: return 0
	var x := index % int(source.width)
	var z := index / int(source.width)
	if not has_cell(source, x, z): return 0
	if not source.is_sectioned(): return source.get(channel)[index]
	var part = source.sections[Vector2i(x / CELLS, z / CELLS)]
	return part.get(channel)[x % CELLS + (z % CELLS) * int(part.width)]


static func window(source, bounds: Rect2i):
	var view = source.get_script().new()
	view.width = bounds.size.x
	view.depth = bounds.size.y
	view.height_limit = source.height_limit
	view.origin_y = source.origin_y
	view.palette = source.palette
	view.palette_surface_roles = source.palette_surface_roles
	view.palette_material_ids = source.palette_material_ids
	var areas: Dictionary = source.sections if source.is_sectioned() else {Vector2i.ZERO: source}
	var spans: Array = []
	for key: Vector2i in areas:
		var part = areas[key]
		var start := key * CELLS if source.is_sectioned() else Vector2i.ZERO
		var overlap := bounds.intersection(Rect2i(start, Vector2i(part.width, part.depth)))
		if not overlap.has_area(): continue
		spans.append({"part": part, "start": start, "overlap": overlap})
		for raw_index in part.column_material_overrides:
			var index := int(raw_index)
			var point := start + Vector2i(index % int(part.width), index / int(part.width))
			if bounds.has_point(point):
				view.column_material_overrides[point.x - bounds.position.x + (point.y - bounds.position.y) * int(view.width)] = part.column_material_overrides[raw_index].duplicate(true)
	spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.overlap.position.x < b.overlap.position.x)
	for channel in CHANNELS:
		var values = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		for span: Dictionary in spans: span["values"] = span.part.get(channel)
		# Copy complete row spans in native PackedArray code. Meshing reads a
		# tile plus a small halo, not one GDScript assignment per column/channel.
		for z in range(bounds.position.y, bounds.end.y):
			var row: int = values.size()
			for span: Dictionary in spans:
				var overlap: Rect2i = span.overlap
				if z < overlap.position.y or z >= overlap.end.y: continue
				values.resize(row + overlap.position.x - bounds.position.x)
				var src: int = overlap.position.x - span.start.x + (z - span.start.y) * span.part.width
				values.append_array(span.values.slice(src, src + overlap.size.x))
			values.resize(row + bounds.size.x)
		view.set(channel, values)
	# Windows used for sections are block-aligned, so flow keeps its authored
	# vectors exactly. Small meshing windows do not need the flow channel.
	if bounds.position.x % 16 == 0 and bounds.position.y % 16 == 0 and bounds.size.x % 16 == 0 and bounds.size.y % 16 == 0 and source.has_flow():
		view.water_flow.resize((view.width / 16) * (view.depth / 16))
		for z in view.depth / 16:
			for x in view.width / 16:
				view.water_flow[x + z * (view.width / 16)] = source.flow_at_cell(bounds.position.x + x * 16, bounds.position.y + z * 16)
	return view


static func convert(source):
	if source.is_sectioned(): return source.working_copy()
	var result = source.duplicate(false)
	result.schema_version = source.SECTION_SCHEMA_VERSION
	result.sections = {}
	for z in ceili(float(source.depth) / CELLS):
		for x in ceili(float(source.width) / CELLS):
			var key := Vector2i(x, z)
			result.sections[key] = window(source, Rect2i(key * CELLS, Vector2i(mini(CELLS, source.width - x * CELLS), mini(CELLS, source.depth - z * CELLS))))
	for channel in CHANNELS:
		result.set(channel, PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray())
	result.water_flow = PackedVector2Array()
	result.column_material_overrides = {}
	return result


static func write(source, indices: PackedInt32Array, heights: PackedInt32Array, tops: PackedByteArray, waters: PackedInt32Array, colors: PackedByteArray) -> void:
	var grouped := {}
	var width: int = source.width
	var limit: int = source.height_limit
	for i in indices.size():
		var index := indices[i]
		var x := index % width
		var z := index / width
		if index < 0 or not has_cell(source, x, z): continue
		var key := Vector2i(x / CELLS, z / CELLS)
		if not grouped.has(key): grouped[key] = []
		grouped[key].append(i)
	for key: Vector2i in grouped:
		# Persistent payloads: baseline/Undo/recovery share unchanged sections.
		# Only the sections touched by this batch receive private column arrays.
		var part = source.sections[key].working_copy()
		var part_width: int = part.width
		part.palette = source.palette
		part.palette_surface_roles = source.palette_surface_roles
		part.palette_material_ids = source.palette_material_ids
		part.height_limit = source.height_limit
		var part_heights: PackedInt32Array = part.heights
		var part_caps: PackedByteArray = part.cap_depths
		var part_tops: PackedByteArray = part.top_materials
		var part_waters: PackedInt32Array = part.water_levels
		var part_colors: PackedByteArray = part.water_materials
		for i: int in grouped[key]:
			var index := indices[i]
			var local := (index % width) % CELLS + ((index / width) % CELLS) * part_width
			part_heights[local] = clampi(heights[i], 0, limit)
			part_caps[local] = mini(part_caps[local], part_heights[local])
			part_tops[local] = tops[i]
			part_waters[local] = clampi(waters[i], 0, limit)
			part_colors[local] = colors[i]
		part.heights = part_heights
		part.cap_depths = part_caps
		part.top_materials = part_tops
		part.water_levels = part_waters
		part.water_materials = part_colors
		source.sections[key] = part


static func tile_keys(source, size: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if source.is_sectioned():
		for key: Vector2i in source.sections:
			var part = source.sections[key]
			for z in ceili(float(part.depth) / size):
				for x in ceili(float(part.width) / size): result.append(key * (CELLS / size) + Vector2i(x, z))
	else:
		for z in ceili(float(source.depth) / size):
			for x in ceili(float(source.width) / size): result.append(Vector2i(x, z))
	return result


static func validation_errors(source, local_sections: Array[Vector2i] = []) -> Array[String]:
	var errors: Array[String] = []
	if source.width > MAX_AXIS * CELLS or source.depth > MAX_AXIS * CELLS: return ["terrain section envelope exceeds supported size"]
	if source.sections.is_empty(): return ["terrain sections are missing"]
	for channel in CHANNELS:
		if not source.get(channel).is_empty(): return ["sectioned terrain also contains dense columns"]
	if not source.water_flow.is_empty() or not source.column_material_overrides.is_empty(): return ["sectioned terrain has dense auxiliary channels"]
	var edge := Vector2i.ZERO
	for raw_key in source.sections:
		if typeof(raw_key) != TYPE_VECTOR2I: return ["terrain section address is invalid"]
		var key: Vector2i = raw_key
		var part = source.sections[key]
		if key.x < 0 or key.y < 0 or key.x >= MAX_AXIS or key.y >= MAX_AXIS or not is_instance_valid(part) or part.get_script() != source.get_script(): return ["terrain section payload is invalid"]
		if part.is_sectioned() or not part.sections.is_empty() or part.width < 1 or part.depth < 1 or part.width > CELLS or part.depth > CELLS: return ["terrain section extent is invalid"]
		if part.height_limit != source.height_limit or part.origin_y != source.origin_y or part.unsupported_holes != 0: return ["terrain section height metadata differs"]
		# Parent palette is authoritative; payloads may predate a palette edit.
		var count: int = part.width * part.depth
		for channel in CHANNELS:
			if part.get(channel).size() != count: return ["terrain section channel has wrong size"]
		edge = edge.max(key * CELLS + Vector2i(part.width, part.depth))
		# Local editor operations enter through an already validated session.
		# Keep global structural checks; inspect payload values only where affected.
		if not local_sections.is_empty() and key not in local_sections: continue
		var heights: PackedInt32Array = part.heights
		var waters: PackedInt32Array = part.water_levels
		var tops: PackedByteArray = part.top_materials
		var bases: PackedByteArray = part.base_materials
		var liquids: PackedByteArray = part.water_materials
		var caps: PackedByteArray = part.cap_depths
		var limit: int = source.height_limit
		var colors: int = source.palette.size()
		for i in count:
			if heights[i] < 0 or heights[i] > limit or waters[i] < 0 or waters[i] > limit: return ["terrain section height is out of range"]
			if tops[i] >= colors or bases[i] >= colors or liquids[i] >= colors: return ["terrain section material is out of palette"]
			if caps[i] > heights[i]: return ["terrain section cap exceeds column height"]
		var flow_count := ceili(float(part.width) / 16) * ceili(float(part.depth) / 16)
		if not part.water_flow.is_empty() and part.water_flow.size() != flow_count: return ["terrain section flow has wrong size"]
		for flow in part.water_flow:
			if not is_finite(flow.x) or not is_finite(flow.y) or flow.length_squared() > 1.0001: return ["terrain section flow is out of range"]
		for raw_index in part.column_material_overrides:
			if typeof(raw_index) != TYPE_INT or raw_index < 0 or raw_index >= count or typeof(part.column_material_overrides[raw_index]) != TYPE_DICTIONARY: return ["terrain section override is invalid"]
			for raw_y in part.column_material_overrides[raw_index]:
				var color = part.column_material_overrides[raw_index][raw_y]
				if typeof(raw_y) != TYPE_INT or typeof(color) != TYPE_INT or raw_y < 0 or raw_y >= source.height_limit or color <= 0 or color >= source.palette.size(): return ["terrain section override is out of range"]
		edge = Vector2i(maxi(edge.x, key.x * CELLS + part.width), maxi(edge.y, key.y * CELLS + part.depth))
	if edge != Vector2i(source.width, source.depth): errors.append("terrain extent differs from section bounds")
	return errors
