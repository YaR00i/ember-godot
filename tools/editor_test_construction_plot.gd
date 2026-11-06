@tool
extends "res://tools/editor_test_terrain_plan.gd"
## Run as a plugin in an isolated project copy, using a disposable flat map.
const Plot = preload("res://addons/ember_import/ember_plot_construction.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const GrassMaterials = preload("res://scripts/ember_voxel_surface_materials.gd")
const LAWN_MASK_STEP := 0.125
const WALK_START := Vector2(7, 9)
const WALK_TURN := Vector2(15, 4.75)
const WALK_END := Vector2(23, 9)
const FORTRESS_WIDTH := 2.75
const FORTRESS_HEIGHT := 4.5
const FORTRESS_DEPTH := 0.625
const TOWER_LINKS := [
	[Vector2(33, 7), Vector2(37.5, 6.25), Vector2(42, 7), Vector2.RIGHT, Vector2.LEFT],
	[Vector2(44, 9), Vector2(44.5, 11.5), Vector2(45, 14), Vector2.DOWN, Vector2.UP],
]

func poses(map: Node) -> Dictionary:
	var result := {}
	for node: Node3D in Plot.snapshot(map):
		result[str(node.name)] = node.transform
	return result


func click(world: Node, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	plot_pointer(world, point, event)


func plot_pointer(world: Node, point: Vector2, event: InputEventMouse, pointer_height := INF) -> void:
	var props: Node3D = world.map.get_node("Props")
	var ground: Vector3 = world._plot_ground(point, props)
	var height: float = pointer_height if is_finite(pointer_height) else world._plot_pointer_y(props)
	if is_finite(height):
		ground.y = height
	event.position = _camera.unproject_position(props.to_global(ground))
	world.forward_input(_camera, event)


func click_deck(world: Node, point: Vector2, height: float) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	plot_pointer(world, point, event, height)


func opening_wall(map: Node, part: String) -> Node3D:
	for node: Node3D in Plot.snapshot(map):
		if node.has_node("Wall/" + part):
			return node
	return null


func check_inset(wall: Node3D, part: String) -> void:
	check(wall != null, part + " wall exists")
	if wall == null:
		return
	var frame := wall.get_node_or_null("Wall/FrameTop") as MeshInstance3D
	if frame == null:
		frame = wall.get_node("Wall/CrownFrame") as MeshInstance3D
	var bottom := wall.get_node("Wall/FrameBottom") as MeshInstance3D
	var fill := wall.get_node("Wall/" + part) as MeshInstance3D
	var plaster := wall.get_node("Wall/PlasterLeft") as MeshInstance3D
	var frame_depth := frame.get_aabb().size.z
	var fill_depth := (fill.mesh as BoxMesh).size.z
	check(is_zero_approx(fill.position.z) and fill_depth < frame_depth and frame_depth < (plaster.mesh as BoxMesh).size.z,
		part + " is recessed inside the frame and the wall")
	check(is_equal_approx(fill.position.y - (fill.mesh as BoxMesh).size.y * 0.5,
		bottom.position.y + (bottom.mesh as BoxMesh).size.y * 0.5), part + " meets the lower frame")
	check(is_equal_approx(fill.position.y + fill.get_aabb().end.y, frame.position.y + frame.get_aabb().position.y),
		part + " meets the upper frame")
	check(wall.get_node_or_null("Wall/" + part + "Shape") is CollisionShape3D, part + " collider exists")


func build_mansion(world: Node, panel: Control, plot_id: String) -> void:
	var a := Vector2(5, 29)
	var b := Vector2(40, 29)
	var c := Vector2(40, 43)
	var d := Vector2(5, 43)
	var front := Vector2(21, 29)
	var back := Vector2(25, 43)
	var fa := Vector2(14, 29)
	var fb := Vector2(30, 29)
	var ba := Vector2(15, 43)
	var bb := Vector2(32, 43)
	var rows := [
		[fa, a, Plot.WALL_WINDOW],
		[front, fa, Plot.WALL_WINDOW],
		[fb, front, Plot.WALL_WINDOW],
		[b, fb, Plot.WALL_WINDOW],
		[c, b, Plot.WALL_WINDOW],
		[bb, c, Plot.WALL_WINDOW],
		[back, bb, Plot.WALL_WINDOW],
		[ba, back, Plot.WALL_WINDOW],
		[d, ba, Plot.WALL_WINDOW],
		[a, d, Plot.WALL_WINDOW],
		[front, back, Plot.WALL_PASSAGE],
	]
	for level in Plot.LEVEL_COUNT:
		panel._buttons.plot_level.select(level)
		panel._buttons.plot_level.item_selected.emit(level)
		panel._buttons.plot_floor.pressed.emit()
		check(world._plot_level == level and world._plot_tool == "plot_floor", "floor tool uses the selected level")
		click(world, c)
		click(world, a)
		panel._buttons.wall_color.color = [Color("cdb49a"), Color("e1c9a2"), Color("ead8ba")][level]
		panel._buttons.wall_finish.select([2, 1, 0][level])
		for index in rows.size():
			var row: Array = rows[index]
			var kind: int = row[2]
			if index == 1 and level < 2:
				kind = Plot.WALL_DOOR if level == 0 else Plot.WALL_PASSAGE
			panel._buttons.wall_opening.select(kind)
			panel._buttons.wall_opening.item_selected.emit(kind)
			if kind in [Plot.WALL_WINDOW, Plot.WALL_DOOR]:
				panel._buttons.custom_opening.button_pressed = true
				var width := 2.5 if level == 1 or kind == Plot.WALL_DOOR else 2.0
				panel._buttons.opening_width.value = 0.875 if level == 2 and index == 9 else width
				panel._buttons.opening_height.value = [1.625, 2.25, 1.5][level] if kind == Plot.WALL_WINDOW else 2.75
				panel._buttons.opening_bottom.value = 0.5 if level == 1 else 0.75
				panel._buttons.opening_top.select(Plot.TOP_TRIANGLE if kind == Plot.WALL_DOOR or level == 0 else (Plot.TOP_ARCH if level == 1 else 0))
				panel._buttons.opening_grid.select(2 if level == 1 else 1)
				panel._buttons.opening_sill.select(1)
				panel._buttons.opening_casing.select(1 if kind == Plot.WALL_DOOR or index % 2 == 0 else 0)
				var closed := (level == 0 and index == 2) or (level == 1 and index == 5) or (level == 2 and index == 9)
				panel._buttons.opening_shutters.select(2 if closed else 1)
				if level == 1 and index == 0:
					panel._buttons.opening_bottom.value = 1.0
					panel._buttons.plot_wall.pressed.emit()
					check(world._plot_tool.is_empty(), "opening taller than the wall is rejected")
					panel._buttons.opening_bottom.value = 0.5
			panel._buttons.plot_wall.pressed.emit()
			click(world, row[0])
			click(world, row[1])
		check_mansion(world.map, plot_id, level + 1)


func check_mansion(map: EmberMapLoader, plot_id: String, levels: int) -> void:
	var props := map.get_node("Props") as Node3D
	var tile := map.imported_tile_size
	var datum := Plot.level_origin(props, plot_id, tile)
	var floors := [0, 0, 0]
	var windows := [0, 0, 0]
	var passages := [0, 0, 0]
	var corners := [0, 0, 0]
	var closed_shutters := 0
	var open_shutters := 0
	var small_window := false
	var checked_window: Node3D
	var entry_door: Node3D
	for node: Node3D in Plot.snapshot(map):
		if node.get_meta(Plot.META, "") != plot_id or not (node.has_node("Wall") or node.has_node("Slab")):
			continue
		var level := int(node.get_meta(Plot.LEVEL_META, -1))
		check(level >= 0 and level < levels, "plot member belongs to a built floor")
		if level < 0 or level >= levels:
			continue
		check(is_equal_approx(node.position.y, datum + level * 3.0 * tile), "every piece uses the common level datum")
		if node.has_node("Slab/FloorShape"):
			var shape := node.get_node("Slab/FloorShape") as CollisionShape3D
			check(is_equal_approx((shape.shape as BoxShape3D).size.x, tile * 35.0), "slab spans the wide mansion")
			floors[level] += 1
		elif node.has_node("Wall/WindowPane"):
			windows[level] += 1
			var settings: Dictionary = node.get_meta("_ember_opening", {})
			var pane := node.get_node("Wall/WindowPane") as MeshInstance3D
			var wall := node.get_node("Wall/PlasterLeft") as MeshInstance3D
			check((wall.mesh as BoxMesh).material.albedo_color == [Color("cdb49a"), Color("e1c9a2"), Color("ead8ba")][level],
				"wall keeps the paint selected when placing the opening")
			var finish := (wall.mesh as BoxMesh).material as StandardMaterial3D
			var texture_path := finish.albedo_texture.resource_path if finish.albedo_texture != null else ""
			check(texture_path == [Plot.MASONRY_TEXTURE, Plot.STONE_TEXTURE, ""][level], "the selected material survives on the wall")
			var lintel := node.get_node("Wall/Lintel") as MeshInstance3D
			check((lintel.mesh as BoxMesh).material == finish and finish.uv1_world_triplanar == (level < 2),
				"the wall and lintel share the same surface projection")
			var casing := node.get_node_or_null("Wall/CasingHead") as MeshInstance3D
			check((casing != null) == settings.get("casing", false), "window casing is optional")
			if casing != null:
				check(casing.position.z + casing.get_aabb().end.z > tile * Plot.WALL_DEPTH_M * 0.5, "window casing projects outside the wall")
			var width := float(settings.get("width", 0.0))
			small_window = small_window or is_equal_approx(width, 0.875)
			check(is_equal_approx(pane.get_aabb().size.x / tile, width - 0.25) and width in [0.875, 2.0, 2.5],
				"window width and authoring parameters persist")
			var sill := node.get_node_or_null("Wall/OuterSill") as MeshInstance3D
			var anchor := node.get_node_or_null("Wall/WindowBoxAnchor") as Marker3D
			check(sill != null and anchor != null and is_equal_approx(anchor.position.y, sill.position.y + sill.get_aabb().end.y),
				"external sill provides an attachment position above its surface")
			check(node.has_node("Wall/GridCrossbar") and node.has_node("Wall/GridUpright1") and node.has_node("Wall/GridUpright3") == (level == 1),
				"the window has the selected four or eight sections")
			if level < 2:
				check_crown(node, tile, 13 if level == 1 else 3)
			var shutter_left := node.get_node_or_null("Wall/ShutterLeft") as MeshInstance3D
			var shutter_right := node.get_node_or_null("Wall/ShutterRight") as MeshInstance3D
			check(shutter_left != null and shutter_right != null, "window owns two exterior shutter leaves")
			if shutter_left != null and shutter_right != null:
				var closed: bool = settings.get("shutters") == 2
				check((shutter_left.basis.x.x > 0) == closed and (shutter_right.basis.x.x > 0) == closed,
					"both shutters preserve the chosen angle")
				var left_center := shutter_left.transform * shutter_left.get_aabb().get_center()
				var right_center := shutter_right.transform * shutter_right.get_aabb().get_center()
				check(minf(left_center.z, right_center.z) > tile * Plot.WALL_DEPTH_M * 0.5,
					"shutters sit on the street side of the wall")
				if closed:
					closed_shutters += 1
				else:
					open_shutters += 1
			if level == levels - 1:
				checked_window = node
		elif node.has_node("Wall/DoorPanel"):
			entry_door = node
			check_crown(node, tile, 3)
			var casing := node.get_node_or_null("Wall/CasingHead") as MeshInstance3D
			check(casing != null and casing.position.z + casing.get_aabb().end.z > tile * Plot.WALL_DEPTH_M * 0.5,
				"the doorway's shaped casing projects past the wall")
			check(node.has_node("Wall/OuterHandleLever") and node.has_node("Wall/InnerHandleLever"), "door has two handles")
		elif node.has_node("Wall/FrameTop"):
			passages[level] += 1
			check(not node.has_node("Wall/FrameBottomShape"), "interior passage leaves the walking surface open")
		for child in node.get_children():
			for piece in child.get_children():
				if piece is CollisionShape3D and piece.shape is ConvexPolygonShape3D:
					corners[level] += 1
	for level in levels:
		var expected_windows := 9 if level < 2 else 10
		var expected_passages := 2 if level == 1 else 1
		check(floors[level] == 1 and windows[level] == expected_windows and passages[level] == expected_passages and corners[level] == 8,
			"level %d: slabs=%d windows=%d passages=%d joins=%d" % [level + 1, floors[level], windows[level], passages[level], corners[level]])
	check_inset(entry_door, "DoorPanel")
	check_inset(checked_window, "WindowPane")
	check(closed_shutters > 0 and open_shutters > 0 and (levels < 3 or small_window),
		"the facade contains both shutter states, including a small window")


func check_crown(node: Node3D, tile: float, vertices: int) -> void:
	var body := node.get_node("Wall")
	for title in ["CrownPlasterLeft", "CrownPlasterRight", "CrownFrame", "CrownPane"]:
		check(body.get_node_or_null(title) is MeshInstance3D and body.get_node_or_null(title + "Shape") is CollisionPolygon3D,
			title + " has a visible profile and matching collision")
	var pane := body.get_node_or_null("CrownPaneShape") as CollisionPolygon3D
	check(pane != null and pane.polygon.size() == vertices and is_equal_approx(pane.depth / tile, 0.05),
		"crown uses the requested profile and remains recessed")


func check_double_door(wall: Node3D, tile: float, shape: int) -> void:
	var left := wall.get_node_or_null("Wall/DoorLeafLeft") as MeshInstance3D
	var right := wall.get_node_or_null("Wall/DoorLeafRight") as MeshInstance3D
	check(left != null and right != null and not wall.has_node("Wall/DoorPanel"), "double door has two separate leaves")
	if left == null or right == null:
		return
	var seam := right.position.x + right.get_aabb().position.x - left.position.x - left.get_aabb().end.x
	check(is_equal_approx(seam / tile, Plot.DOUBLE_DOOR_GAP), "a real seam separates the leaves along their full height")
	var body := wall.get_node("Wall")
	for suffix in ["Left", "Right"]:
		var collision := body.get_node_or_null("DoorLeaf" + suffix + "Shape")
		check(collision is CollisionShape3D if shape == 0 else collision is CollisionPolygon3D,
			"each leaf has its own matching collision")
		check(body.has_node("InnerHandleLever" + suffix) and body.has_node("OuterHandleLever" + suffix),
			"each leaf has a handle on both faces")
	var options := Plot.placed_opening_options(wall, tile)
	check(options.double_leaf and options.top_shape == shape and not wall.has_node("Wall/CrownPane"),
		"two leaves use the opening profile without a fixed upper pane")
	check(not wall.has_node("Wall/GridUpright1"), "a decorative crossbar does not cover the seam")


func check_double_door_profiles() -> void:
	var ground := func(point: Vector2) -> Vector3: return Vector3(point.x, 0, point.y) * 16.0
	for shape in [0, Plot.TOP_ARCH]:
		var options := {"width": 2.25, "height": 2.5, "bottom": 0.0, "top_shape": shape, "double_leaf": true}
		var wall := Plot.make_wall(Vector2.ZERO, Vector2(4, 0), Plot.WALL_DOOR, ground, 16.0, 0.0, true, [], options)
		check(wall != null, "generate a flat or arched double door")
		if wall != null:
			check_double_door(wall, 16.0, shape)
			wall.free()
	var options := {"width": 2.25, "height": 2.5, "bottom": 0.0, "center": 2.0, "double_leaf": true, "top_shape": Plot.TOP_ARCH}
	var thick := Plot.make_wall(Vector2.ZERO, Vector2(4, 0), Plot.WALL_DOOR, ground, 16.0, 0.0, true, [], options,
		Color.WHITE, 0, FORTRESS_DEPTH)
	thick.set_meta(Plot.META, "qa")
	options.center = 2.25
	var moved := Plot.remake_opening_wall(thick, options, Color.WHITE, 0, 16.0)
	check(moved != null, "move a door in a thicker wall")
	if moved != null:
		var plaster := moved.get_node("Wall/PlasterLeft") as MeshInstance3D
		var collision := moved.get_node("Wall/PlasterLeftShape") as CollisionShape3D
		check(is_equal_approx(plaster.get_aabb().size.z / 16.0, FORTRESS_DEPTH)
			and collision.shape.size.is_equal_approx(plaster.get_aabb().size), "door edits retain wall thickness in view and physics")
		moved.free()
	thick.free()


func check_entry(map: EmberMapLoader) -> void:
	var entry := map.get_node_or_null("Props/PlotEntry/Entry") as StaticBody3D
	check(entry != null, "entry platform belongs to the saved scene")
	if entry == null:
		return
	var rise := map.imported_tile_size * Plot.ENTRY_RISE
	for index in 3:
		var title: String = ["Landing", "Step1", "Step2"][index]
		var shape := entry.get_node_or_null(title + "Shape") as CollisionShape3D
		check(shape != null and is_equal_approx(shape.position.y + (shape.shape as BoxShape3D).size.y * 0.5, (3 - index) * rise),
			title + " has the expected physical height")
	var landing := entry.get_node("Landing") as MeshInstance3D
	check(entry.to_global(landing.position).z < entry.global_position.z, "the landing is on the exterior side of the door")
	check(not entry.has_node("PorticoRoof"), "porch remains clear below the balcony")


func check_balcony(map: EmberMapLoader, plot_id: String, width: float, depth: float, columns: bool) -> void:
	var props := map.get_node("Props") as Node3D
	var tile := map.imported_tile_size
	var count := 0
	for member: Node3D in Plot.snapshot(map):
		if member.get_meta(Plot.META, "") != plot_id or not member.has_node("Balcony"):
			continue
		count += 1
		var body := member.get_node("Balcony")
		var deck := body.get_node("DeckShape") as CollisionShape3D
		var size := (deck.shape as BoxShape3D).size
		var datum := Plot.level_origin(props, plot_id, tile)
		check(is_equal_approx(size.x / tile, width) and is_equal_approx(size.z / tile, depth), "balcony matches the selected facade span and depth")
		check(is_equal_approx(member.position.y, datum + Plot.WALL_HEIGHT_M * tile)
			and is_equal_approx((deck.position.y + size.y * 0.5) / tile, 0.125), "balcony deck is flush with the second-floor surface")
		var rail := body.get_node("Railings") as MeshInstance3D
		check(rail.mesh.get_surface_count() == 1, "railing bars are batched in one visual mesh")
		var guards := 0
		for child in body.get_children():
			if child is CollisionShape3D and str(child.name).begins_with("RailingShape"):
				guards += 1
		check(guards == 3, "front and sides block falls, the wall side remains open")
		for index in 2:
			var cap := body.get_node_or_null("Column%dCapitalShape" % index) as CollisionShape3D
			check((cap != null) == columns, "columns respect the option")
			if cap != null:
				var top := cap.position.y + (cap.shape as BoxShape3D).size.y * 0.5
				check(is_equal_approx(top / tile, Plot.BALCONY_UNDERSIDE), "column capital meets the underside of the deck")
	check(count == 1, "one balcony is saved on the house")


func check_cornices(map: EmberMapLoader, plot_id: String) -> void:
	var props := map.get_node("Props") as Node3D
	var tile := map.imported_tile_size
	var datum := Plot.level_origin(props, plot_id, tile)
	var runs := [0, 0, 0]
	for node: Node3D in Plot.snapshot(map):
		if node.get_meta(Plot.META, "") != plot_id or not node.has_node("Cornice"):
			continue
		var level := int(node.get_meta(Plot.LEVEL_META, -1))
		check(level >= 0 and level < 3, "cornice remembers the selected floor")
		if level < 0 or level >= 3:
			continue
		runs[level] += 1
		check(is_equal_approx(node.position.y, datum + (level + 1) * Plot.WALL_HEIGHT_M * tile), "cornice follows the top of its own floor")
		var lip := node.get_node("Cornice/Lip") as MeshInstance3D
		check(lip.position.z + lip.get_aabb().end.z > tile * Plot.WALL_DEPTH_M * 0.5, "cornice projects from the facade")
	check(runs == [2, 2, 2], "two facade sides have distinct trim runs on each level")


func click_facade(world: Node, x: float, level: int) -> void:
	var props := world.map.get_node("Props") as Node3D
	var tile: float = world.map.imported_tile_size
	var point := Vector3(x * tile, world._plot_level_y(props) + tile * 1.5, (29.0 - Plot.WALL_DEPTH_M * 0.5) * tile)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = _camera.unproject_position(props.to_global(point))
	world.forward_input(_camera, event)
	check(world._plot_level == level or world._plot_tool.is_empty(), "facade click uses the active level")


func place_pilasters(world: Node, panel: Control) -> void:
	for level in Plot.LEVEL_COUNT:
		panel._buttons.plot_level.select(level)
		panel._buttons.plot_level.item_selected.emit(level)
		if level == 1:
			var before := poses(world.map)
			panel._buttons.plot_pilaster.pressed.emit()
			click_facade(world, 17.5, level)
			check(poses(world.map) == before, "pilaster placement refuses to cover the centered window")
		for x in [13.25, 20.25, 29.25]:
			panel._buttons.plot_pilaster.pressed.emit()
			click_facade(world, x, level)


func check_pilasters(map: EmberMapLoader, plot_id: String) -> void:
	var props := map.get_node("Props") as Node3D
	var tile := map.imported_tile_size
	var datum := Plot.level_origin(props, plot_id, tile)
	var axes := [[], [], []]
	for node: Node3D in Plot.snapshot(map):
		if node.get_meta(Plot.META, "") != plot_id or not node.has_node("Pilaster"):
			continue
		var level := int(node.get_meta(Plot.LEVEL_META, -1))
		check(level >= 0 and level < 3, "pilaster keeps the chosen floor")
		if level < 0 or level > 2:
			continue
		axes[level].append(snappedf(node.position.x / tile, 0.25))
		check(is_equal_approx(node.position.y, datum + level * Plot.WALL_HEIGHT_M * tile), "pilaster uses the facade datum")
		check(node.basis.z.dot(Vector3.FORWARD) > 0.99
			and is_equal_approx(node.position.z / tile, 29.0 - Plot.WALL_DEPTH_M * 0.5), "pilaster sits on the exterior face")
		check(node.has_node("Pilaster/Base") and node.has_node("Pilaster/Shaft") and node.has_node("Pilaster/Capital"), "pilaster profile survives")
	for axis: Array in axes:
		axis.sort()
		check(axis == [13.25, 20.25, 29.25], "three aligned pilasters on the floor")


func check_roof_geometry() -> void:
	for form in Plot.ROOF_FINISHES.size():
		var roof := Plot.make_roof(Vector2(4, 6), form, 1.75, Plot.ROOF_COLOR, 16.0)
		check(roof != null, "roof form %d builds on a narrow footprint" % form)
		if roof == null:
			continue
		var highest := -INF
		var body := roof.get_node("Roof") as StaticBody3D
		for child in body.get_children():
			if child is MeshInstance3D:
				highest = maxf(highest, child.position.y + child.get_aabb().end.y)
		check(is_equal_approx(highest, 1.75 * 16.0), "roof form %d reaches the requested height" % form)
		check(body.get_node_or_null("DeckShape") is CollisionShape3D, "roof deck has a collider")
		if form not in [Plot.BuildingLayout.ROOF_FLAT, Plot.BuildingLayout.ROOF_PARAPET]:
			var slopes := body.get_node_or_null("SlopesShape") as CollisionShape3D
			check(slopes != null and slopes.shape is ConcavePolygonShape3D, "slopes use the same geometry for collision")
			var roof_mesh := body.get_node("Slopes") as MeshInstance3D
			check(is_equal_approx(roof_mesh.get_aabb().position.z / 16.0, -Plot.ROOF_OVERHANG)
				and Plot.ROOF_OVERHANG > 0.39 and Plot.ROOF_EAVE > 0.125, "front eave clears the cornice")
		roof.free()


func check_roofs(map: EmberMapLoader, plot_id: String, shape: int, height: float, color: Color) -> void:
	var props := map.get_node("Props") as Node3D
	var tile := map.imported_tile_size
	var datum := Plot.level_origin(props, plot_id, tile)
	var count := 0
	for member: Node3D in Plot.snapshot(map):
		if member.get_meta(Plot.META, "") != plot_id or not member.has_meta(Plot.ROOF_META):
			continue
		count += 1
		check(is_equal_approx(member.position.y, datum + 9.0 * tile) and member.get_meta(Plot.LEVEL_META) == 2,
			"roof assembly stays above the third floor")
		var settings: Dictionary = member.get_meta(Plot.ROOF_META)
		check(settings.size == Vector2(35, 14) and settings.shape == shape and settings.height == height and settings.color == color,
			"roof preserves its footprint, shape, height and color")
		check_bay(member, tile)
	check(count == 1, "the bay and roofs are one editable assembly")


func check_bay(roof: Node3D, tile: float) -> void:
	var center := roof.get_node_or_null("Roof/BaySlopes") as MeshInstance3D
	var left := roof.get_node_or_null("Roof/LeftSlopes") as MeshInstance3D
	var right := roof.get_node_or_null("Roof/RightSlopes") as MeshInstance3D
	check(center != null and left != null and right != null, "the raised roof has two lower wings")
	if center == null or left == null or right == null:
		return
	var settings: Dictionary = roof.get_meta(Plot.ROOF_META)
	check(is_equal_approx(center.get_aabb().end.y, settings.height * tile), "the raised roof reaches the requested height")
	check(is_equal_approx(left.get_aabb().end.x, center.get_aabb().position.x)
		and is_equal_approx(right.get_aabb().position.x, center.get_aabb().end.x), "wing meshes terminate at the bay without overlap")
	var front := roof.get_node("Roof/BayWindowPane") as MeshInstance3D
	check(is_equal_approx(front.position.z, -settings.bay.depth * tile)
		and roof.has_node("Roof/LeftAbutmentShape") and roof.has_node("Roof/RightAbutmentShape"),
		"the projected facade supports the upper roof and closes both joins")


func place_edges(world: Node, panel: Control) -> void:
	var sections := [
		[Vector2(15.25, 29), Vector2(3.5, 29), 1.5, Plot.EDGE_STONE],
		[Vector2(41.5, 29), Vector2(19.5, 29), 1.5, Plot.EDGE_STONE],
		[Vector2(40, 43), Vector2(40, 29), 1.5, Plot.EDGE_STONE],
		[Vector2(5, 29), Vector2(5, 43), 1.5, Plot.EDGE_STONE],
		[Vector2(3.5, 43), Vector2(41.5, 43), 1.5, Plot.EDGE_STONE],
		[Vector2(41.5, 42.5), Vector2(41.5, 30), 1.5, Plot.EDGE_SOIL],
		[Vector2(14, 27.5), Vector2(5, 27.5), 1.5, Plot.EDGE_SHRUBS],
	]
	for spec: Array in sections:
		panel._buttons.edge_depth.value = spec[2]
		panel._buttons.edge_style.select(spec[3])
		panel._buttons.plot_edge.pressed.emit()
		click(world, spec[0])
		click(world, spec[1])


func check_edges(map: EmberMapLoader, plot_id: String) -> void:
	var tile := map.imported_tile_size
	var counts := [0, 0, 0]
	var front: CollisionShape3D
	var side: CollisionShape3D
	for node: Node3D in Plot.snapshot(map):
		if node.get_meta(Plot.META, "") != plot_id or not node.has_node("Edge"):
			continue
		var style := int(node.get_meta("_ember_plot_edge_style", -1))
		check(style in [Plot.EDGE_STONE, Plot.EDGE_SOIL, Plot.EDGE_SHRUBS], "edge style is saved on the node")
		if style < 0 or style > Plot.EDGE_SHRUBS:
			continue
		counts[style] += 1
		if style == Plot.EDGE_STONE:
			var shape := node.get_node_or_null("Edge/PavingBaseShape") as CollisionShape3D
			var paving := node.get_node_or_null("Edge/Paving") as MultiMeshInstance3D
			check(shape != null and paving != null and paving.multimesh.instance_count > 1, "stone tiles share a continuous collision surface")
			if shape != null:
				var size := (shape.shape as BoxShape3D).size
				check(is_equal_approx((shape.position.y + size.y * 0.5) / tile, Plot.EDGE_TOP), "stone collision meets the tile tops")
				if is_equal_approx(size.x / tile, 21.75):
					front = shape
				elif is_equal_approx(size.x / tile, 14.0) and is_equal_approx(node.position.x / tile, 40.0):
					side = shape
		else:
			var rim := node.get_node_or_null("Edge/FarRimShape") as CollisionShape3D
			var soil := node.get_node_or_null("Edge/SoilShape") as CollisionShape3D
			check(rim != null and soil != null and rim.position.y > soil.position.y, "soil is below the stone rim")
			var shrubs := node.get_node_or_null("Edge/Shrubs") as MultiMeshInstance3D
			check((shrubs != null) == (style == Plot.EDGE_SHRUBS), "shrub variant preserves the chosen fill")
			if shrubs != null:
				check(shrubs.multimesh.instance_count == 6, "a 9 m planter reuses six shrubs in one batch")
				check(shrubs.get_meta("_ember_bush_generator", "") == "bush"
					and shrubs.has_meta("_ember_bush_seed"), "the planter persists its existing generator identity and seed")
	check(counts == [5, 1, 1], "five paving runs and two planter variants survive")
	check(front != null and side != null, "the front and side paving meet")
	if front != null and side != null:
		var front_size := (front.shape as BoxShape3D).size
		var side_size := (side.shape as BoxShape3D).size
		var front_bounds := front.global_transform * AABB(-front_size * 0.5, front_size)
		var side_bounds := side.global_transform * AABB(-side_size * 0.5, side_size)
		check(is_equal_approx(front_bounds.end.z, side_bounds.position.z)
			and is_equal_approx(front_bounds.end.x, side_bounds.end.x)
			and is_equal_approx(front_bounds.end.y, side_bounds.end.y), "front and side paving touch without overlap or a step")


func _run() -> void:
	if OS.get_environment("EMBER_PLOT_EVIDENCE").is_empty() or not ProjectSettings.globalize_path("res://").contains("ember-entry-"):
		return
	check_roof_geometry()
	check_double_door_profiles()
	await frames(30)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null:
		printerr("Construction fixture requires EmberImportPlugin")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline:
		await frames(1)
	var id := "construction_" + str(OS.get_process_id())
	var creation := Creation.new()
	creation.scene_directory = "res://qa_generation/scenes"
	creation.terrain_directory = "res://qa_generation/terrains"
	if not creation.prepare_sections(id, 2, 3, 12):
		printerr(creation.error)
		get_tree().quit(2)
		return
	var path := creation.commit()
	if path.is_empty():
		printerr(creation.error)
		get_tree().quit(2)
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	var scene := EditorInterface.get_edited_scene_root()
	var open_deadline := Time.get_ticks_msec() + 10000
	while (scene == null or scene.scene_file_path != path) and Time.get_ticks_msec() < open_deadline:
		await frames(1)
		scene = EditorInterface.get_edited_scene_root()
	if scene == null or scene.scene_file_path != path:
		printerr("Construction fixture did not open")
		get_tree().quit(2)
		return
	await frames(24)
	var map := scene.get_node("Map") as EmberMapLoader
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	world.scene_changed(scene)
	world.category.select(0)
	world._category_changed(0)
	await ready_tiles(map._visual_surface_projection)
	EditorInterface.set_main_screen_editor("3D")
	_camera = Camera3D.new()
	EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(640, 700, 700), Vector3(245, 10, 235))
	_camera.far = 4000
	_camera.make_current()
	world._plan_button.pressed.emit()
	var panel: Control = world._plan_panel
	panel._add_menu.get_popup().id_pressed.emit(panel.ADD_ACTIONS.find("add_plot"))
	var first := Rect2i(4, 4, 23, 23)
	select_rect(world, first)
	var plan: Resource = Plan.read(map)
	if plan == null or plan.regions.is_empty():
		printerr("Construction plot was not created")
		get_tree().quit(3)
		return
	var plot_id: String = plan.regions[0].id
	check(plan.regions[0].bounds == first and plan.regions[0].kind == "construction", "plot created with the exact viewport selection")
	check(panel._plot_tools.visible and panel._house.item_count >= 2, "plot tools expose existing houses")
	for index in 2:
		panel._house.select(index)
		panel._buttons.plot_house.pressed.emit()
		click(world, [Vector2(10, 16), Vector2(20, 16)][index])
	check(poses(map).size() == 2, "two clicks place two scene-owned houses")
	panel._buttons.wall_opening.select(Plot.WALL_WINDOW)
	panel._buttons.plot_wall.pressed.emit()
	click(world, Vector2(7, 22))
	click(world, Vector2(13, 25))
	panel._buttons.wall_opening.select(Plot.WALL_DOOR)
	panel._buttons.plot_wall.pressed.emit()
	click(world, Vector2(13, 25))
	click(world, Vector2(21, 25))
	var diagonal := opening_wall(map, "WindowPane")
	check_inset(diagonal, "WindowPane")
	check(diagonal != null and is_equal_approx(diagonal.rotation.y, -atan(0.5)), "window wall follows the diagonal")
	panel._buttons.plot_level.select(2)
	panel._buttons.plot_roof.pressed.emit()
	check(world._plot_tool.is_empty(), "roof needs a built floor beneath it")
	panel._buttons.plot_level.select(0)
	if diagonal != null:
		var normal := diagonal.global_basis.z
		var target := diagonal.to_global(Vector3(12, 24, 0))
		var hit := Plot.wall_face_hit(diagonal, target + normal * 80.0, -normal, map.imported_tile_size)
		check(hit.get("fits", false) and is_equal_approx(hit.get("angle", INF), diagonal.rotation.y),
			"pilaster placement follows the diagonal wall face")
	check_inset(opening_wall(map, "DoorPanel"), "DoorPanel")
	world._terrain_plan_action("plot_fence", plot_id, "")
	click(world, Vector2(7, 9))
	check(world._plot_anchor.is_finite() and poses(map).size() == 4, "first fence point is a draft")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	world.forward_input(_camera, esc)
	check(not world._plot_anchor.is_finite() and poses(map).size() == 4, "Escape discards the unfinished fence")
	world._terrain_plan_action("plot_fence", plot_id, "")
	click(world, Vector2(7, 9))
	click(world, Vector2(23, 9))
	var before := poses(map)
	check(before.size() == 5, "second fence point commits one scene-owned fence")
	var fence := map.get_node_or_null("Props/PlotFence") as Node3D
	if fence != null:
		var gap_center: Vector3 = world._plot_ground(Vector2(15, 9), fence)
		for body: StaticBody3D in fence.get_children():
			var shape := body.get_node("Shape") as CollisionShape3D
			var local_gap := body.to_local(fence.to_global(gap_center))
			check(absf(local_gap.x) - (shape.shape as BoxShape3D).size.x * 0.5 >= map.imported_tile_size * 0.749, "fence collision leaves the central passage open")
	else:
		check(false, "fence has a saved scene root")
	var resized := Rect2i(12, 5, 18, 22)
	world._terrain_plan_action("bounds", plot_id, "")
	select_rect(world, resized)
	check(Plan.read(map).regions[0].bounds == resized and poses(map) == before, "resizing across a house keeps all object transforms")
	await frames(5)
	await RenderingServer.frame_post_draw
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	check(image.save_png(OS.get_environment("EMBER_PLOT_EVIDENCE").path_join("construction-plot.png")) == OK, "capture the resized plot")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	check(Plan.read(map).regions[0].bounds == first and poses(map) == before, "bounds Undo preserves construction")
	history.undo()
	check(poses(map).size() == 4, "fence is one Undo action")
	history.redo()
	history.redo()
	check(Plan.read(map).regions[0].bounds == resized and poses(map) == before, "redo restores fence and bounds")
	check(world.save_all(), world.sessions.error)
	world._terrain_plan_action("plot_house", plot_id, str(panel._house.get_item_metadata(0)))
	click(world, Vector2(15, 21))
	check(poses(map).size() == 6, "new unsaved house")
	world.sessions.discard(scene)
	check(poses(map) == before, "discard restores the saved construction only")
	EditorInterface.reload_scene_from_path(path)
	await frames(30)
	var reloaded := EditorInterface.get_edited_scene_root()
	if reloaded != null:
		var reopened := reloaded.get_node("Map")
		var disk: Resource = Plan.read(reopened)
		check(disk != null and disk.regions[0].bounds == resized and poses(reopened) == before, "native save and reopen preserve bounds and placement")
		check(reopened.get_node_or_null("Props/PlotFence/Panel/Shape") is CollisionShape3D, "fence collision is persisted in the scene")
		check_inset(opening_wall(reopened, "WindowPane"), "WindowPane")
		check_inset(opening_wall(reopened, "DoorPanel"), "DoorPanel")
		world.enabled.button_pressed = true
		world.scene_changed(reloaded)
		world.category.select(0)
		world._category_changed(0)
		await ready_tiles(reopened._visual_surface_projection)
		_camera.look_at_from_position(Vector3(1100, 1030, 1120), Vector3(360, 70, 565))
		world._plan_button.pressed.emit()
		panel = world._plan_panel
		panel._add_menu.get_popup().id_pressed.emit(panel.ADD_ACTIONS.find("add_plot"))
		var mansion_bounds := Rect2i(3, 25, 41, 20)
		select_rect(world, mansion_bounds)
		var updated: Resource = Plan.read(reopened)
		check(updated.regions.size() == 2 and updated.regions[1].bounds == mansion_bounds, "separate mansion plot")
		if updated.regions.size() == 2:
			var mansion_id: String = updated.regions[1].id
			build_mansion(world, panel, mansion_id)
			panel._buttons.entry_portico.button_pressed = false
			panel._buttons.entry_canopy.value = 3.125
			panel._buttons.plot_entry.pressed.emit()
			click(world, Vector2(19.75, 26.5))
			click(world, Vector2(15.25, 26.5))
			check(not reopened.has_node("Props/PlotEntry"), "reject a staircase extending beyond the plot")
			panel._buttons.plot_entry.pressed.emit()
			click(world, Vector2(19.75, 29))
			click(world, Vector2(15.25, 29))
			check_entry(reopened)
			var mansion := poses(reopened)
			history = get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(reloaded))
			history.undo()
			check(poses(reopened).size() == mansion.size() - 1 and not reopened.has_node("Props/PlotEntry"), "undo removes the entire porch")
			history.redo()
			check(poses(reopened) == mansion, "redo restores the entire porch")
			for level in Plot.LEVEL_COUNT:
				panel._buttons.plot_level.select(level)
				panel._buttons.plot_level.item_selected.emit(level)
				panel._buttons.plot_cornice.pressed.emit()
				click(world, Vector2(40, 29))
				click(world, Vector2(5, 29))
				panel._buttons.plot_cornice.pressed.emit()
				click(world, Vector2(40, 43))
				click(world, Vector2(40, 29))
			check_cornices(reopened, mansion_id)
			mansion = poses(reopened)
			history.undo()
			check(poses(reopened).size() == mansion.size() - 1, "undo removes the complete cornice run")
			history.redo()
			check(poses(reopened) == mansion, "redo restores the complete cornice run")
			panel._buttons.plot_level.select(1)
			panel._buttons.plot_level.item_selected.emit(1)
			panel._buttons.balcony_depth.value = 2.25
			panel._buttons.balcony_columns.button_pressed = true
			panel._buttons.plot_balcony.pressed.emit()
			click(world, Vector2(21, 30))
			click(world, Vector2(14, 30))
			check(poses(reopened) == mansion, "balcony refuses a line away from the wall")
			panel._buttons.plot_balcony.pressed.emit()
			click(world, Vector2(21, 29))
			click(world, Vector2(14, 29))
			check_balcony(reopened, mansion_id, 7.0, 2.25, true)
			mansion = poses(reopened)
			history.undo()
			check(poses(reopened).size() == mansion.size() - 1, "balcony and columns undo together")
			history.redo()
			check(poses(reopened) == mansion, "redo restores the complete balcony")
			panel._buttons.edge_depth.value = 1.5
			panel._buttons.plot_edge.pressed.emit()
			click(world, Vector2(16, 26))
			click(world, Vector2(11, 26))
			check(poses(reopened) == mansion, "an edge cannot extend outside the plot")
			panel._buttons.edge_snap.button_pressed = false
			panel._buttons.plot_edge.pressed.emit()
			click(world, Vector2(19.5, 29))
			check(world._plot_anchor.is_equal_approx(Vector2(19.5, 29)), "disabled porch snap leaves the grid point unchanged")
			panel._buttons.edge_snap.button_pressed = true
			panel._buttons.plot_edge.pressed.emit()
			click(world, Vector2(19.5, 29))
			check(world._plot_anchor.is_equal_approx(Vector2(19.75, 29)), "nearby grid point snaps to the actual porch corner")
			place_edges(world, panel)
			check_edges(reopened, mansion_id)
			mansion = poses(reopened)
			history.undo()
			check(poses(reopened).size() == mansion.size() - 1, "undo removes planter, soil and shrubs together")
			history.redo()
			check(poses(reopened) == mansion, "redo restores the planted strip")
			var overhead := _camera.global_transform
			_camera.look_at_from_position(Vector3(410, 170, 206), Vector3(335, 76, 460))
			place_pilasters(world, panel)
			check_pilasters(reopened, mansion_id)
			mansion = poses(reopened)
			history.undo()
			check(poses(reopened).size() == mansion.size() - 1, "undo removes one facade detail")
			history.redo()
			check(poses(reopened) == mansion, "redo restores the pilaster")
			_camera.global_transform = overhead
			panel._buttons.roof_form.select(Plot.BuildingLayout.ROOF_GABLE)
			panel._buttons.roof_height.value = 3.0
			panel._buttons.roof_color.color = Color("4c586c")
			panel._buttons.roof_bay.button_pressed = true
			panel._buttons.roof_bay_width.value = 8.5
			panel._buttons.roof_bay_depth.value = 1.0
			panel._buttons.roof_bay_offset.value = -5.0
			panel._buttons.plot_roof.pressed.emit()
			click(world, Vector2(5, 29))
			click(world, Vector2(40, 43))
			check_roofs(reopened, mansion_id, Plot.BuildingLayout.ROOF_GABLE, 3.0, Color("4c586c"))
			panel._buttons.plot_roofs.select(1)
			panel._buttons.plot_roofs.item_selected.emit(1)
			check(panel._buttons.roof_form.selected == Plot.BuildingLayout.ROOF_GABLE and panel._buttons.roof_height.value == 3.0,
				"selecting a roof loads the current form and height")
			panel._buttons.roof_form.select(Plot.ROOF_MANSARD)
			panel._buttons.roof_height.value = 4.25
			panel._buttons.roof_color.color = Color("586680")
			panel._buttons.plot_roof_apply.pressed.emit()
			check_roofs(reopened, mansion_id, Plot.ROOF_MANSARD, 4.25, Color("586680"))
			history.undo()
			check_roofs(reopened, mansion_id, Plot.BuildingLayout.ROOF_GABLE, 3.0, Color("4c586c"))
			check(panel._buttons.roof_form.selected == Plot.BuildingLayout.ROOF_GABLE and panel._buttons.roof_height.value == 3.0,
				"roof controls follow undo")
			history.redo()
			check_roofs(reopened, mansion_id, Plot.ROOF_MANSARD, 4.25, Color("586680"))
			check(panel._buttons.roof_form.selected == Plot.ROOF_MANSARD and panel._buttons.roof_height.value == 4.25,
				"roof controls follow redo")
			mansion = poses(reopened)
			check(world.save_all(), world.sessions.error)
			var disk_copy := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			var disk_scene := disk_copy.instantiate() if disk_copy != null else null
			var disk_shrubs: MultiMeshInstance3D
			if disk_scene != null:
				for member: Node3D in Plot.snapshot(disk_scene.get_node("Map")):
					disk_shrubs = member.get_node_or_null("Edge/Shrubs") as MultiMeshInstance3D
					if disk_shrubs != null:
						break
				check(disk_shrubs != null and disk_shrubs.multimesh.transform_format == MultiMesh.TRANSFORM_3D
					and disk_shrubs.multimesh.instance_count == 6, "fresh disk load preserves the generated shrub batch")
				disk_scene.free()
			else:
				check(false, "fresh disk load opens the plot scene")
			panel._buttons.plot_level.select(1)
			panel._buttons.plot_balcony.pressed.emit()
			click(world, Vector2(30, 29))
			click(world, Vector2(21, 29))
			check(poses(reopened).size() == mansion.size() + 1, "a second balcony remains an unsaved addition")
			panel._buttons.roof_height.value = 5.5
			panel._buttons.plot_roof_apply.pressed.emit()
			check_roofs(reopened, mansion_id, Plot.ROOF_MANSARD, 5.5, Color("586680"))
			world.sessions.discard(reloaded)
			check(poses(reopened) == mansion, "discard restores the saved roof footprint")
			check_balcony(reopened, mansion_id, 7.0, 2.25, true)
			check_roofs(reopened, mansion_id, Plot.ROOF_MANSARD, 4.25, Color("586680"))
			check(panel._buttons.roof_height.value == 4.25, "roof controls follow discard")
			history.undo()
			check(poses(reopened) == mansion, "undo after discard keeps the restored roof attached once")
			_camera.global_transform = overhead
			EditorInterface.reload_scene_from_path(path)
			await frames(32)
			var saved_map := EditorInterface.get_edited_scene_root().get_node("Map") as EmberMapLoader
			check(poses(saved_map) == mansion, "all three levels survive native save and reopen")
			check_mansion(saved_map, mansion_id, 3)
			check_entry(saved_map)
			check_balcony(saved_map, mansion_id, 7.0, 2.25, true)
			check_cornices(saved_map, mansion_id)
			check_edges(saved_map, mansion_id)
			check_pilasters(saved_map, mansion_id)
			check_roofs(saved_map, mansion_id, Plot.ROOF_MANSARD, 4.25, Color("586680"))
			await ready_tiles(saved_map._visual_surface_projection)
			for member: Node3D in Plot.snapshot(saved_map):
				if member.get_meta(Plot.META, "") != mansion_id:
					member.hide()
			_camera.look_at_from_position(Vector3(790, 422, -10), Vector3(355, 110, 570))
			var fill := DirectionalLight3D.new()
			fill.rotation_degrees = Vector3(-50, 125, 0)
			fill.light_energy = 0.75
			_camera.get_viewport().add_child(fill)
			await frames(5)
			await RenderingServer.frame_post_draw
			var screenshot := _camera.get_viewport().get_texture().get_image()
			check(screenshot.save_png(OS.get_environment("EMBER_PLOT_EVIDENCE").path_join("mira-estate-roof.png")) == OK, "capture the roofs of the estate")
			_camera.look_at_from_position(Vector3(390, 235, 55), Vector3(295, 106, 485))
			await frames(5)
			await RenderingServer.frame_post_draw
			screenshot = _camera.get_viewport().get_texture().get_image()
			check(screenshot.save_png(OS.get_environment("EMBER_PLOT_EVIDENCE").path_join("mira-estate-balcony.png")) == OK, "capture the supported balcony and its entrance")
			await check_small_house(world, saved_map, path)
			fill.free()
			await build_palace_court_and_castle(world, path, mansion_id)
	else:
		check(false, "reopen fixture")
	print("CONSTRUCTION_PLOT ", JSON.stringify({"pass": errors.is_empty(), "errors": errors}))
	get_tree().quit(0 if errors.is_empty() else 1)


func check_small_house(world: Node, map: EmberMapLoader, path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	world.enabled.button_pressed = true
	world.scene_changed(root)
	world.category.select(0)
	world._category_changed(0)
	_camera.look_at_from_position(Vector3(870, 690, -180), Vector3(591, 40, 208))
	world._plan_button.pressed.emit()
	var panel: Control = world._plan_panel
	panel._add_menu.get_popup().id_pressed.emit(panel.ADD_ACTIONS.find("add_plot"))
	select_rect(world, Rect2i(28, 4, 18, 18))
	var plan: Resource = Plan.read(map)
	if plan == null or plan.regions.size() != 3:
		check(false, "create a separate ordinary-house plot")
		return
	var plot_id: String = plan.regions[-1].id
	var a := Vector2(32, 9)
	var b := Vector2(42, 9)
	var c := Vector2(42, 17)
	var d := Vector2(32, 17)
	var split := Vector2(37, 9)
	var recess_left := Vector2(35, 9)
	var recess_right := Vector2(39, 9)
	var recess_back_left := Vector2(35, 11.25)
	var recess_back_right := Vector2(39, 11.25)
	var first_window: Node3D
	for level in 2:
		panel._buttons.plot_level.select(level)
		panel._buttons.plot_level.item_selected.emit(level)
		panel._buttons.plot_floor.pressed.emit()
		click(world, a)
		click(world, c if level == 0 else Vector2(37, 17))
		if level == 1:
			panel._buttons.plot_floor.pressed.emit()
			click(world, split)
			click(world, c)
		var front := [[split, a, Plot.WALL_WINDOW], [b, split, Plot.WALL_DOOR]] if level == 0 else [
			[recess_left, a, Plot.WALL_WINDOW], [b, recess_right, Plot.WALL_WINDOW],
			[recess_back_left, recess_left, Plot.WALL_SOLID], [recess_right, recess_back_right, Plot.WALL_SOLID],
			[recess_back_right, recess_back_left, Plot.WALL_PASSAGE]]
		for segment: Array in front + [[c, b, Plot.WALL_SOLID], [d, c, Plot.WALL_SOLID], [a, d, Plot.WALL_SOLID]]:
			panel._buttons.wall_opening.select(segment[2])
			panel._buttons.custom_opening.button_pressed = false
			panel._buttons.wall_color.color = Color("e7caa7")
			panel._buttons.wall_finish.select(0)
			panel._buttons.plot_wall.pressed.emit()
			var drift := Vector2(0.08, -0.09) if level == 1 and segment[0] == recess_back_right else Vector2.ZERO
			click(world, segment[0] + drift)
			check(world._plot_anchor == segment[0], "wall anchor uses the same grid node as the cursor")
			click(world, segment[1] + drift)
		if level == 0:
			panel._buttons.plot_cornice.pressed.emit()
			click(world, b)
			click(world, a)
		panel._buttons.plot_pilaster.pressed.emit()
		click_small_facade(world, map, 32.75 if level == 0 else 32.5)
	for member: Node3D in Plot.snapshot(map):
		if member.get_meta(Plot.META, "") == plot_id and member.has_node("Wall/WindowPane") and member.get_meta(Plot.LEVEL_META, -1) == 0:
			first_window = member
			break
	check(first_window != null, "ordinary house has a legacy centered window")
	if first_window == null:
		return
	var window_name := str(first_window.name)
	var props := map.get_node("Props") as Node3D
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(root))
	var before_rail := props.get_child_count()
	panel._buttons.railing_style.select(Plot.RAIL_STONE)
	panel._buttons.plot_railing.pressed.emit()
	click(world, recess_left)
	panel._buttons.plot_grid.button_pressed = false
	check(world._plot_anchor == recess_left, "hiding the grid keeps the first railing point")
	panel._buttons.plot_grid.button_pressed = true
	click(world, Vector2(39, 8.75))
	check(props.get_child_count() == before_rail, "reject railing that leaves the floor")
	click(world, recess_right)
	var rail := props.get_child(-1) as Node3D
	check(props.get_child_count() == before_rail + 1 and rail.has_node("Railing/StoneBorder"),
		"stone railing can cross the seam between two adjacent floor pieces")
	history.undo()
	check(props.get_child_count() == before_rail, "undo removes the railing")
	history.redo()
	check(props.get_child_count() == before_rail + 1, "redo restores the railing")
	history.undo()
	panel._buttons.railing_style.select(Plot.RAIL_METAL)
	panel._buttons.plot_railing.pressed.emit()
	click(world, recess_left + Vector2(0.07, -0.10))
	check(world._plot_anchor == recess_left, "railing start snaps to the visible grid")
	_camera.look_at_from_position(Vector3(627, 185, 14), Vector3(592, 85, 156))
	plot_pointer(world, recess_right + Vector2(-0.08, 0.09), InputEventMouseMotion.new())
	check(world._plot_cursor == recess_right and props.get_child_count() == before_rail,
		"railing preview snaps before the second click and leaves scene data intact")
	await frames(5)
	await RenderingServer.frame_post_draw
	var editor_image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	check(editor_image.save_png(OS.get_environment("EMBER_PLOT_EVIDENCE").path_join("floor-grid-preview.png")) == OK,
		"capture the railing preview with the floor grid")
	click(world, recess_right + Vector2(-0.08, 0.09))
	_camera.look_at_from_position(Vector3(870, 690, -180), Vector3(591, 40, 208))
	panel._buttons.roof_form.select(Plot.BuildingLayout.ROOF_GABLE)
	panel._buttons.roof_height.value = 1.75
	panel._buttons.roof_color.color = Color("76554f")
	panel._buttons.roof_bay.button_pressed = false
	panel._buttons.plot_roof.pressed.emit()
	click(world, a)
	click(world, c)
	panel._buttons.entry_portico.button_pressed = false
	panel._buttons.plot_entry.pressed.emit()
	click(world, Vector2(41, 9))
	click(world, Vector2(38, 9))
	panel._buttons.edge_style.select(Plot.EDGE_STONE)
	panel._buttons.plot_edge.pressed.emit()
	click(world, Vector2(38, 9))
	click(world, a)
	panel._buttons.edge_style.select(Plot.EDGE_SHRUBS)
	panel._buttons.plot_edge.pressed.emit()
	click(world, Vector2(37, 7.5))
	click(world, Vector2(32.5, 7.5))
	panel._buttons.plot_level.select(0)
	panel._buttons.plot_window_pick.pressed.emit()
	click_small_facade(world, map, 34.5)
	check(world._plot_window_name == window_name and panel._buttons.window_center.value == 2.5,
		"the ordinary house uses the shared window editor")
	var before := first_window.transform
	panel._buttons.window_center.value = 0.125
	panel._buttons.plot_window_apply.pressed.emit()
	check(props.get_node(window_name) == first_window, "reject an opening too close to the wall end")
	panel._buttons.window_recenter.pressed.emit()
	check(panel._buttons.window_center.value == 2.5, "centering uses the full width of the wall")
	panel._buttons.window_center.value = 1.5
	panel._buttons.opening_casing.select(1)
	panel._buttons.opening_shutters.select(1)
	panel._buttons.wall_finish.select(1)
	panel._buttons.plot_window_apply.pressed.emit()
	var modified := props.get_node(window_name) as Node3D
	check(modified != first_window and modified.transform == before, "moving the window keeps the original wall frame")
	history.undo()
	check(panel._buttons.window_center.value == 2.5, "window undo restores the centered opening")
	history.redo()
	check(panel._buttons.window_center.value == 1.5, "window redo restores the off-center opening")
	check(world.save_all(), world.sessions.error)
	panel._buttons.window_center.value = 2.0
	panel._buttons.plot_window_apply.pressed.emit()
	panel._buttons.plot_level.select(1)
	panel._buttons.railing_style.select(Plot.RAIL_STONE)
	panel._buttons.plot_railing.pressed.emit()
	click(world, recess_left + Vector2(0, 0.5))
	click(world, recess_right + Vector2(0, 0.5))
	check(props.get_child(-1).has_node("Railing/StoneBorder"), "add a stone railing to the unsaved draft")
	world.sessions.discard(root)
	check(not props.get_child(-1).has_node("Railing/StoneBorder"), "discard removes the unsaved stone railing")
	check(panel._buttons.window_center.value == 1.5, "discard restores the saved opening")
	EditorInterface.reload_scene_from_path(path)
	await frames(32)
	var fresh := EditorInterface.get_edited_scene_root().get_node("Map") as EmberMapLoader
	var saved := fresh.get_node("Props/" + window_name) as Node3D
	check(saved.transform == before and Plot.placed_opening_options(saved, fresh.imported_tile_size).center == 1.5
		and saved.has_node("Wall/ShutterLeft") and saved.has_node("Wall/CasingHead")
		and Plot.window_wall_finish(saved).finish == 1, "off-center opening, shutters, casing and material reopen together")
	var pieces := {"Pilaster": 0, "Roof": 0, "Entry": 0, "Edge": 0, "Cornice": 0, "Slab": 0, "Railing": 0}
	for member: Node3D in Plot.snapshot(fresh):
		var belongs: bool = member.get_meta(Plot.META, "") == plot_id
		member.visible = belongs
		if belongs:
			if member.has_node("Railing"):
				var scale := fresh.imported_tile_size
				var guard := member.get_node("Railing/RailingShape") as CollisionShape3D
				check(member.get_meta(Plot.LEVEL_META, -1) == 1 and member.has_node("Railing/Railings")
					and is_equal_approx(member.position.x / scale, recess_left.x)
					and is_equal_approx(member.position.z / scale, recess_left.y)
					and is_equal_approx((guard.shape as BoxShape3D).size.x / scale, 4.0),
					"metal guard and its collision reopen at the edge of the second-storey recess")
			for part in pieces:
				if member.has_node(part):
					pieces[part] += 1
	check(pieces == {"Pilaster": 2, "Roof": 1, "Entry": 1, "Edge": 2, "Cornice": 1, "Slab": 3, "Railing": 1},
		"the two-storey house supports the shared facade and plot pieces")
	await ready_tiles(fresh._visual_surface_projection)
	_camera.look_at_from_position(Vector3(760, 230, -45), Vector3(594, 58, 201))
	await frames(5)
	await RenderingServer.frame_post_draw
	var image := _camera.get_viewport().get_texture().get_image()
	check(image.save_png(OS.get_environment("EMBER_PLOT_EVIDENCE").path_join("two-storey-house.png")) == OK, "capture the ordinary house")
	_camera.look_at_from_position(Vector3(625, 146, -82), Vector3(591, 80, 178))
	await frames(5)
	await RenderingServer.frame_post_draw
	image = _camera.get_viewport().get_texture().get_image()
	check(image.save_png(OS.get_environment("EMBER_PLOT_EVIDENCE").path_join("two-storey-recess.png")) == OK,
		"capture the recessed balcony between the two front bays")


func place_pair(world: Node, panel: Control, tool: String, a: Vector2, b: Vector2) -> void:
	var count := poses(world.map).size()
	if tool == "plot_fence":
		world._terrain_plan_action(tool, world._plan_selected_id, "")
	else:
		panel._buttons[tool].pressed.emit()
	click(world, a)
	click(world, b)
	check(poses(world.map).size() == count + 1, "%s commits between %s and %s" % [tool, a, b])


func build_palace_court_and_castle(world: Node, path: String, mansion_id: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var map := root.get_node("Map") as EmberMapLoader
	world.enabled.button_pressed = true
	world.scene_changed(root)
	world.category.select(0)
	world._category_changed(0)
	_camera.global_position = Vector3(400, 1280, 580)
	# Looking straight down needs a horizontal camera up vector.
	_camera.look_at(Vector3(400, 0, 580), Vector3.FORWARD)
	world._plan_button.pressed.emit()
	var panel: Control = world._plan_panel
	world._terrain_plan_action("bounds", mansion_id, "")
	select_rect(world, Rect2i(3, 19, 41, 47))
	check(Plan.read(map).regions[1].bounds == Rect2i(3, 19, 41, 47), "extend the palace plot for front court and rear garden")
	panel._buttons.plot_level.select(0)
	panel._buttons.roof_form.select(Plot.BuildingLayout.ROOF_HIP)
	panel._buttons.roof_color.color = Color("586680")
	panel._buttons.roof_bay.button_pressed = false
	panel._buttons.roof_height.value = 1.65
	panel._buttons.custom_opening.button_pressed = false
	panel._buttons.wall_color.color = Color("d4b99b")
	panel._buttons.wall_finish.select(2)
	for x in [5.0, 34.0]:
		var a := Vector2(x, 22)
		var b := a + Vector2(6, 0)
		var c := a + Vector2(6, 7)
		var d := a + Vector2(0, 7)
		place_pair(world, panel, "plot_floor", a, c)
		panel._buttons.wall_opening.select(Plot.WALL_WINDOW)
		for segment: Array in [[b, a], [a, d], [c, b]]:
			place_pair(world, panel, "plot_wall", segment[0], segment[1])
		place_pair(world, panel, "plot_roof", a, c)
	place_pair(world, panel, "plot_fence", Vector2(11, 22), Vector2(34, 22))
	panel._buttons.edge_snap.button_pressed = false
	panel._buttons.edge_style.select(Plot.EDGE_STONE)
	panel._buttons.edge_depth.value = 2.25
	place_pair(world, panel, "plot_edge", Vector2(23.5, 20.5), Vector2(23.5, 27))
	place_pair(world, panel, "plot_edge", Vector2(22.5, 19.75), Vector2(42.75, 19.75))
	place_pair(world, panel, "plot_edge", Vector2(42.75, 22), Vector2(42.75, 49))
	place_pair(world, panel, "plot_edge", Vector2(23.5, 46.75), Vector2(40.5, 46.75))
	place_pair(world, panel, "plot_edge", Vector2(23.5, 46.75), Vector2(23.5, 58))
	panel._buttons.edge_depth.value = 3.5
	place_pair(world, panel, "plot_edge", Vector2(23.5, 24.75), Vector2(32, 24.75))
	place_pair(world, panel, "plot_edge", Vector2(23.5, 51), Vector2(33, 51))
	panel._buttons.edge_style.select(Plot.EDGE_SHRUBS)
	panel._buttons.edge_depth.value = 1.25
	place_pair(world, panel, "plot_edge", Vector2(12.5, 25), Vector2(18.5, 25))
	place_pair(world, panel, "plot_edge", Vector2(25, 22.25), Vector2(32.5, 22.25))
	place_pair(world, panel, "plot_edge", Vector2(14, 53), Vector2(19.5, 53))
	place_pair(world, panel, "plot_edge", Vector2(26, 56), Vector2(31.5, 56))
	panel._buttons.edge_style.select(Plot.EDGE_HEDGE)
	panel._buttons.edge_style.item_selected.emit(Plot.EDGE_HEDGE)
	panel._buttons.edge_depth.value = 1.25
	panel._buttons.hedge_height.value = 1.5
	place_pair(world, panel, "plot_edge", Vector2(6, 64), Vector2(18, 64))
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(root))
	var one_hedge := poses(map)
	panel._buttons.hedge_height.value = 1.75
	panel._buttons.hedge_leaf_size.value = 130.0
	panel._buttons.hedge_season.select(1)
	place_pair(world, panel, "plot_edge", Vector2(27.5, 64), Vector2(38, 64))
	panel._buttons.hedge_leaf_size.value = 100.0
	panel._buttons.hedge_season.select(0)
	var both_hedges := poses(map)
	history.undo()
	check(poses(map) == one_hedge, "undo removes a hedge as one section")
	history.redo()
	check(poses(map) == both_hedges, "redo restores the complete hedge")
	var before_orchard := poses(map)
	for point: Vector2 in [Vector2(15, 49), Vector2(12, 59), Vector2(33, 58)]:
		panel._buttons.plot_apple_tree.pressed.emit()
		click(world, point)
	check(poses(map).size() == before_orchard.size() + 3, "place three fruit trees from the plot panel")
	var orchard := poses(map)
	var orchard_keys := {}
	for member: Node3D in Plot.snapshot(map):
		if member.scene_file_path == "res://prefabs/items/fruit_tree.scn":
			orchard_keys[member.name] = member.get("orchard_pickup_id")
	history.undo()
	check(poses(map).size() == orchard.size() - 1, "undo removes one orchard tree")
	history.redo()
	check(poses(map) == orchard, "redo restores the orchard tree")
	var gazebo_start := Vector2(20, 58)
	var gazebo_center := Vector2(22.5, 60.5)
	var gazebo_entry := Vector2(22.5, 58)
	place_pair(world, panel, "plot_floor_round", gazebo_center, gazebo_entry)
	var before_columns := poses(map)
	panel._buttons.plot_column.pressed.emit()
	click(world, gazebo_start)
	check(poses(map) == before_columns, "a bounding-box corner outside the round slab does not support a column")
	panel._buttons.wall_color.color = Color("d5c8af")
	var column_points := [Vector2(21, 59), Vector2(24, 59), Vector2(24, 62), Vector2(21, 62)]
	for point: Vector2 in column_points:
		panel._buttons.plot_column.pressed.emit()
		click(world, point + Vector2(0.08, -0.07))
	var columns := poses(map)
	check(columns.size() == before_columns.size() + 4, "place four independent columns on the grid")
	history.undo()
	check(poses(map).size() == columns.size() - 1, "undo removes just one column")
	history.redo()
	check(poses(map) == columns, "redo restores the column at the same grid node")
	panel._buttons.roof_height.value = 1.35
	panel._buttons.plot_round_roof.pressed.emit()
	click(world, gazebo_center)
	check(poses(map).size() == columns.size() + 1, "place a circular roof on the round floor")
	var roof_picker := panel._buttons.plot_roofs as OptionButton
	for index in roof_picker.item_count:
		if str(roof_picker.get_item_metadata(index)) == "PlotRoundRoof":
			roof_picker.select(index)
			roof_picker.item_selected.emit(index)
			break
	check(str(roof_picker.get_selected_metadata()) == "PlotRoundRoof", "the round roof is available in the normal roof picker")
	panel._buttons.roof_height.value = 1.75
	panel._buttons.plot_roof_apply.pressed.emit()
	panel._buttons.railing_style.select(Plot.RAIL_METAL)
	panel._buttons.plot_round_railing.pressed.emit()
	click(world, gazebo_entry)
	check(poses(map).size() == columns.size() + 2, "place a circular railing with an entrance")
	build_half_round_annex(world, panel)
	var before_fountains := poses(map)
	panel._buttons.fountain_style.select(Plot.FOUNTAIN_COURT)
	panel._buttons.plot_fountain.pressed.emit()
	click(world, Vector2(4, 20))
	check(poses(map) == before_fountains, "reject a fountain whose rim crosses the plot boundary")
	click(world, Vector2(27, 26.5))
	panel._buttons.fountain_style.select(Plot.FOUNTAIN_GARDEN)
	panel._buttons.plot_fountain.pressed.emit()
	click(world, Vector2(29, 60.5))
	var palace := poses(map)
	check(palace.size() == before_fountains.size() + 2, "place the two fountain presets from the plot tool")
	history.undo()
	check(poses(map).size() == palace.size() - 1, "undo removes the whole garden fountain")
	history.redo()
	check(poses(map) == palace, "redo restores the fountain in its original position")
	panel._add_menu.get_popup().id_pressed.emit(panel.ADD_ACTIONS.find("add_plot"))
	select_rect(world, Rect2i(2, 2, 26, 17))
	var plan: Resource = Plan.read(map)
	check(plan.regions.size() == 4 and plan.regions[-1].bounds == Rect2i(2, 2, 26, 17), "create the castle construction plot")
	if plan.regions.size() != 4:
		return
	var castle_id: String = plan.regions[-1].id
	panel._buttons.wall_color.color = Color("b9a58c")
	panel._buttons.wall_finish.select(2)
	panel._buttons.railing_style.select(Plot.RAIL_CRENEL)
	for level in 3:
		panel._buttons.plot_level.select(level)
		for x in [4.0, 20.0]:
			var a := Vector2(x, 8)
			var b := a + Vector2(6, 0)
			var c := a + Vector2(6, 6)
			var d := a + Vector2(0, 6)
			place_pair(world, panel, "plot_floor", a, c)
			for side: Array in [[b, a], [c, b], [d, c], [a, d]]:
				if level == 2:
					if side[0] == b and side[1] == a:
						place_pair(world, panel, "plot_railing", a, a + Vector2.RIGHT)
						place_pair(world, panel, "plot_railing", b - Vector2.RIGHT, b)
					else:
						place_pair(world, panel, "plot_railing", side[0], side[1])
				else:
					var walk_entry: bool = level == 1 and side[0].x == side[1].x and side[0].x in [10.0, 20.0]
					panel._buttons.wall_opening.select(Plot.WALL_PASSAGE if walk_entry else Plot.WALL_SOLID)
					place_pair(world, panel, "plot_wall", side[0], side[1])
		if level == 0:
			for z in [9.5, 12.5]:
				place_pair(world, panel, "plot_wall", Vector2(10, z), Vector2(20, z))
		elif level == 1:
			place_pair(world, panel, "plot_floor", Vector2(10, 9.5), Vector2(20, 12.5))
			for z in [9.5, 12.5]:
				place_pair(world, panel, "plot_railing", Vector2(10, z), Vector2(20, z))
	var finished := poses(map)
	history.undo()
	check(poses(map).size() == finished.size() - 1, "crenellations undo as one railing")
	history.redo()
	check(poses(map) == finished and palace.size() < finished.size(), "redo restores the castle railing")
	var arc_key := place_castle_arc(world, map, history)
	var rounded := round_castle_corner(world, map, history)
	finished = poses(map)
	var finished_parts := []
	var door_key := ""
	for target in [[castle_id, "Wall/Plaster", Plot.FINISH_SURFACE], [castle_id, "Railing/Crenellations", Plot.FINISH_SURFACE],
			[mansion_id, "Roof/BaySlopes", Plot.FINISH_SURFACE], [mansion_id, "Entry/Landing", Plot.FINISH_SURFACE],
			[mansion_id, "Slab/Floor", Plot.FINISH_SURFACE], [mansion_id, "Wall/DoorPanel", Plot.FINISH_DOOR],
			[mansion_id, "Wall/FrameLeft", Plot.FINISH_FRAME, "Wall/DoorPanel"],
			[mansion_id, "Wall/FrameLeft", Plot.FINISH_FRAME, "Wall/WindowPane"],
			[mansion_id, "Roof/BayFrameLeft", Plot.FINISH_FRAME]]:
		var part_path: String = target[1]
		var group: int = target[2]
		world._select_plan_region(target[0])
		for member: Node3D in Plot.snapshot(map):
			if member.get_meta(Plot.META, "") != target[0] or not member.has_node(part_path):
				continue
			if target.size() > 3 and not member.has_node(target[3]):
				continue
			var key := str(member.name)
			if target.size() > 3 and target[3] == "Wall/DoorPanel" and key != door_key:
				continue
			test_piece_finish(world, map, member, part_path, history, group)
			finished_parts.append([key, group])
			if group == Plot.FINISH_DOOR:
				door_key = key
			elif part_path == "Roof/BayFrameLeft":
				check_roof_finish_after_shape_change(world, map, key, history)
			elif target.size() > 3 and target[3] == "Wall/WindowPane":
				check_frame_finish_after_window_move(world, map, key, history)
			break
	check(finished_parts.size() == 9, "find all existing details and opening surfaces to refinish")
	convert_mira_door(world, map, door_key, history)
	check(poses(map) == finished, "finishing keeps every construction piece in place")
	world._select_plan_region(castle_id)
	var walk_key := place_castle_walk(world, map, history)
	var dock_keys := build_docked_towers(world, map, history)
	world._select_plan_region(mansion_id)
	build_chamfered_structures(world, panel, history)
	finished = poses(map)
	check(world.save_all(), world.sessions.error)
	panel._buttons.plot_finish_reset.pressed.emit()
	if not dock_keys.plot.is_empty():
		world._select_plan_region(dock_keys.plot)
		panel._buttons.plot_level.select(1)
		place_pair(world, panel, "plot_tower_deck", Vector2(29, 12), Vector2(33, 16))
	world._select_plan_region(castle_id)
	panel._buttons.plot_level.select(2)
	place_pair(world, panel, "plot_railing", Vector2(4, 9), Vector2(10, 9))
	panel._buttons.plot_level.select(1)
	panel._buttons.plot_arc_walk.button_pressed = true
	panel._buttons.plot_arc_wall.pressed.emit()
	click(world, Vector2(8, 12))
	click(world, Vector2(15, 16))
	click(world, Vector2(22, 12))
	panel._buttons.plot_arc_walk.button_pressed = false
	panel._buttons.plot_level.select(0)
	panel._buttons.plot_round_radius.value = 1.0
	panel._buttons.plot_round_corner.pressed.emit()
	click(world, Vector2(26, 14))
	panel._buttons.plot_arc_wall.pressed.emit()
	click(world, Vector2(6, 16))
	click(world, Vector2(8, 17))
	click(world, Vector2(10, 16))
	world._terrain_plan_action("plot_column", mansion_id, "")
	click(world, Vector2(22.5, 61))
	world._terrain_plan_action("plot_apple_tree", mansion_id, "")
	click(world, Vector2(16, 57))
	world._terrain_plan_action("plot_edge", mansion_id, "")
	click(world, Vector2(6, 60))
	click(world, Vector2(11, 60))
	place_pair(world, panel, "plot_floor_round", Vector2(17, 62), Vector2(18.5, 62))
	place_pair(world, panel, "plot_floor_chamfer", Vector2(6, 56), Vector2(10, 60))
	check(poses(map).size() == finished.size() + 10, "the unsaved draft includes circular and chamfered floors")
	world.sessions.discard(root)
	check(poses(map) == finished, "discard removes all unsaved construction and plants")
	check_rounded_corner(map, rounded, 3.0)
	var discarded := finished_parts.back() as Array
	check_saved_finish(map.get_node(NodePath("Props/" + discarded[0])), map.imported_tile_size, discarded[1])
	EditorInterface.reload_scene_from_path(path)
	await frames(32)
	var fresh := EditorInterface.get_edited_scene_root().get_node("Map") as EmberMapLoader
	check(poses(fresh) == finished, "palace court and castle reopen in their original positions")
	if not arc_key.is_empty():
		check_castle_arc(fresh.get_node_or_null(NodePath("Props/" + arc_key)), fresh.imported_tile_size)
	check_rounded_corner(fresh, rounded, 3.0)
	for finished_part in finished_parts:
		var member := fresh.get_node(NodePath("Props/" + finished_part[0])) as Node3D
		check_saved_finish(member, fresh.imported_tile_size, finished_part[1])
	var reopened_door := fresh.get_node_or_null(NodePath("Props/" + door_key)) as Node3D
	if reopened_door != null:
		check_double_door(reopened_door, fresh.imported_tile_size, Plot.TOP_TRIANGLE)
	var reopened_columns := PackedVector2Array()
	var gazebo_parts := {"Roof": 0, "Slab": 0, "Railing": 0, "Wall": 0}
	var apples := {}
	var hedges := 0
	var old_source: Resource = Generator.build(Generator.default_recipe(Generator.BUSH), Color.WHITE, {},
		"Куст для сравнения", "qa_old_garden_bush").geometry
	var old_plant := EmberVoxelPrefab.prepare_resource(old_source).instantiate()
	var old_mesh: Mesh = old_plant.get_node("Mesh").mesh
	old_plant.free()
	var old_triangles := old_mesh.get_faces().size() / 3
	var hedge_triangles := 0
	var baseline_instances := 0
	var cutout_sample: MeshInstance3D
	for member: Node3D in Plot.snapshot(fresh):
		var point := Vector2(member.position.x, member.position.z) / fresh.imported_tile_size
		if member.get_meta(Plot.META, "") != mansion_id:
			continue
		if member.scene_file_path == "res://prefabs/items/fruit_tree.scn":
			var key: String = member.get("orchard_pickup_id")
			check(not key.is_empty() and not apples.has(key) and orchard_keys.get(member.name) == key
				and member.has_node("ApplePickup") and point.y > 43,
				"fruit tree keeps its unique harvest id, instance and position in the rear garden")
			apples[key] = true
		var hedge := member.get_node_or_null("Edge/HedgeShape") as CollisionShape3D
		if hedge != null:
			var crown := member.get_node_or_null("Edge/HedgeCrown") as MeshInstance3D
			var interior := member.get_node_or_null("Edge/HedgeInterior") as MeshInstance3D
			var wood := member.get_node_or_null("Edge/HedgeBranches") as MeshInstance3D
			var sprigs := member.get_node_or_null("Edge/HedgeSprigs") as MeshInstance3D
			check(crown != null and interior != null and wood != null and sprigs != null and point.y == 64, "crown and interior, sparse branches and edge leaves reopen")
			if crown != null and interior != null and wood != null and sprigs != null:
				var box := crown.get_aabb()
				var size := (hedge.shape as BoxShape3D).size / fresh.imported_tile_size
				var height := 1.5 if point.x == 6 else 1.75
				var mat := crown.material_override as ShaderMaterial
				var autumn := point.x == 27.5
				var leaf_patch := Plot.HEDGE_AUTUMN_PATCH_M * 1.30 if autumn else Plot.HEDGE_LEAF_PATCH_M
				var atlas := mat.get_shader_parameter("leaf_atlas") as Texture2D
				var arrays := (crown.mesh as ArrayMesh).surface_get_arrays(0)
				var cap_point: Vector3 = arrays[Mesh.ARRAY_VERTEX][-1]
				var cap_uv: Vector2 = arrays[Mesh.ARRAY_TEX_UV][-1]
				var ground_y := -Plot.HEDGE_GROUND_OVERLAP_M * fresh.imported_tile_size
				check(is_equal_approx(box.position.y, ground_y) and absf(box.end.y / fresh.imported_tile_size - height) < 0.05
					and is_equal_approx(size.y, height * 0.9), "hedge reaches the ground and keeps its chosen height")
				check(is_equal_approx(box.size.x / fresh.imported_tile_size, size.x)
					and atlas != null and atlas.resource_path == (Plot.HEDGE_AUTUMN_LEAVES if autumn else Plot.HEDGE_LEAVES)
					and bool(mat.get_shader_parameter("autumn")) == autumn
					and is_equal_approx(float(mat.get_shader_parameter("leaf_patch_m")), leaf_patch)
					and cap_uv.is_equal_approx(Vector2(cap_point.x, cap_point.z) / fresh.imported_tile_size),
					"each hedge keeps its chosen leaf scale and seasonal atlas")
				check((sprigs.material_override as StandardMaterial3D).albedo_texture == atlas, "edge leaves use the chosen seasonal atlas")
				if autumn:
					var dry_leaves := interior.material_override as ShaderMaterial
					check(dry_leaves != null and bool(dry_leaves.get_shader_parameter("understory"))
						and dry_leaves.get_shader_parameter("leaf_atlas") == atlas, "autumn core uses dry leaves from the same atlas")
					var leaf_bed := dry_leaves.get_shader_parameter("understory_paint") as Texture2D
					check(leaf_bed != null and leaf_bed.resource_path == Plot.HEDGE_INNER_LEAVES,
						"painted inner foliage survives save and reopen")
					check(wood.get_aabb().end.y / fresh.imported_tile_size > height * 0.75,
						"autumn branches reach into the upper crown")
				else:
					check(interior.material_override is StandardMaterial3D and wood.get_aabb().end.y / fresh.imported_tile_size < height * 0.55,
						"green hedge keeps its own core and shorter branches")
				if point.x == 27.5:
					cutout_sample = crown
				var inner_box := interior.transform * interior.get_aabb()
				var near_gap := (inner_box.position.z - box.position.z) / fresh.imported_tile_size
				var far_gap := (box.end.z - inner_box.end.z) / fresh.imported_tile_size
				var end_gap := (inner_box.position.x - box.position.x) / fresh.imported_tile_size
				check(box.grow(0.001).encloses(inner_box) and is_equal_approx(near_gap, 0.035) and is_equal_approx(far_gap, 0.035)
					and is_equal_approx(end_gap, 0.09), "dense interior almost reaches the outer leaves")
				check(is_equal_approx(inner_box.position.y, ground_y), "the inner crown reaches the same ground height")
				check(not mesh_has_cap_at(crown, ground_y) and not mesh_has_cap_at(interior, ground_y),
					"neither hedge shell has a hidden bottom cap")
				hedge_triangles += (crown.mesh.get_faces().size() + interior.mesh.get_faces().size()
					+ wood.mesh.get_faces().size() + sprigs.mesh.get_faces().size()) / 3
				baseline_instances += ceili(size.x / 0.95)
			hedges += 1
		if point.y < gazebo_start.y or point.x < 20.0 or point.x > 25.0:
			continue
		if member.has_node("Column/ShaftShape"):
			reopened_columns.append(point)
			var top := member.get_node("Column/ShaftCapitalShape") as CollisionShape3D
			var floor_y := Plot.level_origin(fresh.get_node("Props"), mansion_id, fresh.imported_tile_size)
			var top_y := member.position.y + top.position.y + (top.shape as BoxShape3D).size.y * 0.5
			check(is_equal_approx(top_y, floor_y + Plot.WALL_HEIGHT_M * fresh.imported_tile_size), "column meets roof height")
		for part in gazebo_parts:
			if member.has_node(part):
				gazebo_parts[part] += 1
	check(reopened_columns.size() == 4 and gazebo_parts == {"Roof": 1, "Slab": 1, "Railing": 1, "Wall": 0},
		"reopen the garden gazebo as independent pieces behind the palace")
	for point: Vector2 in column_points:
		check(point in reopened_columns, "saved column remains on the selected grid node")
	check(apples.size() == 3 and hedges == 2, "reopen all orchard trees and hedge runs")
	check(hedge_triangles < old_triangles * baseline_instances, "shell hedge geometry is cheaper than repeating the former mesh")
	print("GARDEN_FOLIAGE ", JSON.stringify({"old_triangles": old_triangles * baseline_instances,
		"shell_branches_and_sprigs_triangles": hedge_triangles, "old_instances": baseline_instances}))
	var crenels := 0
	var walk_span := false
	for member: Node3D in Plot.snapshot(fresh):
		var belongs: bool = member.get_meta(Plot.META, "") == castle_id
		var teeth := member.get_node_or_null("Railing/Crenellations") as MeshInstance3D
		if belongs and teeth != null and not member.has_node("Wall"):
			check(teeth.mesh.get_aabb().size.y > 0.4 * fresh.imported_tile_size and member.has_node("Railing/RailingShape"),
				"saved battlements have teeth and a continuous guard collision")
			crenels += 1
		var floor_shape := member.get_node_or_null("Slab/FloorShape") as CollisionShape3D
		if belongs and floor_shape != null and member.get_meta(Plot.LEVEL_META, -1) == 1:
			var size := (floor_shape.shape as BoxShape3D).size / fresh.imported_tile_size
			walk_span = walk_span or (is_equal_approx(size.x, 10.0) and is_equal_approx(size.z, 3.0))
	check(crenels == 12 and walk_span, "two tower decks with walk entrances and the straight walk keep all 12 rails")
	await ready_tiles(fresh._visual_surface_projection)
	await check_round_buildings(fresh, gazebo_center, gazebo_entry)
	await check_chamfered_structures(fresh)
	await check_castle_walk(fresh, walk_key)
	await check_docked_towers(fresh, dock_keys)
	await check_hedge_cutout(cutout_sample, fresh.imported_tile_size)
	await dress_palace_preview(fresh, mansion_id)
	var shots := [
			[mansion_id, Vector3(930, 520, -25), Vector3(352, 105, 510), "mira-palace-court.png"],
			[mansion_id, Vector3(567, 280, 1180), Vector3(350, 72, 846), "mira-garden-gazebo.png"],
			[mansion_id, Vector3(426, 173, 888), Vector3(360, 38, 965), "round-gazebo.png"],
			[mansion_id, Vector3(460, 167, 735), Vector3(576, 40, 829), "half-round-annex.png"],
			[mansion_id, Vector3(582, 93, 828), Vector3(608, 34, 960), "octagonal-gazebo.png"],
			[mansion_id, Vector3(255, 134, 685), Vector3(139, 56, 808), "chamfered-house-balcony.png"],
			[mansion_id, Vector3(732, 345, 1270), Vector3(340, 63, 890), "mira-orchard.png"],
			[mansion_id, Vector3(542, 76, 1197), Vector3(515, 18, 1010), "mira-hedge-close.png"],
			[mansion_id, Vector3(529, 32, 1085), Vector3(521, 16, 1036), "mira-hedge-gaps.png"],
			[castle_id, Vector3(575, 320, -280), Vector3(240, 60, 170), "castle-wall-walk.png"],
			[castle_id, Vector3(253, 315, -170), Vector3(240, 72, 131), "castle-curved-walk.png"],
			[dock_keys.get("plot", ""), Vector3(660, 340, -120), Vector3(654, 34, 178), "castle-tower-docks.png"],
			[castle_id, Vector3(335, 180, -65), Vector3(230, 45, 133), "castle-arc-wall.png"],
			[castle_id, Vector3(530, 104, 32), Vector3(396, 25, 144), "castle-rounded-corner.png"]]
	var fountain_sizes := {}
	for member: Node3D in Plot.snapshot(fresh):
		if member.get_meta(Plot.META, "") != mansion_id or not member.has_node("Basin/Water"):
			continue
		var tile := fresh.imported_tile_size
		var pool := member.get_node("Basin/Water") as MeshInstance3D
		var bowl := member.get_node("Basin/Bowl") as MeshInstance3D
		var drops := member.get_node("Basin/Jet") as GPUParticles3D
		var diameter := bowl.get_aabb().size.x / tile
		fountain_sizes[diameter] = drops
		check(pool.get_active_material(0).shader == Plot.FOUNTAIN_WATER.shader
			and not member.has_node("Basin/Ripple")
			and drops.emitting and drops.draw_pass_1 != null,
			"fountain reopens with current Ember water, a running jet and no separate ripple ring")
		check(member.get_node("Basin/BowlShape").shape is ConcavePolygonShape3D
			and pool.get_aabb().size.x < bowl.get_aabb().size.x,
			"the stone collision follows the bowl and the water stays within the rim")
		var court := diameter > 3.0
		var target := member.global_position + Vector3.UP * tile * 0.7
		var offset := (Vector3(3.8, 2.85, -6.0) if court else Vector3(3.2, 2.25, 4.9)) * tile
		shots.append([mansion_id, target + offset, target,
			"mira-fountain-court.png" if court else "mira-fountain-garden.png", drops])
	check(fountain_sizes.has(2.25) and fountain_sizes.has(4.0), "both bowl sizes survive save and reopen")
	var door := fresh.get_node_or_null(NodePath("Props/" + door_key)) as Node3D
	if door != null:
		var options := Plot.placed_opening_options(door, fresh.imported_tile_size)
		var focus := door.to_global(Vector3(options.center, options.height * 0.5, 0) * fresh.imported_tile_size)
		var view := focus + door.global_basis * Vector3(28, 8, 88)
		shots.append([mansion_id, view, focus, "mira-door-finish.png"])
	var original_visibility := {}
	for member: Node3D in Plot.snapshot(fresh):
		original_visibility[member] = member.visible
	for shot: Array in shots:
		for member: Node3D in original_visibility:
			member.visible = member.get_meta(Plot.META, "") == shot[0]
		_camera.look_at_from_position(shot[1], shot[2])
		var fill: DirectionalLight3D
		if shot[3] == "mira-fountain-court.png":
			fill = DirectionalLight3D.new()
			fill.rotation_degrees = Vector3(-37, 162, 0)
			fill.light_color = Color("ffdfb9")
			fill.light_energy = 0.44
			_camera.get_viewport().add_child(fill)
		await frames(5)
		await RenderingServer.frame_post_draw
		var image := _camera.get_viewport().get_texture().get_image()
		check(image.save_png(OS.get_environment("EMBER_PLOT_EVIDENCE").path_join(shot[3])) == OK, "capture " + str(shot[3]))
		if shot.size() > 4:
			var jet: GPUParticles3D = shot[4]
			check(jet.capture_aabb().size.y > fresh.imported_tile_size * 0.2, "GPU produces a fountain jet above the basin")
		if fill != null:
			fill.free()
	for member: Node3D in original_visibility:
		member.visible = original_visibility[member]


func place_castle_arc(world: Node, map: EmberMapLoader, history: Object) -> String:
	var panel: Control = world._plan_panel
	var start := Vector2(10, 8)
	var through := Vector2(15, 5)
	var end := Vector2(20, 8)
	var expected := Plot.wall_arc(start, through, end)
	var left: PackedVector2Array = expected.left
	var right: PackedVector2Array = expected.right
	for index in left.size():
		check(is_equal_approx(left[index].distance_to(right[index]), Plot.WALL_DEPTH_M), "arc has constant width across the bend")
	check(((left[0] + right[0]) * 0.5).is_equal_approx(start) and ((left[-1] + right[-1]) * 0.5).is_equal_approx(end),
		"arc ends lie on the selected grid nodes")
	var before := poses(map)
	panel._buttons.plot_level.select(0)
	panel._buttons.plot_arc_wall.pressed.emit()
	click(world, start)
	click(world, through)
	check(poses(map) == before, "two clicks leave only an uncommitted preview")
	click(world, Vector2(20, 2))
	check(poses(map) == before, "collinear points cannot commit an arc")
	click(world, end)
	var props := map.get_node("Props")
	var arc := props.get_node_or_null("PlotArcWall") as Node3D
	check_castle_arc(arc, map.imported_tile_size)
	if arc == null:
		return ""
	var key := str(arc.name)
	history.undo()
	check(poses(map) == before, "undo removes the whole arc")
	history.redo()
	check(props.get_node_or_null(NodePath(key)) == arc, "redo restores the same arc")
	return key


func set_corner_cuts(panel: Control, cuts: Vector4) -> void:
	for index in 4:
		panel._buttons["plot_cut_" + ["СЗ", "СВ", "ЮВ", "ЮЗ"][index]].value = cuts[index]


func build_chamfered_structures(world: Node, panel: Control, history: Object) -> void:
	var map: EmberMapLoader = world.map
	panel._buttons.plot_level.select(0)
	var a := Vector2(35, 57)
	var b := Vector2(41, 63)
	set_corner_cuts(panel, Vector4(4.5, 3, 1.5, 1.5))
	var before := poses(map)
	panel._buttons.plot_floor_chamfer.pressed.emit()
	click(world, a)
	click(world, b)
	check(poses(map) == before, "overlapping corner cuts cannot create a slab")
	set_corner_cuts(panel, Vector4.ONE * 1.5)
	place_pair(world, panel, "plot_floor_chamfer", a, b)
	var perimeter := [Vector2(36.5, 57), Vector2(39.5, 57), Vector2(41, 58.5), Vector2(41, 61.5),
		Vector2(39.5, 63), Vector2(36.5, 63), Vector2(35, 61.5), Vector2(35, 58.5)]
	var center := (a + b) * 0.5
	var floor_only := poses(map)
	panel._buttons.plot_column.pressed.emit()
	click(world, a)
	check(poses(map) == floor_only, "a removed corner cannot support a column")
	panel._buttons.wall_color.color = Color("d5c8af")
	panel._buttons.railing_style.select(Plot.RAIL_METAL)
	for index in perimeter.size():
		var pillar: Vector2 = perimeter[index].move_toward(center, 0.45).snapped(Vector2.ONE * Plot.GRID_SNAP_M)
		panel._buttons.plot_column.pressed.emit()
		click(world, pillar)
		if index > 0:
			place_pair(world, panel, "plot_railing", perimeter[index], perimeter[(index + 1) % perimeter.size()])
	check(poses(map).size() == floor_only.size() + 15, "eight columns and seven rails assemble an open octagonal gazebo")
	panel._buttons.roof_height.value = 1.75
	panel._buttons.plot_round_roof.pressed.emit()
	click(world, center)
	var gazebo := poses(map)
	check(gazebo.size() == floor_only.size() + 16, "place an eight-sided roof from the floor contour")
	history.undo()
	check(poses(map).size() == gazebo.size() - 1, "undo removes only the polygon roof")
	history.redo()
	check(poses(map) == gazebo, "redo restores the polygon roof")

	a = Vector2(4.5, 47)
	b = Vector2(12, 54)
	place_pair(world, panel, "plot_floor", a, b)
	var corners := [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
	panel._buttons.wall_opening.select(Plot.WALL_SOLID)
	for index in corners.size():
		place_pair(world, panel, "plot_wall", corners[index], corners[(index + 1) % corners.size()])
	panel._buttons.plot_level.select(1)
	set_corner_cuts(panel, Vector4(2, 0, 1.5, 1))
	place_pair(world, panel, "plot_floor_chamfer", a, b)
	var upstairs := [Vector2(6.5, 47), Vector2(9.5, 47), Vector2(12, 49.5), Vector2(12, 52.5),
		Vector2(10.5, 54), Vector2(5.5, 54), Vector2(4.5, 53), Vector2(4.5, 49)]
	for index in upstairs.size():
		panel._buttons.wall_opening.select(Plot.WALL_PASSAGE if index == 1 else Plot.WALL_SOLID)
		place_pair(world, panel, "plot_wall", upstairs[index], upstairs[(index + 1) % upstairs.size()])
	place_pair(world, panel, "plot_railing", upstairs[1], Vector2(12, 47))
	place_pair(world, panel, "plot_railing", Vector2(12, 47), upstairs[2])
	panel._buttons.plot_round_roof.pressed.emit()
	click(world, (a + b) * 0.5)
	panel._buttons.plot_level.select(0)
	set_corner_cuts(panel, Vector4.ONE)


func check_chamfered_structures(map: EmberMapLoader) -> void:
	var props := map.get_node("Props")
	var octagon := props.get_node_or_null("PlotChamferFloor") as Node3D
	var upper := props.get_node_or_null("PlotChamferFloor2") as Node3D
	var roof := props.get_node_or_null("PlotChamferRoof") as Node3D
	var upper_roof := props.get_node_or_null("PlotChamferRoof2") as Node3D
	var complete := octagon != null and upper != null and roof != null and upper_roof != null
	check(complete, "both chamfered floors and their roofs reopen")
	if not complete:
		return
	var tile := map.imported_tile_size
	var octagonal_profile: Dictionary = octagon.get_meta(Plot.CONTOUR_FLOOR_META)
	var upper_profile: Dictionary = upper.get_meta(Plot.CONTOUR_FLOOR_META)
	check(octagonal_profile.points.size() == 8 and roof.get_meta(Plot.ROOF_META).round == octagonal_profile,
		"an eight-sided floor and roof keep a shared contour")
	check(upper_profile.points.size() == 7 and upper.get_meta(Plot.LEVEL_META) == 1
		and upper_roof.get_meta(Plot.ROOF_META).round == upper_profile, "a different set of corner cuts survives upstairs")
	await get_tree().physics_frame
	var space := upper.get_world_3d().direct_space_state
	var balcony := Vector3(11.25 * tile, upper.global_position.y + Plot.FLOOR_TOP_M * tile, 47.75 * tile)
	var above := balcony + Vector3.UP * tile * 0.5
	var below := balcony - Vector3.UP * tile * 0.25
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(above, below))
	var rail_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(above, above + Vector3.RIGHT * tile))
	check(floor_hit.get("collider") == upper.get_node("Slab"), "the corner balcony has a walkable floor")
	var guard := rail_hit.get("collider") as Node3D
	check(guard != null and guard.name == &"Railing", "the exposed balcony edge has a guard")


func build_half_round_annex(world: Node, panel: Control) -> void:
	var center := Vector2(35, 52)
	var edge := Vector2(38, 52)
	place_pair(world, panel, "plot_floor_half", center, edge)
	panel._buttons.wall_opening.select(Plot.WALL_DOOR)
	place_pair(world, panel, "plot_wall", Vector2(35, 49), Vector2(35, 55))
	var count := poses(world.map).size()
	panel._buttons.plot_arc_wall.pressed.emit()
	click(world, Vector2(35, 49))
	click(world, edge)
	click(world, Vector2(35, 55))
	check(poses(world.map).size() == count + 1, "a standard arc wall closes the back of the semicircular floor")
	panel._buttons.plot_round_roof.pressed.emit()
	click(world, Vector2(36, 52))
	check(poses(world.map).size() == count + 2, "the roof follows the semicircular floor")


func check_round_buildings(map: EmberMapLoader, center: Vector2, entrance: Vector2) -> void:
	var props := map.get_node("Props")
	var floor := props.get_node_or_null("PlotRoundFloor") as Node3D
	var roof := props.get_node_or_null("PlotRoundRoof") as Node3D
	var railing := props.get_node_or_null("PlotRoundRailing") as Node3D
	var half_floor := props.get_node_or_null("PlotRoundFloor2") as Node3D
	var half_roof := props.get_node_or_null("PlotRoundRoof2") as Node3D
	var complete := floor != null and roof != null and railing != null and half_floor != null and half_roof != null
	check(complete, "both radial buildings reopen as ordinary plot pieces")
	if not complete:
		return
	var tile := map.imported_tile_size
	for slab in [floor, half_floor]:
		var floor_mesh := slab.get_node("Slab/Floor") as MeshInstance3D
		var floor_shape := slab.get_node("Slab/FloorShape") as CollisionShape3D
		check(floor_shape.shape.get_faces() == floor_mesh.mesh.get_faces(), "the radial floor collision follows the visible contour")
	check(not floor.get_meta(Plot.CONTOUR_FLOOR_META).half and half_floor.get_meta(Plot.CONTOUR_FLOOR_META).half
		and half_roof.get_meta(Plot.ROOF_META).round.half, "circle and semicircle keep their own profiles on reopen")
	check(is_equal_approx(float(roof.get_meta(Plot.ROOF_META).height), 1.75), "round roof keeps its edited height")
	await get_tree().physics_frame
	var world := floor.get_world_3d().direct_space_state
	var position := floor.global_position
	var deck := position + Vector3.UP * Plot.FLOOR_TOP_M * tile
	var down := PhysicsRayQueryParameters3D.create(deck + Vector3.UP * 0.75 * tile, deck - Vector3.UP * 0.1 * tile)
	check(world.intersect_ray(down).get("collider") == floor.get_node("Slab"), "the circular deck supports a body from above")
	var offset := (entrance - center).normalized() * 2.75 * tile
	var above := deck + Vector3.UP * 0.7 * tile
	var gate := PhysicsRayQueryParameters3D.create(above, above + Vector3(offset.x, 0, offset.y))
	var guard := PhysicsRayQueryParameters3D.create(above, above - Vector3(offset.x, 0, offset.y))
	check(world.intersect_ray(gate).is_empty() and world.intersect_ray(guard).get("collider") == railing.get_node("Railing"),
		"the entrance stays open while the opposite curved railing stops passage")


func place_castle_walk(world: Node, map: EmberMapLoader, history: Object) -> String:
	var panel: Control = world._plan_panel
	var before := poses(map)
	panel._buttons.plot_level.select(1)
	panel._buttons.plot_arc_walk.button_pressed = true
	panel._buttons.plot_arc_wall.pressed.emit()
	click(world, WALK_START)
	click(world, WALK_TURN)
	check(poses(map) == before, "first two walk points change only the preview")
	click(world, WALK_END)
	panel._buttons.plot_arc_walk.button_pressed = false
	var walk := map.get_node_or_null("Props/PlotArcWalk") as Node3D
	check(walk != null and poses(map).size() == before.size() + 1, "create the whole curved walk in one action")
	if walk == null:
		return ""
	var key := str(walk.name)
	history.undo()
	check(poses(map) == before, "undo removes the wall, deck and both parapets")
	history.redo()
	check(map.get_node_or_null("Props/" + key) == walk, "redo restores the whole curved walk")
	return key


func build_docked_towers(world: Node, map: EmberMapLoader, history: Object) -> Dictionary:
	var panel: Control = world._plan_panel
	panel._add_menu.get_popup().id_pressed.emit(panel.ADD_ACTIONS.find("add_plot"))
	var bounds := Rect2i(28, 2, 20, 17)
	select_rect(world, bounds)
	var id: String = world._plan_selected_id
	var plan: Resource = Plan.read(map)
	var index: int = plan.index_of(id)
	var created: bool = index >= 0 and plan.regions[index].bounds == bounds
	check(created, "create the tower docking plot within the fixture extent")
	if not created:
		return {"plot": "", "walks": []}
	panel._buttons.plot_wall_depth.value = FORTRESS_DEPTH
	panel._buttons.plot_walk_width.value = FORTRESS_WIDTH
	panel._buttons.plot_tower_height.value = FORTRESS_HEIGHT
	for recipe in [[Vector2(29, 5), 3, 0], [Vector2(42, 5), 1, 2], [Vector2(43, 14), 4, 0]]:
		var a: Vector2 = recipe[0]
		var c := a + Vector2(4, 4)
		panel._buttons.plot_tower_port_0.select(recipe[1])
		panel._buttons.plot_tower_port_1.select(recipe[2])
		place_pair(world, panel, "plot_fortress", a, c)
	var result := {"plot": id, "walks": []}
	var tile := map.imported_tile_size
	var deck_y := Plot.level_origin(map.get_node("Props"), id, tile) + (FORTRESS_HEIGHT + Plot.FLOOR_TOP_M) * tile
	panel._buttons.plot_tower_height.value = FORTRESS_HEIGHT + 1.0
	panel._buttons.plot_tower_port_0.select(3)
	place_pair(world, panel, "plot_fortress", Vector2(29, 12), Vector2(33, 16))
	panel._buttons.plot_level.select(0)
	panel._buttons.plot_arc_walk.button_pressed = true
	panel._buttons.plot_arc_dock.button_pressed = true
	var incompatible := poses(map)
	panel._buttons.plot_arc_wall.pressed.emit()
	click_deck(world, TOWER_LINKS[0][0], deck_y)
	click(world, TOWER_LINKS[0][1])
	click_deck(world, Vector2(33, 14), deck_y + tile)
	check(poses(map) == incompatible and panel._status.text.contains("той же высоте"),
		"a port at a different height cannot commit a walk: " + panel._status.text)
	history.undo()
	panel._buttons.plot_walk_width.value = Plot.ARC_WALK_WIDTH_M
	panel._buttons.plot_tower_height.value = 6.0
	for link in TOWER_LINKS:
		var before := poses(map)
		panel._buttons.plot_arc_wall.pressed.emit()
		click_deck(world, link[0] + Vector2(0.25, 0), deck_y)
		click(world, link[1])
		click_deck(world, link[2] + Vector2(0.25, 0), deck_y)
		var key := ""
		for name in poses(map):
			if not before.has(name):
				key = name
		check(not key.is_empty() and poses(map).size() == before.size() + 1,
			"dock a walk on both marked tower faces: " + panel._status.text)
		if key.is_empty():
			break
		result.walks.append(key)
		history.undo()
		check(poses(map) == before, "undo releases both ports")
		history.redo()
		panel._buttons.plot_arc_wall.pressed.emit()
		click_deck(world, link[0], deck_y)
		check(not world._plot_anchor.is_finite(), "redo occupies the connected port")
	panel._buttons.plot_arc_dock.button_pressed = false
	panel._buttons.plot_arc_walk.button_pressed = false
	panel._buttons.plot_wall_depth.value = Plot.WALL_DEPTH_M
	return result


func check_docked_towers(map: EmberMapLoader, keys: Dictionary) -> void:
	if keys.walks.size() != TOWER_LINKS.size():
		return
	var tile := map.imported_tile_size
	var route := PackedVector3Array()
	var seam_y := INF
	var towers := 0
	for node: Node3D in Plot.snapshot(map):
		if node.get_meta(Plot.META, "") == keys.plot and node.has_meta(Plot.TOWER_PORTS_META):
			check(node.has_node("Railing/RailingShape"), "tower parapet and declared ports reopen")
			var north := node.get_node("TowerWalls/NorthShape") as CollisionShape3D
			check(is_equal_approx(north.shape.size.z / tile, FORTRESS_DEPTH)
				and is_equal_approx(north.shape.size.y / tile, FORTRESS_HEIGHT)
				and is_equal_approx(float(node.get_meta(Plot.WALK_WIDTH_META)), FORTRESS_WIDTH),
				"the saved tower retains custom thickness, height and port width")
			towers += 1
	check(towers == 3, "all three tower decks reopen")
	for index in TOWER_LINKS.size():
		var link: Array = TOWER_LINKS[index]
		var walk := map.get_node_or_null("Props/" + keys.walks[index]) as Node3D
		if walk == null:
			check(false, "connected walk reopens")
			return
		var ends := Plot.wall_ends(walk)
		for i in 2:
			var expected: Vector2 = link[i * 2]
			var normal: Vector2 = link[3 + i]
			var endpoint := walk.position + ends[i * 2]
			check(Vector2(endpoint.x, endpoint.z).is_equal_approx(expected * tile)
				and ends[i * 2 + 1].is_equal_approx(Vector3(normal.x, 0, normal.y)),
				"the saved end is centered and perpendicular to its own tower face")
		var deck := walk.get_node("Wall/ArcSurface") as MeshInstance3D
		seam_y = deck.global_position.y + deck.get_aabb().end.y
		check(is_equal_approx(float(walk.get_meta(Plot.WALK_WIDTH_META)), FORTRESS_WIDTH)
			and is_equal_approx(deck.get_aabb().end.y / tile, FORTRESS_HEIGHT + Plot.FLOOR_TOP_M - 0.002),
			"the walk inherits the port width and deck height")
		if index > 0:
			route.append(Vector3(44 * tile, seam_y, 7 * tile))
		var arc := Plot.docked_wall_arc(link[0], link[1], link[2], link[3], link[4], FORTRESS_WIDTH)
		for sample in arc.left.size():
			var point: Vector2 = (arc.left[sample] + arc.right[sample]) * 0.5
			route.append(Vector3(point.x * tile, seam_y, point.y * tile))
	route.insert(0, route[0] - Vector3.RIGHT * tile)
	route.append(route[-1] + Vector3.BACK * tile)
	await walk_test_capsule(map, route, seam_y)


func check_castle_walk(map: EmberMapLoader, key: String) -> void:
	var walk := map.get_node_or_null("Props/" + key) as Node3D
	check(not key.is_empty() and walk != null and walk.has_node("Railing/RailingShape"), "walk and parapets reopen")
	if key.is_empty() or walk == null or not walk.has_node("Railing/RailingShape"):
		return
	var tile := map.imported_tile_size
	var deck := walk.get_node("Wall/ArcSurface") as MeshInstance3D
	var shape := walk.get_node("Wall/ArcShape") as CollisionShape3D
	var teeth := walk.get_node("Railing/Crenellations") as MeshInstance3D
	check(shape.shape.get_faces() == deck.mesh.get_faces() and teeth.mesh.get_faces().size() > 72,
		"saved deck collision matches the visible wall and both parapets have crenellations")
	var top := deck.global_position.y + deck.get_aabb().end.y
	var arc := Plot.wall_arc(WALK_START, WALK_TURN, WALK_END, Plot.ARC_WALK_WIDTH_M)
	var route := PackedVector3Array()
	for index in arc.left.size():
		var point: Vector2 = (arc.left[index] + arc.right[index]) * 0.5
		route.append(Vector3(point.x * tile, top, point.y * tile))
	var middle := route[route.size() / 2]
	route.insert(0, route[0] + Vector3(-0.8 * tile, 0, 0.3 * tile))
	route.append(route[-1] + Vector3(0.8 * tile, 0, 0.3 * tile))
	await walk_test_capsule(map, route, top, middle)


func walk_test_capsule(map: EmberMapLoader, route: PackedVector3Array, top: float, middle := Vector3.INF) -> void:
	var tile := map.imported_tile_size
	var actor := CharacterBody3D.new()
	actor.collision_layer = 0
	actor.collision_mask = 1
	actor.floor_snap_length = 0.12 * tile
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.2 * tile
	capsule.height = 1.48 * tile
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	actor.add_child(collider)
	map.add_child(actor)
	actor.global_position = route[0] + Vector3.UP * 0.1 * tile
	for step in 10:
		await get_tree().physics_frame
		actor.velocity = Vector3.DOWN * tile
		actor.move_and_slide()
	check(actor.is_on_floor(), "the capsule starts on the first tower deck")
	for direction in ["outbound", "return"]:
		var index := 1
		var lost_floor := Vector3.INF
		for step in 650:
			await get_tree().physics_frame
			var delta := route[index] - actor.global_position
			delta.y = 0.0
			if delta.length() < tile * 0.08:
				index += 1
				if index == route.size():
					break
				continue
			actor.velocity = delta.normalized() * tile * 5.0 + Vector3.DOWN * tile
			actor.move_and_slide()
			if not lost_floor.is_finite() and (not actor.is_on_floor() or absf(actor.global_position.y - top) >= tile * 0.08):
				lost_floor = actor.global_position / tile
		check(index == route.size() and not lost_floor.is_finite(),
			"continuous floor %s: waypoint %d/%d, position %s, first loss %s" % [
				direction, index, route.size(), actor.global_position / tile, lost_floor])
		route.reverse()
	for side in [-1, 1] if middle.is_finite() else []:
		actor.global_position = middle + Vector3.UP * 0.05 * tile
		var hit := false
		for step in 25:
			await get_tree().physics_frame
			actor.velocity = Vector3(0, -1, side * 5) * tile
			actor.move_and_slide()
			hit = hit or actor.is_on_wall()
		check(hit and actor.is_on_floor() and absf(actor.global_position.z - middle.z) < tile * 1.1,
			"the continuous parapet stops the capsule on side " + str(side))
	actor.queue_free()


func round_castle_corner(world: Node, map: EmberMapLoader, history: Object) -> Dictionary:
	var panel: Control = world._plan_panel
	var props := map.get_node("Props")
	var bounds := Rect2(2, 2, 26, 17)
	var corner := Vector2(26, 8)
	var before := poses(map)
	panel._buttons.plot_round_corner.pressed.emit()
	click(world, Vector2(20, 8))
	check(poses(map) == before, "a junction with a third wall cannot be rounded")
	panel._buttons.plot_round_radius.value = 6.0
	click(world, corner)
	check(poses(map) == before, "a radius that consumes the straight wall cannot commit")
	var saved := {}
	for radius in [2.0, 3.0]:
		panel._buttons.plot_round_radius.value = radius
		plot_pointer(world, corner, InputEventMouseMotion.new())
		var layout: Dictionary = world._plot_corner_layout(props, world._plot_cursor, bounds)
		check(layout.has("arc") and is_equal_approx(layout.get("arc", {}).get("cut", 0.0), radius),
			"the preview uses radius %s at %s (cursor %s, level %s, result %s)" % [
				radius, corner, world._plot_cursor, world._plot_level, layout.get("error", layout.get("arc", {}).get("cut", "none"))])
		if not layout.has("arc"):
			return {}
		var wall_names: Array[String] = []
		for side in layout.sides:
			wall_names.append(str(side.wall.name))
		click(world, corner)
		var curve := ""
		for key in poses(map):
			if not before.has(key):
				curve = key
		saved = {"curve": curve, "walls": wall_names}
		check_rounded_corner(map, saved, radius)
		history.undo()
		check(poses(map) == before, "one undo restores the complete sharp corner")
		if radius == 2.0:
			panel._buttons.plot_round_corner.pressed.emit()
	history.redo()
	check_rounded_corner(map, saved, 3.0)
	return saved


func check_rounded_corner(map: EmberMapLoader, saved: Dictionary, radius: float) -> void:
	var curve := map.get_node_or_null("Props/" + saved.get("curve", "")) as Node3D
	var exists := not saved.is_empty() and curve != null and curve.has_node("Wall/ArcSurface")
	check(exists, "rounded corner exists")
	if not exists:
		return
	var mesh := curve.get_node("Wall/ArcSurface") as MeshInstance3D
	var collision := curve.get_node("Wall/ArcShape") as CollisionShape3D
	check(collision.shape.get_faces() == mesh.mesh.get_faces(), "the curved corner collision matches its rendered geometry")
	var ends: PackedVector3Array = curve.get_meta(Plot.ARC_ENDS_META)
	var tile := map.imported_tile_size
	check(is_equal_approx(ends[0].distance_to(ends[2]) / tile, radius * sqrt(2.0)), "the saved arc has the chosen radius")
	for index in 2:
		var wall := map.get_node_or_null("Props/" + saved.walls[index]) as Node3D
		check(wall != null, "shortened wall keeps its name")
		if wall == null:
			continue
		var face := wall.get_node("Wall/Plaster") as MeshInstance3D
		var shape := wall.get_node("Wall/PlasterShape") as CollisionShape3D
		check(is_equal_approx(Plot.wall_end(wall) / tile, 6.0 - radius)
			and shape.shape.size.is_equal_approx(face.mesh.size), "the straight piece and collision have the same trimmed length")
		var tangent := curve.position + ends[index * 2]
		var wall_ends := Plot.wall_ends(wall)
		var end_index := 0 if (wall.transform * wall_ends[0]).distance_to(tangent) < 0.01 else 2
		check((wall.transform * wall_ends[end_index]).distance_to(tangent) < 0.01
			and (wall.basis * wall_ends[end_index + 1]).dot(ends[index * 2 + 1]) < -0.999,
			"the straight wall meets the arc without a gap or kink")
		var old_corner := Vector3(26.0, 0, 8.0) * tile + Vector3.UP * wall.position.y
		for piece in wall.get_node("Wall").get_children():
			if piece is CollisionShape3D and piece.shape is ConvexPolygonShape3D:
				check(not (wall.transform * piece.shape.points[0]).is_equal_approx(old_corner),
					"the old sharp corner has no remaining collision")


func check_castle_arc(arc: Node3D, tile: float) -> void:
	check(arc != null, "arc exists on the saved plot")
	if arc == null:
		return
	var visual := arc.get_node("Wall/ArcSurface") as MeshInstance3D
	var collision := arc.get_node("Wall/ArcShape") as CollisionShape3D
	var shape := collision.shape as ConcavePolygonShape3D
	check(shape != null and shape.get_faces() == visual.mesh.get_faces(),
		"the curved collision uses the exact wall triangles")
	check(is_equal_approx(visual.get_aabb().size.y / tile, Plot.WALL_HEIGHT_M), "arc keeps the standard wall height")
	var ends: PackedVector3Array = arc.get_meta(Plot.ARC_ENDS_META)
	var joined := {}
	for child in arc.get_node("Wall").get_children():
		if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			for index in [0, 2]:
				if ends[index] in child.shape.points:
					joined[index] = true
	check(joined.size() == 2 and Plot.finish_parts(arc).size() >= 3,
		"the arc has solid joints at both tower walls and shares the normal finish")


func dress_palace_preview(map: EmberMapLoader, mansion_id: String) -> void:
	# Presentation only, after the saved construction has already passed reload.
	var reference := (load("res://scenes/landscape_compact.tscn") as PackedScene).instantiate()
	var main := reference.get_node("Map") as EmberMapLoader
	var main_look := main.get_node("Look")
	var old_look := map.get_node("Look")
	map.remove_child(old_look)
	old_look.free()
	map.add_child(main_look.duplicate())
	check(main.compact_water_visual_material.shader == Plot.FOUNTAIN_WATER.shader, "the fountain uses the current main-map water shader")
	var painted := map.compact_terrain.working_copy()
	for slot in painted.palette_surface_roles.size():
		var role := painted.palette_surface_roles[slot]
		if GrassMaterials.WORLD_GROUND_MATERIALS.has(role):
			var material_id: String = GrassMaterials.WORLD_GROUND_MATERIALS[role]
			check(main.compact_terrain.palette_material_ids.has(material_id), "the surface material is used by the main-map terrain")
			painted.palette_material_ids[slot] = material_id
	map.compact_smooth_study_column_limit = main.compact_smooth_study_column_limit
	map.compact_ground_style = main.compact_ground_style
	map.compact_smooth_material_blend = main.compact_smooth_material_blend
	map.compact_material_light_mode = main.compact_material_light_mode
	map.set_editor_terrain_preview(painted)
	await ready_tiles(map._visual_surface_projection)

	reference.free()
	await fill_palace_lawn(map, mansion_id)


func fill_palace_lawn(map: EmberMapLoader, mansion_id: String) -> void:
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	var tile := map.imported_tile_size
	var size := map.authored_size_blocks
	var raster_size := Vector2i(Vector2(size) / LAWN_MASK_STEP)
	var occupied := PackedByteArray()
	occupied.resize(raster_size.x * raster_size.y)
	for member: Node3D in Plot.snapshot(map):
		if member.get_meta(Plot.META, "") != mansion_id or member.get_meta(Plot.LEVEL_META, 0) > 0:
			continue
		if member.has_node("Basin/Bowl"):
			var bowl := member.get_node("Basin/Bowl") as MeshInstance3D
			stamp_lawn_footprint(occupied, raster_size, projection, bowl, bowl.get_aabb(), true, tile)
		elif member.scene_file_path == "res://prefabs/items/fruit_tree.scn":
			stamp_lawn_footprint(occupied, raster_size, projection, member,
				AABB(Vector3(-0.32, 0, -0.32) * tile, Vector3(0.64, 1, 0.64) * tile), true, tile)
		else:
			for body in member.get_children():
				if body is not StaticBody3D or body.name == "Roof":
					continue
				for node in body.get_children():
					var collider := node as CollisionShape3D
					if collider != null and collider.shape is BoxShape3D:
						var box := collider.shape as BoxShape3D
						stamp_lawn_footprint(occupied, raster_size, projection, collider, AABB(-box.size * 0.5, box.size), false, tile)

	var detail := preload("res://scripts/ember_detail_scatter.gd")
	var patch_script := preload("res://scripts/ember_grass_patch.gd")
	var props := map.get_node("Props") as Node3D
	var masks := {}
	var covered := 0
	for z in raster_size.y:
		for x in raster_size.x:
			if occupied[z * raster_size.x + x] != 0:
				continue
			var point := Vector2(x + 0.5, z + 0.5) * LAWN_MASK_STEP
			var hit := projection.floor_surface_sample(projection.to_global(Vector3(point.x, 0, point.y) * tile))
			if not hit.get("solid", false) or hit.get("material_role") != "grass":
				continue
			var address := detail.patch_address(point)
			if not masks.has(address):
				masks[address] = {}
			masks[address][detail.cell_address(point) - address * detail.CELLS] = 44
			covered += 1
		if z % 8 == 0:
			await frames(1)
	for address: Vector2i in masks:
		var patch := patch_script.new()
		patch.name = "DetailGrass_%d_%d" % [address.x, address.y]
		patch.painted_only = true
		patch.density_cells = masks[address]
		props.add_child(patch)
		patch.position = Vector3(address.x, 0, address.y) * detail.PATCH_M * tile
		patch.owner = map.owner
	check(covered * LAWN_MASK_STEP * LAWN_MASK_STEP > size.x * size.y * 0.6, "native lawn covers dry ground and leaves construction clear")


func stamp_lawn_footprint(mask: PackedByteArray, extent: Vector2i, projection: Node3D,
		node: Node3D, bounds: AABB, round_footprint: bool, tile: float) -> void:
	var padding := 0.12 * tile
	var padded := bounds.grow(padding)
	var frame := projection.global_transform.affine_inverse() * node.global_transform
	var box := frame * padded
	var step := LAWN_MASK_STEP * tile
	var lo := Vector2i((Vector2(box.position.x, box.position.z) / step).floor()).max(Vector2i.ZERO)
	var hi := Vector2i((Vector2(box.end.x, box.end.z) / step).ceil()).min(extent)
	var inverse := frame.affine_inverse()
	var half := Vector2(padded.size.x, padded.size.z) * 0.5
	var center := Vector2(padded.get_center().x, padded.get_center().z)
	for z in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var point := inverse * Vector3((x + 0.5) * step, frame.origin.y, (z + 0.5) * step)
			var distance := (Vector2(point.x, point.z) - center) / half
			if (distance.length_squared() if round_footprint else maxf(absf(distance.x), absf(distance.y))) <= 1.0:
				mask[z * extent.x + x] = 1


func convert_mira_door(world: Node, map: EmberMapLoader, key: String, history: Object) -> void:
	var path := NodePath("Props/" + key)
	var single := map.get_node_or_null(path) as Node3D
	check(single != null and single.has_node("Wall/DoorPanel"), "find the existing single entrance door")
	if single == null or not single.has_node("Wall/DoorPanel"):
		return
	var tile := map.imported_tile_size
	var before := Plot.placed_opening_options(single, tile)
	var panel: Control = world._plan_panel
	panel._buttons.plot_level.select(0)
	panel._buttons.plot_window_pick.pressed.emit()
	var camera_pose := _camera.transform
	var point := single.to_global(Vector3(before.center, 1.1, 0) * tile)
	_camera.look_at_from_position(point + single.global_basis.z * tile * 0.85, point)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = _camera.unproject_position(point)
	world.forward_input(_camera, event)
	_camera.transform = camera_pose
	check(world._plot_window_name == key and panel._buttons.opening_leaves.selected == 0, "existing door loads as single-leaf")
	panel._buttons.opening_leaves.select(1)
	panel._buttons.opening_leaves.item_selected.emit(1)
	panel._buttons.plot_window_apply.pressed.emit()
	var paired := map.get_node(path) as Node3D
	check(paired != single and paired.transform == single.transform, "convert the existing door without moving the wall")
	check_double_door(paired, tile, Plot.TOP_TRIANGLE)
	var after := Plot.placed_opening_options(paired, tile)
	check(is_equal_approx(after.center, before.center) and after.width == before.width and after.height == before.height,
		"conversion keeps the doorway centered with its previous dimensions")
	check_saved_finish(paired, tile, Plot.FINISH_DOOR)
	check_saved_finish(paired, tile, Plot.FINISH_FRAME)
	history.undo()
	check(map.get_node(path) == single, "undo restores the single door")
	history.redo()
	check(map.get_node(path) == paired, "redo restores both leaves")


func test_piece_finish(world: Node, map: EmberMapLoader, piece: Node3D, part_path: String, history: Object, group: int) -> void:
	var panel: Control = world._plan_panel
	var part := piece.get_node(part_path) as MeshInstance3D
	var key := piece.name
	var tile := map.imported_tile_size
	var starting_finish := Plot.piece_finish(piece, tile, group)
	var shape_path := "Railing/RailingShape" if part_path.begins_with("Railing") else part_path + "Shape"
	var shape := piece.get_node(shape_path) as CollisionShape3D
	var props := piece.get_parent()
	var camera_pose := _camera.transform
	var bounds := part.get_aabb()
	var aim := part.to_global(bounds.get_center())
	var offset := piece.global_basis.z * tile * 1.7
	if group == Plot.FINISH_DOOR:
		# Aim between the decorative crossbar and uprights, not at the center of the frame.
		aim = part.to_global(bounds.get_center() + bounds.size * Vector3(0.23, 0.2, 0))
		offset = part.global_basis.z * tile * 0.65
	elif group == Plot.FINISH_FRAME:
		offset = -part.global_basis.z * tile * 0.6
	elif part_path.begins_with("Slab") or part_path.begins_with("Entry"):
		offset = Vector3(0, 0.35, 0.05) * tile
	elif part.mesh is not BoxMesh:
		var faces := part.mesh.get_faces()
		var normal := (faces[1] - faces[0]).cross(faces[2] - faces[0]).normalized()
		aim = part.to_global((faces[0] + faces[1] + faces[2]) / 3.0)
		var outward := part.global_basis * normal
		if part_path.begins_with("Roof") and outward.y < 0.0:
			outward = -outward
		offset = outward * tile * 0.5 + Vector3(0, 0, 0.035) * tile
	_camera.look_at_from_position(aim + offset, aim)
	panel._buttons.plot_level.select(piece.get_meta(Plot.LEVEL_META, 0))
	panel._buttons.plot_finish_pick.pressed.emit()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = _camera.unproject_position(aim)
	world.forward_input(_camera, event)
	_camera.transform = camera_pose
	check(world._plot_finish_name == str(key) and world._plot_finish_group == group,
		"pick %s on %s in group %d, got %s in group %d" % [part_path, key, group, world._plot_finish_name, world._plot_finish_group])
	if world._plot_finish_name != str(key) or world._plot_finish_group != group:
		return
	panel._buttons.finish_texture.select(0 if group == Plot.FINISH_DOOR else 1)
	panel._buttons.finish_color.color = Color("304964") if group == Plot.FINISH_DOOR else Color("c99d73")
	panel._buttons.finish_scale.value = 1.5
	panel._buttons.plot_finish_apply.pressed.emit()
	var edited := props.get_node(NodePath(key)) as Node3D
	check_saved_finish(edited, tile, group)
	check(edited.transform == piece.transform, "editing keeps the original piece transform")
	var changed_parts := Plot.finish_parts(edited, group)
	for sibling in changed_parts[0].get_parent().get_children():
		if sibling is MeshInstance3D and sibling not in changed_parts:
			var original := piece.get_node(edited.get_path_to(sibling)) as MeshInstance3D
			check(sibling.material_override == original.material_override, "finishing leaves adjacent surfaces untouched")
	var next_shape := edited.get_node(shape_path) as CollisionShape3D
	check(next_shape.shape == shape.shape and next_shape.transform == shape.transform, "finishing leaves collision unchanged")
	history.undo()
	check(Plot.piece_finish(props.get_node(NodePath(key)), tile, group) == starting_finish, "undo restores the original finish")
	history.redo()
	check_saved_finish(props.get_node(NodePath(key)), tile, group)
	panel._buttons.plot_finish_reset.pressed.emit()
	var reset := props.get_node(NodePath(key)) as Node3D
	check(Plot.piece_finish(reset, tile, group) == starting_finish, "reset restores the original finish")
	for restored in Plot.finish_parts(reset, group):
		var original := piece.get_node(reset.get_path_to(restored)) as MeshInstance3D
		check(restored.get_active_material(0) == original.get_active_material(0), "reset restores each original material")
	history.undo()
	check_saved_finish(props.get_node(NodePath(key)), tile, group)


func check_roof_finish_after_shape_change(world: Node, map: EmberMapLoader, key: String, history: Object) -> void:
	var path := NodePath("Props/" + key)
	var before := map.get_node(path) as Node3D
	var panel: Control = world._plan_panel
	world._terrain_plan_action("plot_roof_select", world._plan_selected_id, key)
	panel._buttons.roof_height.value += 0.25
	world._terrain_plan_action("plot_roof_apply", world._plan_selected_id, key)
	var after := map.get_node(path) as Node3D
	check(after != before, "change the roof shape after finishing it")
	check_saved_finish(after, map.imported_tile_size)
	check_saved_finish(after, map.imported_tile_size, Plot.FINISH_FRAME)
	history.undo()


func check_frame_finish_after_window_move(world: Node, map: EmberMapLoader, key: String, history: Object) -> void:
	var path := NodePath("Props/" + key)
	var before := map.get_node(path) as Node3D
	var panel: Control = world._plan_panel
	world._plot_window_name = key
	world._refresh_plot_window()
	panel._buttons.window_center.value += 0.125
	panel._buttons.plot_window_apply.pressed.emit()
	var after := map.get_node(path) as Node3D
	check(after != before, "move the window after finishing its frame")
	check_saved_finish(after, map.imported_tile_size, Plot.FINISH_FRAME)
	history.undo()


func check_saved_finish(piece: Node3D, tile: float, group := Plot.FINISH_SURFACE) -> void:
	var settings := Plot.piece_finish(piece, tile, group)
	var is_door := group == Plot.FINISH_DOOR
	var tint := Color("304964") if is_door else Color("c99d73")
	check(settings.get("finish") == (0 if is_door else 1) and settings.color.is_equal_approx(tint)
		and is_equal_approx(settings.scale, 1.0 if is_door else 1.5), "finish keeps its texture, tint and scale")
	for part in Plot.finish_parts(piece, group):
		var material := part.material_override as StandardMaterial3D
		var texture := material.albedo_texture if material != null else null
		check(material != null and material.albedo_color.is_equal_approx(tint)
			and (texture == null if is_door else texture != null and texture.resource_path == Plot.STONE_TEXTURE),
			"the finish covers each surface in the chosen group")


func mesh_has_cap_at(part: MeshInstance3D, height: float) -> bool:
	var faces := part.mesh.get_faces()
	for first in range(0, faces.size(), 3):
		if is_equal_approx((part.transform * faces[first]).y, height) \
				and is_equal_approx((part.transform * faces[first + 1]).y, height) \
				and is_equal_approx((part.transform * faces[first + 2]).y, height):
			return true
	return false


func check_hedge_cutout(crown: MeshInstance3D, tile: float) -> void:
	if crown == null:
		check(false, "find the saved hedge cutout sample")
		return
	var material := crown.material_override as ShaderMaterial
	var atlas := material.get_shader_parameter("leaf_atlas") as Texture2D
	check(atlas != null and atlas.resource_path == Plot.HEDGE_AUTUMN_LEAVES, "the autumn leaf atlas survives save and reopen")
	var interior := crown.get_parent().get_node_or_null("HedgeInterior") as MeshInstance3D
	if interior == null:
		check(false, "find the inner crown for the render comparison")
		return
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 0.9, 0.025) * tile
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color.MAGENTA
	var marker := MeshInstance3D.new()
	marker.mesh = box
	marker.material_override = paint
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crown.add_child(marker)
	marker.position = Vector3(crown.get_aabb().get_center().x / tile, 1.0, 0.38) * tile
	var center := crown.to_global(Vector3(marker.position.x, marker.position.y, 0))
	_camera.look_at_from_position(center - crown.global_basis.z.normalized() * (tile * 3.5), center)
	var visible_marker_pixels: Array[int] = []
	for mode in 3:
		crown.material_override = StandardMaterial3D.new() if mode == 0 else material
		interior.visible = mode == 2
		await frames(4)
		await RenderingServer.frame_post_draw
		var image := _camera.get_viewport().get_texture().get_image()
		var middle := image.get_size() / 2
		var count := 0
		for y in range(middle.y - 60, middle.y + 60, 2):
			for x in range(middle.x - 100, middle.x + 100, 2):
				var pixel := image.get_pixel(x, y)
				if pixel.r > 0.70 and pixel.b > 0.70 and pixel.g < 0.25:
					count += 1
		visible_marker_pixels.append(count)
	marker.free()
	check(visible_marker_pixels[0] == 0 and visible_marker_pixels[1] > 40,
		"opaque foliage hides an interior marker and cutouts reveal it")
	check(visible_marker_pixels[2] < visible_marker_pixels[1] * 0.5, "inner crown closes most see-through gaps in the middle")
	print("GARDEN_HEDGE_GAPS ", JSON.stringify({"opaque": visible_marker_pixels[0],
		"cutout": visible_marker_pixels[1], "with_inner_crown": visible_marker_pixels[2]}))


func click_small_facade(world: Node, map: EmberMapLoader, x: float) -> void:
	var props := map.get_node("Props") as Node3D
	var tile := map.imported_tile_size
	var point := Vector3(x * tile, world._plot_level_y(props) + tile * 1.5, (9.0 - Plot.WALL_DEPTH_M * 0.5) * tile)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = _camera.unproject_position(props.to_global(point))
	world.forward_input(_camera, event)
