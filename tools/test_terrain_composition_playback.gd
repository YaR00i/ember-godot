extends "res://tools/test_compact_terrain_generation_playback.gd"
## A wall-clock gate, not a frame count: cold loading can render many cheap frames.
func _ready() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	var scene := get_parent()
	var deadline := Time.get_ticks_msec() + 75000
	while not scene.get("_startup_complete") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not scene.get("_startup_complete"):
		var result := {"ok": false, "reason": "startup barrier timed out", "status": scene._startup_status()}
		var file := FileAccess.open("res://qa_generation/play_result.json", FileAccess.WRITE); file.store_string(JSON.stringify(result)); file.close()
		print("COMPOSITION_PLAYBACK ", result)
		return
	await super._ready()
