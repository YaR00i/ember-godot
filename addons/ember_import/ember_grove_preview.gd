@tool
extends Node3D
signal preview_built
var _job: RefCounted
var _cursor := 0
var _hidden: Array[Dictionary] = []

func show_job(job: RefCounted) -> void:
	_job = job
	for prop: Node3D in job.removals:
		_hidden.append({"node":weakref(prop),"visible":prop.visible}); prop.hide()
	set_process(true)

func _process(_delta: float) -> void:
	if _job == null: return
	var started := Time.get_ticks_usec()
	while _cursor < _job.placements.size() and Time.get_ticks_usec()-started < 4000:
		var prop: EmberVoxelProp = _job.make_prop(_job.placements[_cursor],self)
		_cursor += 1
		if prop == null: continue
		add_child(prop)
		for child in prop.find_children("*","CollisionShape3D",true,false): (child as CollisionShape3D).disabled = true
	if _cursor == _job.placements.size(): set_process(false); preview_built.emit()

func clear_preview() -> void:
	set_process(false)
	for item in _hidden:
		var prop: Node3D = item.node.get_ref()
		if is_instance_valid(prop): prop.visible = item.visible
	_hidden.clear(); _job = null

func _exit_tree() -> void: clear_preview()
