@tool
extends RefCounted
## Editor helpers. The scene stores ordinary props, meshes and collisions.
const META := &"_ember_construction_plot"
const LEVEL_META := &"_ember_construction_level"
const OPENING_META := &"_ember_opening"
const GAP_M := preload("res://scripts/prototypes/ember_terrain_plan_math.gd").STREET_GATE_WIDTH_M
const STREET_FRONT_META := &"_ember_plot_street_front"
const SURFACE_ROAD_META := &"_ember_surface_road"
enum RoadSupport { GROUND, LEDGE, VOID, WATER }
const STREET_BRIDGE_META := &"_ember_street_bridge"
const BRIDGE_STYLE_META := &"_ember_bridge_style"
const BRIDGE_MATERIAL_META := &"_ember_bridge_material"
const BRIDGE_DECK_META := &"_ember_bridge_deck"
const BRIDGE_RAIL_META := &"_ember_bridge_rail"
const BRIDGE_SNAP_META := &"_ember_bridge_snap"
const BRIDGE_AXES_META := &"_ember_bridge_axes"
const MIN_FENCE_M := 3.5
const MAX_FENCE_M := 48.0
const WALL_SOLID := 0
const WALL_WINDOW := 1
const WALL_DOOR := 2
const WALL_PASSAGE := 3
const WALL_HEIGHT_M := 3.0
const WALL_DEPTH_M := 0.375
const ARC_WALK_WIDTH_M := 3.0
const FLOOR_TOP_M := 0.125
const CRENEL_WIDTH_M := 0.45
const CRENEL_BASE_M := 0.6
const GUARD_HEIGHT_M := 1.05
const TOWER_PORTS_META := &"_ember_tower_ports"
const TOWER_HEIGHT_META := &"_ember_tower_height_m"
const WALK_WIDTH_META := &"_ember_walk_width_m"
const WALL_DEPTH_META := &"_ember_wall_depth_m"
const DOCKED_WALK_META := &"_ember_docked_walk"
const TOWER_PORT_LABELS := ["Запад (−X)", "Юг (+Z)", "Восток (+X)", "Север (−Z)"]
const ARC_ENDS_META := &"_ember_plot_arc_ends"
const WALL_FINISHES := ["Штукатурка", "Фактурный камень", "Каменная кладка"]
const FINISH_SURFACE := 0
const FINISH_FRAME := 1
const FINISH_DOOR := 2
const FOUNTAIN_GARDEN := 0
const FOUNTAIN_COURT := 1
const FOUNTAIN_RADII := [1.125, 2.0]
const FOUNTAIN_WATER := preload("res://materials/ember_compact_sky_reflection_study.tres")
const PILASTER_HALF_WIDTH := 0.375
const STONE_TEXTURE := "res://content/terrain_materials/textures/rock-painted-calm-v2-runtime.png"
const MASONRY_TEXTURE := "res://content/terrain_materials/textures/material_depth_study/stone_color.png"
const LEVEL_COUNT := 3
const TOP_ARCH := 1
const TOP_TRIANGLE := 2
const OPENING_BORDER := 0.125
const DOUBLE_DOOR_MIN_WIDTH := 1.5
const DOUBLE_DOOR_GAP := 0.032
const ENTRY_DEPTH := 2.0
const ENTRY_TREAD := 0.375
const ENTRY_RISE := 0.125
const ENTRY_MIN_WIDTH := 2.0
const ENTRY_MAX_WIDTH := 12.0
const EDGE_STONE := 0
const EDGE_SOIL := 1
const EDGE_SHRUBS := 2
const EDGE_HEDGE := 3
const HEDGE_HEIGHT_M := 1.5
const HEDGE_MIN_HEIGHT_M := 0.75
const HEDGE_MAX_HEIGHT_M := 2.75
const HEDGE_LEAVES := "res://content/material_studies/trees/leaf_cluster_atlas_v8_separate_leaves.png"
const HEDGE_INNER_LEAVES := "res://content/material_studies/trees/painterly_foliage_v1.png"
const HEDGE_LEAF_PATCH_M := 0.72
const HEDGE_AUTUMN_PATCH_M := 0.26
const HEDGE_MIN_LEAF_SCALE := 0.6
const HEDGE_MAX_LEAF_SCALE := 1.6
const HEDGE_AUTUMN_LEAVES := "res://content/material_studies/foliage/autumn_leaf_atlas_v2.res"
const HEDGE_GROUND_OVERLAP_M := 0.015
const EDGE_MIN_DEPTH := 0.75
const EDGE_MAX_DEPTH := 3.5
const EDGE_TOP := 0.125
const PLANTER_SOIL_TOP := 0.375
const PLANTER_RIM_TOP := 0.5
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const TreeSurface = preload("res://scripts/ember_tree_surface.gd")

static var _garden_bush_mesh: ArrayMesh
const BuildingLayout = preload("res://addons/ember_import/ember_building_layout.gd")
const ROOF_MANSARD := 4
const ROOF_META := &"_ember_plot_roof"
const CONTOUR_FLOOR_META := &"_ember_round_floor"
const ROOF_FINISHES := ["Двускатная", "Четырёхскатная", "Плоская", "С парапетом", "Ломаная"]
const ROOF_COLOR := Color("536477")
const ROOF_OVERHANG := 0.5
const ROOF_EAVE := 0.14
const BALCONY_TOP := 0.125
const RAIL_METAL := 0
const RAIL_STONE := 1
const RAIL_CRENEL := 2
const GRID_SNAP_M := 0.25
const BALCONY_UNDERSIDE := -0.1875

static func house_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in EmberVoxelCatalog.definitions(true).values():
		if "building" in record.tags and ResourceLoader.exists(EmberVoxelPrefab.prefab_path(record.id)):
			result.append({"id": record.id, "name": record.nameRu})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	return result


static func fence_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var distance := a.distance_to(b)
	if distance < MIN_FENCE_M or distance > MAX_FENCE_M:
		return PackedVector2Array()
	var center := (a + b) * 0.5
	var half_gap := (b - a).normalized() * (GAP_M * 0.5)
	return PackedVector2Array([a, center - half_gap, center + half_gap, b])


static func make_fence(points: PackedVector2Array, surface: Callable, tile_size: float) -> Node3D:
	if points.size() != 4:
		return null
	return _make_fence_runs([points.slice(0, 2), points.slice(2, 4)], surface, tile_size)


static func _make_fence_runs(runs: Array, surface: Callable, tile_size: float) -> Node3D:
	var fence := Node3D.new()
	fence.name = "PlotFence"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("76543d")
	wood.roughness = 0.9
	var origin: Vector3 = surface.call(runs[0][0])
	if not origin.is_finite():
		fence.free()
		return null
	fence.position = origin
	for run: PackedVector2Array in runs:
		var previous: Vector3 = surface.call(run[0])
		for segment in range(run.size() - 1):
			var a := run[segment]
			var b := run[segment + 1]
			var count := ceili(a.distance_to(b))
			for index in range(1, count + 1):
				var next: Vector3 = surface.call(a.lerp(b, float(index) / count))
				if not previous.is_finite() or not next.is_finite() or absf(next.y - previous.y) > tile_size * 0.5:
					fence.free()
					return null
				_add_fence_panel(fence, previous, next, wood, tile_size)
				previous = next
	return fence


static func _add_fence_panel(fence: Node3D, previous: Vector3, next: Vector3, wood: Material, tile: float) -> void:
	var delta := next - previous
	var size := Vector3(Vector2(delta.x, delta.z).length(), tile + absf(delta.y), tile * 0.125)
	var body := StaticBody3D.new()
	body.name = "Panel"
	body.position = (previous + next) * 0.5 - fence.position + Vector3.UP * (tile * 0.5)
	body.rotation.y = atan2(-delta.z, delta.x)
	fence.add_child(body, true)
	var box := BoxMesh.new()
	box.size = size
	box.material = wood
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = box
	body.add_child(visual)
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	collision.shape = box_shape
	body.add_child(collision)


static func make_street_front(layout: Dictionary, surface: Callable, tile: float) -> Node3D:
	var fence := _make_fence_runs(layout.runs, surface, tile)
	if fence == null:
		return null
	fence.name = "StreetFront"
	var path: PackedVector2Array = layout.approach
	var axis := path[0].direction_to(path[1])
	var side := Vector2(-axis.y, axis.x)
	var start := path[0] - axis * 0.25
	var length := start.distance_to(path[1])
	var count := ceili(length / 0.125)
	var rows: Array[PackedVector3Array] = []
	for row in range(count + 1):
		var point := start.lerp(path[1], float(row) / count)
		var line := PackedVector3Array()
		for width in [-0.65, 0.0, 0.65]:
			var ground: Vector3 = surface.call(point + side * width)
			if not ground.is_finite() or (row > 0 and absf(ground.y - rows[-1][line.size()].y) > tile * 0.085) \
					or (not line.is_empty() and absf(ground.y - line[-1].y) > tile * 0.26):
				fence.free()
				return null
			line.append(ground)
		rows.append(line)
	var strip := SurfaceTool.new()
	strip.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paving := EmberVoxelSurfaceMaterials.load_compact_terrain_variant("paving")
	var repeat_m := paving.pattern_size_m if paving != null else 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b6a592")
	material.roughness = 0.95
	if paving != null:
		material.albedo_texture = paving.albedo_texture
	strip.set_material(material)
	for row in count:
		for column in 2:
			for vertex in [Vector2i(column,row), Vector2i(column,row+1), Vector2i(column+1,row+1),
					Vector2i(column,row), Vector2i(column+1,row+1), Vector2i(column+1,row)]:
				var point: Vector3 = rows[vertex.y][vertex.x]
				strip.set_normal(Vector3.UP)
				strip.set_uv(Vector2(point.x, point.z) / (tile * repeat_m))
				strip.add_vertex(point - fence.position + Vector3.UP * tile * 0.022)
	var approach := MeshInstance3D.new()
	approach.name = "Approach"
	approach.mesh = strip.commit()
	approach.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fence.add_child(approach)
	var gate := StaticBody3D.new()
	gate.name = "Gate"
	fence.add_child(gate)
	var posts := StandardMaterial3D.new()
	posts.albedo_color = Color("8b715b")
	posts.roughness = 0.9
	for sign_value in [-1.0, 1.0]:
		var foot: Vector3 = surface.call(path[0] + side * sign_value * (GAP_M * 0.5 + 0.08))
		if not foot.is_finite():
			fence.free()
			return null
		var point := (foot - fence.position) / tile
		add_wall_box(gate, "GatePost", point + Vector3(-0.08, 0.0, -0.08), point + Vector3(0.08, 1.18, 0.08), posts, tile)
	return fence


static func make_surface_road(region: Dictionary, sample: Callable, tile: float, place := Callable()) -> Dictionary:
	var curve := preload("res://scripts/prototypes/ember_terrain_plan_math.gd").path_curve(region.points_m)
	var length := curve.get_baked_length()
	if length < 1.0 or length > 32.0:
		return {"error": "Первый маршрут по уступу должен быть длиной от 1 до 32 м."}
	var columns := maxi(2, ceili(float(region.parameters.width_m) / 0.25))
	var rows := ceili(length / 0.125)
	var half_width := float(region.parameters.width_m) * 0.5
	var vertices := PackedVector3Array()
	var heights := PackedFloat32Array()
	var water := PackedFloat32Array()
	var kinds := PackedByteArray()
	var cross_sections := PackedByteArray()
	var steps := PackedInt32Array()
	var on_ledge := false
	var stride := columns + 1
	for row in range(rows + 1):
		var station := length * float(row) / rows
		var frame := _bridge_path_frame(curve, station)
		var full_width := true
		var cut_edge := false
		for col in range(columns + 1):
			var hit: Dictionary = sample.call(frame.origin - frame.x * lerpf(-half_width, half_width, float(col) / columns))
			var dry: bool = hit.get("solid", false) and not hit.get("submerged", false)
			var point: Vector3 = hit.position if dry else Vector3.INF
			water.append(hit.get("road_water_y", -INF))
			full_width = full_width and dry
			if dry and row > 0 and absf(point.y - vertices[-stride].y) > tile * 0.16 and vertices[-stride].is_finite() and (steps.is_empty() or steps[-1] != row):
				steps.append(row)
			if dry and col > 0 and vertices[-1].is_finite() and absf(point.y - vertices[-1].y) > tile * 0.18:
				cut_edge = true
			if col == columns / 2:
				var floor_point: Vector3 = hit.get("position", Vector3.INF)
				var kind := RoadSupport.WATER if hit.get("submerged", false) else RoadSupport.VOID if not dry else RoadSupport.LEDGE if hit.has("object") else RoadSupport.GROUND
				heights.append(INF if kind == RoadSupport.VOID else floor_point.y / tile)
				kinds.append(kind)
			vertices.append(point)
			on_ledge = on_ledge or (dry and hit.has("object"))
		cross_sections.append(1 if full_width and not cut_edge else 0)
	var spans := _surface_road_spans(heights, kinds, cross_sections, steps, length / rows)
	var result := {"profile": {"length": length, "heights": heights, "kinds": kinds,
		"cross_sections": cross_sections, "steps": steps, "spans": spans}}
	if region.get("bridge_over_gap", false):
		if spans.size() != 1:
			result.error = "Для примерки нужен один пролёт с двумя сухими въездами."
			return result
		var bridge := _surface_road_bridge(region, curve, vertices, water, cross_sections, steps, spans[0], stride, length / rows, tile, sample, place)
		if bridge.has("deck"):
			result.profile.deck = bridge.deck
			bridge.erase("deck")
		result.merge(bridge)
		return result
	var error := ""
	if not spans.is_empty():
		error = "На линии есть разрыв. Проверьте предложенный пролёт на профиле."
	elif kinds[0] in [RoadSupport.VOID, RoadSupport.WATER] or kinds[-1] in [RoadSupport.VOID, RoadSupport.WATER]:
		error = "Один из концов линии без сухой опоры. Продлите линию до земли."
	elif cross_sections.has(0):
		error = "Под всей шириной дороги нужна сухая опора. Проверьте отмеченные участки."
	elif not steps.is_empty():
		error = "На пути ступень. Сгладьте въезд или измените линию."
	elif not on_ledge:
		error = "Линия должна выходить на выбранный уступ."
	if not error.is_empty():
		result.error = error
		return result
	result.node = _surface_road_strip(region, vertices, stride, 0, rows, tile)
	return result


static func _surface_road_strip(region: Dictionary, vertices: PackedVector3Array, stride: int, first: int, last: int, tile: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "SurfaceRoad"
	node.position = vertices[first * stride]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta(SURFACE_ROAD_META, region.id)
	var strip := SurfaceTool.new()
	strip.begin(Mesh.PRIMITIVE_TRIANGLES)
	strip.set_material(_street_bridge_deck_material(region.parameters.get("surface", "paving"), tile))
	for index in range(first * stride, (last + 1) * stride):
		strip.set_normal(Vector3.UP)
		strip.add_vertex(vertices[index] - node.position + Vector3.UP * tile / 16.0)
	for row in last - first:
		for col in stride - 1:
			var a := row * stride + col
			for index in [a, a + stride, a + stride + 1, a, a + stride + 1, a + 1]:
				strip.add_index(index)
	node.mesh = strip.commit()
	return node


static func _surface_road_bridge(region: Dictionary, curve: Curve2D, vertices: PackedVector3Array, water: PackedFloat32Array,
		sections: PackedByteArray, steps: PackedInt32Array, span: Vector2i, stride: int, spacing: float, tile: float, sample: Callable, place: Callable) -> Dictionary:
	var ends := PackedInt32Array()
	var anchors := PackedVector3Array()
	var margin := ceili(0.5 / spacing)
	var max_search := ceili(2.0 / spacing)
	for side in [-1, 1]:
		var shore := span.x if side == -1 else span.y
		for offset in range(margin, max_search + 1):
			var row: int = shore + offset * side
			var outer: int = row + margin * side
			if mini(row, outer) < 0 or maxi(row, outer) >= sections.size():
				break
			var low := INF
			var high := -INF
			for probe in range(mini(row, outer), maxi(row, outer) + 1):
				if sections[probe] == 0:
					high = INF
					break
				for col in stride:
					var y := vertices[probe * stride + col].y
					low = minf(low, y)
					high = maxf(high, y)
			if high - low > tile * 0.10:
				continue
			var bank := (vertices[row * stride] + vertices[row * stride + stride - 1]) * 0.5
			bank.y = low - tile * 0.015
			ends.append(row)
			anchors.append(bank)
			break
	if ends.size() != 2:
		return {"error": "Удлините линию до ровного сухого места по обе стороны разрыва."}
	var first := ends[0]
	var last := ends[1]
	var axis_start := curve.sample_baked(first * spacing)
	var axis_end := curve.sample_baked(last * spacing)
	var metres := (last - first) * spacing
	if metres < 2.0 or absf(anchors[1].y - anchors[0].y) > tile * metres * 0.2:
		return {"error": "Въезды моста слишком близко или сильно различаются по высоте."}
	var rise := float(region.get("bridge_rise_m", 0.0)) * tile
	var width: float = region.parameters.width_m
	var curved := false
	var previous_frame := _bridge_path_frame(curve, first * spacing)
	var chord_direction := axis_start.direction_to(axis_end)
	var deck_heights := PackedFloat32Array()
	for row in range(first, last + 1):
		var t := float(row - first) / (last - first)
		var height := _bridge_height(anchors[0].y, anchors[1].y, rise, t)
		if not deck_heights.is_empty() and absf(height / tile - deck_heights[-1]) > 0.30 * metres / (last - first):
			return {"error": "Дуга слишком крутая. Уменьшите подъём или удлините пролёт."}
		deck_heights.append(height / tile)
	for row in sections.size():
		if row < first or row > last:
			if sections[row] == 0 or steps.has(row):
				return {"error": "За пределами моста остался неподдержанный участок дороги."}
			continue
		var frame := _bridge_path_frame(curve, row * spacing)
		curved = curved or Geometry2D.get_closest_point_to_segment(frame.origin, axis_start, axis_end).distance_to(frame.origin) > 0.005
		if frame.y.dot(chord_direction) < 0.2:
			return {"error": "Пролёт разворачивается обратно. Наметьте более плавный изгиб."}
		if row > first:
			var advance := (frame.origin - previous_frame.origin).dot(frame.y)
			var edge_turn := absf((frame.x - previous_frame.x).dot(frame.y)) * width * 0.5
			if advance - edge_turn < spacing * 0.2:
				return {"error": "Для такой ширины поворот слишком тесный. Разнесите точки линии."}
		previous_frame = frame
		var deck := deck_heights[row - first] * tile
		for col in stride:
			var index := row * stride + col
			if vertices[index].is_finite() and vertices[index].y > deck + tile * 0.12:
				return {"error": "Настил пересекает берег. Измените линию моста."}
			if water[index] > deck - tile * 0.08:
				return {"error": "Настил слишком близко к воде. Выберите въезды повыше."}
	var path_frame := func(z: float) -> Transform2D:
		return _bridge_path_frame(curve, first * spacing + z)
	var local_frame := func(z: float) -> Transform3D:
		var path: Transform2D = path_frame.call(z)
		var center: Vector3 = _bridge_place(path.origin, tile, place)
		var across := _bridge_place(path.origin + path.x, tile, place) - center
		center -= anchors[0]
		center.y = 0.0
		across.y = 0.0
		across = across.normalized()
		return Transform3D(Basis(across, Vector3.UP, across.cross(Vector3.UP)), center)
	var supports: MeshInstance3D
	var support_style: String = region.get("bridge_supports", "none")
	if support_style != "none":
		var gap := Vector2(span.x - first, span.y - first) * spacing
		var footings := _make_bridge_supports(support_style, anchors, metres, gap, rise, width, tile, sample, path_frame, local_frame)
		if footings.has("error"):
			return footings
		supports = footings.node
	var assembly := Node3D.new()
	assembly.name = "SurfaceRoad"
	assembly.set_meta(SURFACE_ROAD_META, region.id)
	var covering: String = region.parameters.get("surface", "paving")
	var railing: String = region.get("bridge_railing", "stone")
	var planks := region.has("bridge_plank_roughness")
	var stations: Array[Transform3D] = []
	if curved or rise > 0.0 or planks:
		for index in deck_heights.size():
			var station: Transform3D = local_frame.call(index * spacing)
			station.origin.y = deck_heights[index] * tile - anchors[0].y
			stations.append(station)
	var seam := Vector2i(span.x + 1, span.y - 1)
	var plank_stations: Array[Transform3D] = []
	if planks:
		plank_stations = stations.slice(seam.x - first, seam.y - first + 1)
	var bridge: StaticBody3D
	if curved or rise > 0.0:
		bridge = _make_profiled_bridge(anchors[0], stations, spacing, width, covering, tile, railing, plank_stations)
	elif planks:
		bridge = _make_straight_bridge_deck(anchors[0], anchors[1], width, tile)
		# Keep the straight collision deck, but lay out the rails in the same
		# upright frames as the boards, including on a sloped bridge.
		var plank_to_bridge := bridge.transform.affine_inverse() * Transform3D(Basis.IDENTITY, anchors[0])
		var rail_stations: Array[Transform3D] = []
		for station in plank_stations:
			rail_stations.append(plank_to_bridge * station)
		_add_profile_bridge_rails(bridge, rail_stations, spacing, width, tile, railing, 0.0)
	else:
		bridge = make_street_bridge(anchors[0], anchors[1], width, tile, "stone", {"deck":covering, "rail":railing, "trimmed_stone":true})
	assembly.add_child(bridge)
	if supports != null:
		assembly.add_child(supports)
	# Carry the paving onto each dry end of the deck. Its collision stays in
	# the existing deck and terrain, so the visible join adds no raised edge.
	var paving_ends := Vector2i(first, last)
	for offset in range(1, ceili(0.25 / spacing) + 1):
		if paving_ends.x == first + offset - 1 and first + offset < span.x and sections[first + offset] == 1:
			paving_ends.x = first + offset
		if paving_ends.y == last - offset + 1 and last - offset > span.y and sections[last - offset] == 1:
			paving_ends.y = last - offset
	if planks:
		# The two finishes share one cross-section instead of overlapping.
		# Keep the stone through the bank, then land it on the timber height.
		for row in range(paving_ends.x, seam.x + 1):
			_set_bridge_seam_ring(vertices, row, stride, stations[row - first], anchors[0], width, tile)
		for row in range(seam.y, paving_ends.y + 1):
			_set_bridge_seam_ring(vertices, row, stride, stations[row - first], anchors[0], width, tile)
		paving_ends = seam
		bridge.get_node("Deck").hide()
		var timber := _make_bridge_planks(plank_stations, spacing, width, tile,
			float(region.bridge_plank_roughness), String(region.id).hash())
		timber.position = anchors[0]
		assembly.add_child(timber)
	for run in [Vector2i(0, paving_ends.x), Vector2i(paving_ends.y, sections.size() - 1)]:
		var approach := _surface_road_strip(region, vertices, stride, run.x, run.y, tile)
		approach.remove_meta(SURFACE_ROAD_META)
		assembly.add_child(approach, true)
	return {"node": assembly, "deck": {"rows": Vector2i(first, last), "heights": deck_heights}}


static func _set_bridge_seam_ring(vertices: PackedVector3Array, row: int, stride: int, station: Transform3D, origin: Vector3, width: float, tile: float) -> void:
	for column in stride:
		var across := (0.5 - float(column) / (stride - 1)) * width * tile
		# The road strip adds a visual offset above its input vertices.
		vertices[row * stride + column] = origin + station * Vector3(across, -tile / 16.0, 0.0)


static func _bridge_path_frame(curve: Curve2D, station: float) -> Transform2D:
	var center := curve.sample_baked(station)
	var tangent := curve.sample_baked(maxf(0, station - 0.25)).direction_to(curve.sample_baked(minf(curve.get_baked_length(), station + 0.25)))
	return Transform2D(Vector2(tangent.y, -tangent.x), tangent, center)


static func _bridge_place(point: Vector2, tile: float, place: Callable) -> Vector3:
	return place.call(point) if place.is_valid() else Vector3(point.x, 0.0, point.y) * tile


static func _make_bridge_supports(style: String, anchors: PackedVector3Array, length: float,
		gap: Vector2, rise: float, width: float, tile: float, sample: Callable, path_frame: Callable, local_frame: Callable) -> Dictionary:
	var footing := func(x: float, z: float, footprint: Vector2) -> float:
		var frame: Transform2D = path_frame.call(z)
		var height := INF
		for offset in [Vector2.ZERO, footprint, -footprint, Vector2(footprint.x, -footprint.y), Vector2(-footprint.x, footprint.y)]:
			var hit: Dictionary = sample.call(frame * (Vector2(x, 0.0) + offset))
			if not hit.get("solid", false):
				return INF
			height = minf(height, (hit.position.y - anchors[0].y) / tile)
		return height - 0.08
	var soffit := func(z: float) -> float:
		return (_bridge_height(anchors[0].y, anchors[1].y, rise, z / length) - anchors[0].y) / tile - 0.12
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_smooth_group(-1)
	mesh.set_material(wall_material(Color("77523b")) if style == "wood" else wall_finish(Color("d4c5b1"), 2, tile))
	var span := gap.y - gap.x
	if style == "arch":
		var arch_error := _add_bridge_support_arches(mesh, gap, width, tile, footing, soffit, local_frame)
		if not arch_error.is_empty():
			return {"error": arch_error}
	else:
		var piers := maxi(1, roundi(span / 3.0))
		for index in piers:
			var z := lerpf(gap.x, gap.y, float(index + 1) / (piers + 1))
			var frame: Transform3D = local_frame.call(z)
			var top: float = soffit.call(z)
			var pier_width := width * 0.62 if style == "stone" else 0.22
			var depth := 0.55 if style == "stone" else 0.24
			for x: float in [-width * 0.31, width * 0.31] if style == "wood" else [0.0]:
				var bottom: float = footing.call(x, z, Vector2(pier_width, depth) * 0.5)
				if not is_finite(bottom) or top - bottom < 0.15:
					return {"error": "Под опорой нет подходящего твёрдого дна."}
				_add_bridge_support_box(mesh, frame, x, pier_width, depth, bottom, top, tile)
			_add_bridge_support_box(mesh, frame, 0.0, width * 0.88, depth + 0.12, top - 0.20, top, tile)
	mesh.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "BridgeSupports"
	node.mesh = mesh.commit()
	node.position = anchors[0]
	return {"node": node}


static func _add_bridge_support_box(mesh: SurfaceTool, frame: Transform3D, x: float, width: float, depth: float, bottom: float, top: float, tile: float) -> void:
	var low := Vector3(x - width * 0.5, bottom, -depth * 0.5) * tile
	var high := Vector3(x + width * 0.5, top, depth * 0.5) * tile
	var a := frame * low
	var b := frame * Vector3(high.x, low.y, low.z)
	var c := frame * Vector3(high.x, high.y, low.z)
	var d := frame * Vector3(low.x, high.y, low.z)
	var dz := frame.basis.z * depth * tile
	add_arc_quad(mesh, a, b, c, d)
	add_arc_quad(mesh, d + dz, c + dz, b + dz, a + dz)
	add_arc_quad(mesh, a, a + dz, b + dz, b)
	add_arc_quad(mesh, b, b + dz, c + dz, c)
	add_arc_quad(mesh, c, c + dz, d + dz, d)
	add_arc_quad(mesh, d, d + dz, a + dz, a)


static func _add_bridge_support_arches(mesh: SurfaceTool, gap: Vector2, width: float, tile: float, footing: Callable, soffit: Callable, local_frame: Callable) -> String:
	var span := gap.y - gap.x
	if span < 1.5:
		return "Для каменной арки нужен пролёт от 1,5 м."
	var arches := clampi(roundi(span / 3.5), 1, 6)
	var half := width * 0.42
	var pier_depth := 0.46
	var feet := PackedFloat32Array()
	for index in range(arches + 1):
		var z := lerpf(gap.x, gap.y, float(index) / arches)
		var bottom: float = footing.call(0.0, z, Vector2(half, pier_depth * 0.5))
		var top: float = soffit.call(z)
		if not is_finite(bottom) or top - bottom < 0.25:
			return "Для каменных арок нужно больше места между дном и настилом."
		feet.append(bottom)
		_add_bridge_support_box(mesh, local_frame.call(z), 0.0, half * 2.0, pier_depth, bottom, top, tile)
	for index in arches:
		var start := gap.x + index * span / arches + pier_depth * 0.40
		var end := gap.x + (index + 1) * span / arches - pier_depth * 0.40
		var crown: float = soffit.call((start + end) * 0.5) - 0.14
		if crown - maxf(feet[index], feet[index + 1]) < 0.25:
			return "Для каменной арки мало места под настилом. Поднимите дугу или выберите стойки."
		var previous := PackedVector3Array()
		for row in range(13):
			var t := float(row) / 12.0
			var z := lerpf(start, end, t)
			var top: float = soffit.call(z)
			var spring := lerpf(feet[index], feet[index + 1], t)
			var bottom := minf(top - 0.10, lerpf(spring, crown, sqrt(4.0 * t * (1.0 - t))))
			var frame: Transform3D = local_frame.call(z)
			var section := PackedVector3Array([frame * (Vector3(-half, bottom, 0) * tile), frame * (Vector3(half, bottom, 0) * tile),
				frame * (Vector3(half, top, 0) * tile), frame * (Vector3(-half, top, 0) * tile)])
			for edge in 4 if row > 0 else 0:
				var next := (edge + 1) % 4
				add_arc_quad(mesh, previous[edge], section[edge], section[next], previous[next])
			previous = section
	return ""


static func _bridge_height(start: float, end: float, rise: float, t: float) -> float:
	# The arch adds zero height and zero slope at both dry entries.
	var hump := 4.0 * t * (1.0 - t)
	return lerpf(start, end, t) + rise * hump * hump


static func _make_profiled_bridge(start: Vector3, stations: Array[Transform3D], spacing: float, width: float, covering: String, tile: float, railing: String, plank_stations: Array[Transform3D]) -> StaticBody3D:
	var bridge := StaticBody3D.new()
	bridge.name = "StreetBridge"
	bridge.position = start
	var half := width * tile * 0.5
	_add_arch_strip(bridge, "Deck", stations, Rect2(-half, -0.18 * tile, 2.0 * half, 0.18 * tile), _street_bridge_deck_material(covering, tile))
	if plank_stations.is_empty():
		_add_profile_bridge_rails(bridge, stations, spacing, width, tile, railing, 0.3)
	else:
		_add_profile_bridge_rails(bridge, plank_stations, spacing, width, tile, railing, 0.0)
	return bridge


static func _add_profile_bridge_rails(bridge: StaticBody3D, stations: Array[Transform3D], spacing: float, width: float, tile: float, railing: String, inset_m: float) -> void:
	var half := width * tile * 0.5
	var stone := wall_finish(Color("a89885"), 1, tile)
	var cap := wall_material(Color("cbbca9"))
	var timber := wall_material(Color("79563d"))
	var inset := inset_m / spacing
	for side in [-1, 1]:
		var edge: float = side * (half - 0.075 * tile)
		var name := "Left" if side < 0 else "Right"
		_add_arch_strip(bridge, name + "Guard", stations, Rect2(edge - 0.065 * tile, 0, 0.13 * tile, 0.84 * tile), null, inset, true, false)
		if railing == "lattice":
			_add_arch_strip(bridge, name + "Handrail", stations, Rect2(edge - 0.065 * tile, 0.74 * tile, 0.13 * tile, 0.10 * tile), timber, inset, false)
			_add_arch_strip(bridge, name + "LowerBeam", stations, Rect2(edge - 0.042 * tile, 0.10 * tile, 0.084 * tile, 0.08 * tile), timber, inset, false)
			_add_profile_bridge_lattice(bridge, name, stations, edge, spacing, tile, timber, inset_m)
		else:
			_add_arch_strip(bridge, name + "Parapet", stations, Rect2(edge - 0.061 * tile, 0, 0.122 * tile, 0.70 * tile), stone, inset, false)
			_add_arch_strip(bridge, name + "Coping", stations, Rect2(edge - 0.084 * tile, 0.70 * tile, 0.168 * tile, 0.11 * tile), cap, inset, false)


static func _add_profile_bridge_lattice(bridge: StaticBody3D, label: String, stations: Array[Transform3D], edge: float, spacing: float, tile: float, material: Material, inset_m: float) -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	var length := (stations.size() - 1) * spacing
	var post_half_depth := 0.07
	var flush := is_zero_approx(inset_m)
	var post_inset := post_half_depth if flush else inset_m
	var ends := Vector2(post_inset, length - post_inset)
	var point_at := func(z: float, height: float) -> Vector3:
		return _bridge_station_at(stations, z / spacing) * Vector3(edge, height * tile, 0)
	_append_bridge_cross_braces(mesh, box, ends, tile, point_at, 0.76)
	var bays := maxi(1, ceili((ends.y - ends.x) / 2.1))
	for index in range(bays + 1):
		var z := lerpf(ends.x, ends.y, float(index) / bays)
		var frame := _bridge_station_at(stations, z / spacing)
		var depth_offset := 0.0
		if flush and (index == 0 or index == bays):
			# Set the end post face on the seam plane even on a bend.
			frame = stations[0] if index == 0 else stations[-1]
			depth_offset = post_half_depth * tile * (1.0 if index == 0 else -1.0)
		mesh.append_from(box, 0, Transform3D(frame.basis.scaled_local(Vector3(0.13, 0.90, post_half_depth * 2.0) * tile),
			frame * Vector3(edge, 0.41 * tile, depth_offset)))
	var visual := MeshInstance3D.new()
	visual.name = label + "TimberLattice"
	visual.mesh = mesh.commit()
	visual.material_override = material
	bridge.add_child(visual)


static func _bridge_station_at(stations: Array[Transform3D], offset: float) -> Transform3D:
	var index := mini(floori(offset), stations.size() - 2)
	return stations[index].interpolate_with(stations[index + 1], offset - index)


static func _make_bridge_planks(stations: Array[Transform3D], spacing: float, width: float, tile: float, roughness: float, seed_value: int) -> MeshInstance3D:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_smooth_group(-1)
	var material := wall_material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	mesh.set_material(material)
	var length := spacing * (stations.size() - 1)
	var count := maxi(2, roundi(length / 0.25))
	var pitch := length / count
	var half := width * 0.5
	for board in count:
		var a := _bridge_station_at(stations, (board * pitch + (0.022 if board > 0 else 0.0)) / spacing)
		var b := _bridge_station_at(stations, ((board + 1) * pitch - (0.022 if board < count - 1 else 0.0)) / spacing)
		var variation := roughness if board > 0 and board < count - 1 else 0.0
		var yaw := random.randf_range(-0.016, 0.016) / half * variation
		var lift := random.randf_range(-0.012, 0.012) * variation
		var bow := random.randf_range(-0.014, 0.018) * variation
		var tone := Color("9b6c46").lerp(Color("c69362"), random.randf())
		mesh.set_color(tone.srgb_to_linear())
		var front := _bridge_plank_end(a, half, yaw, lift, bow, tile)
		var back := _bridge_plank_end(b, half, yaw, lift, bow, tile)
		for edge in front.size():
			var next := (edge + 1) % front.size()
			add_arc_quad(mesh, front[edge], back[edge], back[next], front[next])
		add_arc_quad(mesh, front[0], front[1], front[4], front[5])
		add_arc_quad(mesh, front[1], front[2], front[3], front[4])
		add_arc_quad(mesh, back[5], back[4], back[1], back[0])
		add_arc_quad(mesh, back[4], back[3], back[2], back[1])
	mesh.set_color(Color("68462f").srgb_to_linear())
	for x in [-half * 0.58, half * 0.58]:
		var beam := [Vector3(x - 0.07, -0.22, 0) * tile, Vector3(x + 0.07, -0.22, 0) * tile,
			Vector3(x + 0.07, -0.065, 0) * tile, Vector3(x - 0.07, -0.065, 0) * tile]
		for row in range(1, stations.size()):
			for edge in 4:
				var p: Vector3 = beam[edge]
				var q: Vector3 = beam[(edge + 1) % 4]
				add_arc_quad(mesh, stations[row - 1] * p, stations[row] * p, stations[row] * q, stations[row - 1] * q)
	mesh.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "BridgePlanks"
	node.mesh = mesh.commit()
	return node


static func _bridge_plank_end(frame: Transform3D, half: float, yaw: float, lift: float, bow: float, tile: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in 6:
		var across := float(index if index < 3 else 5 - index)
		var x := (across - 1.0) * half
		var y := lift + (bow if is_zero_approx(x) else 0.0) - (0.085 if index < 3 else 0.0)
		points.append(frame * (Vector3(x, y, x * yaw) * tile))
	return points


static func _add_arch_strip(body: StaticBody3D, label: String, stations: Array[Transform3D], section: Rect2, material: Material, inset := 0.0, collidable := true, visible := true) -> void:
	var cross_section := [Vector3(section.position.x, section.position.y, 0), Vector3(section.end.x, section.position.y, 0),
		Vector3(section.end.x, section.end.y, 0), Vector3(section.position.x, section.end.y, 0)]
	var strip := SurfaceTool.new()
	strip.begin(Mesh.PRIMITIVE_TRIANGLES)
	strip.set_smooth_group(-1)
	strip.set_material(material)
	var first := floori(inset)
	var last := ceili(stations.size() - 1 - inset)
	var start := stations[first].interpolate_with(stations[first + 1], inset - first)
	var end := stations[last].interpolate_with(stations[last - 1], last - (stations.size() - 1 - inset))
	for row in range(first + 1, last + 1):
		var a := start if row == first + 1 else stations[row - 1]
		var b := end if row == last else stations[row]
		for edge in 4:
			var p: Vector3 = cross_section[edge]
			var q: Vector3 = cross_section[(edge + 1) % 4]
			add_arc_quad(strip, a * p, b * p, b * q, a * q)
	add_arc_quad(strip, start * cross_section[0], start * cross_section[1], start * cross_section[2], start * cross_section[3])
	add_arc_quad(strip, end * cross_section[3], end * cross_section[2], end * cross_section[1], end * cross_section[0])
	strip.generate_normals()
	var mesh := strip.commit()
	if visible:
		var visual := MeshInstance3D.new()
		visual.name = label
		visual.mesh = mesh
		body.add_child(visual)
	if collidable:
		var collision := CollisionShape3D.new()
		collision.name = label + "Shape"
		collision.shape = mesh.create_trimesh_shape()
		body.add_child(collision)


static func _surface_road_spans(heights: PackedFloat32Array, kinds: PackedByteArray, sections: PackedByteArray, steps: PackedInt32Array, spacing: float) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var left := -1
	for row in kinds.size():
		if kinds[row] in [RoadSupport.VOID, RoadSupport.WATER]:
			if left < 0:
				left = row
		elif left >= 0:
			candidates.append(Vector2i(left - 1, row))
			left = -1
	for index in range(1, steps.size()):
		var drop := steps[index - 1]
		var rise := steps[index]
		if heights[drop - 1] - heights[drop] > 0.16 and heights[rise] - heights[rise - 1] > 0.16:
			candidates.append(Vector2i(drop - 1, rise))
	var spans: Array[Vector2i] = []
	for candidate in candidates:
		var span := candidate
		var shore_search := ceili(1.0 / spacing)
		# A diagonal shoreline may be dry at the centre before it is dry
		# across the deck. Look just beyond it for the first full bank.
		while span.x >= 0 and sections[span.x] == 0 and candidate.x - span.x < shore_search:
			span.x -= 1
		while span.y < sections.size() and sections[span.y] == 0 and span.y - candidate.y < shore_search:
			span.y += 1
		var metres := (span.y - span.x) * spacing
		if span.x < 0 or span.y >= sections.size() or sections[span.x] == 0 or sections[span.y] == 0 or metres < 0.5:
			continue
		if absf(heights[span.y] - heights[span.x]) <= 0.25 * metres and not spans.has(span):
			spans.append(span)
	spans.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	return spans


static func _make_straight_bridge_deck(start: Vector3, end: Vector3, width_m: float, tile: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "StreetBridge"
	body.position = (start + end) * 0.5
	var forward := start.direction_to(end)
	var side := Vector3.UP.cross(forward).normalized()
	body.basis = Basis(side, forward.cross(side), forward)
	var half_length := start.distance_to(end) / (2.0 * tile)
	var half_width := width_m * 0.5
	add_wall_box(body, "Deck", Vector3(-half_width, -0.18, -half_length),
		Vector3(half_width, 0.0, half_length), null, tile)
	return body


static func make_street_bridge(start: Vector3, end: Vector3, width_m: float, tile: float, style := "wood", options := {}) -> StaticBody3D:
	var body := _make_straight_bridge_deck(start, end, width_m, tile)
	var half_length := start.distance_to(end) / (2.0 * tile)
	var half_width := width_m * 0.5
	var rail_length := half_length - 0.3
	for edge in [-half_width + 0.07, half_width - 0.07]:
		var guard := BoxShape3D.new()
		guard.size = Vector3(0.13, 0.96, rail_length * 2.0) * tile
		var barrier := CollisionShape3D.new()
		barrier.name = "SideGuard"
		barrier.shape = guard
		barrier.position = Vector3(edge, 0.48, 0.0) * tile
		body.add_child(barrier, true)
	style_street_bridge(body, style, tile, options)
	return body


static func style_street_bridge(body: StaticBody3D, style: String, tile: float, options := {}) -> bool:
	var deck := body.get_node_or_null("DeckShape") as CollisionShape3D
	if deck == null or not deck.shape is BoxShape3D or style not in ["wood", "stone", "broken"]:
		return false
	var size: Vector3 = deck.shape.size / tile
	var half_length := size.z * 0.5
	var legacy := not body.has_meta(BRIDGE_STYLE_META)
	var broken := style == "broken"
	var material_style: String = body.get_meta(BRIDGE_MATERIAL_META, body.get_meta(BRIDGE_STYLE_META, "wood")) if broken else style
	var covering: String = options.get("deck", "preset")
	var railing: String = options.get("rail", "preset")
	if covering == "preset":
		covering = body.get_meta(BRIDGE_DECK_META, material_style) if broken else material_style
	if railing == "preset":
		railing = body.get_meta(BRIDGE_RAIL_META, material_style) if broken else material_style
	for child in body.get_children():
		if child.has_meta(BRIDGE_STYLE_META):
			body.remove_child(child)
			child.free()
			continue
		if child is CollisionShape3D and child.name in [&"DeckShape", &"SideGuard", &"SideGuard2"]:
			child.disabled = broken
		if child is not MeshInstance3D:
			continue
		# Packed scenes and duplicate() can use different spellings for old
		# automatically named posts and rails.
		var part_name := String(child.name)
		var old_box: bool = legacy and child.mesh is BoxMesh and (child.name in [&"Deck", &"Handrail", &"Post", &"Stringer"]
			or part_name.trim_prefix("@MeshInstance3D@").is_valid_int()
			or part_name.trim_prefix("_MeshInstance3D_").is_valid_int())
		if old_box:
			body.remove_child(child)
			child.free()
	var surface := _street_bridge_deck_material(covering, tile)
	if broken:
		var gap := minf(half_length - 0.3, maxf(1.25, half_length * 0.55))
		_add_street_bridge_span(body, size, Vector2(-half_length, -gap), tile, surface, railing, true)
		_add_street_bridge_span(body, size, Vector2(gap, half_length), tile, surface, railing, true)
		body.set_meta(BRIDGE_MATERIAL_META, material_style)
	else:
		_add_street_bridge_span(body, size, Vector2(-half_length, half_length), tile, surface, railing, false, options.get("trimmed_stone", false))
		body.remove_meta(BRIDGE_MATERIAL_META)
	body.set_meta(BRIDGE_STYLE_META, style)
	body.set_meta(BRIDGE_DECK_META, covering)
	body.set_meta(BRIDGE_RAIL_META, railing)
	return true


static func _street_bridge_deck_material(covering: String, tile: float) -> StandardMaterial3D:
	if covering == "stone":
		return wall_finish(Color("d4c5b1"), 2, tile)
	if covering == "paving":
		var paving := EmberVoxelSurfaceMaterials.load_compact_terrain_variant("paving")
		if paving != null and paving.albedo_texture != null:
			var material := wall_material(Color.WHITE)
			material.albedo_texture = paving.albedo_texture
			material.uv1_triplanar = true
			material.uv1_world_triplanar = true
			material.uv1_triplanar_sharpness = 8.0
			material.uv1_scale = Vector3.ONE / (tile * paving.pattern_size_m)
			return material
	return wall_material(Color("a07a57"))


static func _add_street_bridge_span(body: StaticBody3D, size: Vector3, span: Vector2, tile: float, surface: Material, railing: String, broken: bool, trimmed_stone := false) -> void:
	var half_width := size.x * 0.5
	var deck := add_wall_box(body, "Deck", Vector3(-half_width, -size.y, span.x),
		Vector3(half_width, 0.0, span.y), surface, tile, broken)
	deck.set_meta(BRIDGE_STYLE_META, true)
	if broken:
		body.get_child(-1).set_meta(BRIDGE_STYLE_META, true)
	var rail := span + Vector2(0.3, -0.3)
	if broken:
		var inner_inset := minf(0.12, (span.y - span.x) * 0.25)
		if span.y < 0.0:
			rail = Vector2(span.x + minf(0.3, (span.y - span.x) * 0.3), span.y - inner_inset)
		else:
			rail = Vector2(span.x + inner_inset, span.y - minf(0.3, (span.y - span.x) * 0.3))
	var bays := maxi(1, ceili((rail.y - rail.x) / 2.2))
	var stone := railing == "stone"
	var trim := wall_finish(Color("a89885") if trimmed_stone else Color("b7a68e"), 1, tile) if stone else wall_material(Color("654a38"))
	for edge in [-half_width + 0.07, half_width - 0.07]:
		if broken:
			var guard := BoxShape3D.new()
			guard.size = Vector3(0.13, 0.96, rail.y - rail.x) * tile
			var barrier := CollisionShape3D.new()
			barrier.name = "BrokenSideGuard"
			barrier.shape = guard
			barrier.position = Vector3(edge, 0.48, (rail.x + rail.y) * 0.5) * tile
			barrier.set_meta(BRIDGE_STYLE_META, true)
			body.add_child(barrier, true)
		if stone:
			var wall_top := 0.70 if trimmed_stone else 0.82
			var cap_top := 0.81 if trimmed_stone else 0.96
			var cap_half := 0.084 if trimmed_stone else 0.07
			var cap := wall_material(Color("cbbca9")) if trimmed_stone else trim
			add_wall_box(body, "Parapet", Vector3(edge - 0.065, 0.0, rail.x),
				Vector3(edge + 0.065, wall_top, rail.y), trim, tile, false).set_meta(BRIDGE_STYLE_META, true)
			add_wall_box(body, "Coping", Vector3(edge - cap_half, wall_top, rail.x),
				Vector3(edge + cap_half, cap_top, rail.y), cap, tile, false).set_meta(BRIDGE_STYLE_META, true)
			add_wall_box(body, "StoneBand", Vector3(edge - 0.07, -0.34, span.x),
				Vector3(edge + 0.07, -size.y, span.y), trim, tile, false).set_meta(BRIDGE_STYLE_META, true)
			continue
		add_wall_box(body, "Handrail", Vector3(edge - 0.065, 0.83, rail.x),
			Vector3(edge + 0.065, 0.96, rail.y), trim, tile, false).set_meta(BRIDGE_STYLE_META, true)
		if railing == "lattice":
			_add_bridge_lattice(body, edge, rail, tile, trim)
		for bay in range(bays + 1):
			var z := lerpf(rail.x, rail.y, float(bay) / bays)
			add_wall_box(body, "Post", Vector3(edge - 0.085, -0.22, z - 0.085),
				Vector3(edge + 0.085, 1.02, z + 0.085), trim, tile, false).set_meta(BRIDGE_STYLE_META, true)
		add_wall_box(body, "Stringer", Vector3(edge - 0.12, -0.37, span.x),
			Vector3(edge + 0.12, -size.y, span.y), trim, tile, false).set_meta(BRIDGE_STYLE_META, true)


static func _add_bridge_lattice(body: StaticBody3D, edge: float, rail: Vector2, tile: float, material: Material) -> void:
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	var point_at := func(z: float, height: float) -> Vector3:
		return Vector3(edge, height, z) * tile
	_append_bridge_cross_braces(bars, box, rail, tile, point_at)
	var lattice := MeshInstance3D.new()
	lattice.name = "TimberLattice"
	lattice.mesh = bars.commit()
	lattice.material_override = material
	lattice.set_meta(BRIDGE_STYLE_META, true)
	body.add_child(lattice, true)


static func _append_bridge_cross_braces(bars: SurfaceTool, box: BoxMesh, rail: Vector2, tile: float, point_at: Callable, top := 0.83) -> void:
	var cells := maxi(1, ceili((rail.y - rail.x) / 0.72))
	for index in cells:
		var a := lerpf(rail.x, rail.y, float(index) / cells)
		var b := lerpf(rail.x, rail.y, float(index + 1) / cells)
		for flip in [false, true]:
			var low: Vector3 = point_at.call(b if flip else a, 0.12)
			var high: Vector3 = point_at.call(a if flip else b, top)
			var axis := low.direction_to(high)
			var side := axis.cross(Vector3.UP).normalized()
			var basis := Basis(side, axis, side.cross(axis))
			bars.append_from(box, 0, Transform3D(basis.scaled_local(Vector3(0.055 * tile, low.distance_to(high), 0.045 * tile)), (low + high) * 0.5))


static func level_origin(props: Node3D, plot_id: String, tile_size: float) -> float:
	for node in props.get_children():
		if node is Node3D and node.get_meta(META, "") == plot_id and (node.has_node("Wall") or node.has_node("Slab")):
			var height := float(node.get_meta(TOWER_HEIGHT_META, float(node.get_meta(LEVEL_META, 0)) * WALL_HEIGHT_M))
			return node.position.y - height * tile_size
	return INF


static func wall_depth(wall: Node3D) -> float:
	return float(wall.get_meta(WALL_DEPTH_META, WALL_DEPTH_M))


static func opening_defaults(kind: int) -> Dictionary:
	if kind == WALL_WINDOW:
		return {"width": 1.25, "height": 1.25, "bottom": 0.875}
	return {"width": 1.125, "height": 2.375, "bottom": 0.0}


static func minimum_wall_length(kind: int, options: Dictionary) -> float:
	return 1.0 if kind == WALL_SOLID else maxf(2.5, float(options.get("width", 0.0)) + 0.5)


static func opening_fits(options: Dictionary) -> bool:
	return options.is_empty() or (float(options.height) + float(options.bottom) <= WALL_HEIGHT_M - 0.125
		and (not options.get("double_leaf", false) or float(options.width) >= DOUBLE_DOOR_MIN_WIDTH))


static func opening_position_fits(options: Dictionary, span: float) -> bool:
	var half := float(options.width) * 0.5 + 0.25
	return float(options.center) >= half and float(options.center) <= span - half


static func make_wall(a: Vector2, b: Vector2, opening: int, surface: Callable, tile_size: float, floor_y: float, on_ground: bool,
		neighbors: Array[Node3D], options: Dictionary = {}, wall_color := Color("e1c9a2"), finish_id := 0, depth := WALL_DEPTH_M) -> Node3D:
	var length := a.distance_to(b)
	if length < minimum_wall_length(opening, options) or length > MAX_FENCE_M or not opening_fits(options) or opening not in [WALL_SOLID, WALL_WINDOW, WALL_DOOR, WALL_PASSAGE]:
		return null
	var start: Vector3 = surface.call(a)
	var finish: Vector3 = surface.call(b)
	if not start.is_finite() or not finish.is_finite():
		return null
	var minimum_y := minf(start.y, finish.y)
	var maximum_y := maxf(start.y, finish.y)
	var samples := ceili(length)
	for index in range(1, samples):
		var ground: Vector3 = surface.call(a.lerp(b, float(index) / samples))
		if not ground.is_finite():
			return null
		minimum_y = minf(minimum_y, ground.y)
		maximum_y = maxf(maximum_y, ground.y)
	if not is_finite(floor_y):
		floor_y = minimum_y
	if on_ground and maxf(absf(minimum_y - floor_y), absf(maximum_y - floor_y)) > tile_size * 0.125:
		return null
	var delta := finish - start
	var wall := Node3D.new()
	wall.name = "PlotWall"
	wall.set_meta(WALL_DEPTH_META, depth)
	wall.position = Vector3(start.x, floor_y, start.z)
	wall.rotation.y = atan2(-delta.z, delta.x)
	var body := StaticBody3D.new()
	body.name = "Wall"
	wall.add_child(body)
	var span := Vector2(delta.x, delta.z).length() / tile_size
	var thickness := depth * 0.5
	var plaster := wall_finish(wall_color, finish_id, tile_size)
	add_wall_joins(wall, body, straight_wall_ends(span * tile_size), neighbors, plaster, tile_size)
	if opening == WALL_SOLID:
		add_wall_box(body, "Plaster", Vector3(0, 0, -thickness), Vector3(span, WALL_HEIGHT_M, thickness), plaster, tile_size)
		return wall

	var is_window := opening == WALL_WINDOW
	var double_door := opening == WALL_DOOR and bool(options.get("double_leaf", false))
	var center := float(options.get("center", span * 0.5))
	var dimensions := opening_defaults(opening) if options.is_empty() else options
	var half_width := float(dimensions.width) * 0.5
	var bottom := float(dimensions.bottom)
	var top := bottom + float(dimensions.height)
	var left := center - half_width
	var right := center + half_width
	add_wall_box(body, "PlasterLeft", Vector3(0, 0, -thickness), Vector3(left, WALL_HEIGHT_M, thickness), plaster, tile_size)
	add_wall_box(body, "PlasterRight", Vector3(right, 0, -thickness), Vector3(span, WALL_HEIGHT_M, thickness), plaster, tile_size)
	add_wall_box(body, "Lintel", Vector3(left, top, -thickness), Vector3(right, WALL_HEIGHT_M, thickness), plaster, tile_size)
	if is_window:
		add_wall_box(body, "WallBelowSill", Vector3(left, 0, -thickness), Vector3(right, bottom, thickness), plaster, tile_size)

	var trim := wall_material(Color("a48e72"))
	var border := OPENING_BORDER
	var frame_depth := maxf(0.125, thickness - 0.0625)
	var top_shape := int(options.get("top_shape", 0))
	var frame_end := top - border
	var inner_cap := PackedVector2Array()
	var outer_cap := PackedVector2Array()
	var infill := wall_material(Color("72989c") if is_window else Color("654737"))
	if top_shape == TOP_ARCH or top_shape == TOP_TRIANGLE:
		var rise := minf(half_width, float(dimensions.height) * 0.45)
		frame_end = top - rise
		outer_cap = opening_cap(center, frame_end, half_width, rise, top_shape)
		inner_cap = opening_cap(center, frame_end, half_width - border, rise - border, top_shape)
		add_opening_crown(body, outer_cap, inner_cap, top, plaster, trim, thickness, frame_depth, tile_size)
		if not double_door:
			add_opening_prism(body, "CrownPane", inner_cap, 0.025, infill, tile_size)
	else:
		add_wall_box(body, "FrameTop", Vector3(left, frame_end, -frame_depth), Vector3(right, top, frame_depth), trim, tile_size)
	if opening != WALL_PASSAGE:
		add_wall_box(body, "FrameBottom", Vector3(left, bottom, -frame_depth), Vector3(right, bottom + border, frame_depth), trim, tile_size)
	add_wall_box(body, "FrameLeft", Vector3(left, bottom + border, -frame_depth), Vector3(left + border, frame_end, frame_depth), trim, tile_size)
	add_wall_box(body, "FrameRight", Vector3(right - border, bottom + border, -frame_depth), Vector3(right, frame_end, frame_depth), trim, tile_size)
	if double_door:
		add_double_door(body, Rect2(left + border, bottom + border, right - left - 2.0 * border, frame_end - bottom - border),
			inner_cap, infill, tile_size)
	elif opening != WALL_PASSAGE:
		add_wall_box(body, "WindowPane" if is_window else "DoorPanel",
			Vector3(left + border, bottom + border, -0.025), Vector3(right - border, frame_end, 0.025), infill, tile_size)
		var grid := int(options.get("grid", 0))
		if grid > 0:
			add_opening_grid(body, Rect2(left + border, bottom + border, right - left - 2.0 * border, frame_end - bottom - border),
				inner_cap, 2 if grid == 1 else 4, trim, tile_size)
	if is_window and options.get("sill", false):
		add_wall_box(body, "OuterSill", Vector3(left - 0.125, bottom - 0.125, thickness - 0.03125),
			Vector3(right + 0.125, bottom, thickness + 0.25), trim, tile_size)
		var planter := Marker3D.new()
		planter.name = "WindowBoxAnchor"
		planter.position = Vector3(center, bottom, thickness + 0.125) * tile_size
		body.add_child(planter)
	if is_window and int(options.get("shutters", 0)) > 0:
		add_shutters(body, Rect2(left, bottom, right - left, top - bottom), outer_cap,
			thickness, int(options.shutters) == 1, tile_size)
	if opening == WALL_DOOR and not double_door:
		add_door_handle(body, left + border + 0.11, minf(frame_end - 0.14, top * 0.45), tile_size)
	if options.get("casing", false):
		var rect := Rect2(left, bottom, right - left, top - bottom)
		add_opening_casing(body, rect, outer_cap, top_shape, thickness, is_window and not options.get("sill", false), tile_size)
	if not options.is_empty():
		wall.set_meta(OPENING_META, options.merged({"kind": opening}))
	return wall


static func wall_arc(start: Vector2, through: Vector2, end: Vector2, width := WALL_DEPTH_M) -> Dictionary:
	if not start.is_finite() or not through.is_finite() or not end.is_finite():
		return {}
	var u := through - start
	var v := end - start
	var cross := u.cross(v)
	if minf(u.length(), through.distance_to(end)) < 0.5 or absf(cross) < 0.01:
		return {}
	var center := start + (Vector2(v.y, -v.x) * u.length_squared()
		+ Vector2(-u.y, u.x) * v.length_squared()) / (2.0 * cross)
	var radius := start.distance_to(center)
	var first_angle := (start - center).angle()
	var sweep := fposmod((end - center).angle() - first_angle, TAU)
	if fposmod((through - center).angle() - first_angle, TAU) > sweep:
		sweep -= TAU
	return sample_wall_arc(start, end, center, radius, sweep, 1.0, width)


static func rounded_wall_corner(first: Vector2, corner: Vector2, last: Vector2, radius: float, depth := WALL_DEPTH_M) -> Dictionary:
	var a := (first - corner).normalized()
	var b := (last - corner).normalized()
	var angle := acos(clampf(a.dot(b), -1.0, 1.0))
	if not is_finite(radius) or radius < 0.75 or angle < 0.01 or angle > PI - 0.01:
		return {}
	var cut := radius / tan(angle * 0.5)
	if cut > minf(first.distance_to(corner), last.distance_to(corner)) - 1.0:
		return {}
	var start := corner + a * cut
	var end := corner + b * cut
	var center := corner + (a + b).normalized() * (radius / sin(angle * 0.5))
	var arc := sample_wall_arc(start, end, center, radius, -signf(a.cross(b)) * (PI - angle), 0.0, depth)
	if not arc.is_empty():
		arc.cut = cut
	return arc


static func sample_wall_arc(start: Vector2, end: Vector2, center: Vector2, radius: float, sweep: float,
		minimum_length := 1.0, width := WALL_DEPTH_M) -> Dictionary:
	var length := radius * absf(sweep)
	if radius < maxf(0.75, width * 0.5 + 0.25) or absf(sweep) > PI + 0.001 or length < minimum_length or length > MAX_FENCE_M:
		return {}
	var first_angle := (start - center).angle()
	var segments := maxi(ceili(length / 0.4), ceili(absf(sweep) / deg_to_rad(6.0)))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in segments + 1:
		var radial := Vector2.from_angle(first_angle + sweep * float(index) / segments)
		var point := start if index == 0 else (end if index == segments else center + radial * radius)
		var offset := -radial * signf(sweep) * width * 0.5
		left.append(point + offset)
		right.append(point - offset)
	var start_radial := (start - center).normalized()
	var end_radial := (end - center).normalized()
	return {"left": left, "right": right,
		"start_direction": Vector2(-start_radial.y, start_radial.x) * signf(sweep),
		"end_direction": Vector2(end_radial.y, -end_radial.x) * signf(sweep)}


static func docked_wall_arc(start: Vector2, through: Vector2, end: Vector2, outward: Vector2, end_outward: Vector2,
		width := ARC_WALK_WIDTH_M) -> Dictionary:
	# Leave a short straight throat at each face so the built mesh also meets it squarely.
	var throat := WALL_DEPTH_M
	var entry := start + outward * throat
	var exit := end + end_outward * throat
	var first := through - entry
	var last := exit - through
	if minf(first.dot(outward), last.dot(-end_outward)) < 1.5 or first.length() + last.length() > MAX_FENCE_M:
		return {}
	var tangent := (first.normalized() + last.normalized()).normalized()
	if tangent.is_zero_approx():
		return {}
	var join := tangent * minf(first.length(), last.length()) / 3.0
	var half := width * 0.5
	var start_offset := Vector2(-outward.y, outward.x) * half
	var end_offset := Vector2(end_outward.y, -end_outward.x) * half
	var left := PackedVector2Array([start + start_offset])
	var right := PackedVector2Array([start - start_offset])
	var previous := start
	var length := throat
	for segment in [[entry, entry + outward * first.length() * 0.4, through - join, through],
			[through, through + join, exit + end_outward * last.length() * 0.4, exit]]:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var c: Vector2 = segment[2]
		var d: Vector2 = segment[3]
		var steps := ceili((a.distance_to(b) + b.distance_to(c) + c.distance_to(d)) / 0.3)
		for index in range(0 if left.size() == 1 else 1, steps + 1):
			var t := float(index) / steps
			var point := a.bezier_interpolate(b, c, d, t)
			var direction := a.bezier_derivative(b, c, d, t).normalized()
			if direction.is_zero_approx():
				return {}
			var offset := Vector2(-direction.y, direction.x) * half
			var l := point + offset
			var r := point - offset
			# The full width stays outside the two landing faces. Reject folded inner edges.
			if minf((l - start).dot(outward), (r - start).dot(outward)) < -0.001 \
					or minf((l - end).dot(end_outward), (r - end).dot(end_outward)) < -0.001:
				return {}
			var step := point - previous
			if minf((l - left[-1]).dot(step), (r - right[-1]).dot(step)) <= 0.0:
				return {}
			length += step.length()
			left.append(l)
			right.append(r)
			previous = point
	if length + throat > MAX_FENCE_M:
		return {}
	left.append(end + end_offset)
	right.append(end - end_offset)
	return {"left": left, "right": right, "start_direction": outward, "end_direction": end_outward}


static func shorten_solid_wall(wall: Node3D, at_start: bool, cut: float, tile_size: float) -> Node3D:
	var replacement := wall.duplicate() as Node3D
	var body := replacement.get_node("Wall")
	var visual := body.get_node("Plaster") as MeshInstance3D
	var collision := body.get_node("PlasterShape") as CollisionShape3D
	var mesh := visual.mesh.duplicate() as BoxMesh
	var shape := collision.shape.duplicate() as BoxShape3D
	var endpoint := Vector3.ZERO if at_start else Vector3.RIGHT * wall_end(wall)
	for child in body.get_children():
		# The first vertex of a corner wedge is the original junction.
		if child is MeshInstance3D and str(child.name).begins_with("Corner"):
			if (child.mesh.get_faces()[0] - endpoint).length() < tile_size * 0.0001:
				child.free()
		elif child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			if (child.shape.points[0] - endpoint).length() < tile_size * 0.0001:
				child.free()
	mesh.size.x -= cut
	shape.size = mesh.size
	visual.mesh = mesh
	collision.shape = shape
	visual.position.x += cut * (0.5 if at_start else -0.5)
	collision.position = visual.position
	if at_start:
		replacement.position += replacement.basis.x * cut
		for child: Node3D in body.get_children():
			child.position.x -= cut
	return replacement


static func make_arc_wall(arc: Dictionary, surface: Callable, tile_size: float, floor_y: float, on_ground: bool,
		neighbors: Array[Node3D], color: Color, finish: int, walk_height := 0.0) -> Node3D:
	var left: PackedVector2Array = arc.left
	var right: PackedVector2Array = arc.right
	var start: Vector3 = surface.call((left[0] + right[0]) * 0.5)
	var end: Vector3 = surface.call((left[-1] + right[-1]) * 0.5)
	if not start.is_finite() or not end.is_finite():
		return null
	if not is_finite(floor_y):
		floor_y = start.y
	var origin := Vector3(start.x, floor_y, start.z)
	var height := WALL_HEIGHT_M * tile_size
	if walk_height > 0.0:
		# Slightly below the landing slab to avoid flicker where they overlap.
		height = (walk_height + FLOOR_TOP_M - 0.002) * tile_size
	var left_edge := PackedVector3Array()
	var right_edge := PackedVector3Array()
	for index in left.size():
		var a: Vector3 = surface.call(left[index])
		var b: Vector3 = surface.call(right[index])
		if not a.is_finite() or not b.is_finite() or (on_ground and maxf(absf(a.y - floor_y), absf(b.y - floor_y)) > tile_size * 0.125):
			return null
		a.y = floor_y
		b.y = floor_y
		left_edge.append(a - origin)
		right_edge.append(b - origin)

	var wall := Node3D.new()
	wall.name = "PlotArcWalk" if walk_height > 0.0 else "PlotArcWall"
	wall.position = origin
	var width := left[0].distance_to(right[0])
	wall.set_meta(WALK_WIDTH_META if walk_height > 0.0 else WALL_DEPTH_META, width)
	var first: Vector2 = arc.start_direction
	var last: Vector2 = arc.end_direction
	var endpoints := PackedVector3Array([Vector3.ZERO, Vector3(first.x, 0, first.y),
		Vector3(end.x - origin.x, 0, end.z - origin.z), Vector3(last.x, 0, last.y)])
	wall.set_meta(ARC_ENDS_META, endpoints)
	var body := StaticBody3D.new()
	body.name = "Wall"
	wall.add_child(body)
	var plaster := wall_finish(color, finish, tile_size)
	var surface_mesh := SurfaceTool.new()
	surface_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface_mesh.set_material(plaster)
	add_arc_strip(surface_mesh, left_edge, right_edge, 0.0, height)
	var visual := finish_arc_mesh(body, "ArcSurface", surface_mesh)
	add_arc_collision(body, "ArcShape", visual.mesh)
	if walk_height > 0.0:
		add_arc_parapet(wall, left_edge, right_edge, height, tile_size)
	else:
		add_wall_joins(wall, body, endpoints, neighbors, plaster, tile_size)
	return wall


static func add_arc_strip(surface: SurfaceTool, left: PackedVector3Array, right: PackedVector3Array, bottom: float, top: float) -> void:
	var rings: Array[PackedVector3Array] = []
	for index in left.size():
		rings.append(PackedVector3Array([left[index] + Vector3.UP * bottom, right[index] + Vector3.UP * bottom,
			right[index] + Vector3.UP * top, left[index] + Vector3.UP * top]))
	for side in 4:
		surface.set_smooth_group(side)
		var next := (side + 1) % 4
		for index in rings.size() - 1:
			add_arc_quad(surface, rings[index][side], rings[index + 1][side], rings[index + 1][next], rings[index][next])
	surface.set_smooth_group(-1)
	add_arc_quad(surface, rings[0][0], rings[0][1], rings[0][2], rings[0][3])
	add_arc_quad(surface, rings[-1][3], rings[-1][2], rings[-1][1], rings[-1][0])


static func finish_arc_mesh(body: Node3D, title: String, surface: SurfaceTool) -> MeshInstance3D:
	surface.generate_normals()
	surface.index()
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = surface.commit()
	body.add_child(visual)
	return visual


static func add_arc_collision(body: StaticBody3D, title: String, mesh: Mesh) -> void:
	var shape := CollisionShape3D.new()
	shape.name = title
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)


static func add_arc_parapet(wall: Node3D, left: PackedVector3Array, right: PackedVector3Array, deck: float, tile: float) -> void:
	var inner_left := PackedVector3Array()
	var inner_right := PackedVector3Array()
	for index in left.size():
		var across := (right[index] - left[index]).normalized() * CRENEL_WIDTH_M * tile
		inner_left.append(left[index] + across)
		inner_right.append(right[index] - across)
	add_parapet_runs(wall, [[left, inner_left], [inner_right, right]], deck, tile)


static func add_parapet_runs(piece: Node3D, runs: Array, deck: float, tile: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Railing"
	piece.add_child(body)
	var stone := wall_material(Color("c8ae8d"))
	var base := SurfaceTool.new()
	var teeth := SurfaceTool.new()
	var guard := SurfaceTool.new()
	for surface in [base, teeth, guard]:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(stone)
	var lip := deck + CRENEL_BASE_M * tile
	var top := deck + GUARD_HEIGHT_M * tile
	for pair in runs:
		add_arc_strip(base, pair[0], pair[1], deck, lip)
		add_arc_strip(guard, pair[0], pair[1], deck, top)
		var length := 0.0
		for index in pair[0].size() - 1:
			length += pair[0][index].distance_to(pair[0][index + 1])
		var count := maxi(1, roundi(length / (1.25 * tile)))
		var stride := float(pair[0].size() - 1) / count
		for index in count:
			var from := stride * (index + 0.15)
			var to := stride * (index + 0.75)
			add_arc_strip(teeth, arc_slice(pair[0], from, to), arc_slice(pair[1], from, to), lip, top)
	finish_arc_mesh(body, "StoneBorder", base)
	finish_arc_mesh(body, "Crenellations", teeth)
	add_arc_collision(body, "RailingShape", guard.commit())


static func arc_slice(edge: PackedVector3Array, from: float, to: float) -> PackedVector3Array:
	var first := floori(from)
	var last := floori(to)
	var points := PackedVector3Array([edge[first].lerp(edge[first + 1], from - first)])
	for index in range(first + 1, ceili(to)):
		points.append(edge[index])
	points.append(edge[last].lerp(edge[mini(last + 1, edge.size() - 1)], to - last))
	return points


static func add_arc_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		surface.add_vertex(point)


static func placed_opening_kind(wall: Node3D) -> int:
	if wall.has_node("Wall/WindowPane"):
		return WALL_WINDOW
	if wall.has_node("Wall/DoorPanel") or wall.has_node("Wall/DoorLeafLeft"):
		return WALL_DOOR
	return WALL_SOLID


static func placed_opening_options(wall: Node3D, tile_size: float) -> Dictionary:
	var kind := placed_opening_kind(wall)
	if kind == WALL_SOLID:
		return {}
	var left := wall.get_node("Wall/FrameLeft") as MeshInstance3D
	var right := wall.get_node("Wall/FrameRight") as MeshInstance3D
	var options := opening_defaults(kind).merged(wall.get_meta(OPENING_META, {}), true)
	options.kind = kind
	options.center = (left.position.x + right.position.x) / (2.0 * tile_size)
	return options


static func window_wall_finish(wall: Node3D) -> Dictionary:
	var side := wall.get_node("Wall/PlasterLeft") as MeshInstance3D
	var material := side.get_active_material(0) as StandardMaterial3D
	var texture := material.albedo_texture.resource_path if material.albedo_texture != null else ""
	return {"color": material.albedo_color, "finish": ["", STONE_TEXTURE, MASONRY_TEXTURE].find(texture)}


static func finish_parts(piece: Node3D, group := FINISH_SURFACE) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	var wall := piece.get_node_or_null("Wall")
	var roof := piece.get_node_or_null("Roof")
	if group != FINISH_SURFACE:
		var body := wall if wall != null else roof
		if body == null:
			return parts
		var prefix := "Bay" if body == roof else ""
		if group == FINISH_DOOR and placed_opening_kind(piece) != WALL_DOOR:
			return parts
		for part in body.get_children():
			if part is not MeshInstance3D:
				continue
			var title := str(part.name)
			if not title.begins_with(prefix):
				continue
			title = title.trim_prefix(prefix)
			if group == FINISH_FRAME and (title.begins_with("Frame") or title.begins_with("Casing")
					or title.begins_with("Grid") or title == "CrownFrame"):
				parts.append(part)
			elif group == FINISH_DOOR and title in ["DoorPanel", "CrownPane", "DoorLeafLeft", "DoorLeafRight"]:
				parts.append(part)
		return parts
	if wall != null:
		var face := wall.get_node_or_null("Plaster") as MeshInstance3D
		if face == null:
			face = wall.get_node_or_null("PlasterLeft") as MeshInstance3D
		if face == null:
			face = wall.get_node_or_null("ArcSurface") as MeshInstance3D
		if face == null:
			return parts
		var base := face.mesh.surface_get_material(0)
		for part in wall.get_children():
			if part is MeshInstance3D and part.mesh.surface_get_material(0) == base:
				parts.append(part)
		return parts
	if roof != null:
		for part in roof.get_children():
			if part is MeshInstance3D and str(part.name).ends_with("Slopes"):
				parts.append(part)
		if not parts.is_empty():
			return parts
	for path in ["Railing/StoneBorder", "Railing/Crenellations", "Railing/Railings", "Roof/Deck",
			"Entry/Landing", "Entry/Step1", "Entry/Step2", "Slab/Floor", "Basin/Bowl", "Basin/Spout"]:
		var part := piece.get_node_or_null(path) as MeshInstance3D
		if part != null:
			parts.append(part)
	return parts


static func finish_title(piece: Node3D, group := FINISH_SURFACE) -> String:
	if group == FINISH_DOOR:
		return "Дверное полотно"
	if group == FINISH_FRAME:
		return "Дверная рама" if placed_opening_kind(piece) == WALL_DOOR else "Рама проёма"
	if piece.has_node("Wall"):
		return "Стена"
	if piece.has_node("Roof"):
		return "Кровля"
	if piece.has_node("Entry"):
		return "Основание крыльца и ступени"
	if piece.has_node("Slab"):
		return "Перекрытие"
	if piece.has_node("Basin"):
		return "Камень фонтана"
	return "Каменный парапет"


static func piece_finish(piece: Node3D, tile_size: float, group := FINISH_SURFACE) -> Dictionary:
	var parts := finish_parts(piece, group)
	if parts.is_empty():
		return {}
	var material := parts[0].get_active_material(0) as StandardMaterial3D
	var texture := material.albedo_texture.resource_path if material.albedo_texture != null else ""
	var finish := maxi(0, ["", STONE_TEXTURE, MASONRY_TEXTURE].find(texture))
	var scale_factor := material.uv1_scale.x * tile_size * (1.8 if finish == 2 else 2.4) if finish != 0 else 1.0
	return {"finish": finish, "color": material.albedo_color, "scale": scale_factor}


static func set_piece_finish(piece: Node3D, material: StandardMaterial3D, group := FINISH_SURFACE) -> void:
	for part in finish_parts(piece, group):
		# Older parapets have the default teeth material on the instance.
		# Keep that default on the copied mesh so clearing the override restores it.
		if part.name == "Crenellations" and part.mesh.surface_get_material(0) == null:
			var mesh := part.mesh.duplicate() as ArrayMesh
			mesh.surface_set_material(0, part.material_override)
			part.mesh = mesh
		part.material_override = material


static func copy_piece_finish(from: Node3D, to: Node3D, group: int) -> void:
	var parts := finish_parts(from, group)
	if not parts.is_empty() and parts[0].material_override is StandardMaterial3D:
		set_piece_finish(to, parts[0].material_override, group)


static func remake_opening_wall(wall: Node3D, options: Dictionary, color: Color, finish: int, tile_size: float) -> Node3D:
	var kind := placed_opening_kind(wall)
	var span := wall_end(wall) / tile_size
	if kind == WALL_SOLID or not opening_fits(options) or not opening_position_fits(options, span):
		return null
	# Use the saved wall frame. Later edits to the terrain do not move this wall.
	var surface := func(point: Vector2) -> Vector3:
		return wall.transform * Vector3(point.x * tile_size, 0, point.y * tile_size)
	var side := wall.get_node("Wall/PlasterLeft") as MeshInstance3D
	var current := window_wall_finish(wall)
	var preserve_finish: bool = side.material_override != null and current.color == color and current.finish == finish
	var base := side.mesh.surface_get_material(0) as StandardMaterial3D
	var texture := base.albedo_texture.resource_path if base.albedo_texture != null else ""
	var base_finish := maxi(0, ["", STONE_TEXTURE, MASONRY_TEXTURE].find(texture))
	var next := make_wall(Vector2.ZERO, Vector2(span, 0), kind, surface, tile_size,
		wall.position.y, false, [], options, base.albedo_color if preserve_finish else color, base_finish if preserve_finish else finish, wall_depth(wall))
	if next == null:
		return null
	next.name = wall.name
	next.transform = wall.transform
	next.set_meta(META, wall.get_meta(META))
	next.set_meta(LEVEL_META, wall.get_meta(LEVEL_META, 0))
	for child in wall.get_node("Wall").get_children():
		if str(child.name).begins_with("Corner"):
			var piece := child.duplicate()
			if piece is MeshInstance3D and piece.mesh is ArrayMesh:
				piece.mesh = piece.mesh.duplicate()
				piece.mesh.surface_set_material(0, next.get_node("Wall/PlasterLeft").mesh.material)
				piece.material_override = null
			next.get_node("Wall").add_child(piece, true)
	if preserve_finish:
		set_piece_finish(next, side.material_override as StandardMaterial3D)
	copy_piece_finish(wall, next, FINISH_FRAME)
	copy_piece_finish(wall, next, FINISH_DOOR)
	return next


static func opening_cap(center: float, base: float, half_width: float, rise: float, kind: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 12 if kind == TOP_ARCH else 2
	for index in steps + 1:
		var x := 2.0 * float(index) / steps - 1.0
		var height := sqrt(maxf(0.0, 1.0 - x * x)) if kind == TOP_ARCH else 1.0 - absf(x)
		points.append(Vector2(center + x * half_width, base + height * rise))
	return points


static func add_opening_crown(body: StaticBody3D, outer: PackedVector2Array, inner: PackedVector2Array, top: float,
		plaster: Material, trim: Material, wall_depth: float, frame_depth: float, tile_size: float) -> void:
	var left := outer[0]
	var right := outer[-1]
	# The outline touches the top at its peak. Split there to keep both polygons simple.
	var middle := floori(outer.size() * 0.5)
	add_opening_prism(body, "CrownPlasterLeft", outer.slice(0, middle + 1) + PackedVector2Array([Vector2(left.x, top)]), wall_depth, plaster, tile_size)
	add_opening_prism(body, "CrownPlasterRight", outer.slice(middle) + PackedVector2Array([Vector2(right.x, top)]), wall_depth, plaster, tile_size)
	var reversed_inner := inner.duplicate()
	reversed_inner.reverse()
	add_opening_prism(body, "CrownFrame", outer + reversed_inner, frame_depth, trim, tile_size)


static func add_double_door(body: StaticBody3D, opening: Rect2, cap: PackedVector2Array,
		material: Material, tile_size: float) -> void:
	var center := opening.get_center().x
	var gap := DOUBLE_DOOR_GAP * 0.5
	var bottom := opening.position.y
	for left_leaf in [true, false]:
		var side := "Left" if left_leaf else "Right"
		var seam := center - gap if left_leaf else center + gap
		var a := opening.position.x if left_leaf else seam
		var b := seam if left_leaf else opening.end.x
		if cap.is_empty():
			add_wall_box(body, "DoorLeaf" + side, Vector3(a, bottom, -0.025),
				Vector3(b, opening.end.y, 0.025), material, tile_size)
		else:
			var middle := floori(cap.size() * 0.5)
			var peak := cap[middle]
			var neighbor := cap[middle - 1] if left_leaf else cap[middle + 1]
			var inner_tip := peak.lerp(neighbor, gap / absf(neighbor.x - peak.x))
			var top := cap.slice(0, middle) if left_leaf else cap.slice(middle + 1)
			if left_leaf:
				top.append(inner_tip)
			else:
				top.insert(0, inner_tip)
			top.reverse()
			var outline := PackedVector2Array([Vector2(a, bottom), Vector2(b, bottom)])
			outline.append_array(top)
			add_opening_prism(body, "DoorLeaf" + side, outline, 0.025, material, tile_size)
		var handle_x := center - 0.11 if left_leaf else center + 0.11
		add_door_handle(body, handle_x, bottom + opening.size.y * 0.54, tile_size, left_leaf, side)


static func add_opening_prism(body: StaticBody3D, title: String, outline: PackedVector2Array, half_depth: float, material: Material, tile_size: float, collidable := true) -> MeshInstance3D:
	var polygon := PackedVector2Array()
	for point in outline:
		polygon.append(point * tile_size)
	if Geometry2D.is_polygon_clockwise(polygon):
		polygon.reverse()
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty():
		return null
	var depth := half_depth * tile_size
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	surface.set_material(material)
	for index in range(0, triangles.size(), 3):
		for corner in [2, 1, 0]:
			var point := polygon[triangles[index + corner]]
			surface.add_vertex(Vector3(point.x, point.y, depth))
		for corner in [0, 1, 2]:
			var point := polygon[triangles[index + corner]]
			surface.add_vertex(Vector3(point.x, point.y, -depth))
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		var a_front := Vector3(a.x, a.y, depth)
		var b_front := Vector3(b.x, b.y, depth)
		var a_back := Vector3(a.x, a.y, -depth)
		var b_back := Vector3(b.x, b.y, -depth)
		for vertex in [a_front, b_front, b_back, a_front, b_back, a_back]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = surface.commit()
	body.add_child(visual)
	if not collidable:
		return visual
	var collision := CollisionPolygon3D.new()
	collision.name = title + "Shape"
	collision.polygon = polygon
	collision.depth = depth * 2.0
	body.add_child(collision)
	return visual


static func add_opening_grid(body: StaticBody3D, glass: Rect2, cap: PackedVector2Array, columns: int, material: Material, tile_size: float) -> void:
	var middle_y := glass.get_center().y
	add_wall_box(body, "GridCrossbar", Vector3(glass.position.x, middle_y - 0.025, -0.05),
		Vector3(glass.end.x, middle_y + 0.025, 0.05), material, tile_size, false)
	for index in range(1, columns):
		var x := lerpf(glass.position.x, glass.end.x, float(index) / columns)
		var end_y := glass.end.y
		if not cap.is_empty():
			var sample := float(index) * (cap.size() - 1) / columns
			end_y = lerpf(cap[floori(sample)].y, cap[ceili(sample)].y, fposmod(sample, 1.0))
		add_wall_box(body, "GridUpright%d" % index, Vector3(x - 0.025, glass.position.y, -0.05),
			Vector3(x + 0.025, end_y, 0.05), material, tile_size, false)


static func add_door_handle(body: StaticBody3D, x: float, y: float, tile_size: float, mirrored := false, suffix := "") -> void:
	var metal := wall_material(Color("b58b49"))
	metal.metallic = 0.55
	for side: float in [-1.0, 1.0]:
		var face := "Outer" if side > 0.0 else "Inner"
		var z := minf(side * 0.024, side * 0.071)
		add_wall_box(body, face + "HandlePlate" + suffix, Vector3(x - 0.04, y - 0.095, z),
			Vector3(x + 0.04, y + 0.095, z + 0.047), metal, tile_size, false)
		z = minf(side * 0.065, side * 0.115)
		add_wall_box(body, face + "HandleLever" + suffix, Vector3(x - (0.14 if mirrored else 0.021), y - 0.025, z),
			Vector3(x + (0.021 if mirrored else 0.14), y + 0.025, z + 0.05), metal, tile_size, false)


static func add_opening_casing(body: StaticBody3D, opening: Rect2, cap: PackedVector2Array,
		top_shape: int, wall_face: float, lower_trim: bool, tile_size: float) -> void:
	var stone := wall_material(Color("e7d5b5"))
	var edge := OPENING_BORDER
	var depth := 0.07
	var z := wall_face - 0.015625
	var left := opening.position.x
	var right := opening.end.x
	var bottom := opening.position.y
	var top := opening.end.y
	var shoulder := top if cap.is_empty() else cap[0].y
	add_wall_box(body, "CasingLeft", Vector3(left - edge, bottom, z), Vector3(left, shoulder, z + depth * 2.0), stone, tile_size, false)
	add_wall_box(body, "CasingRight", Vector3(right, bottom, z), Vector3(right + edge, shoulder, z + depth * 2.0), stone, tile_size, false)
	if lower_trim:
		add_wall_box(body, "CasingSill", Vector3(left - edge, bottom - edge, z),
			Vector3(right + edge, bottom, z + depth * 2.0), stone, tile_size, false)
	if cap.is_empty():
		add_wall_box(body, "CasingHead", Vector3(left - edge, top, z), Vector3(right + edge, top + edge, z + depth * 2.0),
			stone, tile_size, false)
		return
	var wider := opening_cap((left + right) * 0.5, shoulder, (right - left) * 0.5 + edge, top - shoulder + edge, top_shape)
	var inner := cap.duplicate()
	inner.reverse()
	var crown := add_opening_prism(body, "CasingHead", wider + inner, depth, stone, tile_size, false)
	if crown != null:
		crown.position.z = (z + depth) * tile_size


static func add_shutters(body: StaticBody3D, opening: Rect2, cap: PackedVector2Array, wall_face: float,
		opened: bool, tile_size: float) -> void:
	var paint := wall_material(Color("456458"))
	var brace_paint := wall_material(Color("567367"))
	var center := opening.get_center().x
	var bottom := opening.position.y + 0.025
	var gap := 0.015625
	var left_cap := PackedVector2Array([Vector2(opening.position.x, opening.end.y), Vector2(center - gap, opening.end.y)])
	var right_cap := PackedVector2Array([Vector2(center + gap, opening.end.y), Vector2(opening.end.x, opening.end.y)])
	if not cap.is_empty():
		var middle := floori(cap.size() * 0.5)
		left_cap = cap.slice(0, middle + 1)
		right_cap = cap.slice(middle)
		left_cap[-1] = left_cap[-1].lerp(left_cap[-2], gap / (center - left_cap[-2].x))
		right_cap[0] = right_cap[0].lerp(right_cap[1], gap / (right_cap[1].x - center))
	for side in 2:
		var crown := left_cap if side == 0 else right_cap
		var polygon := PackedVector2Array([Vector2(crown[-1].x, bottom), Vector2(crown[0].x, bottom)]) + crown
		var title := "ShutterLeft" if side == 0 else "ShutterRight"
		var leaf := add_opening_prism(body, title, polygon, 0.04, paint, tile_size, false)
		if leaf != null:
			var hinge_x := opening.position.x if side == 0 else opening.end.x
			var hinge := Vector3(hinge_x * tile_size, 0, 0)
			var rotation := Basis(Vector3.UP, (PI - 0.04) * (-1.0 if side == 0 else 1.0)) if opened else Basis.IDENTITY
			leaf.transform = Transform3D(rotation, hinge - rotation * hinge + Vector3(0, 0, (wall_face + 0.05) * tile_size))
			var shoulder := minf(crown[0].y, crown[-1].y)
			for index in 2:
				var y := lerpf(bottom, shoulder, [0.24, 0.76][index])
				var brace := add_wall_box(body, "%sBrace%d" % [title, index],
					Vector3(crown[0].x + 0.03, y - 0.033, -0.05),
					Vector3(crown[-1].x - 0.03, y + 0.033, 0.05), brace_paint, tile_size, false)
				brace.transform = leaf.transform * brace.transform


static func strip_outline(a: Vector2, b: Vector2, depth: float) -> PackedVector2Array:
	var forward := Vector2(a.y - b.y, b.x - a.x).normalized() * depth
	return PackedVector2Array([a, b, b + forward, a + forward])


static func entry_outline(a: Vector2, b: Vector2) -> PackedVector2Array:
	return strip_outline(a, b, ENTRY_DEPTH + ENTRY_TREAD * 2.0)


static func strip_datum(outline: PackedVector2Array, surface: Callable, tile_size: float) -> float:
	var minimum := INF
	var maximum := -INF
	var samples := ceili(outline[0].distance_to(outline[1]))
	var rows := ceili(outline[0].distance_to(outline[3]))
	for index in samples + 1:
		var fraction := float(index) / samples
		var rear := outline[0].lerp(outline[1], fraction)
		var front := outline[3].lerp(outline[2], fraction)
		for row in rows + 1:
			var ground: Vector3 = surface.call(rear.lerp(front, float(row) / rows))
			if not ground.is_finite():
				return INF
			minimum = minf(minimum, ground.y)
			maximum = maxf(maximum, ground.y)
	return minimum if maximum - minimum <= ENTRY_RISE * tile_size else INF


static func make_entry(a: Vector2, b: Vector2, surface: Callable, tile_size: float, portico := false, canopy_height := 3.0) -> Node3D:
	var width := a.distance_to(b)
	if width < ENTRY_MIN_WIDTH or width > ENTRY_MAX_WIDTH:
		return null
	var datum := strip_datum(entry_outline(a, b), surface, tile_size)
	if not is_finite(datum):
		return null
	var start: Vector3 = surface.call(a)
	var finish: Vector3 = surface.call(b)
	var entry := Node3D.new()
	entry.name = "PlotEntry"
	entry.position = Vector3(start.x, datum, start.z)
	entry.rotation.y = atan2(start.z - finish.z, finish.x - start.x)
	var body := StaticBody3D.new()
	body.name = "Entry"
	entry.add_child(body)
	var stone := wall_material(Color("c9ad89"))
	add_wall_box(body, "Landing", Vector3(0, -ENTRY_RISE, 0), Vector3(width, ENTRY_RISE * 3.0, ENTRY_DEPTH), stone, tile_size)
	for index in 2:
		var tread := ENTRY_DEPTH + index * ENTRY_TREAD
		add_wall_box(body, "Step%d" % (index + 1), Vector3(0, -ENTRY_RISE, tread),
			Vector3(width, ENTRY_RISE * (2 - index), tread + ENTRY_TREAD), stone, tile_size)
	if portico:
		add_portico(body, width, tile_size, canopy_height)
	return entry


static func make_column(point: Vector3, level_y: float, tile_size: float, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "PlotColumn"
	root.position = Vector3(point.x, level_y, point.z)
	var body := StaticBody3D.new()
	body.name = "Column"
	root.add_child(body)
	add_column(body, "Shaft", Vector2.ZERO, BALCONY_TOP, WALL_HEIGHT_M, wall_material(color), tile_size)
	return root


static func make_apple_tree(point: Vector3) -> Node3D:
	var tree := preload("res://prefabs/items/fruit_tree.scn").instantiate() as Node3D
	tree.name = "PlotAppleTree"
	tree.position = point
	tree.set("orchard_pickup_id", "orchard_apple_" + Crypto.new().generate_random_bytes(12).hex_encode())
	return tree


static func make_fountain(point: Vector2, style: int, surface: Callable, tile_size: float) -> Node3D:
	if style < 0 or style >= FOUNTAIN_RADII.size():
		return null
	var court := style == FOUNTAIN_COURT
	var radius: float = FOUNTAIN_RADII[style]
	var lo := point - Vector2.ONE * radius
	var hi := point + Vector2.ONE * radius
	var outline := PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])
	var datum := strip_datum(outline, surface, tile_size)
	if not is_finite(datum):
		return null
	var ground: Vector3 = surface.call(point)
	var fountain := Node3D.new()
	fountain.name = "PlotFountain"
	fountain.position = Vector3(ground.x, datum, ground.z)
	var body := StaticBody3D.new()
	body.name = "Basin"
	fountain.add_child(body)

	var water_y := 0.52 if court else 0.40
	var bottom_y := 0.18 if court else 0.13
	var rim_y := water_y + 0.13
	var stone := wall_finish(Color("e1c9a7"), 1, tile_size)
	var profile := PackedVector2Array([
		Vector2(0, bottom_y), Vector2(radius - 0.26, bottom_y),
		Vector2(radius - 0.17, water_y), Vector2(radius - 0.15, rim_y - 0.05),
		Vector2(radius - 0.12, rim_y), Vector2(radius - 0.04, rim_y),
		Vector2(radius, rim_y - 0.05), Vector2(radius, water_y - 0.04),
		Vector2(radius - 0.05, water_y - 0.08), Vector2(radius - 0.08, 0.08),
		Vector2(radius - 0.035, 0.065), Vector2(radius - 0.035, -0.15)])
	var bowl := add_fountain_profile(body, "Bowl", profile, tile_size, stone)
	var shape := CollisionShape3D.new()
	shape.name = "BowlShape"
	shape.shape = bowl.mesh.create_trimesh_shape()
	body.add_child(shape)

	var water := FOUNTAIN_WATER.duplicate() as ShaderMaterial
	water.set_shader_parameter("wave_height_voxels", 0.42 * tile_size / 16.0)
	water.set_shader_parameter("world_units_per_metre", tile_size)
	water.set_shader_parameter("local_bob_strength", 0.0)
	water.set_shader_parameter("planar_reflection_mix", 0.0)
	var surface_depth := (water_y - bottom_y) * tile_size / 64.0
	var water_radius := radius - 0.185
	var water_profile := PackedVector2Array()
	for band in 5:
		water_profile.append(Vector2((water_radius - 0.14) * float(band) / 4.0, water_y))
	water_profile.append(Vector2(water_radius, water_y))
	var pool := add_fountain_profile(body, "Water", water_profile, tile_size, water, surface_depth, true)
	pool.set_script(preload("res://scripts/ember_local_water_surface.gd"))
	pool.set("water_depth", (water_y - bottom_y) * tile_size)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var lip := water_y + (0.40 if court else 0.13)
	var cap := 0.34 if court else 0.17
	add_fountain_profile(body, "Spout", PackedVector2Array([
		Vector2(0, lip), Vector2(cap * 0.8, lip), Vector2(cap, lip - 0.045),
		Vector2(cap, lip - 0.105), Vector2(cap * 0.48, lip - 0.15),
		Vector2(cap * 0.44, bottom_y + 0.12), Vector2(cap * 0.8, bottom_y + 0.08),
		Vector2(cap * 0.8, bottom_y)]), tile_size, stone)
	add_fountain_jet(body, lip, radius, tile_size, court)
	return fountain


static func add_fountain_profile(parent: Node3D, title: String, profile: PackedVector2Array,
		tile_size: float, material: Material, depth_alpha := 1.0, shallow_rim := false) -> MeshInstance3D:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_material(material)
	var sides := 48
	for band in profile.size() - 1:
		mesh.set_smooth_group(band)
		var inner := profile[band] * tile_size
		var outer := profile[band + 1] * tile_size
		var outer_alpha := 0.0 if shallow_rim and band == profile.size() - 2 else depth_alpha
		for side in sides:
			var first := TAU * float(side) / sides
			var last := TAU * float((side + 1) % sides) / sides
			var a := Vector3(cos(first) * inner.x, inner.y, sin(first) * inner.x)
			var b := Vector3(cos(last) * inner.x, inner.y, sin(last) * inner.x)
			var c := Vector3(cos(last) * outer.x, outer.y, sin(last) * outer.x)
			var d := Vector3(cos(first) * outer.x, outer.y, sin(first) * outer.x)
			mesh.set_color(Color(1.0, 1.0, 1.0, depth_alpha))
			mesh.add_vertex(a)
			mesh.set_color(Color(1.0, 1.0, 1.0, outer_alpha))
			mesh.add_vertex(d)
			mesh.add_vertex(c)
			if not is_zero_approx(inner.x):
				mesh.set_color(Color(1.0, 1.0, 1.0, depth_alpha))
				mesh.add_vertex(a)
				mesh.set_color(Color(1.0, 1.0, 1.0, outer_alpha))
				mesh.add_vertex(c)
				mesh.set_color(Color(1.0, 1.0, 1.0, depth_alpha))
				mesh.add_vertex(b)
	mesh.generate_normals()
	mesh.index()
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = mesh.commit()
	parent.add_child(visual)
	return visual


static func add_fountain_jet(parent: Node3D, height: float, radius: float, tile_size: float, court: bool) -> void:
	var drops := GPUParticles3D.new()
	drops.name = "Jet"
	drops.amount = 144 if court else 88
	drops.lifetime = 0.95 if court else 0.73
	drops.preprocess = drops.lifetime
	drops.local_coords = true
	drops.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.position.y = height * tile_size
	drops.visibility_aabb = AABB(Vector3(-radius, -height, -radius) * tile_size,
		Vector3(radius * 2.0, height + 1.25, radius * 2.0) * tile_size)
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 19.0 if court else 15.0
	motion.initial_velocity_min = (4.15 if court else 3.0) * tile_size
	motion.initial_velocity_max = (4.55 if court else 3.45) * tile_size
	motion.gravity = Vector3.DOWN * 10.6 * tile_size
	motion.scale_min = 0.55
	motion.scale_max = 1.15
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.78))
	fade.add_point(Vector2(0.22, 1.0))
	fade.add_point(Vector2(0.72, 0.75))
	fade.add_point(Vector2(1.0, 0.0))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = fade
	motion.scale_curve = scale_curve
	drops.process_material = motion
	var bead := SphereMesh.new()
	bead.radius = (0.026 if court else 0.022) * tile_size
	bead.height = bead.radius * 4.1
	bead.radial_segments = 6
	bead.rings = 3
	var water := wall_material(Color("b8e6eb"))
	water.roughness = 0.2
	water.emission_enabled = true
	water.emission = Color("78b0bf")
	water.emission_energy_multiplier = 0.21
	bead.material = water
	drops.draw_pass_1 = bead
	parent.add_child(drops)


static func make_edge(a: Vector2, b: Vector2, depth: float, style: int, surface: Callable, tile_size: float,
		hedge_height := HEDGE_HEIGHT_M, hedge_leaf_scale := 1.0, hedge_autumn := false) -> Node3D:
	var span := a.distance_to(b)
	if span < 1.0 or span > MAX_FENCE_M or depth < EDGE_MIN_DEPTH or depth > EDGE_MAX_DEPTH or style not in [EDGE_STONE, EDGE_SOIL, EDGE_SHRUBS, EDGE_HEDGE]:
		return null
	if style == EDGE_HEDGE and (not is_finite(hedge_height) or hedge_height < HEDGE_MIN_HEIGHT_M or hedge_height > HEDGE_MAX_HEIGHT_M):
		return null
	if style == EDGE_HEDGE and (not is_finite(hedge_leaf_scale) or hedge_leaf_scale < HEDGE_MIN_LEAF_SCALE or hedge_leaf_scale > HEDGE_MAX_LEAF_SCALE):
		return null
	var datum := strip_datum(strip_outline(a, b, depth), surface, tile_size)
	if not is_finite(datum):
		return null
	var start: Vector3 = surface.call(a)
	var finish: Vector3 = surface.call(b)
	var strip := Node3D.new()
	strip.name = "PlotEdge"
	strip.position = Vector3(start.x, datum, start.z)
	strip.rotation.y = atan2(start.z - finish.z, finish.x - start.x)
	strip.set_meta(&"_ember_plot_edge_style", style)
	var body := StaticBody3D.new()
	body.name = "Edge"
	strip.add_child(body)
	if style == EDGE_STONE:
		add_wall_box(body, "PavingBase", Vector3(0, -0.125, 0), Vector3(span, EDGE_TOP - 0.02, depth),
			wall_material(Color("a89c86")), tile_size)
		var collider := body.get_node("PavingBaseShape") as CollisionShape3D
		(collider.shape as BoxShape3D).size.y += 0.02 * tile_size
		collider.position.y += 0.01 * tile_size
		add_edge_paving(body, span, depth, tile_size)
	elif style == EDGE_HEDGE:
		add_hedge(body, span, depth, hedge_height, tile_size, hedge_leaf_scale, hedge_autumn)
	else:
		add_edge_planter(body, span, depth, tile_size)
	if style == EDGE_SHRUBS and not add_edge_shrubs(body, span, depth, tile_size):
		strip.free()
		return null
	return strip


static func add_edge_paving(body: Node3D, span: float, depth: float, tile_size: float) -> void:
	var columns := ceili(span / 0.95)
	var rows := ceili(depth / 0.75)
	var tile := Vector2(span / columns, depth / rows)
	var slab := BoxMesh.new()
	slab.size = Vector3(tile.x - 0.026, 0.035, tile.y - 0.026) * tile_size
	var stone := wall_material(Color("d5c8af"))
	stone.vertex_color_use_as_albedo = true
	slab.material = stone
	var paving := MultiMesh.new()
	paving.transform_format = MultiMesh.TRANSFORM_3D
	paving.use_colors = true
	paving.mesh = slab
	paving.instance_count = columns * rows
	var shades := [0.86, 0.94, 0.9, 1.0, 0.97]
	for row in rows:
		for column in columns:
			var index := row * columns + column
			var offset := Vector3((column + 0.5) * tile.x, EDGE_TOP - 0.0175, (row + 0.5) * tile.y)
			paving.set_instance_transform(index, Transform3D(Basis.IDENTITY, offset * tile_size))
			var shade: float = shades[(column * 3 + row * 2) % shades.size()]
			paving.set_instance_color(index, Color(shade, shade, shade))
	var visual := MultiMeshInstance3D.new()
	visual.name = "Paving"
	visual.multimesh = paving
	body.add_child(visual)


static func add_edge_planter(body: StaticBody3D, span: float, depth: float, tile_size: float) -> void:
	var border := 0.175
	var stone := wall_material(Color("bead92"))
	add_wall_box(body, "NearRim", Vector3(0, -0.125, 0), Vector3(span, PLANTER_RIM_TOP, border), stone, tile_size)
	add_wall_box(body, "FarRim", Vector3(0, -0.125, depth - border), Vector3(span, PLANTER_RIM_TOP, depth), stone, tile_size)
	add_wall_box(body, "StartRim", Vector3(0, -0.125, border), Vector3(border, PLANTER_RIM_TOP, depth - border), stone, tile_size)
	add_wall_box(body, "EndRim", Vector3(span - border, -0.125, border), Vector3(span, PLANTER_RIM_TOP, depth - border), stone, tile_size)
	add_wall_box(body, "Soil", Vector3(border, -0.125, border), Vector3(span - border, PLANTER_SOIL_TOP, depth - border),
		wall_material(Color("6d5240")), tile_size)


static func garden_shrub_mesh(recipe: Resource) -> ArrayMesh:
	if _garden_bush_mesh == null:
		var generated := Generator.build(recipe, Color.WHITE, {}, "Садовый куст", "plot_planter_bush")
		if generated.has("error"):
			return null
		var model := EmberVoxelPrefab.model_of(generated.geometry.to_definition())
		_garden_bush_mesh = TreeSurface.build(model)
		for index in _garden_bush_mesh.get_surface_count():
			if _garden_bush_mesh.surface_get_name(index) == "tree_leaves":
				var leaf_cards := _garden_bush_mesh.surface_get_material(index) as ShaderMaterial
				# This shader samples the card atlas. The solid-canopy texture adds only save payload.
				leaf_cards.set_shader_parameter("painted_foliage_albedo", null)
	return _garden_bush_mesh


static func add_edge_shrubs(body: StaticBody3D, span: float, depth: float, tile_size: float) -> bool:
	var recipe := Generator.garden_bush_recipe()
	var mesh := garden_shrub_mesh(recipe)
	if mesh == null:
		return false
	var box := mesh.get_aabb()
	var size := minf(0.95, minf(span, depth) - 0.4) * tile_size
	var basis := Basis.from_scale(Vector3.ONE * size / Vector2(box.size.x, box.size.z).length())
	var ground_center := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var shrubs := MultiMesh.new()
	shrubs.transform_format = MultiMesh.TRANSFORM_3D
	shrubs.mesh = mesh
	shrubs.instance_count = maxi(1, floori(span / 1.4))
	for index in shrubs.instance_count:
		var x := span * (index + 0.5) / shrubs.instance_count
		var rotation := basis.rotated(Vector3.UP, 0.28 * (index % 5 - 2))
		var ground := Vector3(x, PLANTER_SOIL_TOP, depth * 0.5) * tile_size
		shrubs.set_instance_transform(index, Transform3D(rotation, ground - rotation * ground_center))
	var visual := MultiMeshInstance3D.new()
	visual.name = "Shrubs"
	visual.multimesh = shrubs
	visual.set_meta(&"_ember_bush_generator", recipe.generator_id)
	visual.set_meta(&"_ember_bush_seed", recipe.seed)
	body.add_child(visual)
	return true


static func add_hedge(body: StaticBody3D, span: float, depth: float, height: float, tile_size: float,
		leaf_scale: float, autumn: bool) -> void:
	var atlas := load(HEDGE_AUTUMN_LEAVES if autumn else HEDGE_LEAVES) as Texture2D
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/ember_hedge_leaf_atlas.gdshader")
	material.set_shader_parameter("leaf_atlas", atlas)
	material.set_shader_parameter("leaf_patch_m", (HEDGE_AUTUMN_PATCH_M if autumn else HEDGE_LEAF_PATCH_M) * leaf_scale)
	if autumn:
		material.set_shader_parameter("autumn", true)
		material.set_shader_parameter("leaf_tint", Color("f0cf9f"))
	var crown := MeshInstance3D.new()
	crown.name = "HedgeCrown"
	crown.mesh = hedge_shell(span, depth, height, tile_size)
	crown.material_override = material
	body.add_child(crown)
	var end_gap := 0.09
	var side_gap := 0.035
	var rise := height * 0.07
	var inner_height := minf(height * 0.82, height - rise - 0.14)
	var interior := MeshInstance3D.new()
	interior.name = "HedgeInterior"
	interior.mesh = hedge_shell(span - 2.0 * end_gap, depth - 2.0 * side_gap, inner_height, tile_size, 1.2, height * 0.055, rise)
	interior.position = Vector3(end_gap, rise, side_gap) * tile_size
	if autumn:
		var dry_leaves := material.duplicate() as ShaderMaterial
		dry_leaves.set_shader_parameter("understory", true)
		dry_leaves.set_shader_parameter("understory_paint", load(HEDGE_INNER_LEAVES))
		dry_leaves.set_shader_parameter("leaf_patch_m", HEDGE_AUTUMN_PATCH_M * 0.77 * leaf_scale)
		interior.material_override = dry_leaves
	else:
		var inner_leaves := wall_material(Color("829064"))
		inner_leaves.albedo_texture = load(HEDGE_INNER_LEAVES) as Texture2D
		inner_leaves.uv1_scale = Vector3(1.4, 1.4, 1.0)
		inner_leaves.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		interior.material_override = inner_leaves
	interior.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(interior)
	add_hedge_sprigs(body, span, depth, height, tile_size, atlas, leaf_scale, autumn)
	var shape := BoxShape3D.new()
	shape.size = Vector3(span, height * 0.9, depth * 0.8) * tile_size
	var guard := CollisionShape3D.new()
	guard.name = "HedgeShape"
	guard.shape = shape
	guard.position = Vector3(span * tile_size, shape.size.y, depth * tile_size) * 0.5
	body.add_child(guard)
	add_hedge_branches(body, span, depth, height, tile_size, autumn)


static func add_hedge_branches(body: StaticBody3D, span: float, depth: float, height: float, tile_size: float, autumn: bool) -> void:
	var branches := SurfaceTool.new()
	branches.begin(Mesh.PRIMITIVE_TRIANGLES)
	var twig := CylinderMesh.new()
	twig.radial_segments = 5
	twig.rings = 0
	twig.top_radius = 0.55
	twig.bottom_radius = 1.0
	twig.height = 1.0
	twig.cap_bottom = false
	var count := maxi(1, ceili(span / 1.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12581
	for index in count:
		var x := span * (index + 0.5) / count
		var base := Vector3(x, 0, depth * 0.5)
		for side: float in [-1.0, 1.0]:
			if autumn:
				var face_z := 0.012 if side < 0.0 else depth - 0.012
				var lean := rng.randf_range(0.17, 0.35) * (-1.0 if rng.randf() < 0.5 else 1.0)
				var knee := Vector3(x - lean * 0.28, height * 0.31, lerpf(base.z, face_z, 0.82))
				var fork := Vector3(x + lean * 0.56, height * rng.randf_range(0.47, 0.65), face_z)
				var tip := Vector3(x + lean, height * rng.randf_range(0.71, 0.93), face_z + side * 0.013)
				var offshoot := fork + Vector3(-lean * 0.82, height * rng.randf_range(0.11, 0.19), side * 0.01)
				append_hedge_twig(branches, twig, base, knee, 0.043, tile_size)
				append_hedge_twig(branches, twig, knee, fork, 0.033, tile_size)
				append_hedge_twig(branches, twig, fork, tip, 0.021, tile_size)
				append_hedge_twig(branches, twig, fork, offshoot, 0.012, tile_size)
				continue
			var tip_height := height * 0.46 if index % 2 == 0 and side > 0.0 else height * 0.27
			var tip := base + Vector3(0.12 * side, tip_height, side * depth * 0.26)
			append_hedge_twig(branches, twig, base, tip, 0.027, tile_size)
	var wood := MeshInstance3D.new()
	wood.name = "HedgeBranches"
	wood.mesh = branches.commit()
	wood.material_override = wall_material(Color("8c6d51") if autumn else Color("645138"))
	body.add_child(wood)


static func append_hedge_twig(surface: SurfaceTool, twig: CylinderMesh, start: Vector3, tip: Vector3, radius: float, tile_size: float) -> void:
	var axis := tip - start
	var basis := Basis(Vector3.UP.cross(axis).normalized(), Vector3.UP.angle_to(axis))
	basis = basis.scaled_local(Vector3(radius, axis.length(), radius) * tile_size)
	surface.append_from(twig, 0, Transform3D(basis, (start + tip) * (tile_size * 0.5)))


static func hedge_shell(span: float, depth: float, height: float, tile_size: float, spacing := 0.55,
		crown_wave := 0.0, ground_offset := 0.0) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var bevel := minf(0.22, minf(depth, height) * 0.23)
	var radius := bevel * 1.35
	var center := Vector2(span, depth) * 0.5
	var corners := [Vector2(span - radius, radius), Vector2(span - radius, depth - radius),
		Vector2(radius, depth - radius), Vector2(radius, radius)]
	var path := PackedVector2Array()
	var directions := PackedVector2Array()
	for corner in 4:
		for step in 4:
			var angle := (float(corner) - 1.0 + float(step) / 3.0) * PI * 0.5
			var normal := Vector2.from_angle(angle)
			path.append(corners[corner] + normal * radius)
			directions.append(normal)
	var perimeter := PackedVector2Array()
	var outward := PackedVector2Array()
	for index in path.size():
		var next := (index + 1) % path.size()
		var divisions := maxi(1, ceili(path[index].distance_to(path[next]) / spacing))
		for step in divisions:
			var t := float(step) / divisions
			perimeter.append(path[index].lerp(path[next], t))
			outward.append(directions[index].lerp(directions[next], t).normalized())
	var layers := [Vector3(-ground_offset - HEDGE_GROUND_OVERLAP_M, bevel * 0.34, -0.35),
		Vector3(0.30, bevel * 0.14, -0.12),
		Vector3(height - bevel, 0, 0), Vector3(height - bevel * 0.23, bevel * 0.27, 0.65),
		Vector3(height, bevel, 1)]
	var ring_size := perimeter.size()
	var stride := ring_size + 1
	var lengths := PackedFloat32Array([0.0])
	for i in ring_size:
		lengths.append(lengths[i] + perimeter[i].distance_to(perimeter[(i + 1) % ring_size]))
	for layer_index in layers.size():
		var layer: Vector3 = layers[layer_index]
		for column in stride:
			var i := column % ring_size
			var normal := outward[i]
			var at := perimeter[i] - normal * layer.y
			var ripple := sin(at.x * 7.9 + at.y * 3.4) * 0.025 + sin(at.x * 13.2 - at.y * 5.7) * 0.014
			ripple += crown_wave * layer.x / height * (sin(at.x * 1.9 + at.y * 3.1) * 0.68 + sin(at.x * 4.3) * 0.32)
			if layer_index == 0:
				ripple = 0.0
			vertices.append(Vector3(at.x, layer.x + ripple, at.y) * tile_size)
			normals.append(Vector3(normal.x * (1.0 - absf(layer.z)), layer.z, normal.y * (1.0 - absf(layer.z))).normalized())
			var shade := 0.72 + float(layer_index) * 0.07
			colors.append(Color(shade, shade, shade))
			uvs.append(Vector2(lengths[column], layer.x))
			if layer_index > 0 and column < ring_size:
				var a := (layer_index - 1) * stride + column
				var b := a + 1
				indices.append_array(PackedInt32Array([a, b + stride, a + stride, a, b, b + stride]))
	var top_center := vertices.size()
	vertices.append(Vector3(center.x, height, center.y) * tile_size)
	normals.append(Vector3.UP)
	colors.append(Color.WHITE)
	uvs.append(center)
	# The cap uses planar meter UVs while the sides unwrap around the perimeter.
	var last_ring := (layers.size() - 1) * stride
	for i in ring_size:
		var point := vertices[last_ring + i]
		vertices.append(point)
		normals.append(Vector3.UP)
		colors.append(Color.WHITE)
		uvs.append(Vector2(point.x, point.z) / tile_size)
		indices.append_array(PackedInt32Array([top_center, top_center + i + 1, top_center + (i + 1) % ring_size + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func add_hedge_sprigs(body: StaticBody3D, span: float, depth: float, height: float, tile_size: float,
		atlas: Texture2D, leaf_scale: float, autumn: bool) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := maxi(1, floori(span / ((0.68 if autumn else 0.52) * maxf(1.0, leaf_scale))))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7319
	for side: float in [-1.0, 1.0]:
		for index in count:
			var x := 0.21 + (span - 0.42) * (index + rng.randf_range(0.32, 0.68)) / count
			var y := height - rng.randf_range(0.18, 0.29)
			var z := 0.015 if side < 0.0 else depth - 0.015
			var root := Vector3(x, y, z)
			var rise := Vector3(rng.randf_range(-0.09, 0.09), rng.randf_range(0.25, 0.37), -side * 0.13)
			var variant := Vector2(index % 2, (index >> 1) % 2) if autumn else Vector2.ZERO
			hedge_sprig_card(surface, root, rise * leaf_scale, rng.randf_range(0.22, 0.33) * leaf_scale,
				side, index % 2 == 0, tile_size, variant)
	var material := wall_material(Color("f0cf9f") if autumn else Color("e3edc9"))
	material.albedo_texture = atlas
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.45
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var leaves := MeshInstance3D.new()
	leaves.name = "HedgeSprigs"
	leaves.mesh = surface.commit()
	leaves.material_override = material
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(leaves)


static func hedge_sprig_card(surface: SurfaceTool, root: Vector3, rise: Vector3, width: float, side: float,
		flipped: bool, tile_size: float, variant: Vector2) -> void:
	var half := Vector3.RIGHT * width * 0.5
	var corners := [root - half, root + half, root + rise + half, root + rise - half]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var normal := Vector3(0, 0.62, side).normalized()
	for index in ([0, 1, 2, 0, 2, 3] if side < 0.0 else [0, 2, 1, 0, 3, 2]):
		var sample: Vector2 = uv[index]
		if flipped:
			sample.x = 1.0 - sample.x
		surface.set_normal(normal)
		surface.set_uv((variant + sample * 0.96 + Vector2(0.02, 0.02)) * 0.5)
		surface.add_vertex(corners[index] * tile_size)


static func add_portico(body: StaticBody3D, width: float, tile_size: float, canopy_height: float) -> void:
	var stone := wall_material(Color("e1ccaa"))
	var floor := ENTRY_RISE * 3.0
	var top := clampf(canopy_height, 2.625, 4.0)
	var z := ENTRY_DEPTH - 0.325
	for index in 2:
		var x := 0.325 if index == 0 else width - 0.325
		var title := "LeftColumn" if index == 0 else "RightColumn"
		add_column(body, title, Vector2(x, z), floor, top, stone, tile_size)
	add_wall_box(body, "PorticoRoof", Vector3(-0.0625, top, 0), Vector3(width + 0.0625, top + 0.23, ENTRY_DEPTH), stone, tile_size)
	add_wall_box(body, "PorticoLip", Vector3(-0.125, top + 0.23, 0),
		Vector3(width + 0.125, top + 0.33, ENTRY_DEPTH + 0.125), stone, tile_size)


static func add_column(body: StaticBody3D, title: String, center: Vector2, floor: float, top: float, stone: Material, tile_size: float) -> void:
	var x := center.x
	var z := center.y
	add_wall_box(body, title + "Base", Vector3(x - 0.23, floor, z - 0.23),
		Vector3(x + 0.23, floor + 0.19, z + 0.23), stone, tile_size)
	add_wall_box(body, title + "Capital", Vector3(x - 0.21, top - 0.2, z - 0.21),
		Vector3(x + 0.21, top, z + 0.21), stone, tile_size)
	var shaft_height := (top - 0.2 - floor - 0.19) * tile_size
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.145 * tile_size
	mesh.bottom_radius = 0.175 * tile_size
	mesh.height = shaft_height
	mesh.radial_segments = 12
	mesh.rings = 0
	mesh.material = stone
	var shaft := MeshInstance3D.new()
	shaft.name = title
	shaft.mesh = mesh
	shaft.position = Vector3(x * tile_size, (floor + 0.19) * tile_size + shaft_height * 0.5, z * tile_size)
	body.add_child(shaft)
	var cylinder := CylinderShape3D.new()
	cylinder.radius = mesh.bottom_radius
	cylinder.height = shaft_height
	var collision := CollisionShape3D.new()
	collision.name = title + "Shape"
	collision.shape = cylinder
	collision.position = shaft.position
	body.add_child(collision)


static func make_balcony(a: Vector2, b: Vector2, depth: float, columns: bool, surface: Callable, level_y: float, tile_size: float) -> Node3D:
	var span := a.distance_to(b)
	if span < 2.5 or span > 18.0 or depth < 1.0 or depth > 4.0 or not is_finite(level_y):
		return null
	var first: Vector3 = surface.call(a)
	var last: Vector3 = surface.call(b)
	if not first.is_finite() or not last.is_finite():
		return null
	var bases := PackedFloat32Array()
	var posts := [Vector2(0.375, depth - 0.375), Vector2(span - 0.375, depth - 0.375)]
	if columns:
		var axis := (b - a).normalized()
		var outward := Vector2(-axis.y, axis.x)
		for post: Vector2 in posts:
			var ground: Vector3 = surface.call(a + axis * post.x + outward * post.y)
			if not ground.is_finite() or (level_y - ground.y) / tile_size < 0.75:
				return null
			bases.append((ground.y - level_y) / tile_size)
	var root := Node3D.new()
	root.name = "PlotBalcony"
	root.position = Vector3(first.x, level_y, first.z)
	root.rotation.y = atan2(first.z - last.z, last.x - first.x)
	var body := StaticBody3D.new()
	body.name = "Balcony"
	root.add_child(body)
	var stone := wall_material(Color("e1ccaa"))
	var deck := add_wall_box(body, "Deck", Vector3(0, BALCONY_UNDERSIDE, 0), Vector3(span, BALCONY_TOP, depth), stone, tile_size)
	deck.position.y += 0.003 * tile_size
	for index in bases.size():
		add_column(body, "Column%d" % index, posts[index], bases[index], BALCONY_UNDERSIDE, stone, tile_size)
	var inset := 0.07
	var back := WALL_DEPTH_M * 0.5
	var left := Vector2(inset, depth - inset)
	var right := Vector2(span - inset, depth - inset)
	add_railings(body, [[Vector2(inset, back), left], [left, right], [right, Vector2(span - inset, back)]], tile_size, RAIL_METAL)
	return root


static func make_railing(first: Vector3, last: Vector3, level_y: float, tile_size: float, style: int) -> Node3D:
	var span := Vector2(last.x - first.x, last.z - first.z).length() / tile_size
	if span < 0.5 or span > MAX_FENCE_M:
		return null
	var root := Node3D.new()
	root.name = "PlotRailing"
	root.position = Vector3(first.x, level_y, first.z)
	root.rotation.y = atan2(first.z - last.z, last.x - first.x)
	var body := StaticBody3D.new()
	body.name = "Railing"
	root.add_child(body)
	add_railings(body, [[Vector2(0.0375, 0), Vector2(span - 0.0375, 0)]], tile_size, style)
	return root


static func add_railings(body: StaticBody3D, runs: Array, tile_size: float, style: int) -> void:
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var rail_size := (b - a).abs() + Vector2.ONE * 0.075
		if style != RAIL_METAL:
			var width := 0.45 if style == RAIL_CRENEL else 0.22
			rail_size = rail_size.max(Vector2.ONE * width)
		var center := (a + b) * 0.5
		var top := BALCONY_TOP + 1.05
		var guard := CollisionShape3D.new()
		guard.name = "RailingShape"
		var shape := BoxShape3D.new()
		shape.size = Vector3(rail_size.x, 1.05, rail_size.y) * tile_size
		guard.shape = shape
		guard.position = Vector3(center.x, BALCONY_TOP + 0.525, center.y) * tile_size
		body.add_child(guard, true)
		if style != RAIL_METAL:
			var half := Vector3(rail_size.x, 0, rail_size.y) * 0.5
			var base := Vector3(center.x, BALCONY_TOP, center.y)
			var border_height := 0.6 if style == RAIL_CRENEL else 1.05
			add_wall_box(body, "StoneBorder", base - half, base + half + Vector3.UP * border_height,
				wall_material(Color("c8ae8d")), tile_size, false)
			if style == RAIL_CRENEL:
				var teeth := maxi(1, roundi(rail_size.x / 1.25))
				var tooth_width := rail_size.x if teeth == 1 else rail_size.x / (teeth * 1.65 - 0.65)
				var stride := (rail_size.x - tooth_width) / maxi(1, teeth - 1)
				var tooth_size := Vector3(tooth_width, 1.05 - border_height, rail_size.y) * tile_size
				for index in teeth:
					var tooth_center := Vector3(center.x - half.x + tooth_width * 0.5 + stride * index,
						BALCONY_TOP + (border_height + 1.05) * 0.5, center.y) * tile_size
					bars.append_from(box, 0, Transform3D(Basis.from_scale(tooth_size), tooth_center))
			continue
		for y in [BALCONY_TOP + 0.13, top - 0.038]:
			var size := Vector3(rail_size.x, 0.075, rail_size.y) * tile_size
			bars.append_from(box, 0, Transform3D(Basis.from_scale(size), Vector3(center.x, y, center.y) * tile_size))
		var intervals := ceili(a.distance_to(b) / 0.23)
		for index in intervals:
			var point := a.lerp(b, float(index) / intervals)
			var size := Vector3(0.045, 1.0, 0.045) * tile_size
			bars.append_from(box, 0, Transform3D(Basis.from_scale(size), Vector3(point.x, BALCONY_TOP + 0.5, point.y) * tile_size))
	if style == RAIL_STONE:
		return
	var rail := MeshInstance3D.new()
	rail.name = "Crenellations" if style == RAIL_CRENEL else "Railings"
	rail.mesh = bars.commit()
	rail.material_override = wall_material(Color("c8ae8d") if style == RAIL_CRENEL else Color("455956"))
	body.add_child(rail)


static func entry_corners(entry: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for part in ["Landing", "Step1", "Step2"]:
		var tread := entry.get_node_or_null("Entry/" + part) as MeshInstance3D
		if tread == null:
			continue
		var box := tread.get_aabb()
		for x in [box.position.x, box.end.x]:
			for z in [box.position.z, box.end.z]:
				points.append(tread.to_global(Vector3(x, box.end.y, z)))
	return points


static func make_cornice(a: Vector3, b: Vector3, height: float, tile_size: float) -> Node3D:
	var span := Vector2(b.x - a.x, b.z - a.z).length() / tile_size
	if not is_finite(height) or span < 1.0 or span > MAX_FENCE_M:
		return null
	var root := Node3D.new()
	root.name = "PlotCornice"
	root.position = Vector3(a.x, height, a.z)
	root.rotation.y = atan2(a.z - b.z, b.x - a.x)
	var moulding := Node3D.new()
	moulding.name = "Cornice"
	root.add_child(moulding)
	var face := WALL_DEPTH_M * 0.5 - 0.0125
	var stone := wall_material(Color("dbc4a1"))
	add_wall_box(moulding, "Lower", Vector3(0, -0.125, face), Vector3(span, -0.0625, 0.26), stone, tile_size, false)
	add_wall_box(moulding, "Body", Vector3(0, -0.0625, face), Vector3(span, 0.0625, 0.31), stone, tile_size, false)
	add_wall_box(moulding, "Lip", Vector3(0, 0.0625, face), Vector3(span, 0.125, 0.39), stone, tile_size, false)
	return root


static func make_roof(size: Vector2, shape: int, height: float, color: Color, tile_size: float, bay: Dictionary = {}) -> Node3D:
	if not size.is_finite() or minf(size.x, size.y) < 2.0 or maxf(size.x, size.y) > MAX_FENCE_M:
		return null
	if shape < 0 or shape >= ROOF_FINISHES.size() or not is_finite(height) or height < 0.25 or height > 6.0:
		return null
	if not bay.is_empty() and (not roof_bay_fits(size, bay) or height < 0.75 or shape in [BuildingLayout.ROOF_FLAT, BuildingLayout.ROOF_PARAPET]):
		return null
	var roof := Node3D.new()
	roof.name = "PlotRoof"
	roof.set_meta(ROOF_META, {"size": size, "shape": shape, "height": height, "color": color, "bay": bay})
	var body := StaticBody3D.new()
	body.name = "Roof"
	roof.add_child(body)
	var outline := Rect2(Vector2.ZERO, size).grow(ROOF_OVERHANG)
	var slate := wall_material(color)
	var fascia := wall_material(color.darkened(0.2))
	if not bay.is_empty():
		add_bay_roof(body, size, bay, shape, height, slate, fascia, tile_size)
		return roof
	var a := Vector3(outline.position.x, -0.0625, outline.position.y)
	var b := Vector3(outline.end.x, 0.0, outline.end.y)
	if shape == BuildingLayout.ROOF_FLAT:
		b.y = height
		add_wall_box(body, "Deck", a, b, slate, tile_size)
	elif shape == BuildingLayout.ROOF_PARAPET:
		b.y = 0.125
		add_wall_box(body, "Deck", a, b, slate, tile_size)
		add_roof_parapet(body, outline, height, fascia, tile_size)
	else:
		b.y = ROOF_EAVE
		add_wall_box(body, "Deck", a, b, fascia, tile_size)
		add_roof_slopes(body, outline, shape, height, slate, tile_size, ROOF_EAVE)
	return roof


static func roof_bay_rect(size: Vector2, bay: Dictionary) -> Rect2:
	var width := float(bay.width)
	return Rect2(Vector2(size.x * 0.5 + float(bay.offset) - width * 0.5, -float(bay.depth)),
		Vector2(width, size.y + float(bay.depth)))


static func roof_bay_fits(size: Vector2, bay: Dictionary) -> bool:
	var side := int(bay.side)
	var depth := float(bay.depth)
	var width := float(bay.width)
	if side not in [0, 1, 2, 3] or depth < 0.5 or depth > 3.0 or width < 2.5 or width > 20.0:
		return false
	var length := size.y if side >= 2 else size.x
	var center := length * 0.5 + float(bay.offset)
	var half := float(bay.width) * 0.5
	return center - half >= 1.0 and center + half <= length - 1.0


static func roof_outline(size: Vector2, bay: Dictionary) -> Rect2:
	var outline := Rect2(Vector2.ZERO, size).grow(ROOF_OVERHANG)
	if bay.is_empty():
		return outline
	var depth := float(bay.depth)
	match int(bay.side):
		0: return Rect2(outline.position - Vector2(0, depth), outline.size + Vector2(0, depth))
		1: return Rect2(outline.position, outline.size + Vector2(0, depth))
		2: return Rect2(outline.position - Vector2(depth, 0), outline.size + Vector2(depth, 0))
		_: return Rect2(outline.position, outline.size + Vector2(depth, 0))


static func roof_border(size: Vector2, bay: Dictionary) -> PackedVector2Array:
	if bay.is_empty():
		var outline := roof_outline(size, bay)
		return PackedVector2Array([outline.position, Vector2(outline.end.x, outline.position.y),
			outline.end, Vector2(outline.position.x, outline.end.y)])
	var side := int(bay.side)
	var frame := Vector2(size.y, size.x) if side >= 2 else size
	var center := roof_bay_rect(frame, bay)
	var near := -ROOF_OVERHANG
	var far := frame.y + ROOF_OVERHANG
	var front := center.position.y - ROOF_OVERHANG
	var points := PackedVector2Array([Vector2(near, near), Vector2(center.position.x, near),
		Vector2(center.position.x, front), Vector2(center.end.x, front), Vector2(center.end.x, near),
		Vector2(frame.x + ROOF_OVERHANG, near), Vector2(frame.x + ROOF_OVERHANG, far), Vector2(near, far)])
	for index in points.size():
		var point := points[index]
		match side:
			1: points[index] = size - point
			2: points[index] = Vector2(point.y, size.y - point.x)
			3: points[index] = Vector2(size.x - point.y, point.x)
	return points


static func add_bay_roof(body: StaticBody3D, size: Vector2, bay: Dictionary, shape: int, height: float,
		slate: Material, fascia: Material, tile_size: float) -> void:
	match int(bay.side):
		1:
			body.rotation.y = PI
			body.position = Vector3(size.x, 0, size.y) * tile_size
		2:
			body.rotation.y = PI * 0.5
			body.position.z = size.y * tile_size
		3:
			body.rotation.y = -PI * 0.5
			body.position.x = size.x * tile_size
	if int(bay.side) >= 2:
		size = Vector2(size.y, size.x)
	var center := roof_bay_rect(size, bay)
	var wing_top := minf(1.5, height * 0.4)
	var left := Rect2(-ROOF_OVERHANG, -ROOF_OVERHANG, center.position.x + ROOF_OVERHANG, size.y + ROOF_OVERHANG * 2.0)
	var right := Rect2(center.end.x, left.position.y, size.x + ROOF_OVERHANG - center.end.x, left.size.y)
	for wing: Rect2 in [left, right]:
		var title := "Left" if wing == left else "Right"
		add_wall_box(body, title + "Deck", Vector3(wing.position.x, -0.0625, wing.position.y),
			Vector3(wing.end.x, ROOF_EAVE, wing.end.y), fascia, tile_size)
		add_roof_slopes(body, wing, BuildingLayout.ROOF_HIP, wing_top, slate, tile_size, ROOF_EAVE, title + "Slopes")
	var crown := Rect2(center.position - Vector2(0, ROOF_OVERHANG), center.size + Vector2(0, ROOF_OVERHANG * 2.0))
	add_wall_box(body, "BayDeck", Vector3(crown.position.x, wing_top - 0.1, crown.position.y),
		Vector3(crown.end.x, wing_top, crown.end.y), fascia, tile_size)
	add_roof_slopes(body, crown, shape, height, slate, tile_size, wing_top, "BaySlopes")
	var plaster := wall_material(Color("e1c9a2"))
	var edge := WALL_DEPTH_M * 0.5
	var front := center.position.y
	var lo := center.position.x
	var hi := center.end.x
	# Upper abutments receive the wing slopes. The returns below form the projecting storey.
	add_wall_box(body, "LeftAbutment", Vector3(lo, 0, front - edge), Vector3(lo + edge, wing_top, size.y), plaster, tile_size)
	add_wall_box(body, "RightAbutment", Vector3(hi - edge, 0, front - edge), Vector3(hi, wing_top, size.y), plaster, tile_size)
	add_wall_box(body, "BackAbutment", Vector3(lo + edge, 0, size.y - edge), Vector3(hi - edge, wing_top, size.y), plaster, tile_size)
	add_wall_box(body, "FrontAbutment", Vector3(lo + edge, 0, front - edge), Vector3(hi - edge, wing_top, front + edge), plaster, tile_size)
	add_wall_box(body, "LeftReturn", Vector3(lo, -WALL_HEIGHT_M, front + edge), Vector3(lo + edge, 0, edge), plaster, tile_size)
	add_wall_box(body, "RightReturn", Vector3(hi - edge, -WALL_HEIGHT_M, front + edge), Vector3(hi, 0, edge), plaster, tile_size)
	add_wall_box(body, "BayFloor", Vector3(lo - 0.06, -WALL_HEIGHT_M - 0.0625, front - edge - 0.06),
		Vector3(hi + 0.06, -WALL_HEIGHT_M + 0.125, 0), plaster, tile_size)
	add_wall_box(body, "BayBand", Vector3(lo - 0.045, -0.08, front - edge - 0.075),
		Vector3(hi + 0.045, ROOF_EAVE, front - edge + 0.035), plaster, tile_size, false)
	for index in 2:
		var x := lo + 0.4 if index == 0 else hi - 0.4
		add_wall_box(body, "BayCorbel%d" % index, Vector3(x - 0.11, -WALL_HEIGHT_M - 0.52, front * 0.42),
			Vector3(x + 0.11, -WALL_HEIGHT_M, 0), plaster, tile_size, false)
		add_wall_box(body, "BayCorbelCap%d" % index, Vector3(x - 0.15, -WALL_HEIGHT_M - 0.24, front * 0.86),
			Vector3(x + 0.15, -WALL_HEIGHT_M, 0), plaster, tile_size, false)
	var surface := func(point: Vector2) -> Vector3: return Vector3(point.x, 0, point.y) * tile_size
	var window := {"width": clampf(center.size.x * 0.34, 1.25, 2.75), "height": 1.75, "bottom": 0.625,
		"top_shape": TOP_ARCH if shape == ROOF_MANSARD else 0, "grid": 1, "sill": true, "casing": true}
	var window_wall := make_wall(Vector2(center.size.x, 0), Vector2.ZERO, WALL_WINDOW, surface, tile_size, 0.0, false, [], window)
	if window_wall != null:
		var wall := window_wall.get_node("Wall")
		var facade := window_wall.transform
		facade.origin += Vector3(lo, -WALL_HEIGHT_M, front) * tile_size
		for piece: Node3D in wall.get_children():
			wall.remove_child(piece)
			piece.name = "Bay" + str(piece.name)
			piece.transform = facade * piece.transform
			body.add_child(piece, true)
		window_wall.free()


static func add_roof_parapet(body: StaticBody3D, rect: Rect2, height: float, material: Material, tile_size: float) -> void:
	var lo := rect.position
	var hi := rect.end
	var band := 0.16
	add_wall_box(body, "ParapetFront", Vector3(lo.x, 0.125, lo.y), Vector3(hi.x, height, lo.y + band), material, tile_size)
	add_wall_box(body, "ParapetBack", Vector3(lo.x, 0.125, hi.y - band), Vector3(hi.x, height, hi.y), material, tile_size)
	add_wall_box(body, "ParapetLeft", Vector3(lo.x, 0.125, lo.y + band), Vector3(lo.x + band, height, hi.y - band), material, tile_size)
	add_wall_box(body, "ParapetRight", Vector3(hi.x - band, 0.125, lo.y + band), Vector3(hi.x, height, hi.y - band), material, tile_size)


static func roof_ring(rect: Rect2, height: float) -> PackedVector3Array:
	var a := rect.position
	var b := rect.end
	return PackedVector3Array([Vector3(a.x, height, a.y), Vector3(b.x, height, a.y),
		Vector3(b.x, height, b.y), Vector3(a.x, height, b.y)])


static func add_roof_slopes(body: StaticBody3D, rect: Rect2, shape: int, height: float, material: Material, tile_size: float,
		eave: float, title := "Slopes") -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	surface.set_smooth_group(-1)
	var lower := roof_ring(rect, eave)
	if shape == ROOF_MANSARD:
		var shoulder := Rect2(rect.position + rect.size * 0.17, rect.size * 0.66)
		var middle := roof_ring(shoulder, lerpf(eave, height, 0.74))
		add_roof_ring(surface, lower, middle, tile_size)
		lower = middle
		rect = shoulder
	var ridge := rect.get_center()
	var span := rect.size
	if span.x >= span.y:
		var half := span.x * 0.5 if shape == BuildingLayout.ROOF_GABLE else (span.x - span.y) * 0.5
		var left := Vector3(ridge.x - half, height, ridge.y)
		var right := Vector3(ridge.x + half, height, ridge.y)
		add_roof_ring(surface, lower, PackedVector3Array([left, right, right, left]), tile_size)
	else:
		var half := span.y * 0.5 if shape == BuildingLayout.ROOF_GABLE else (span.y - span.x) * 0.5
		var front := Vector3(ridge.x, height, ridge.y - half)
		var back := Vector3(ridge.x, height, ridge.y + half)
		add_roof_ring(surface, lower, PackedVector3Array([front, front, back, back]), tile_size)
	surface.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = surface.commit()
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = title + "Shape"
	collision.shape = visual.mesh.create_trimesh_shape()
	body.add_child(collision)


static func add_roof_ring(surface: SurfaceTool, low: PackedVector3Array, high: PackedVector3Array, tile_size: float) -> void:
	for index in 4:
		var next := (index + 1) % 4
		for triangle: Array in [[low[index], low[next], high[next]], [low[index], high[next], high[index]]]:
			if triangle[1].is_equal_approx(triangle[2]):
				continue
			for vertex: Vector3 in triangle:
				surface.add_vertex(vertex * tile_size)


static func wall_face_hit(wall: Node3D, ray_origin: Vector3, ray_direction: Vector3, tile_size: float) -> Dictionary:
	var end_x := wall_end(wall)
	if end_x <= 0.0:
		return {}
	var inverse := wall.global_transform.affine_inverse()
	var start := inverse * ray_origin
	var direction := inverse.basis * ray_direction
	if is_zero_approx(direction.z):
		return {}
	var side := -signf(direction.z)
	var face := side * wall_depth(wall) * tile_size * 0.5
	var distance := (face - start.z) / direction.z
	var hit := start + direction * distance
	if distance <= 0.0 or hit.x < 0.0 or hit.x > end_x or hit.y < 0.0 or hit.y > WALL_HEIGHT_M * tile_size:
		return {}
	var x := snappedf(hit.x, tile_size * 0.25)
	var half := PILASTER_HALF_WIDTH * tile_size
	var fits := false
	for title in ["Plaster", "PlasterLeft", "PlasterRight"]:
		var panel := wall.get_node_or_null("Wall/" + title) as MeshInstance3D
		if panel != null:
			var limits := panel.get_aabb()
			if x - half >= panel.position.x + limits.position.x and x + half <= panel.position.x + limits.end.x:
				fits = true
				break
	return {"distance": distance, "fits": fits, "wall": wall,
		"point": wall.transform * Vector3(x, 0, face),
		"angle": wall.rotation.y + (PI if side < 0.0 else 0.0)}


static func make_pilaster(point: Vector3, angle: float, tile_size: float) -> Node3D:
	var root := Node3D.new()
	root.name = "PlotPilaster"
	root.position = point
	root.rotation.y = angle
	var detail := Node3D.new()
	detail.name = "Pilaster"
	root.add_child(detail)
	var stone := wall_material(Color("e7d5b5"))
	var half := PILASTER_HALF_WIDTH
	add_wall_box(detail, "Base", Vector3(-half, 0.125, -0.018), Vector3(half, 0.375, 0.24), stone, tile_size, false)
	add_wall_box(detail, "Shaft", Vector3(-0.265, 0.375, -0.018), Vector3(0.265, WALL_HEIGHT_M - 0.375, 0.18), stone, tile_size, false)
	add_wall_box(detail, "Capital", Vector3(-half, WALL_HEIGHT_M - 0.375, -0.018),
		Vector3(half, WALL_HEIGHT_M - 0.125, 0.24), stone, tile_size, false)
	return root


static func make_floor(a: Vector2, b: Vector2, surface: Callable, tile_size: float, floor_y: float) -> Node3D:
	var rect := Rect2(a.min(b), (a - b).abs())
	if minf(rect.size.x, rect.size.y) < 1.0 or maxf(rect.size.x, rect.size.y) > MAX_FENCE_M:
		return null
	var start: Vector3 = surface.call(rect.position)
	var finish: Vector3 = surface.call(rect.end)
	if not start.is_finite() or not finish.is_finite():
		return null
	if not is_finite(floor_y):
		floor_y = start.y
	for point in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.get_center()]:
		var ground: Vector3 = surface.call(point)
		if not ground.is_finite() or ground.y > floor_y + tile_size * 0.125:
			return null
	var floor := Node3D.new()
	floor.name = "PlotFloor"
	floor.position = Vector3(minf(start.x, finish.x), floor_y, minf(start.z, finish.z))
	var body := StaticBody3D.new()
	body.name = "Slab"
	floor.add_child(body)
	var size := (finish - start).abs() / tile_size
	add_wall_box(body, "Floor", Vector3(0, -0.0625, 0), Vector3(size.x, FLOOR_TOP_M, size.z), wall_material(Color("a98764")), tile_size)
	return floor


static func round_profile(center: Vector2, edge: Vector2, half: bool) -> Dictionary:
	var radius := center.distance_to(edge)
	if radius < 1.5 or radius > 12.0:
		return {}
	return {"radius": radius, "angle": (edge - center).angle(), "half": half}


static func chamfer_profile(size: Vector2, cuts: Vector4) -> Dictionary:
	if minf(size.x, size.y) < 2.0 or maxf(size.x, size.y) > MAX_FENCE_M:
		return {}
	if maxf(cuts.x + cuts.y, cuts.z + cuts.w) > size.x - 0.5 \
			or maxf(cuts.y + cuts.z, cuts.w + cuts.x) > size.y - 0.5:
		return {}
	var half := size * 0.5
	var points := PackedVector2Array()
	for point: Vector2 in [Vector2(-half.x + cuts.x, -half.y), Vector2(half.x - cuts.y, -half.y),
			Vector2(half.x, -half.y + cuts.y), Vector2(half.x, half.y - cuts.z),
			Vector2(half.x - cuts.z, half.y), Vector2(-half.x + cuts.w, half.y),
			Vector2(-half.x, half.y - cuts.w), Vector2(-half.x, -half.y + cuts.x)]:
		if points.is_empty() or not points[-1].is_equal_approx(point):
			points.append(point)
	if points[-1].is_equal_approx(points[0]):
		points.resize(points.size() - 1)
	return {"points": points}


static func radial_path(radius: float, start: float, sweep: float) -> PackedVector2Array:
	var steps := maxi(ceili(absf(sweep) / deg_to_rad(6.0)), ceili(absf(sweep) * radius / 0.35))
	var points := PackedVector2Array()
	for index in steps + 1:
		points.append(Vector2.from_angle(start + sweep * index / steps) * radius)
	if is_equal_approx(sweep, TAU):
		points[-1] = points[0]
	return points


static func floor_outline(profile: Dictionary, overhang := 0.0) -> PackedVector2Array:
	if profile.has("points"):
		return profile.points
	var sweep := PI if profile.half else TAU
	var points := radial_path(profile.radius + overhang, profile.angle - sweep * 0.5, sweep)
	if not profile.half:
		points.resize(points.size() - 1)
	return points


static func make_contour_floor(center: Vector2, profile: Dictionary, surface: Callable, tile: float, floor_y: float) -> Node3D:
	var ground: Vector3 = surface.call(center)
	if not ground.is_finite():
		return null
	if not is_finite(floor_y):
		floor_y = ground.y
	var points := floor_outline(profile)
	for index in points.size():
		for offset in [points[index], points[index] * 0.5]:
			var sample: Vector3 = surface.call(center + offset)
			if not sample.is_finite() or sample.y > floor_y + 0.125 * tile:
				return null
	var floor := Node3D.new()
	floor.name = "PlotChamferFloor" if profile.has("points") else "PlotRoundFloor"
	floor.position = Vector3(ground.x, floor_y, ground.z)
	floor.set_meta(CONTOUR_FLOOR_META, profile)
	var body := StaticBody3D.new()
	body.name = "Slab"
	floor.add_child(body)
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_material(wall_finish(Color("c3b395"), 1, tile))
	var bottom := Vector3.DOWN * tile * 0.0625
	var top := Vector3.UP * tile * FLOOR_TOP_M
	for index in points.size():
		var a := flat_vertex(points[index], tile)
		var b := flat_vertex(points[(index + 1) % points.size()], tile)
		mesh.set_smooth_group(0)
		add_arc_quad(mesh, a + bottom, b + bottom, b + top, a + top)
		# The closing diameter goes through the fan origin.
		if not profile.get("half", false) or index < points.size() - 1:
			mesh.set_smooth_group(-1)
			for vertex in [top, a + top, b + top, bottom, b + bottom, a + bottom]:
				mesh.add_vertex(vertex)
	var visual := finish_arc_mesh(body, "Floor", mesh)
	add_arc_collision(body, "FloorShape", visual.mesh)
	return floor


static func flat_vertex(point: Vector2, tile: float) -> Vector3:
	return Vector3(point.x, 0, point.y) * tile


static func contour_floor_span(profile: Dictionary, first: Vector2, last: Vector2) -> Vector2:
	var points := floor_outline(profile)
	var span := Vector2(0, 1)
	for index in points.size():
		var origin := points[index]
		var side := origin.direction_to(points[(index + 1) % points.size()])
		var a := side.cross(first - origin) + 0.001
		var b := side.cross(last - origin) + 0.001
		if a < 0 and b < 0:
			return Vector2(1, 0)
		if a < 0:
			span.x = maxf(span.x, a / (a - b))
		elif b < 0:
			span.y = minf(span.y, a / (a - b))
	return span


static func round_roof_offset(profile: Dictionary) -> Vector2:
	return -Vector2.from_angle(profile.angle) * 0.25 if profile.get("half", false) else Vector2.ZERO


static func contour_roof_outline(profile: Dictionary) -> PackedVector2Array:
	if profile.has("points"):
		var outline := Geometry2D.offset_polygon(profile.points, ROOF_OVERHANG, Geometry2D.JOIN_MITER)[0]
		if (outline[1] - outline[0]).cross(outline[2] - outline[1]) < 0.0:
			outline.reverse()
		return outline
	var offset := round_roof_offset(profile)
	var rim := floor_outline(profile, ROOF_OVERHANG + offset.length())
	for index in rim.size():
		rim[index] += offset
	return rim


static func make_contour_roof(profile: Dictionary, height: float, color: Color, tile: float) -> Node3D:
	var root := Node3D.new()
	var chamfered := profile.has("points")
	var half: bool = profile.get("half", false)
	root.name = "PlotChamferRoof" if chamfered else "PlotRoundRoof"
	# Retain the serialized profile key used by the first contour roofs.
	root.set_meta(ROOF_META, {"round": profile, "shape": BuildingLayout.ROOF_HIP, "height": height, "color": color, "bay": {}})
	var body := StaticBody3D.new()
	body.name = "Roof"
	root.add_child(body)
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_material(wall_finish(color, 1, tile))
	var rim := contour_roof_outline(profile)
	var center := flat_vertex(round_roof_offset(profile), tile)
	var eave := Vector3.UP * tile * ROOF_EAVE
	var apex := center + Vector3.UP * tile * height
	for index in rim.size():
		var a := flat_vertex(rim[index], tile)
		var b := flat_vertex(rim[(index + 1) % rim.size()], tile)
		mesh.set_smooth_group(-1 if chamfered or (half and index == rim.size() - 1) else 0)
		for vertex in [a + eave, b + eave, apex]:
			mesh.add_vertex(vertex)
		mesh.set_smooth_group(-1)
		add_arc_quad(mesh, a, b, b + eave, a + eave)
		if not half or index < rim.size() - 1:
			for vertex in [center, b, a]:
				mesh.add_vertex(vertex)
	var visual := finish_arc_mesh(body, "ContourSlopes" if chamfered else "RoundSlopes", mesh)
	add_arc_collision(body, "RoundRoofShape", visual.mesh)
	return root


static func round_rail_path(profile: Dictionary, entrance: Vector2, style: int) -> PackedVector2Array:
	var width := 0.10 if style == RAIL_METAL else (0.22 if style == RAIL_STONE else CRENEL_WIDTH_M)
	var radius: float = profile.radius - width * 0.5 - 0.02
	var gap := asin(0.75 / radius)
	return radial_path(radius, entrance.angle() + gap, TAU - 2.0 * gap)


static func make_round_railing(profile: Dictionary, entrance: Vector2, tile: float, style: int) -> Node3D:
	var root := Node3D.new()
	root.name = "PlotRoundRailing"
	var width := 0.10 if style == RAIL_METAL else (0.22 if style == RAIL_STONE else CRENEL_WIDTH_M)
	var path := round_rail_path(profile, entrance, style)
	var outer := PackedVector3Array()
	var inner := PackedVector3Array()
	for point in path:
		var offset := point.normalized() * width * 0.5
		outer.append(flat_vertex(point + offset, tile))
		inner.append(flat_vertex(point - offset, tile))
	var deck := FLOOR_TOP_M * tile
	if style == RAIL_CRENEL:
		add_parapet_runs(root, [[outer, inner]], deck, tile)
		return root
	var body := StaticBody3D.new()
	body.name = "Railing"
	root.add_child(body)
	var guard := SurfaceTool.new()
	guard.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := deck + GUARD_HEIGHT_M * tile
	add_arc_strip(guard, outer, inner, deck, top)
	if style == RAIL_STONE:
		guard.set_material(wall_material(Color("c8ae8d")))
		var stone := finish_arc_mesh(body, "StoneBorder", guard)
		add_arc_collision(body, "RailingShape", stone.mesh)
		return root
	add_arc_collision(body, "RailingShape", guard.commit())
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	bars.set_material(wall_material(Color("455956")))
	add_arc_strip(bars, outer, inner, top - 0.07 * tile, top)
	add_arc_strip(bars, outer, inner, deck + 0.12 * tile, deck + 0.18 * tile)
	var intervals := ceili(float(path.size() - 1) * 1.25)
	for index in intervals + 1:
		var at := float(index) / intervals * (path.size() - 1)
		var start := clampf(at - 0.075, 0.0, path.size() - 1.0)
		var end := clampf(at + 0.075, 0.0, path.size() - 1.0)
		add_arc_strip(bars, arc_slice(outer, start, end), arc_slice(inner, start, end), deck, top - 0.07 * tile)
	finish_arc_mesh(body, "Railings", bars)
	return root


static func tower_faces(piece: Node3D) -> PackedVector2Array:
	var floor := piece.get_node("Slab/Floor") as MeshInstance3D
	var size := floor.get_aabb().size
	return PackedVector2Array([Vector2.ZERO, Vector2(0, size.z), Vector2(size.x, size.z), Vector2(size.x, 0)])


static func add_tower_ports(piece: Node3D, ports: int, tile: float, width := ARC_WALK_WIDTH_M) -> bool:
	var corners := tower_faces(piece)
	if minf(corners[2].x, corners[2].y) < (width + 1.0) * tile:
		return false
	piece.name = "PlotTowerDeck"
	piece.set_meta(TOWER_PORTS_META, ports)
	piece.set_meta(WALK_WIDTH_META, width)
	var runs := []
	var rail := CRENEL_WIDTH_M * tile
	var half_opening := (width * 0.5 - CRENEL_WIDTH_M) * tile
	for side in 4:
		var a := corners[side]
		var b := corners[(side + 1) % 4]
		var tangent := a.direction_to(b)
		var inward := Vector2(tangent.y, -tangent.x) * rail
		var inner_a := a + inward + tangent * rail
		var inner_b := b + inward - tangent * rail
		if ports & (1 << side):
			var center := (a + b) * 0.5
			var first := center - tangent * half_opening
			var last := center + tangent * half_opening
			runs.append(parapet_run(a, first, inner_a, first + inward))
			runs.append(parapet_run(last, b, last + inward, inner_b))
		else:
			runs.append(parapet_run(a, b, inner_a, inner_b))
	add_parapet_runs(piece, runs, FLOOR_TOP_M * tile, tile)
	return true


static func make_fortress_tower(a: Vector2, b: Vector2, surface: Callable, tile: float, base: float, height: float,
		depth: float, width: float, ports: int, color: Color, finish: int) -> Node3D:
	var rect := Rect2(a.min(b), (a - b).abs())
	if minf(rect.size.x, rect.size.y) < maxf(width + 1.0, depth * 2.0 + 1.0):
		return null
	if not is_finite(base):
		var ground: Vector3 = surface.call(rect.position)
		base = ground.y
	if not is_finite(base):
		return null
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	for side in 4:
		var start := corners[side]
		var end := corners[(side + 1) % 4]
		var steps := ceili(start.distance_to(end))
		for index in steps + 1:
			var ground: Vector3 = surface.call(start.lerp(end, float(index) / steps))
			if not ground.is_finite() or absf(ground.y - base) > 0.125 * tile:
				return null
	var tower := make_floor(a, b, surface, tile, base + height * tile)
	if tower == null:
		return null
	add_tower_ports(tower, ports, tile, width)
	tower.set_meta(TOWER_HEIGHT_META, height)
	tower.set_meta(WALL_DEPTH_META, depth)
	var body := StaticBody3D.new()
	body.name = "TowerWalls"
	tower.add_child(body)
	var stone := wall_finish(color, finish, tile)
	var x := rect.size.x
	var z := rect.size.y
	add_wall_box(body, "North", Vector3(0, -height, 0), Vector3(x, 0, depth), stone, tile)
	add_wall_box(body, "South", Vector3(0, -height, z - depth), Vector3(x, 0, z), stone, tile)
	add_wall_box(body, "West", Vector3(0, -height, depth), Vector3(depth, 0, z - depth), stone, tile)
	add_wall_box(body, "East", Vector3(x - depth, -height, depth), Vector3(x, 0, z - depth), stone, tile)
	return tower


static func parapet_run(a: Vector2, b: Vector2, inner_a: Vector2, inner_b: Vector2) -> Array:
	return [PackedVector3Array([Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y)]),
		PackedVector3Array([Vector3(inner_a.x, 0, inner_a.y), Vector3(inner_b.x, 0, inner_b.y)])]


static func straight_wall_ends(span: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3(span, 0, 0), Vector3.LEFT])


static func wall_ends(wall: Node3D) -> PackedVector3Array:
	var ends: PackedVector3Array = wall.get_meta(ARC_ENDS_META, PackedVector3Array())
	if ends.size() == 4:
		return ends
	var span := wall_end(wall)
	return straight_wall_ends(span) if span > 0.0 else PackedVector3Array()


static func add_wall_joins(wall: Node3D, body: StaticBody3D, ends: PackedVector3Array, neighbors: Array[Node3D], material: Material, tile_size: float) -> void:
	var inverse := wall.transform.affine_inverse()
	var half := wall_depth(wall) * tile_size * 0.5
	for endpoint in [0, 2]:
		var center := ends[endpoint]
		var direction := Vector2(ends[endpoint + 1].x, ends[endpoint + 1].z)
		for other in neighbors:
			var other_ends := wall_ends(other)
			if other_ends.is_empty():
				continue
			var other_half := wall_depth(other) * tile_size * 0.5
			var frame := inverse * other.transform
			for junction in [0, 2]:
				if (frame * other_ends[junction]).distance_to(center) >= tile_size * 0.0001:
					continue
				var delta := frame.basis * other_ends[junction + 1]
				var other_direction := Vector2(delta.x, delta.z).normalized()
				if absf(direction.cross(other_direction)) < 0.001:
					continue
				var a := direction.orthogonal()
				var b := other_direction.orthogonal()
				a *= -half if a.dot(other_direction) > 0 else half
				b *= -other_half if b.dot(direction) > 0 else other_half
				add_corner(body, center, a, b, WALL_HEIGHT_M * tile_size, material)


static func wall_end(wall: Node3D) -> float:
	var last := wall.get_node_or_null("Wall/PlasterRight") as MeshInstance3D
	if last == null:
		last = wall.get_node_or_null("Wall/Plaster") as MeshInstance3D
	return last.position.x + last.get_aabb().end.x if last != null and last.mesh != null else 0.0


static func add_corner(body: StaticBody3D, center: Vector3, a: Vector2, b: Vector2, height: float, material: Material) -> void:
	var low := PackedVector3Array([center, center + Vector3(a.x, 0, a.y), center + Vector3(b.x, 0, b.y)])
	if a.cross(b) < 0.0:
		low = PackedVector3Array([low[0], low[2], low[1]])
	var top := PackedVector3Array()
	for vertex in low:
		top.append(vertex + Vector3.UP * height)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	surface.set_smooth_group(-1)
	for point in [low[0], low[2], low[1], top[0], top[1], top[2]]:
		surface.add_vertex(point)
	for i in 3:
		var next := (i + 1) % 3
		for point in [low[i], low[next], top[next], low[i], top[next], top[i]]:
			surface.add_vertex(point)
	surface.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = "Corner"
	visual.mesh = surface.commit()
	body.add_child(visual, true)
	var hull := ConvexPolygonShape3D.new()
	hull.points = low + top
	var collision := CollisionShape3D.new()
	collision.name = "CornerShape"
	collision.shape = hull
	body.add_child(collision, true)


static func wall_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material


static func wall_finish(color: Color, finish_id: int, tile_size: float) -> StandardMaterial3D:
	var material := wall_material(color)
	if finish_id in [1, 2]:
		var is_masonry := finish_id == 2
		material.albedo_texture = load(MASONRY_TEXTURE if is_masonry else STONE_TEXTURE) as Texture2D
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_triplanar_sharpness = 8.0
		material.uv1_scale = Vector3.ONE / (tile_size * (1.8 if is_masonry else 2.4))
	return material


static func add_wall_box(body: Node3D, title: String, lo: Vector3, hi: Vector3, material: Material, scale_m: float, collidable := true) -> MeshInstance3D:
	var size := (hi - lo) * scale_m
	var center := (lo + hi) * (scale_m * 0.5)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = mesh
	visual.position = center
	body.add_child(visual)
	if not collidable:
		return visual
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = title + "Shape"
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	return visual


static func snapshot(map: Node) -> Dictionary:
	var result := {}
	var props := map.get_node_or_null("Props") if is_instance_valid(map) else null
	if props != null:
		for node in props.get_children():
			if node is Node3D and (node.has_meta(META) or node.has_meta(STREET_BRIDGE_META) or node.has_meta(SURFACE_ROAD_META)):
				result[node] = node.transform
	return result


static func restore(map: Node, scene: Node, baseline: Dictionary) -> void:
	var props := map.get_node_or_null("Props") if is_instance_valid(map) else null
	if props == null:
		return
	for node in snapshot(map):
		if not baseline.has(node):
			props.remove_child(node)
	for node in baseline:
		if not is_instance_valid(node):
			continue
		if node.get_parent() == null:
			attach(scene, props, node)
		if node.get_parent() == props:
			node.transform = baseline[node]


static func attach(scene: Node, parent: Node, node: Node3D) -> void:
	if node is EmberVoxelProp:
		EmberSceneAuthoring.attach_model_instance(scene, parent, node)
	else:
		parent.add_child(node, true)
		node.owner = scene
		if not node.scene_file_path.is_empty():
			return
		for panel in node.get_children():
			panel.owner = scene
			for child in panel.get_children():
				child.owner = scene
