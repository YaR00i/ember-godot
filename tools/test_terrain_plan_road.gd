extends "res://tools/test_terrain_plan_mountain.gd"
const StreetPlot = preload("res://addons/ember_import/ember_plot_construction.gd")

func road_plan() -> Resource:
	var plan := mountain_plan()
	var points := PackedVector2Array([Vector2(8,24),Vector2(18,24),Vector2(30,24),Vector2(40,24)])
	plan.regions.append({"id":"road","name":"Дорога","kind":"road","enabled":true,"points_m":points,"bounds":Plan.Influence.road_bounds(points,Plan.Influence.ROAD_DEFAULTS,Vector2i(48,48)),"parameters":Plan.Influence.ROAD_DEFAULTS.duplicate()})
	return plan

func _check_street_frontage() -> void:
	var points := PackedVector2Array([Vector2(14,28),Vector2(23,28),Vector2(30,30),Vector2(38,33)])
	var params: Dictionary = Plan.Influence.ROAD_DEFAULTS.duplicate()
	var road := {"id":"bend", "points_m":points, "parameters":params}
	var bounds := Rect2i(26,37,8,8)
	var plot := {"bounds": bounds}
	var layout := Plan.Influence.street_frontage(road, plot)
	check(not layout.is_empty(), "curved road gives a usable frontage")
	if layout.is_empty():
		return
	var left: PackedVector2Array = layout.runs[0]
	var right: PackedVector2Array = layout.runs[1]
	var path: PackedVector2Array = layout.approach
	var curve := Plan.Influence.path_curve(points)
	check(left[0] == Vector2(26,37) and right[-1] == Vector2(34,37), "fence returns touch the parcel corners")
	check(absf(left[-1].distance_to(right[0]) - StreetPlot.GAP_M) < 0.01, "gate keeps its clear opening on the curve")
	check(path[0].distance_to(path[1]) < 3.0 and curve.get_closest_point(path[1]).distance_to(path[1]) < params.width_m * 0.5,
		"short gate approach reaches the roadway")
	check(absf((left[3]-left[2]).normalized().cross((right[-3]-right[-4]).normalized())) > 0.02,
		"the fence bends along the shoulder")
	var envelope := Plan.Influence.street_plot_envelope(plot, layout)
	var gate_side := (path[1] - path[0]).normalized().orthogonal() * 0.6
	check(Geometry2D.is_point_in_polygon(path[1] + gate_side, envelope)
		and Geometry2D.is_point_in_polygon(path[1] - gate_side, envelope)
		and Geometry2D.is_point_in_polygon(Rect2(bounds).get_center(), envelope),
		"layout reserves the lot and both sides of the approach")
	var neighbor := Rect2i(29, 33, 3, 3)
	check(not neighbor.intersects(bounds) and not Geometry2D.intersect_polygons(
		envelope, Plan.Influence.plan_controls({"bounds":neighbor})).is_empty(),
		"neighboring plots can conflict with a frontage without overlapping its rectangle")
	var dry := func(point: Vector2) -> Vector3: return Vector3(point.x,0.0,point.y) * 16.0
	var frontage := StreetPlot.make_street_front(layout, dry, 16.0)
	check(frontage != null and frontage.has_node("Approach") and frontage.has_node("Gate"), "fence, gate and paved approach form one construction piece")
	if frontage != null:
		frontage.free()
	var blocked := func(point: Vector2) -> Vector3: return Vector3.INF if point.distance_to(path[1]) < 0.5 else dry.call(point)
	check(StreetPlot.make_street_front(layout, blocked, 16.0) == null, "approach refuses missing or wet ground")
	check(Plan.Influence.street_frontage(road, {"bounds":Rect2i(25,43,8,4)}).is_empty(), "distant parcel cannot extend to road")

func _check_rotated_plot_grid() -> void:
	var size := Vector2i(5, 7)
	var points := PackedVector2Array([Vector2(5, 8), Vector2(14, 12), Vector2(23, 17), Vector2(35, 25)])
	var road := {"id":"diagonal", "kind":"road", "points_m":points, "parameters":Plan.Influence.ROAD_DEFAULTS.duplicate()}
	var lots := Plan.Influence.street_plot_candidates(road, [road], Vector2i(48, 48), size, 1, 1, 0, 12,
		func(_lot: Dictionary): return true)
	check(lots.size() >= 2, "diagonal road fits multiple rotated plots")
	if lots.size() < 2:
		return
	var lot := lots[0]
	var frame: Transform2D = lot.plot_frame
	var frontage := Plan.Influence.street_frontage(road, lot)
	check(absf(frame.x.y) > 0.2 and absf(frame.x.dot(frame.y)) < 0.001 and frame.x.is_normalized(), "street rotates a unit plot grid")
	check(not frontage.is_empty() and (frame.affine_inverse() * frontage.approach[0]).y < 0.0, "gate lies in front of the rotated lot")
	var corners := Plan.Influence.plan_controls(lot)
	var resized := Plan.Influence.plan_edit(lot, 2, frame.basis_xform(Vector2(1, 2)), false)
	check(resized.plot_size_m == size + Vector2i(1, 2) and Plan.Influence.plan_controls(resized)[0].is_equal_approx(corners[0]),
		"resizing one rotated corner preserves the opposite corner")
	var plan := Plan.new()
	plan.upgrade_local_layers()
	lot.merge({"id":"lot", "name":"Rotated lot", "kind":"construction", "parameters":{}})
	plan.regions.append(lot)
	var restored: Resource = Plan.from_data(plan.data())
	check(restored != null and Plan.same(plan, restored), "saved plan round trips a rotated plot without changing its frame")
	var shifted: Resource = plan.translated(Vector2i(24, 12))
	check(shifted.validation_errors().is_empty() and shifted.regions[0].plot_frame.origin.is_equal_approx(frame.origin + Vector2(24, 12)),
		"map expansion shifts the plot origin with its bounds")
	lot.plot_frame = frame.scaled_local(Vector2(2, 1))
	check(not plan.validation_errors().is_empty(), "a scaled frame is rejected")

func _check_street_block() -> void:
	var road := func(id: String, points: Array) -> Dictionary:
		return {"id": id, "kind": "road", "points_m": PackedVector2Array(points),
			"parameters": {"width_m": 2.0, "edge_m": 0.5}}
	var north := road.call("north", [Vector2(8, 8), Vector2(32, 8)]) as Dictionary
	var east := road.call("east", [Vector2(36, 34), Vector2(36, 12), Vector2(35, 9), Vector2(32, 8)]) as Dictionary
	var south := road.call("south", [Vector2(36, 34), Vector2(8, 34)]) as Dictionary
	var west := road.call("west", [Vector2(8, 34), Vector2(8, 8)]) as Dictionary
	var alley := road.call("alley", [Vector2(21, 8), Vector2(21, 24)]) as Dictionary
	var detached := road.call("detached", [Vector2(11, 30), Vector2(15, 30)]) as Dictionary
	var outside := road.call("outside", [Vector2(8, 8), Vector2(3, 5)]) as Dictionary
	var regions := [north, east, south, west, alley, detached, outside]
	var block := Plan.Influence.street_block("north", regions)
	check(not block.is_empty(), "joined streets detect a block with a rounded corner and a dead end")
	if not block.is_empty():
		var count := {}
		var candidates := 0
		for seed: Dictionary in block.seeds:
			count[seed.road.id] = count.get(seed.road.id, 0) + 1
			var lots := Plan.Influence.street_plot_candidates(seed.road, regions, Vector2i(48, 48), Vector2i(4, 4), seed.side, 1, 0, 10,
				func(lot: Dictionary): return Geometry2D.clip_polygons(Plan.Influence.plan_controls(lot), block.outline).is_empty())
			if seed.road.id == "alley":
				candidates += lots.size()
		check(count == {"north":1, "east":1, "south":1, "west":1, "alley":2} and candidates > 0,
			"lots face the four inner curbs and both sides of the connected alley")
		check(block.outside_seeds.size() == 4 and block.outside_seeds.all(func(seed: Dictionary): return seed.road.id in ["north", "east", "south", "west"]),
			"outside preview uses only the outer curbs of the ring")
		var outer_seed: Dictionary = block.outside_seeds[0]
		var outer_lots := Plan.Influence.street_plot_candidates(outer_seed.road, regions, Vector2i(48,48), Vector2i(7,4), outer_seed.side, 1, 0, 10,
			func(lot: Dictionary): return Plan.Influence.street_block_fits(Plan.Influence.plan_controls(lot), block.outline, true))
		check(not outer_lots.is_empty() and outer_lots[0].plot_size_m == Vector2i(7,4),
			"a wide lot fits on the outside of the same ring")
		var crossing := Plan.Influence.rectangle_points(Rect2(16, 6, 4, 4))
		check(not Plan.Influence.street_block_fits(crossing,block.outline,true) and not Plan.Influence.street_block_fits(crossing,block.outline,false),
			"a shape straddling the ring is invalid on either side")
		check(Plan.Influence.street_block("east", regions).seeds.size() == 6, "selecting the reversed road finds the same block")
	check(Plan.Influence.street_block("north", [north, east, south, alley]).is_empty(), "a gap in the ring prevents placement")
	var diagonal := road.call("shortcut", [Vector2(8, 8), Vector2(36, 34)]) as Dictionary
	check(Plan.Influence.street_block("north", regions + [diagonal]).is_empty(), "a shared edge requires a unique ring")

func _check_street_plot_spacing() -> void:
	var road := {"id":"packing", "kind":"road", "points_m":PackedVector2Array([Vector2(4, 12), Vector2(25, 12)]),
		"parameters":{"width_m":2.0, "edge_m":0.5}}
	var existing := {"id":"existing", "kind":"construction", "bounds":Rect2i(4, 14, 1, 6)}
	var extent := Vector2i(48, 48)
	var size := Vector2i(4, 4)
	var available := func(_lot: Dictionary): return true
	var dense := Plan.Influence.street_plot_candidates(road, [road, existing], extent, size, 1, 0, 0, 20, available)
	check(dense.size() == 5, "quarter finds five lots in the twenty metres left beside an existing lot")
	var spaced := Plan.Influence.street_plot_candidates(road, [road, existing], extent, size, 1, 1, 0, 20, available)
	check(spaced.size() == 4 and is_equal_approx(spaced[0].plot_frame.origin.x, 6.0), "one metre gap also applies to previously placed lots")
	var diagonal := road.duplicate(true)
	diagonal.points_m = PackedVector2Array([Vector2(6, 6), Vector2(30, 18)])
	var normal := Vector2(-1.0, 2.0).normalized()
	var anchor := Vector2(18, 12) + normal * 7.0
	var placed := Plan.Influence.street_plot_candidates(diagonal, [diagonal], extent, size, -1, 0, 0, 20, available, anchor)
	diagonal.parameters.width_m = 4.0
	var wider := Plan.Influence.street_plot_candidates(diagonal, [diagonal], extent, size, -1, 0, 0, 20, available, anchor)
	check(placed.size() == 1 and wider.size() == 1, "manual placement yields a single lot on a diagonal street")
	if placed.size() == 1 and wider.size() == 1:
		var a: Transform2D = placed[0].plot_frame
		var b: Transform2D = wider[0].plot_frame
		check(a.y.is_equal_approx(normal) and (b.origin - a.origin).is_equal_approx(normal),
			"lot is perpendicular to the street and moves one metre when the road widens by two")

func _check_detailed_road_edge(source: Resource, parameters: Dictionary) -> void:
	var points := PackedVector2Array([Vector2(8,24),Vector2(18,24),Vector2(28,29),Vector2(38,34)])
	var plan := Plan.new()
	plan.upgrade_local_layers()
	plan.regions.append({"id":"curve", "name":"Curve", "kind":"road", "enabled":true, "points_m":points,
		"bounds":Plan.Influence.road_bounds(points, parameters, Vector2i(48,48)), "parameters":parameters})
	var job := compose(source, plan)
	if job.candidate == null:
		check(false, "detailed road composes")
		return
	var curve := Plan.Influence.path_curve(points)
	var paving_slot: int = job.candidate.palette_material_ids.find("paving")
	var half_width := float(parameters.width_m) * 0.5
	var mismatches := 0
	for station in range(4, floori(curve.get_baked_length()) - 3):
		var center := curve.sample_baked(station)
		var tangent := curve.sample_baked(station - 0.25).direction_to(curve.sample_baked(station + 0.25))
		var normal := Vector2(-tangent.y, tangent.x)
		for side in [-1.0, 1.0]:
			for margin in [-0.11, 0.11]:
				var point: Vector2 = center + normal * side * (half_width + margin)
				var cell := Vector2i((point * 16.0).floor())
				var slot: int = job.candidate.column_value("top_materials", source.column_index(cell.x, cell.y))
				if (slot == paving_slot) != (margin < 0.0):
					mismatches += 1
	check(mismatches == 0, "curved paving edge follows the road within 11 cm at the checked cross sections")

func _check_surface_road_profile() -> void:
	var region := {"id":"profile", "points_m":PackedVector2Array([Vector2(2,8),Vector2(12,8)]),
		"parameters":{"width_m":2.0, "surface":"paving"}}
	var dry := func(point: Vector2) -> Dictionary:
		var hit := {"solid":true, "position":Vector3(point.x, point.x * 0.2, point.y)}
		if point.x > 8.0:
			hit.object = true
		return hit
	var dry_result := StreetPlot.make_surface_road(region, dry, 1.0)
	check(dry_result.has("node") and dry_result.profile.spans.is_empty()
		and dry_result.profile.kinds.has(StreetPlot.RoadSupport.LEDGE), "smooth road profile reaches its ledge without proposing a bridge")
	if dry_result.has("node"):
		dry_result.node.free()
	for mode in ["void", "water", "cut", "open"]:
		var floor_sample := func(point: Vector2) -> Dictionary:
			if point.x < 5.0 or (mode != "open" and point.x > 8.0):
				return {"solid":true, "position":Vector3(point.x, 2.0, point.y), "object":true}
			if mode == "water" or mode == "cut":
				return {"solid":true, "position":Vector3(point.x, 0.0, point.y), "submerged":mode == "water"}
			return {"solid":false}
		var result := StreetPlot.make_surface_road(region, floor_sample, 1.0)
		check(result.has("error") and not result.has("node"), "unsafe %s road remains a preview" % mode)
		var spans: Array[Vector2i] = result.profile.spans
		check(spans.size() == (0 if mode == "open" else 1), "bridge needs two dry banks for %s" % mode)
		if spans.size() == 1:
			var spacing: float = result.profile.length / (result.profile.heights.size() - 1)
			check(absf(spans[0].x * spacing - 3.0) < 0.25 and absf(spans[0].y * spacing - 6.0) < 0.25, "proposal shows both ends of %s" % mode)
	region.bridge_over_gap = true
	var lake := func(point: Vector2, water_y: float) -> Dictionary:
		var wet := point.x >= 5.0 and point.x <= 8.0
		return {"solid":true, "position":Vector3(point.x, 0.0 if wet else 2.0, point.y),
			"submerged":wet, "road_water_y":water_y if wet else -INF}
	var bridged := StreetPlot.make_surface_road(region, lake.bind(1.0), 1.0)
	check(bridged.has("node") and bridged.profile.has("deck"), "confirmed bridge reports the fitted deck")
	if bridged.has("node"):
		var assembly: Node3D = bridged.node
		var deck := assembly.get_node_or_null("StreetBridge/DeckShape") as CollisionShape3D
		check(deck != null and assembly.get_child_count() == 3, "bridge uses a physical deck and two visual approaches")
		var fitted: Vector2i = bridged.profile.deck.rows
		var proposed: Vector2i = bridged.profile.spans[0]
		check(fitted.x < proposed.x and fitted.y > proposed.y, "deck reaches dry ground beyond both shores")
		assembly.free()
	var flooded := StreetPlot.make_surface_road(region, lake.bind(2.0), 1.0)
	check(flooded.has("error") and not flooded.has("node"), "bridge preview refuses a deck intersecting the water")
	var diagonal_shore := func(point: Vector2) -> Dictionary:
		if point.x > 8.0 and point.x < 8.45 and point.y > 8.25:
			return {"solid":true, "position":Vector3(point.x, 0, point.y), "submerged":true}
		return lake.call(point, 1.0)
	var proposal_region := region.duplicate()
	proposal_region.erase("bridge_over_gap")
	var diagonal := StreetPlot.make_surface_road(proposal_region, diagonal_shore, 1.0)
	check(diagonal.profile.spans.size() == 1, "proposal reaches the dry part of a diagonal shoreline")
	var unequal_banks := func(point: Vector2) -> Dictionary:
		var hit: Dictionary = lake.call(point, 1.0)
		if point.x > 8.0:
			hit.position.y += 0.3
		return hit
	var incline := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
	region.bridge_plank_roughness = 0.5
	region.bridge_railing = "lattice"
	var timber_incline := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
	if timber_incline.has("node"):
		var straight_deck := timber_incline.node.get_node("StreetBridge/DeckShape") as CollisionShape3D
		check(straight_deck.shape is BoxShape3D, "straight planks keep the original deck collision")
		_check_plank_rail_seams(timber_incline.node, region.parameters.width_m)
		timber_incline.node.free()
	else:
		check(false, "timber bridge fits a straight incline")
	region.erase("bridge_plank_roughness")
	region.bridge_rise_m = 0.25
	var arch := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
	check(incline.has("node") and arch.has("node"), "straight and arched decks both fit unequal banks")
	if incline.has("node") and arch.has("node"):
		var direct: PackedFloat32Array = incline.profile.deck.heights
		var curved: PackedFloat32Array = arch.profile.deck.heights
		var midpoint := floori(curved.size() * 0.5)
		check(is_equal_approx(direct[0], curved[0]) and is_equal_approx(direct[-1], curved[-1])
			and curved[midpoint] > maxf(curved[0], curved[-1]) and absf(curved[midpoint] - direct[midpoint] - 0.25) < 0.005,
			"arch changes the middle height while preserving both entries")
		var arch_deck := arch.node.get_node("StreetBridge/DeckShape") as CollisionShape3D
		check(arch_deck.shape is ConcavePolygonShape3D, "arch collision uses the generated deck mesh")
	for result in [incline, arch]:
		if result.has("node"):
			result.node.free()
	region.bridge_rise_m = 1.8
	var steep := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
	check(steep.has("error") and not steep.has("node"), "bridge rejects an over-steep rise")
	region.bridge_rise_m = 0.25
	for style in ["wood", "stone", "arch"]:
		region.bridge_supports = style
		var result := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
		check(result.has("node"), "%s bridge supports fit the bed beneath a sloped arch" % style)
		if result.has("node"):
			var supports := result.node.get_node("BridgeSupports") as MeshInstance3D
			check(supports.mesh.get_surface_count() == 1 and supports.get_child_count() == 0 and supports.mesh.get_aabb().position.y < -2.0,
				"%s supports form one visual mesh reaching into the bed" % style)
			result.node.free()
	var unsupported := func(point: Vector2) -> Dictionary:
		return {"solid":false} if point.x >= 5.0 and point.x <= 8.0 else unequal_banks.call(point)
	region.bridge_supports = "stone"
	var missing_bed := StreetPlot.make_surface_road(region, unsupported, 1.0)
	check(missing_bed.has("error") and not missing_bed.has("node"), "bridge refuses unsupported stone piers")
	region.points_m = PackedVector2Array([Vector2(2,8), Vector2(4,8.1), Vector2(6.5,8.55), Vector2(9,8.25), Vector2(12,8)])
	region.bridge_supports = "arch"
	var bent := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
	check(bent.has("node"), "bridge follows a bend and rises on the same path")
	if bent.has("node"):
		var body := bent.node.get_node("StreetBridge") as StaticBody3D
		var deck_mesh := body.get_node("Deck") as MeshInstance3D
		var support_mesh := bent.node.get_node("BridgeSupports") as MeshInstance3D
		var deck_shape := body.get_node("DeckShape") as CollisionShape3D
		check(deck_mesh.mesh.get_aabb().size.z > 2.2 and support_mesh.mesh.get_aabb().size.z > 1.7
			and deck_shape.shape.get_faces() == deck_mesh.mesh.get_faces(), "deck and supports bend and collision follows the deck mesh")
		var original_faces: PackedVector3Array = deck_shape.shape.get_faces()
		region.bridge_plank_roughness = 0.0
		var regular := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
		region.bridge_plank_roughness = 1.0
		var rough := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
		var repeat_rough := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
		check(regular.has("node") and rough.has("node") and repeat_rough.has("node"), "boards fit the curved deck")
		if regular.has("node") and rough.has("node") and repeat_rough.has("node"):
			var regular_mesh: Mesh = regular.node.get_node("BridgePlanks").mesh
			var rough_mesh: Mesh = rough.node.get_node("BridgePlanks").mesh
			check(rough_mesh.get_surface_count()==1 and regular_mesh.get_faces()!=rough_mesh.get_faces()
				and rough_mesh.get_faces()==repeat_rough.node.get_node("BridgePlanks").mesh.get_faces(), "roughness is visual and deterministic in one mesh")
			check(not rough.node.get_node("StreetBridge/Deck").visible and rough.node.get_node("StreetBridge/DeckShape").shape.get_faces()==original_faces,
				"planks leave the continuous collision intact")
			_check_plank_rail_seams(rough.node, region.parameters.width_m)
		for result in [regular,rough,repeat_rough]:
			if result.has("node"):
				result.node.free()
		region.erase("bridge_plank_roughness")
		bent.node.free()
	region.points_m = PackedVector2Array([Vector2(2,8), Vector2(6,8), Vector2(5.8,9.1), Vector2(10,9.1), Vector2(12,8)])
	var folded := StreetPlot.make_surface_road(region, unequal_banks, 1.0)
	check(folded.has("error") and not folded.has("node"), "reject a bridge that doubles back within its own width")

func _check_plank_rail_seams(assembly: Node3D, width: float) -> void:
	var boards := assembly.get_node("BridgePlanks") as MeshInstance3D
	var vertices := Array(boards.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var seams: Array[Plane] = []
	var stride := ceili(width / 0.25) + 1
	for part in assembly.get_children():
		if part is not MeshInstance3D or part.name in ["BridgeSupports", "BridgePlanks"]:
			continue
		var paving: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for row in [0, paving.size() - stride]:
			var left: Vector3 = part.position + paving[row]
			var right: Vector3 = part.position + paving[row + stride - 1]
			var has_left := vertices.any(func(point: Vector3): return (boards.position + point).distance_to(left) < 0.0005)
			var has_right := vertices.any(func(point: Vector3): return (boards.position + point).distance_to(right) < 0.0005)
			if has_left and has_right:
				seams.append(Plane((right - left).cross(Vector3.UP).normalized(), left))
	check(seams.size() == 2, "both paved ends terminate on a plank edge")
	if seams.size() != 2:
		return
	var bridge := assembly.get_node("StreetBridge") as StaticBody3D
	for side in ["Left", "Right"]:
		var handrail := bridge.get_node_or_null(side + "Handrail") as MeshInstance3D
		var guard := bridge.get_node_or_null(side + "GuardShape") as CollisionShape3D
		check(handrail != null and guard != null, "plank rail and guard follow the same strip")
		if handrail == null or guard == null:
			continue
		for faces: PackedVector3Array in [handrail.mesh.get_faces(), guard.shape.get_faces()]:
			for seam in seams:
				var has_cap := false
				for index in range(0, faces.size(), 3):
					var a := absf(seam.distance_to(bridge.transform * faces[index]))
					var b := absf(seam.distance_to(bridge.transform * faces[index + 1]))
					var c := absf(seam.distance_to(bridge.transform * faces[index + 2]))
					if maxf(a, maxf(b, c)) < 0.0005:
						has_cap = true
						break
				check(has_cap, "both rail ends and guards meet the plank edges")

func _check_road_junction(source: Resource) -> void:
	var host_only := Plan.new()
	host_only.upgrade_local_layers()
	var extent := Vector2i(48,48)
	var params: Dictionary = Plan.Influence.ROAD_DEFAULTS.duplicate()
	params.terrain_sampling = "fine16"
	params.surface = "paving"
	var points := PackedVector2Array([Vector2(8,24), Vector2(40,24)])
	host_only.regions.append({"id":"host", "name":"Host", "kind":"road", "points_m":points,
		"bounds":Plan.Influence.road_bounds(points,params,extent), "parameters":params})
	var baseline := compose(source, host_only)
	var input: Resource = baseline.output_plan.working_copy()
	points = PackedVector2Array([Vector2(24,24), Vector2(24,15)])
	var branch_params := params.duplicate()
	branch_params.surface = "soil"
	var branch := {"id":"branch", "name":"Branch", "kind":"road", "points_m":points, "road_join":{"host":"host","fraction":0.5},
		"bounds":Plan.Influence.road_bounds(points,branch_params,extent), "parameters":branch_params}
	input.regions.append(branch)
	var local := Job.new()
	var scope := branch.duplicate()
	scope.branch_edit = true
	check(local.begin(baseline.candidate,input,scope) and local.local_road,"junction can prepare only local tiles while preserving neighbours")
	while not local.finished and local.error.is_empty():
		local.step()
	check(local.finished and local.candidate != null,"junction composition " + local.error)
	if not local.finished:
		return
	var full := compose(baseline.candidate,input)
	check(local.candidate.same_terrain_data(full.candidate) and Plan.same(local.output_plan,full.output_plan),"local junction matches full composition")
	var center: int = source.column_index(24*16,24*16)
	var lane: int = source.column_index(24*16,20*16)
	check(local.candidate.column_value("top_materials",center)==baseline.candidate.column_value("top_materials",center)
		and local.candidate.column_value("heights",center)==baseline.candidate.column_value("heights",center)
		and local.candidate.column_value("top_materials",lane)==source.palette_surface_roles.find("soil"),
		"host stays level and keeps paving while branch can have its own finish")
	var shortened: Resource = local.output_plan.working_copy()
	shortened.regions[1].points_m = PackedVector2Array([Vector2(24,24),Vector2(24,20)])
	shortened.regions[1].bounds = Plan.Influence.road_bounds(shortened.regions[1].points_m,branch_params,extent)
	var trim := Job.new()
	check(trim.begin(local.candidate,shortened,scope) and trim.local_road,"branch edit includes the old footprint")
	while not trim.finished and trim.error.is_empty():
		trim.step()
	var old_end: int = source.column_index(24*16,15*16)
	check(trim.finished and trim.candidate.column_value("top_materials",old_end)==baseline.candidate.column_value("top_materials",old_end),
		"shortening branch removes old paving and restores ground")
	input.regions[0].enabled = false
	check(not input.validation_errors(extent).is_empty(),"active branch cannot lose its host")

func _run() -> void:
	_check_street_frontage()
	_check_rotated_plot_grid()
	_check_street_block()
	_check_street_plot_spacing()
	_check_surface_road_profile()
	var source := fixture(); var plan := road_plan(); var first := compose(source,plan)
	_check_road_junction(source)
	var soil: int = source.palette_surface_roles.find("soil"); var grass: int = source.palette_surface_roles.find("grass")
	if first.candidate == null: quit(1); return
	var layer: Dictionary = first._layers[1]
	check(layer.start_height_m == 6.0 and layer.end_height_m == 6.0,"road endpoint heights")
	var center := Vector2i(384,384); var index: int = source.column_index(center.x,center.y)
	check(first.candidate.column_value("heights",index) == 96 and first.candidate.column_value("top_materials",index) == soil,"road core height/material")
	for x in range(8*16,40*16,8):
		var i: int = source.column_index(x,24*16)
		check(first.candidate.column_value("heights",i) == 96 and first.candidate.column_value("top_materials",i) == soil,"road centre gap")
	var mountain := compose(source,mountain_plan())
	var supported: Resource = plan.working_copy()
	supported.regions[1].support_placement_id = "fixture_ledge"
	var support_job := compose(source, supported)
	check(support_job.candidate != null and support_job.candidate.same_terrain_data(mountain.candidate),
		"road over a volume preserves ground geometry and paint")
	check(support_job.output_plan != null and support_job.output_plan.regions[1].support_placement_id == "fixture_ledge",
		"terrain composition retains the road's selected support")
	check(first.candidate.column_value("heights",source.column_index(24*16,30*16)) == mountain.candidate.column_value("heights",source.column_index(24*16,30*16)),"outside corridor changed")
	check(first.candidate.column_value("heights",source.column_index(24*16,27*16)) > 96,"shoulder not blended")
	check(source.column_value("heights",index) == 96 and plan.patches.is_empty(),"road source mutated")
	for key in source.sections:
		for channel in ["water_levels","water_materials","water_flow"]: check(first.candidate.sections[key].get(channel) == source.sections[key].get(channel),"road changed water "+channel)
	var repeat := compose(first.candidate,first.output_plan,1300)
	check(repeat.candidate != null and repeat.candidate.same_terrain_data(first.candidate) and Plan.same(repeat.output_plan,first.output_plan),"road repeat accumulation")
	check(compose(source,plan,50000).candidate.same_terrain_data(first.candidate),"road work budget changed geometry")
	var scoped_overlap := Job.new()
	check(scoped_overlap.begin(source, plan, plan.regions[1]) and not scoped_overlap.local_road,
		"road intersecting a mountain must use full composition")
	scoped_overlap.cancel()
	var isolated: Resource = mountain.output_plan.working_copy()
	var isolated_road: Dictionary = plan.regions[1].duplicate(true)
	isolated_road.points_m = PackedVector2Array([Vector2(8,44),Vector2(24,44),Vector2(40,44)])
	isolated_road.bounds = Plan.Influence.road_bounds(isolated_road.points_m, isolated_road.parameters, Vector2i(48,48))
	isolated.regions.append(isolated_road)
	var scoped := Job.new()
	check(scoped.begin(mountain.candidate, isolated, isolated_road) and scoped.local_road,
		"independent road must use local composition")
	while not scoped.finished and scoped.error.is_empty():
		scoped.step()
	var whole := compose(mountain.candidate, isolated)
	check(scoped.candidate != null and scoped.candidate.same_terrain_data(whole.candidate)
		and Plan.same(scoped.output_plan, whole.output_plan), "independent road matches full composition")
	var reverse: Resource = plan.working_copy(); reverse.regions[1].points_m.reverse()
	check(compose(source,reverse).candidate.same_terrain_data(first.candidate),"road reverse changed geometry")
	var moved: Resource = first.output_plan.working_copy()
	var points := PackedVector2Array([Vector2(8,40),Vector2(20,40),Vector2(40,40)])
	moved.regions[1].points_m = points; moved.regions[1].bounds = Plan.Influence.road_bounds(points,moved.regions[1].parameters,Vector2i(48,48))
	var move := compose(first.candidate,moved)
	check(move.candidate != null and move.candidate.column_value("heights",index) == 192 and move.candidate.column_value("top_materials",index) == grass,"old road terrain/material not restored")
	var off: Resource = first.output_plan.working_copy(); off.regions[1].enabled = false
	check(compose(first.candidate,off).candidate.same_terrain_data(mountain.candidate),"road off did not restore previous mountain")
	var deleted: Resource = first.output_plan.working_copy(); deleted.regions.clear()
	check(compose(first.candidate,deleted).candidate.same_terrain_geometry(source,true),"road/layers delete did not restore source")
	for channel in ["heights","top_materials","water_levels","side","flow"]:
		var manual: Resource = first.candidate.working_copy(); var part: Resource = manual.sections[Vector2i(1,1)].working_copy()
		if channel == "side": part.column_material_overrides[0] = {0:1}
		elif channel == "flow": part.water_flow.resize(24*24); part.water_flow[0] = Vector2(0.1,0.2)
		else:
			var values: Variant = part.get(channel); values[0] = values[0]+4 if channel == "heights" else 4 if channel == "water_levels" else grass; part.set(channel,values)
		manual.sections[Vector2i(1,1)] = part
		var keep := compose(manual,moved)
		if keep.candidate == null: quit(1); return
		check(keep.protected_blocks.has(center/16),"road protection missing "+channel)
		check(keep.candidate.column_value("heights",index) == manual.column_value("heights",index) and keep.candidate.column_value("top_materials",index) == manual.column_value("top_materials",index) and keep.candidate.flow_at_cell(center.x,center.y) == manual.flow_at_cell(center.x,center.y),"road erased manual "+channel)
	var slope: Resource = plan.working_copy(); points = PackedVector2Array([Vector2(12,24),Vector2(24,24)])
	slope.regions[1].points_m = points; slope.regions[1].bounds = Plan.Influence.road_bounds(points,slope.regions[1].parameters,Vector2i(48,48))
	reject(source,slope,"excessive road grade accepted")
	slope.regions[1].parameters.grade_percent = 50.0
	var allowed := compose(source,slope)
	check(allowed.candidate != null and allowed._layers[1].end_height_m == 12.0,"allowed grade rejected")
	var invalid: Resource = plan.working_copy(); points = PackedVector2Array([Vector2(8,4),Vector2(32,4)])
	invalid.regions[1].points_m = points; invalid.regions[1].bounds = Plan.Influence.road_bounds(points,invalid.regions[1].parameters,Vector2i(48,48))
	reject(source,invalid,"wet road accepted")
	invalid = plan.working_copy(); invalid.regions[1].parameters.width_m = NAN
	check(not invalid.validation_errors().is_empty(),"road NaN accepted")
	invalid = plan.working_copy(); invalid.regions[1].points_m[1] = Vector2(INF,24)
	check(not invalid.validation_errors().is_empty(),"road invalid points accepted")
	var paved_plan: Resource = plan.working_copy()
	paved_plan.regions[1].parameters.surface = "paving"
	var paved := compose(source, paved_plan)
	if paved.candidate == null: quit(1); return
	var paving_slot: int = paved.candidate.palette_material_ids.find("paving")
	check(paving_slot > 0 and paved.candidate.column_value("top_materials", index) == paving_slot, "paving covers the road core")
	check(source.palette_material_ids.find("paving") == -1, "paving preview leaves the source palette intact")
	var shoulder: int = source.column_index(24 * 16, 27 * 16)
	check(paved.candidate.column_value("top_materials", shoulder) == first.candidate.column_value("top_materials", shoulder)
		and paved.candidate.column_value("heights", index) == first.candidate.column_value("heights", index), "surface selection changes only the core finish")
	var repaved := compose(paved.candidate, paved.output_plan)
	check(repaved.candidate.same_terrain_data(paved.candidate), "repeat paving reuses the same material slot")
	var unpaved: Resource = paved.output_plan.working_copy()
	unpaved.regions[1].parameters.erase("surface")
	check(compose(paved.candidate, unpaved).candidate.column_value("top_materials", index) == soil, "switch paving back to soil")
	paved_plan.regions[1].parameters.surface = "unknown"
	check(not paved_plan.validation_errors().is_empty(), "unknown road surface rejected")
	var missing_soil: Resource = source.working_copy(); missing_soil.palette_surface_roles[soil] = ""; missing_soil.palette_material_ids[soil] = ""
	reject(missing_soil,plan,"road without soil role accepted")
	var legacy: Resource = mountain.output_plan.working_copy(); legacy.schema_version = 5
	var v5: Resource = Plan.from_data(legacy.data()); check(v5 != null,"v5 read")
	var upgraded: Resource = v5.working_copy(); upgraded.upgrade_local_layers()
	check(upgraded.patches == v5.patches and v5.schema_version == 5,"v5 upgrade mutated provenance")
	var shifted: Resource = first.output_plan.translated(Vector2i(24,24))
	check(shifted.validation_errors(Vector2i(96,96)).is_empty() and shifted.regions[1].points_m[0] == Vector2(32,48),"road translated points/patches")
	var dock := VBoxContainer.new(); dock.size = Vector2(302,650); var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme; root.add_child(dock)
	var panel := LakePanel.new(); dock.add_child(panel); await process_frame
	panel.open_influence(plan.regions[1].bounds,plan.regions[1].parameters,"road")
	var detailed_params: Dictionary = plan.regions[1].parameters.merged({"terrain_sampling":"fine16"})
	check(panel._road_grid.visible and not panel._river_grid.visible and panel.parameters() == detailed_params,
		"road dock proposes fine sampling for a recipe without an explicit resolution")
	panel._fine.button_pressed = false
	check(panel.parameters().get("terrain_sampling") == "legacy8", "explicit coarse resolution survives reopening")
	panel.open_influence(plan.regions[1].bounds, panel.parameters(), "road")
	check(not panel._fine.button_pressed, "opening an explicit coarse road preserves its resolution")
	panel._fine.button_pressed = true
	panel._road_surface.select(1)
	panel._road_surface.item_selected.emit(1)
	check(panel.parameters().get("surface") == "paving", "choose paving in the normal road panel")
	_check_detailed_road_edge(source, panel.parameters())
	panel.set_ready("Ready"); panel._road_fields.edge_m.value = 3.0; check(panel.get_apply_button().disabled,"stale road Apply")
	for i in 5: await process_frame
	check(panel.get_combined_minimum_size().x <= 302 and dock.get_global_rect().encloses(panel.get_apply_button().get_global_rect()),"road dock overflow"); dock.free()
	var folder := "user://ember-tests/road-%d" % Time.get_ticks_usec(); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var terrain_path := folder.path_join("terrain.res"); var scene_path := folder.path_join("map.tscn")
	check(ResourceSaver.save(source,terrain_path) == OK,"road fixture save")
	var scene := Node3D.new(); scene.scene_file_path = scene_path; root.add_child(scene)
	var map := EmberMapLoader.new(); map.name = "Map"; map.hydrate_legacy_regions = false; map.authored_size_blocks = Vector2i(48,48)
	map.compact_terrain = ResourceLoader.load(terrain_path,"",ResourceLoader.CACHE_MODE_IGNORE); scene.add_child(map); map.owner = scene; map.set_meta(Plan.META,plan)
	var editor := Editor.new(); root.add_child(editor); editor.scene = scene; var history := UndoRedo.new()
	editor.sessions.configure(history,func() -> int:
		var packed := PackedScene.new(); var error := packed.pack(scene); return ResourceSaver.save(packed,scene_path) if error == OK else error)
	editor.sessions.recovery_directory = folder.path_join("recovery")
	var draft := editor.sessions.open_map(map,scene)
	var context := {"draft":draft,"version":draft.resource.working_copy(),"candidate":first.candidate,"output_plan":first.output_plan,"plan_version":plan.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"road commit")
	history.undo(); check(draft.resource.same_terrain_data(source) and Plan.read(map).patches.is_empty(),"road atomic Undo")
	history.redo(); check(draft.resource == first.candidate and Plan.same(Plan.read(map),first.output_plan),"road Redo")
	check(not editor.commit_terrain_composition(map,context).is_empty(),"stale road commit")
	check(editor.sessions.save_all(scene),editor.sessions.error)
	var reopened := (ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),first.output_plan) and reopened.get_node("Map").compact_terrain.same_terrain_data(first.candidate),"road fresh Save/Reopen"); reopened.free()
	check(editor.commit_terrain_plan(map,moved).is_empty(),"move road recipe")
	context = {"draft":draft,"version":draft.resource.working_copy(),"candidate":move.candidate,"output_plan":move.output_plan,"plan_version":moved.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"move road commit")
	editor.sessions.write_recovery(); editor.sessions.discard(scene)
	check(draft.resource.same_terrain_data(first.candidate),"road Discard")
	check(editor.sessions.restore_recovery(scene) == 1 and draft.resource.same_terrain_data(move.candidate) and Plan.same(Plan.read(map),move.output_plan),"road recovery")
	var paving_recipe: Resource = move.output_plan.working_copy()
	paving_recipe.regions[1].parameters.surface = "paving"
	paving_recipe.regions[1].parameters.terrain_sampling = "fine16"
	check(editor.commit_terrain_plan(map, paving_recipe).is_empty(), "save paving recipe")
	var finished_road := compose(draft.resource, paving_recipe)
	check(finished_road.candidate != null, "compose changed paving recipe")
	context = {"draft":draft,"version":draft.resource.working_copy(),"candidate":finished_road.candidate,"output_plan":finished_road.output_plan,"plan_version":paving_recipe.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map, context).is_empty(), "apply paving recipe")
	history.undo()
	check(draft.resource.same_terrain_data(move.candidate), "undo applied paving")
	history.redo()
	check(draft.resource == finished_road.candidate, "redo applied paving")
	check(editor.sessions.save_all(scene), editor.sessions.error)
	reopened = (ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	var reopened_map := reopened.get_node("Map") as EmberMapLoader
	check(Plan.read(reopened_map).regions[1].parameters.surface == "paving"
		and Plan.read(reopened_map).regions[1].parameters.terrain_sampling == "fine16"
		and reopened_map.compact_terrain.same_terrain_data(finished_road.candidate), "paving Save/Reopen")
	reopened.free()
	history.clear_history(); editor.sessions.release(); editor.free(); history.free(); scene.free()
	print("ROAD_PLAN ","PASS" if errors.is_empty() else errors," cpu_ms=",first.elapsed_us/1000.0," repeat_ms=",repeat.elapsed_us/1000.0," worst_step_ms=",first.worst_step_us/1000.0," tiles=",first.changed_tiles.size())
	quit(0 if errors.is_empty() else 1)
