@tool
extends RefCounted
## Opt-in, editor-only edit-cost trace. No printing or file IO during a gesture.
## Timed scopes are exclusive: a parent never counts its children's time twice.

var operation := "outside"
var stages: Dictionary = {}
var operations: Dictionary = {}
var chunks: Array[Dictionary] = []
var queue_requests: Dictionary = {}
var _stack: Array[Dictionary] = []
var _operation_start_usec := 0


func begin_operation(label: String) -> void:
	assert(_stack.is_empty())
	assert(_operation_start_usec == 0)
	operation = label
	_operation_start_usec = Time.get_ticks_usec()


func end_operation() -> void:
	assert(_stack.is_empty())
	if _operation_start_usec == 0:
		return
	var elapsed := Time.get_ticks_usec() - _operation_start_usec
	var item: Dictionary = operations.get(operation, {"wall_usec": 0, "count": 0})
	item.wall_usec = int(item.wall_usec) + elapsed
	item.count = int(item.count) + 1
	operations[operation] = item
	_operation_start_usec = 0
	operation = "outside"


func begin(label: String) -> void:
	_stack.append({"label": label, "start": Time.get_ticks_usec(), "child_usec": 0})


func end() -> void:
	assert(not _stack.is_empty())
	var elapsed := Time.get_ticks_usec() - int(_stack.back().start)
	var item := _stack.pop_back() as Dictionary
	var exclusive := maxi(0, elapsed - int(item.child_usec))
	var key := "%s/%s" % [operation, str(item.label)]
	var total: Dictionary = stages.get(key, {"exclusive_usec": 0, "inclusive_usec": 0, "count": 0})
	total.exclusive_usec = int(total.exclusive_usec) + exclusive
	total.inclusive_usec = int(total.inclusive_usec) + elapsed
	total.count = int(total.count) + 1
	stages[key] = total
	if not _stack.is_empty():
		_stack.back().child_usec = int(_stack.back().child_usec) + elapsed


func queued(chunk: Vector2i, draft: bool) -> void:
	var previous: Dictionary = queue_requests.get(chunk, {})
	queue_requests[chunk] = {
		"queued_usec": Time.get_ticks_usec(),
		"requested_op": operation,
		"draft": draft,
		"superseded": int(previous.get("superseded", -1)) + 1,
	}


func queue_cleared() -> void:
	queue_requests.clear()


func chunk_started(chunk: Vector2i) -> Dictionary:
	var request: Dictionary = queue_requests.get(chunk, {})
	queue_requests.erase(chunk)
	return {
		"wait_usec": Time.get_ticks_usec() - int(request.queued_usec)
			if request.has("queued_usec") else -1,
		"requested_op": str(request.get("requested_op", "direct")),
		"superseded": int(request.get("superseded", 0)),
	}


func chunk_finished(event: Dictionary) -> void:
	event["operation"] = operation
	chunks.append(event)


func snapshot() -> Dictionary:
	assert(_stack.is_empty())
	assert(_operation_start_usec == 0)
	var rebuilds := {}
	var hold_rebuilds := {}
	var gesture_rebuilds := {}
	for event in chunks:
		var key := "%d,%d" % [event.chunk_x, event.chunk_z]
		rebuilds[key] = int(rebuilds.get(key, 0)) + 1
		if event.operation == "paint_hold":
			hold_rebuilds[key] = int(hold_rebuilds.get(key, 0)) + 1
		if event.operation in ["paint_hold", "exact_settle"]:
			gesture_rebuilds[key] = int(gesture_rebuilds.get(key, 0)) + 1
	for event in chunks:
		var key := "%d,%d" % [event.chunk_x, event.chunk_z]
		event["rebuilds_this_trace"] = int(rebuilds[key])
		event["rebuilds_during_hold"] = int(hold_rebuilds.get(key, 0))
		event["rebuilds_during_gesture"] = int(gesture_rebuilds.get(key, 0))
	return {"operations": operations.duplicate(true), "stages": stages.duplicate(true), "chunks": chunks.duplicate(true)}
