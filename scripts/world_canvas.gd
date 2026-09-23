extends "res://scripts/fan_town.gd"
## Isolated, non-story authoring scene. Continue the existing play controller.
## No duplicate floor: wait for native Surface physics before spawning heroes.
const STORAGE_ROOT := "user://ember-world-canvas-v1"

func _ready() -> void:
	if Engine.is_editor_hint(): return
	_hud.text = "ХОЛСТ МИРА · подготовка земли…"
	var progress := _progress()
	if progress != null:
		var isolated_root := str(progress.get_meta("world_canvas_storage_root", STORAGE_ROOT))
		if progress.storage_root != isolated_root:
			progress.storage_root = isolated_root
			progress.legacy_storage_root = isolated_root.path_join("legacy-unused")
			progress.combat_party_locked = false
			progress.set_world_context(map_id, null, 16.0)
			progress.reset_new_game()
			progress.load_latest_available()
		progress.set_active_hero_ids(["protagonist", "mira"], false)
	var projection := _map._visual_surface_projection
	while is_instance_valid(projection) and projection.pending_physics_chunk_count() > 0:
		await get_tree().process_frame
	if not is_inside_tree(): return
	super._ready()

func _play_text() -> String:
	return "ХОЛСТ МИРА · берег и вода\nWASD — идти · Tab — герой · I — сумка · Esc — меню · RMB — камера"
