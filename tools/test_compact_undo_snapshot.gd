extends SceneTree
## Isolated million-column Undo snapshot. No authored scene or Resource is saved.

const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const SIDE := 1536
const CHANGED := 1048576


class StageSink extends RefCounted:
	var stages := {}

	func stage(name: String, duration_usec: int) -> void:
		stages[name] = int(stages.get(name, 0)) + duration_usec


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := TerrainResource.new()
	source.width = SIDE
	source.depth = SIDE
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.GREEN])
	var count := SIDE * SIDE
	source.heights.resize(count)
	source.heights.fill(8)
	source.top_materials.resize(count)
	source.top_materials.fill(2)
	source.base_materials.resize(count)
	source.base_materials.fill(1)
	source.cap_depths.resize(count)
	source.cap_depths.fill(3)
	source.water_levels.resize(count)
	source.water_materials.resize(count)
	var owner := Node3D.new()
	var undo := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"target": weakref(owner), "resource": source}, undo, owner)
	if not brush.begin("raise", 8.0, 36, 2, 0, 16, 0, 371, 0, -99999, "coarse", "square", 4):
		_fail("brush did not begin")
		return
	var shuffled := OS.get_cmdline_user_args().has("shuffled")
	var striped := OS.get_cmdline_user_args().has("striped")
	var changed_count := 65536 if striped else CHANGED
	brush._indices.resize(changed_count)
	var edited := source.heights
	for i in changed_count:
		var ordered_index := (i * 65537) % changed_count if shuffled else i
		var index := (ordered_index / 8) * 16 + ordered_index % 8 if striped else ordered_index
		brush._indices[i] = index
		edited[index] = 12
	source.heights = edited
	var sink := StageSink.new()
	brush.diagnostic_sink = sink
	var started := Time.get_ticks_usec()
	brush.end()
	var total_usec := Time.get_ticks_usec() - started
	brush.diagnostic_sink = null
	if not sink.stages.has("undo_snapshot"):
		_fail("snapshot timing was not recorded")
		return
	undo.undo()
	var last_changed := (changed_count / 8 - 1) * 16 + 7 if striped else changed_count - 1
	var first_unchanged := 8 if striped else changed_count
	if source.heights[0] != 8 or source.heights[last_changed] != 8 or source.heights[first_unchanged] != 8:
		_fail("undo did not restore the edited range")
		return
	undo.redo()
	if source.heights[0] != 12 or source.heights[last_changed] != 12 or source.heights[first_unchanged] != 8:
		_fail("redo did not restore the edited range")
		return
	print("COMPACT_UNDO_SNAPSHOT changed=", changed_count, " shuffled=", shuffled, " striped=", striped,
		" snapshot_ms=", snappedf(float(sink.stages.undo_snapshot) / 1000.0, 0.1),
		" total_ms=", snappedf(float(total_usec) / 1000.0, 0.1),
		" undo_redo=ok")
	undo.clear_history()
	undo.free()
	owner.free()
	quit()


func _fail(message: String) -> void:
	push_error("COMPACT_UNDO_SNAPSHOT " + message)
	quit(1)
