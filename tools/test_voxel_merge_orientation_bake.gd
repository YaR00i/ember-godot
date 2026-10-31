extends SceneTree
## Pure merge mathematics; scene/UI/history/publication are covered by test_canvas_forms and the editor entry gate.
const Merge = preload("res://addons/ember_import/ember_voxel_merge.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
var errors := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)

func _init() -> void:
	_run.call_deferred()

func _key(source: EmberVoxelModelResource, frame: Transform3D, index: int) -> Vector3i:
	var cell := Merge.Selection.cell_of(index,source.grid_size())
	return Vector3i((frame*((Vector3(cell)+Vector3.ONE*0.5)/source.normalized_density())*4096.0).round())

func _cells(source: EmberVoxelModelResource, frame: Transform3D) -> Dictionary:
	var result := {}
	for i in source.voxels.size():
		if source.voxels[i] == 0:
			continue
		var attributes: Array = [source.palette[source.voxels[i]],source.voxel_part_ids[i]]
		for channel in Merge.Fragment.CHANNELS:
			if channel == "voxels":
				continue
			var values: PackedByteArray = source.get(channel)
			attributes.append(values[i] if not values.is_empty() else -1)
		result[_key(source,frame,i)] = attributes
	return result

func _groups(source: EmberVoxelModelResource, frame: Transform3D) -> Array:
	var result: Array = []
	for group in source.voxel_groups:
		var copy: Dictionary = group.duplicate(true)
		var points: Array[String] = []
		for i in group.indices:
			points.append(str(_key(source,frame,i)))
		points.sort()
		copy.erase("indices")
		copy.points = points
		result.append(copy)
	return result

func _overlap(plan: Dictionary) -> Dictionary:
	var result := {}
	for i in plan.overlap:
		result[_key(plan.source,plan.frame,i)] = true
	return result

func _run() -> void:
	var a: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,4,16),16,Color.BROWN,"bake_a","A").source
	a.palette.append(Color.GREEN)
	a.voxels[0] = 1
	a.voxels[17] = 2
	a.voxels[256] = 1
	for channel in Merge.Fragment.CHANNELS:
		if channel == "voxels":
			continue
		var values := PackedByteArray()
		values.resize(a.voxels.size())
		values[0] = 1 if channel == "collision_voxels" else 40
		values[17] = 1 if channel == "collision_voxels" else 70
		values[256] = 1 if channel == "collision_voxels" else 100
		a.set(channel,values)
	a.voxel_groups = [{"id":"paint","name":"Pattern","locked":true,"color":Color.ORANGE,"indices":PackedInt32Array([0,17,256])}]
	var b: EmberVoxelModelResource = Shapes.build("empty",Vector3i(32,4,32),32,Color.BLUE,"bake_b","B").source
	b.voxels[0] = 1
	b.voxels[67] = 1
	var originals := [a.to_definition(),b.to_definition()]
	var axes := [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
	var count := 0
	for x in axes:
		for y in axes:
			if absf(x.dot(y)) > 0.1:
				continue
			var rotation := Basis(x,y,x.cross(y))
			var base := Transform3D(rotation.scaled(Vector3.ONE*24),Vector3(123,45,-67))
			var inputs: Array[Dictionary] = [{"source":a,"frame":base},{"source":b,"frame":base}]
			var ordinary := Merge.plan(inputs)
			var baked := Merge.plan(inputs,false,true)
			check(not ordinary.has("error") and not baked.has("error"),"orthogonal bake %d" % count)
			if ordinary.has("error") or baked.has("error"):
				continue
			check(baked.source.validation_errors().is_empty(),"valid baked resource")
			check(baked.frame.basis.is_equal_approx(Basis.IDENTITY.scaled(Vector3.ONE*24)),"scene-aligned output frame")
			check(_cells(ordinary.source,ordinary.frame) == _cells(baked.source,baked.frame),"world occupancy/color/six channels/parts unchanged")
			check(_groups(ordinary.source,ordinary.frame) == _groups(baked.source,baked.frame),"group members and metadata unchanged")
			check(_overlap(ordinary) == _overlap(baked),"overlap world positions unchanged")
			check(ordinary.source.merge_parts == baked.source.merge_parts,"part library unchanged")
			inputs[1].frame = base*Transform3D(Basis(Vector3.UP,PI/2.0),Vector3(0.01,0.2,0.05))
			ordinary = Merge.plan(inputs,true)
			baked = Merge.plan(inputs,true,true)
			check(not ordinary.has("error") and not baked.has("error"),"rotated secondary + alignment bake")
			if not ordinary.has("error") and not baked.has("error"):
				check(ordinary.adjustments == baked.adjustments,"alignment reports primary-grid axes and identical world delta")
				check(_cells(ordinary.source,ordinary.frame) == _cells(baked.source,baked.frame),"aligned bake matches ordinary world geometry")
			count += 1
	check(count == 24,"all24 proper orthogonal rotations")
	check(a.to_definition() == originals[0] and b.to_definition() == originals[1],"bake never mutates source drafts")
	var bad_inputs: Array[Dictionary] = [{"source":a,"frame":Transform3D.IDENTITY},{"source":b,"frame":Transform3D.IDENTITY}]
	for basis in [Basis(Vector3.UP,0.1),Basis.IDENTITY.scaled(Vector3(2,3,2)),Basis.IDENTITY.scaled(Vector3(-2,2,2)),Basis(Vector3(1,0,0),Vector3(0.1,1,0),Vector3(0,0,1))]:
		for input in bad_inputs:
			input.frame = Transform3D(basis,Vector3.ZERO)
		check(not Merge.plan(bad_inputs).has("error"),"ordinary merge still supports common frame")
		check(Merge.plan(bad_inputs,false,true).has("error"),"unsupported bake rejected without rounding")
	var tall: EmberVoxelModelResource = Shapes.build("empty",Vector3i(144,4,16),16,Color.BROWN,"tall_bake","Tall").source
	tall.voxels[0] = 1
	var turned := Transform3D(Basis(Vector3.FORWARD,PI/2.0),Vector3.ZERO)
	var large: Array[Dictionary] = [{"source":tall,"frame":turned},{"source":tall,"frame":turned}]
	check(not Merge.plan(large).has("error") and Merge.plan(large,false,true).has("error"),"baked height limits checked before publication")
	print("test_voxel_merge_orientation_bake: ","PASS" if errors == 0 else "FAIL"," · ",errors," · rotations=",count)
	quit(errors)
