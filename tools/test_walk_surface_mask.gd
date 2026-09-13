extends SceneTree
const Mask = preload("res://addons/ember_import/ember_walk_surface_mask.gd")
const Surface = preload("res://addons/ember_import/ember_walk_surface.gd")
const Session = preload("res://addons/ember_import/ember_walk_surface_session.gd")
const WalkPanel = preload("res://addons/ember_import/ember_walk_surface_panel.gd")
var failures: Array[String] = []
class FixturePlayer extends EmberPlayer:
	func _progress() -> EmberExploreState:
		return null

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func board(group: Node3D, pos: Vector3, extent: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = extent
	node.mesh = mesh
	node.position = pos
	group.add_child(node)
	node.owner = group.owner
	return node

func ray(scene: Node3D, x: float, z: float) -> Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,20,z),Vector3(x,-5,z),1))

func _run() -> void:
	# A short gap which touches the outside is still closed between two boards;
	# a simple enclosed-hole flood fill would miss it. Open board ends stay empty.
	var count := Vector2i(12,8)
	var source := PackedByteArray()
	source.resize(96)
	for z in range(1,7):
		for x in [2,3,6,7,10]:
			source[z*12+x] = 1
	var closed := Mask.close_gaps(source,count,2)
	check(closed[3*12+4] == 1 and closed[3*12+5] == 1,"two-voxel gap not closed")
	check(closed[0] == 0 and closed[3*12+1] == 0 and closed[3*12+11] == 0,"outer contour grew")
	check(Mask.close_gaps(source,count,1)[3*12+4] == 0,"gap limit ignored")
	var data := Mask.make(count,Vector2(0.5,0.5),closed)
	check(Mask.at(Vector3(-3,0,-2),data) == Vector2i.ZERO,"grid origin")
	Mask.paint(data,Vector2i(2,3),Vector2i(10,3),1,false)
	check(data.bits[3*12+6] == 0,"fast stroke has skipped cells")
	Mask.paint(data,Vector2i(0,0),Vector2i(11,7),3,true)
	check(data.bits[0] == 0 and data.bits[3*12+6] == 1,"restore invents outer support")
	check(Mask.valid(data),"valid brush data rejected")
	var malformed := data.duplicate(true)
	malformed.bits[0] = 1
	check(not Mask.valid(malformed),"bits outside allowed footprint accepted")
	var represented := PackedByteArray()
	represented.resize(data.bits.size())
	for rect in Mask.rectangles(data):
		for z in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				represented[z*count.x+x] += 1
	check(represented == data.bits,"rectangles overlap or change footprint")
	var scene := Node3D.new()
	scene.name = "MaskFixture"
	root.add_child(scene)
	var group := Node3D.new()
	group.name = "Bridge"
	scene.add_child(group)
	group.owner = scene
	for x in [0,10,20,30]:
		board(group,Vector3(x,0.5,0),Vector3(8,1,20))
	# Uneven board end: supported main span, absent outer corner.
	board(group,Vector3(40,0.5,-3),Vector3(8,1,14))
	# Lower beam should not turn the entire top into solid support.
	board(group,Vector3(20,-4,0),Vector3(55,1,30))
	var edit := Session.new()
	check(edit.open(group,scene),edit.error)
	var started := Time.get_ticks_usec()
	check(edit.generate(2,2),edit.error)
	print("MASK_GENERATE_MS ",float(Time.get_ticks_usec()-started)/1000)
	check(not edit.planned_mask.is_empty(),"generation missing")
	if edit.planned_mask.is_empty() or not edit._has_plan:
		_finish(scene,null)
		return
	var gap := Mask.at(edit.world_pose().affine_inverse()*Vector3(5.5,1,0.5),edit.planned_mask)
	var edge := Mask.at(edit.world_pose().affine_inverse()*Vector3(40,1,8),edit.planned_mask)
	check(edit.planned_mask.bits[gap.y*edit.planned_mask.count.x+gap.x] == 1,"physical board gap not filled")
	check(edit.planned_mask.bits[edge.y*edit.planned_mask.count.x+edge.x] == 0,"ragged end filled")
	var undo := UndoRedo.new()
	var support := edit.commit(undo)
	check(support != null,edit.error)
	if support == null:
		_finish(scene,undo)
		return
	await physics_frame
	await physics_frame
	check(not ray(scene,5,0).is_empty(),"no collision over small gap")
	check(ray(scene,40,8).is_empty() and ray(scene,46,0).is_empty(),"collision beyond outer contour")
	var player := FixturePlayer.new()
	scene.add_child(player)
	player.position = Vector3(0,3,0)
	for frame in 40:
		await physics_frame
	var low := player.position.y
	var high := low
	Input.action_press("move_east")
	for frame in 40:
		await physics_frame
		low = minf(low,player.position.y)
		high = maxf(high,player.position.y)
	Input.action_release("move_east")
	check(player.position.x > 25 and player.is_on_floor() and high-low < 0.04,"player oscillates/sticks on mask collision seams")
	player.free()
	var panel := WalkPanel.new()
	root.add_child(panel)
	check(panel.open_for(support,scene,undo),"saved mask panel open")
	check(panel._numbers[0].value == edit.planned_mask.count.x and not panel._numbers[0].editable,"voxel dimensions missing")
	var before: Dictionary = panel.session.planned_mask.duplicate(true)
	panel._stroke_before = before.duplicate(true)
	Mask.paint(panel.session.planned_mask,gap,gap,1,false)
	panel._finish_stroke()
	check(panel._undo_masks.size() == 1,"stroke not atomic")
	panel._history(false)
	check(panel.session.planned_mask.bits == before.bits,"draft stroke undo")
	panel._history(true)
	check(panel.session.planned_mask.bits != before.bits,"draft stroke redo")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK,"pack during brush preview")
	var reopened := packed.instantiate()
	check(reopened.get_node("Bridge/WalkSurface").get_meta(Surface.MASK_KEY).bits == before.bits,"draft brush serialized")
	reopened.free()
	panel._commit()
	await physics_frame
	await physics_frame
	check(ray(scene,5.5,0.5).is_empty(),"erased voxel still collides")
	undo.undo()
	await physics_frame
	await physics_frame
	check(not ray(scene,5,0).is_empty(),"whole action undo loses mask")
	undo.redo()
	var saved := PackedScene.new()
	check(saved.pack(scene) == OK,"pack applied mask")
	var path := "user://walk-mask-%d.tscn" % Time.get_ticks_usec()
	check(ResourceSaver.save(saved,path) == OK,"save applied mask")
	reopened = (ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var loaded := reopened.get_node("Bridge/WalkSurface") as StaticBody3D
	check(loaded.get_script() == null and loaded.get_meta(Surface.MASK_KEY).bits == support.get_meta(Surface.MASK_KEY).bits,"saved mask reopen")
	var reopened_edit := Session.new()
	root.add_child(reopened)
	check(reopened_edit.open(loaded,reopened),"reopened mask cannot be edited")
	reopened.free()
	check(panel.open_for(support,scene,undo),"mask panel reopen")
	panel._stroke_before = panel.session.planned_mask.duplicate(true)
	Mask.paint(panel.session.planned_mask,gap,gap,1,true)
	panel._abort_stroke()
	check(panel.session.planned_mask.bits == support.get_meta(Surface.MASK_KEY).bits,"Escape/abort keeps uncommitted stroke")
	panel.cancel_edit()
	check(panel._instances.is_empty() and not panel._cursor.is_valid(),"preview/cursor leak")
	support.position += Vector3(0.21,0.96,0.38)
	var fractional := support.position
	check(panel.open_for(support,scene,undo),"fractional saved footprint open")
	check(is_equal_approx(panel._numbers[2].value,fractional.x) and is_equal_approx(panel._numbers[3].value,fractional.y),"opening mask rounds its scene position")
	panel.cancel_edit()
	panel.free()
	# A 32-voxel/block prop with a scaled derived mesh uses half-unit cells.
	var prop := EmberVoxelProp.new()
	prop.name = "Dense"
	prop.voxels_per_block = 32
	group.add_child(prop)
	prop.owner = scene
	var visual := board(prop,Vector3.ZERO,Vector3.ONE)
	visual.name = "Mesh"
	visual.scale = Vector3.ONE*16
	var dense := Session.new()
	check(dense.open(prop,scene) and dense.voxel_cell == Vector2(0.5,0.5),"32-density voxel spacing ignored")
	check(dense.generate(1,2) and dense.planned_mask.count == Vector2i(32,32),"dense prop generation")
	visual.position.x += 1
	check(not dense.geometry_current() and dense.commit(undo) == null,"stale geometry applied")
	visual.position.x -= 1
	visual.scale.y = 8
	var compressed := Session.new()
	check(compressed.open(prop,scene) and is_equal_approx(compressed.voxel_height,0.25),"vertical voxel scale ignored")
	check(compressed.generate(1,2),"nonuniform voxel scale generation")
	var added_mesh := board(prop,Vector3.ZERO,Vector3.ONE)
	check(not compressed.geometry_current(true) and compressed.commit(undo) == null,"added source geometry applied with stale footprint")
	added_mesh.free()
	var rebound := Session.new()
	check(rebound.open(support,scene),"source rebind edit open")
	var old_mask: Dictionary = support.get_meta(Surface.MASK_KEY).duplicate(true)
	check(rebound.rebind_geometry(visual) and rebound.voxel_cell == Vector2(0.5,0.5),"selected derived Mesh loses voxel density")
	check(rebound.rebind_geometry(prop) and rebound.generate(1,2),"source rebind generation")
	check(rebound.commit(undo) == support and support.get_meta("ember_walk_source") == NodePath("Dense"),"source rebind created duplicate or lost binding")
	undo.undo()
	check(support.get_meta(Surface.MASK_KEY).bits == old_mask.bits and support.get_meta("ember_walk_source") == NodePath("."),"source rebind Undo loses footprint/binding")
	# Exact bug reported on the authored bridge: a second helper kept the erased
	# voxels collidable. Resolve explicitly, preserve both nodes, Undo everything.
	var duplicate := Surface.make_node(Surface.dimensions(support))
	duplicate.name = "OldSupport"
	var duplicate_data: Dictionary = support.get_meta(Surface.MASK_KEY).duplicate(true)
	duplicate_data.bits = duplicate_data.allowed.duplicate()
	Surface.set_mask(duplicate,duplicate_data)
	duplicate.transform = support.transform
	duplicate.set_meta("ember_walk_source",NodePath("."))
	group.add_child(duplicate)
	duplicate.owner = scene
	for child in duplicate.get_children():
		child.owner = scene
	var ambiguous := Session.new()
	check(not ambiguous.open(group,scene),"multiple linked supports silently create a third")
	var duplicate_panel := WalkPanel.new()
	root.add_child(duplicate_panel)
	check(duplicate_panel.open_for(support,scene,undo),"duplicate panel open")
	check(duplicate_panel._replace.visible and duplicate_panel._apply.disabled and duplicate_panel._status.text.contains("OldSupport"),"duplicate warning/action missing")
	var point := support.global_transform*Mask.rect_pose(Rect2i(gap,Vector2i.ONE),old_mask)
	await physics_frame
	await physics_frame
	check(not ray(scene,point.x,point.z).is_empty(),"duplicate fixture does not cover erased cell")
	check(duplicate_panel.session.commit(undo) == null and duplicate.collision_layer == 1,"ordinary Apply silently resolves/ignores overlap")
	duplicate_panel._commit(true)
	await physics_frame
	await physics_frame
	check(duplicate.collision_layer == 0 and duplicate.get_parent() == group and ray(scene,point.x,point.z).is_empty(),"resolved duplicate still supports erased voxel")
	undo.undo()
	check(duplicate.collision_layer == 1,"duplicate resolution Undo")
	undo.redo()
	check(duplicate.collision_layer == 0,"duplicate resolution Redo")
	var resumed := Session.new()
	check(resumed.open(group,scene) and resumed.target == support,"reopening source creates a duplicate rather than editing active helper")
	var resolved_pack := PackedScene.new()
	resolved_pack.pack(scene)
	var resolved_scene := resolved_pack.instantiate()
	check(resolved_scene.get_node("Bridge/OldSupport").collision_layer == 0,"disabled duplicate not serialized")
	resolved_scene.free()
	duplicate_panel.free()
	# Representative 192x256 footprint, measured once at generation, never on
	# pointer motion. Fixtures remain independent from mutable authored models.
	var wide := Node3D.new()
	scene.add_child(wide)
	wide.owner = scene
	for index in 8:
		board(wide,Vector3(index*24,0.5,0),Vector3(22,1,256-index%3))
	board(wide,Vector3(84,-5,0),Vector3(192,1,256))
	var large := Session.new()
	check(large.open(wide,scene),"large footprint open")
	started = Time.get_ticks_usec()
	check(large.generate(2,2),large.error)
	print("MASK_192x256_GENERATE_MS ",float(Time.get_ticks_usec()-started)/1000," rectangles=",Mask.rectangles(large.planned_mask).size())
	check(large.planned_mask.count == Vector2i(192,256),"representative fixture wrong size")
	if OS.get_cmdline_user_args().has("--benchmark-native"):
		var real_prop := (load("res://prefabs/voxels/vox_merge_60949294_0.tscn") as PackedScene).instantiate() as EmberVoxelProp
		scene.add_child(real_prop)
		real_prop.owner = scene
		var native := Session.new()
		check(native.open(real_prop,scene),"native prefab open")
		started = Time.get_ticks_usec()
		check(native.generate(2,2),native.error)
		print("MASK_NATIVE_GENERATE_MS ",float(Time.get_ticks_usec()-started)/1000," cells=",native.planned_mask.count," spacing=",native.voxel_cell)
	_finish(scene,undo)

func _finish(scene: Node, undo: UndoRedo) -> void:
	for message in failures:
		push_error(message)
	print("test_walk_surface_mask: ","PASS" if failures.is_empty() else "FAIL"," · ",failures.size())
	if undo != null:
		undo.clear_history()
		undo.free()
	scene.free()
	quit(0 if failures.is_empty() else 1)
