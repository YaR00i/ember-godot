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
				var parallel := Vector3.ZERO
				parallel[(axis+1)%3] = 1
				check(surface.bounds(center+normal*10,parallel,1).has("error"),"parallel rejection")
	var source: EmberVoxelModelResource = Shapes.build("block",Vector3i(16,8,16),16,Color.BROWN,"marquee","Board").source
	var query := Selection.new()
	query.start_box(source,Vector3i(-5,-5,-5),Vector3i(2,2,2))
	while not query.done:
		query.step(128)
	check(query.error.is_empty() and query.indices.size() == 27,"clip to existing volume")
	print("test_voxel_surface_marquee: ","PASS" if failures == 0 else "FAIL"," · ",failures)
	quit(failures)
