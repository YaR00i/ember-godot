extends SceneTree
const Surface = preload("res://addons/ember_import/ember_voxel_surface_marquee.gd")
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void:
	for density in [16,32]:
		for axis in 3:
			for sign_value in [-1,1]:
				var cell := Vector3i(4,4,4)
				var normal := Vector3.ZERO
				normal[axis] = sign_value
				var center: Vector3 = (Vector3(cell)+Vector3.ONE*0.5)/density
				var surface := Surface.new()
				check(surface.begin(cell,center+normal*10,-normal,density),"face begin")
				check(surface.axis == axis and surface.outward == sign_value,"face sign")
				var along := Vector3.ONE
				along[axis] = 0
				var plan := surface.bounds(center+normal*10+along*2.0/density,-normal,3)
				check(not plan.has("error"),"plane intersection")
				check(plan.high-plan.low == Vector3i(2,2,2),"depth and tangent extent")
				check(plan.low[axis] == (2 if sign_value > 0 else 4),"depth goes inward")
				var reverse := surface.bounds(center+normal*10-along*2.0/density,-normal,1)
				check(reverse.low[axis] == 4 and reverse.high[axis] == 4,"reverse tangent depth1")
				var footprint := surface.footprint_bounds(center+normal*10+along*2.0/density,-normal)
				var staged := surface.bounds_from_footprint(footprint.low,footprint.high,3)
				check(staged.low == plan.low and staged.high == plan.high,"staged bounds match direct bounds")
				var grid := Vector3i(9,10,11)
				var expected_max := cell[axis]+1 if sign_value > 0 else grid[axis]-cell[axis]
				check(surface.maximum_depth(grid) == expected_max,"face-aware maximum depth")
				var parallel := Vector3.ZERO
				parallel[(axis+1)%3] = 1
				check(surface.bounds(center+normal*10,parallel,1).has("error"),"parallel rejection")
	check(Surface.depth_from_screen(Vector2(10,10),Vector2(10,10),Vector2(0,8),12) == 1,"screen depth starts at one")
	check(Surface.depth_from_screen(Vector2(10,10),Vector2(10,34),Vector2(0,8),12) == 4,"screen depth follows projected voxel step")
	check(Surface.depth_from_screen(Vector2(10,10),Vector2(10,-100),Vector2(0,8),12) == 1,"screen depth clamps before surface")
	check(Surface.depth_from_screen(Vector2(10,10),Vector2(10,500),Vector2(0,8),12) == 12,"screen depth clamps to model")
	var source: EmberVoxelModelResource = Shapes.build("block",Vector3i(16,8,16),16,Color.BROWN,"marquee","Board").source
	var query := Selection.new()
	query.start_box(source,Vector3i(-5,-5,-5),Vector3i(2,2,2))
	while not query.done:
		query.step(128)
	check(query.error.is_empty() and query.indices.size() == 27,"clip to existing volume")
	print("test_voxel_surface_marquee: ","PASS" if failures == 0 else "FAIL"," · ",failures)
	quit(failures)
