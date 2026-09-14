extends SceneTree
## Readiness, error/timeout escape and exit cleanup without authored content.

const Preparation = preload("res://addons/ember_import/ember_editor_preparation.gd")
var errors := 0

class Filesystem extends RefCounted:
	var scanning := true
	var importing := false
	func is_scanning() -> bool: return scanning
	func is_importing() -> bool: return importing

class Shelf extends Node:
	var defer_initial_refresh := true
	var prepared := 0
	var cancelled := 0
	var pending := 2
	var failures := 0
	func prepare_for_startup() -> void:
		prepared += 1
		defer_initial_refresh = false
	func preparation_pending_count() -> int: return pending
	func preparation_failure_count() -> int: return failures
	func preparation_loading_fraction() -> float: return 0.0
	func cancel_preparation() -> void:
		cancelled += 1
		pending = 0


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)


func wait_until(predicate: Callable, label: String) -> void:
	var deadline := Time.get_ticks_msec() + 2500
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(predicate.call(), label)


func _run() -> void:
	var filesystem := Filesystem.new()
	var shelf := Shelf.new()
	root.add_child(shelf)
	var gate = Preparation.new()
	root.add_child(gate)
	var results: Array = []
	gate.finished.connect(func(ok: bool, _ms: int, failures: int): results.append([ok, failures]))
	gate.begin(shelf, filesystem)
	await create_timer(0.65).timeout
	gate.close_requested.emit()
	check(shelf.prepared == 0 and results.is_empty(), "scan and loading-window close never expose unfinished preparation")
	filesystem.scanning = false
	filesystem.importing = true
	await create_timer(0.15).timeout
	check(shelf.prepared == 0, "catalog waits for importing as well as scanning")
	filesystem.importing = false
	await wait_until(func(): return shelf.prepared == 1, "catalog begins once filesystem is settled")
	await create_timer(0.15).timeout
	check(results.is_empty() and shelf.prepared == 1, "pending previews keep the gate closed without duplicate catalog preparation")
	shelf.pending = 0
	await wait_until(func(): return not results.is_empty(), "ready previews release the gate")
	check(results == [[true, 0]] and shelf.cancelled == 0, "successful preparation preserves prepared thumbnails")
	await process_frame
	check(is_instance_valid(gate) and not gate.visible and not gate.is_processing(), "completed window stays alive and inactive until plugin cleanup")
	check(not gate.exclusive and not gate.transient and gate._shelf == null and gate._filesystem == null, "completed window releases modal state and preparation references")
	gate._continue_without_previews()
	check(results == [[true, 0]] and shelf.cancelled == 0, "completed controller cannot cancel prepared thumbnails or emit another result")

	var failed_shelf := Shelf.new()
	failed_shelf.pending = 0
	failed_shelf.failures = 1
	root.add_child(failed_shelf)
	var failed_gate = Preparation.new()
	root.add_child(failed_gate)
	var failed_results: Array = []
	failed_gate.finished.connect(func(ok: bool, _ms: int, count: int): failed_results.append([ok, count]))
	failed_gate.begin(failed_shelf, filesystem)
	await wait_until(func(): return failed_gate._waiting_for_choice, "failed preview offers an explicit way to continue")
	check(failed_results.is_empty() and failed_gate._continue.visible, "failure never reports success or traps the user")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(failed_gate._continue.get_global_rect().end.y <= failed_gate.size.y, "continuation button fits native loading window")
		check(failed_gate.size.y <= 360, "error window stays compact instead of expanding to the root viewport")
		failed_gate.get_texture().get_image().save_png("user://editor_preparation_failure.png")
	failed_gate._continue.pressed.emit()
	check(failed_results == [[false, 1]] and failed_shelf.cancelled == 1, "continuing after failure cancels unfinished work")

	var timeout_shelf := Shelf.new()
	root.add_child(timeout_shelf)
	var timeout_gate = Preparation.new()
	root.add_child(timeout_gate)
	timeout_gate.begin(timeout_shelf, filesystem)
	timeout_gate._started = Time.get_ticks_msec() - Preparation.TIMEOUT_MSEC - 1
	await wait_until(func(): return timeout_gate._waiting_for_choice, "startup timeout offers continuation")
	check(timeout_shelf.prepared == 0, "timeout can happen safely before catalog preparation")
	timeout_gate._continue.pressed.emit()
	check(not timeout_shelf.defer_initial_refresh and timeout_shelf.cancelled == 1, "timeout leaves shelf usable on normal opening")

	var exit_shelf := Shelf.new()
	root.add_child(exit_shelf)
	var exit_gate = Preparation.new()
	root.add_child(exit_gate)
	exit_gate.begin(exit_shelf, filesystem)
	exit_gate.free()
	check(exit_shelf.cancelled == 1, "plugin/window exit cancels preparation")
	for completed_gate in [gate, failed_gate, timeout_gate]: completed_gate.free()
	for item in [shelf, failed_shelf, timeout_shelf, exit_shelf]: item.free()
	await process_frame
	print("test_voxel_editor_preparation: %s · %d" % ["PASS" if errors == 0 else "FAIL", errors])
	quit(errors)
