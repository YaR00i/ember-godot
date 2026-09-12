@tool
extends RefCounted
## Shared editor-only publication queue. Keep file writes synchronous; postpone
## only discovery, coalesce adjacent saves, and never scan during import/scan.

const QUIET_SECONDS := 0.15
static var _pending: Dictionary = {}
static var _holds: Dictionary = {}
static var _stats := {"scans": 0, "source_scans": 0, "merged": 0, "busy_waits": 0}


static func request(filesystem: Object = null, sources_only := false) -> void:
	if filesystem == null:
		if not Engine.is_editor_hint():
			return
		filesystem = EditorInterface.get_resource_filesystem()
	if not is_instance_valid(filesystem):
		return
	var id := filesystem.get_instance_id()
	var deadline := Time.get_ticks_msec() + int(QUIET_SECONDS * 1000)
	if _pending.has(id):
		_pending[id].sources_only = bool(_pending[id].sources_only) and sources_only
		_pending[id].deadline = deadline
		_stats.merged += 1
		return
	_pending[id] = {"filesystem": weakref(filesystem), "sources_only": sources_only, "deadline": deadline}
	_schedule(id, QUIET_SECONDS)


static func diagnostics() -> Dictionary:
	var result := _stats.duplicate()
	result["pending"] = _pending.size()
	return result


static func defer_scans(filesystem: Object = null) -> RefCounted:
	# Weak lease: normal return/cancellation/plugin destruction cannot leave a
	# permanent suspension behind. Requests remain pending and coalesced.
	var lease := RefCounted.new()
	if filesystem == null and Engine.is_editor_hint(): filesystem = EditorInterface.get_resource_filesystem()
	if not is_instance_valid(filesystem): return lease
	var id := filesystem.get_instance_id()
	if not _holds.has(id): _holds[id] = []
	_holds[id].append(weakref(lease))
	return lease


static func _scans_deferred(id: int) -> bool:
	if not _holds.has(id): return false
	var alive: Array = []
	for reference in _holds[id]:
		if reference.get_ref() != null: alive.append(reference)
	if alive.is_empty():
		_holds.erase(id)
		return false
	_holds[id] = alive
	return true


static func _schedule(id: int, seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_pending.erase(id)
		return
	_pending[id]["next_check"] = Time.get_ticks_msec() + int(seconds * 1000)
	# Editor SceneTree timers need not advance like runtime timers. Use the
	# editor's frame signal and wall-clock deadlines instead.
	if not tree.process_frame.is_connected(_on_frame):
		tree.process_frame.connect(_on_frame)


static func _on_frame() -> void:
	for id in _pending.keys():
		_flush(int(id))
	if _pending.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.process_frame.is_connected(_on_frame):
			tree.process_frame.disconnect(_on_frame)


static func _flush(id: int) -> void:
	if not _pending.has(id):
		return
	var entry: Dictionary = _pending[id]
	var filesystem: Object = entry.filesystem.get_ref()
	if not is_instance_valid(filesystem):
		_pending.erase(id)
		return
	var remaining := maxi(int(entry.deadline), int(entry.next_check)) - Time.get_ticks_msec()
	if remaining > 0:
		return
	if _scans_deferred(id):
		_pending[id].next_check = Time.get_ticks_msec() + 100
		return
	if filesystem.is_scanning() or filesystem.is_importing():
		_stats.busy_waits += 1
		_pending[id].next_check = Time.get_ticks_msec() + 100
		return
	# Erase first: requests raised synchronously by scan signals form a new batch.
	_pending.erase(id)
	if bool(entry.sources_only):
		_stats.source_scans += 1
		filesystem.scan_sources()
	else:
		_stats.scans += 1
		filesystem.scan()
