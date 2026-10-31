extends SceneTree
## Pure merge mathematics; scene/UI/history/publication are covered by test_canvas_forms and the editor entry gate.
const Store=preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Merge = preload("res://addons/ember_import/ember_voxel_merge.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Growth = preload("res://addons/ember_import/ember_voxel_canvas_growth.gd")
var errors := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)
func _init() -> void:
	_run.call_deferred()
func shape(id: String, density := 16) -> EmberVoxelModelResource:
	var source: EmberVoxelModelResource = Shapes.build("empty",Vector3i(density,4,density),density,Color.BROWN,id,id).source
	source.voxels[0] = 1
	return source
func _run() -> void:
	var a := shape("a")
	a.shine.resize(a.voxels.size())
	a.shine[0] = 70
	a.voxel_groups = [{"id":"board","name":"Board","indices":PackedInt32Array([0]),"locked":false}]
	var b := shape("b",32)
	b.palette[1] = Color.GREEN
	var inputs: Array[Dictionary] = [{"source":a,"frame":Transform3D.IDENTITY,"name":"A"},{"source":b,"frame":Transform3D.IDENTITY,"name":"B"}]
	var initial := a.to_definition()
	var result := Merge.plan(inputs)
	check(not result.has("error"),"merge plan")
	if result.has("error"):
		print(result)
		quit(1)
		return
	var source: EmberVoxelModelResource = result.source
	check(a.to_definition() == initial,"detached preview")
	check(source.voxels.size()-source.voxels.count(0) == 8,"16 to 32 preserves occupied volume")
	check(result.overlap.size() == 1 and source.palette[source.voxels[0]] == Color.BROWN,"primary wins overlap")
	check(source.validation_errors().is_empty(),"valid merged resource")
	check(source.shine[0] == 70 and source.shine[1] == 70 and source.voxel_groups[0].indices.size() == 8,"promoted channels and groups")
	check(Merge.separate(source).pieces.size() == 1,"fully overlapped part does not resurrect")
	var undo := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(undo)
	var baseline := source.to_definition()
	var before_live := source.voxels.duplicate()
	source.voxels[10] = 1
	check(actions.commit_applied_stroke(source,before_live,source.voxels,PackedInt32Array([10])),"live pointer-up")
	check(source.voxel_part_ids[10] == 0,"live Added assigned")
	undo.undo()
	check(source.to_definition() == baseline,"live Undo exact")
	check(actions.apply_stroke(source,{0:{"before":1,"after":0},10:{"before":0,"after":1}}),"erase and add")
	check(source.voxel_part_ids[0] == 0 and source.voxel_part_ids[10] == 0,"added ownership")
	actions.active_part = 2
	check(actions.apply_stroke(source,{11:{"before":0,"after":1}}),"selected part stroke")
	check(source.voxel_part_ids[11] == 2,"selected part assigned")
	var separated := Merge.separate(source)
	check(not separated.has("error") and separated.pieces.size() == 3,"current shape split with Added")
	var occupied := 0
	for item in separated.pieces:
		occupied += item.source.voxels.size()-item.source.voxels.count(0)
		check(item.source.validation_errors().is_empty() and item.source.merge_parts.is_empty(),"valid ordinary output")
	check(occupied == 9,"removed voxels not resurrected")
	undo.undo()
	undo.undo()
	check(source.to_definition() == baseline,"one stroke undo exact ownership")
	undo.redo()
	undo.redo()
	var moved := Fragment.plan(source,PackedInt32Array([11]),Vector3i(1,0,0),1,0,false)
	check(not moved.has("error") and actions.apply_fragment(source,moved),"move part voxel")
	check(source.voxel_part_ids[12] == 2 and source.voxel_part_ids[11] == 0,"ownership follows move")
	check(actions.grow_canvas(source,Vector3i(64,source.grid_size().y,64)).has("properties"),"grow merged canvas")
	check(source.validation_errors().is_empty(),"growth ownership grid matches")
	var cut := Merge.Extract.plan(source,PackedInt32Array([12+16+16*64]),true)
	check(not cut.has("error") and cut.piece.voxel_part_ids[0] == 2,"crop ownership")
	var cutter := preload("res://addons/ember_import/ember_voxel_object_split.gd").new()
	cutter.source = source
	var section: EmberVoxelModelResource = cutter._extract({"origin":Vector3i.ZERO,"size":Vector3i(32,source.grid_size().y,64)},"ownership_section")
	check(section.validation_errors().is_empty() and section.merge_parts == source.merge_parts and section.voxel_part_ids.count(2) == 1,"section split preserves ownership")
	var path := "user://merge_%d.tres" % Time.get_ticks_usec()
	check(ResourceSaver.save(source,path) == OK,"save parts")
	var reopened := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(reopened.to_definition().model == source.to_definition().model,"reopen preserves all parts")
	inputs[1].frame = Transform3D(Basis(Vector3.UP,PI/2),Vector3(1,0,1))
	check(not Merge.plan(inputs).has("error"),"quarter rotation")
	inputs[1].frame = Transform3D(Basis(Vector3.UP,0.1),Vector3.ZERO)
	check(Merge.plan(inputs).has("error"),"arbitrary rotation refused")
	check(Merge.plan(inputs,true).has("error"),"alignment does not round rotation")
	inputs[1].frame = Transform3D(Basis.IDENTITY,Vector3(0.01,0,0))
	check(Merge.plan(inputs).has("error"),"unaligned position refused")
	var snapped := Merge.plan(inputs,true)
	check(not snapped.has("error") and snapped.adjustments.size() == 1,"mixed density alignment")
	check(snapped.adjustments[0].delta_world.is_equal_approx(Vector3(-0.01,0,0)),"alignment uses high-density grid")
	inputs[1].frame = Transform3D.IDENTITY
	a.palette.resize(256)
	for i in range(1,256):
		a.palette[i] = Color(float(i)/256,0,0)
	check(Merge.plan(inputs).has("error"),"palette overflow refuses without approximation")
	undo.clear_history()
	undo.free()
	if "--benchmark" in OS.get_cmdline_user_args():
		_benchmark()
	print("Voxel merge: ","PASS" if errors == 0 else "FAIL %d" % errors)
	quit(0 if errors == 0 else 1)

func _benchmark() -> void:
	var a: EmberVoxelModelResource = Shapes.build("block",Vector3i(64,16,64),16,Color.BROWN,"bench_a","A").source
	var inputs: Array[Dictionary] = [{"source":a,"frame":Transform3D.IDENTITY},{"source":a,"frame":Transform3D(Basis.IDENTITY,Vector3(4,0,0))}]
	var started := Time.get_ticks_usec()
	var result := Merge.plan(inputs)
	print("Merge dense 131072 occupied cells ms: ",(Time.get_ticks_usec()-started)/1000.0)
	check(not result.has("error"),"dense benchmark merge")
	started = Time.get_ticks_usec()
	var split := Merge.separate(result.source)
	print("Unmerge dense 131072 occupied cells ms: ",(Time.get_ticks_usec()-started)/1000.0)
	check(not split.has("error") and split.pieces.size() == 2,"dense benchmark unmerge")
	started = Time.get_ticks_usec()
	var packed := EmberVoxelPrefab.prepare_resource(result.source)
	print("Dense merged mesh + collision ms: ",(Time.get_ticks_usec()-started)/1000.0)
	var directory := "user://merge_benchmark_%d" % Time.get_ticks_usec()
	started = Time.get_ticks_usec()
	var saved := Store.install_prepared_asset(result.source,packed,directory.path_join("merge.tres"),directory.path_join("merge.tscn"))
	print("Dense merged asset publish ms: ",(Time.get_ticks_usec()-started)/1000.0)
	check(saved.ok,"dense benchmark publish")
