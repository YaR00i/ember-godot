extends SceneTree

const Queue := preload("res://addons/ember_import/ember_editor_filesystem.gd")

class FakeFilesystem extends RefCounted:
	var scanning := false
	var importing := false
	var scans := 0
	var source_scans := 0
	var request_during_scan := false
	func is_scanning() -> bool:
		return scanning
	func is_importing() -> bool:
		return importing
	func scan() -> void:
		scans += 1
		if request_during_scan:
			request_during_scan = false
			Queue.request(self)
	func scan_sources() -> void:
		source_scans += 1

var errors: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 450
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _run() -> void:
	var fs := FakeFilesystem.new()
	Queue.request() # Runtime has no default EditorInterface side effect.
	check(Queue.diagnostics().pending == 0, "runtime request queued an editor scan")
	for index in 8:
		Queue.request(fs)
	check(fs.scans == 0, "request scanned synchronously")
	await settle()
	check(fs.scans == 1, "adjacent requests were not coalesced")
	fs.importing = true
	Queue.request(fs)
	await settle()
	check(fs.scans == 1, "scan ran during import")
	fs.importing = false
	fs.scanning = true
	await settle()
	check(fs.scans == 1, "scan ran during another scan")
	Queue.request(fs)
	fs.scanning = false
	await settle()
	check(fs.scans == 2, "busy requests were lost or duplicated")
	Queue.request(fs, true)
	Queue.request(fs, true)
	await settle()
	check(fs.source_scans == 1, "source-only request changed semantics")
	Queue.request(fs, true)
	Queue.request(fs)
	await settle()
	check(fs.scans == 3 and fs.source_scans == 1, "full request did not supersede source scan")
	fs.request_during_scan = true
	Queue.request(fs)
	await settle()
	check(fs.scans == 5, "request raised by a scan callback was lost")
	var hold := Queue.defer_scans(fs)
	var nested := Queue.defer_scans(fs)
	for index in 5: Queue.request(fs)
	await settle()
	check(fs.scans == 5, "scan started inside publication batch")
	hold = null
	await settle()
	check(fs.scans == 5, "nested scan hold was released early")
	nested = null
	await settle()
	check(fs.scans == 6, "pending batch scan lost after lease release")
	var released := FakeFilesystem.new()
	Queue.request(released)
	released = null
	await settle()
	check(Queue.diagnostics().pending == 0, "dead filesystem retained a pending request")
	for message in errors:
		push_error(message)
	print("test_editor_filesystem: ", "PASS" if errors.is_empty() else "FAIL", " ", Queue.diagnostics())
	quit(0 if errors.is_empty() else 1)
