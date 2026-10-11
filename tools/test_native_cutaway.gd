extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_map_startup_test_fixture.gd")
var _state: Dictionary

func _init() -> void:
	_state = Fixture.prepare(self)
	if _state.refused:
		quit.call_deferred(2)
		return
	_run.call_deferred()

func _run() -> void:
	var errors: Array[String] = []
	var saved := Fixture.saved_scene(_state, true)
	if saved.is_empty():
		printerr("FAIL native cutaway fixture")
		quit(1)
		return
	for absent in [false, true]:
		if absent: ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(str(_state.directory).path_join("absent-pack")))
		var scene := (saved.scene as PackedScene).instantiate()
		root.add_child(scene)
		await process_frame
		var map := scene.get_node("Map") as EmberMapLoader
		var group := map.get_node_or_null("Cutaways")
		if group == null or map.cutaway_section_count() != 2:
			errors.append("startup removed saved native roofs or missed nested volume")
			scene.free()
			continue
		var volumes := map._cutaway_volumes()
		map.refresh_cutaway_runtime()
		map.refresh_cutaway_runtime()
		if map.get_node("Cutaways") != group or map.cutaway_section_count() != 2: errors.append("repeat refresh replaced authored cutaways")
		for volume in volumes:
			if volume.roof() == null or volume.roof().transparency != 0.0 or volume.is_processing(): errors.append("saved roof did not reopen opaque/event driven")
			if volume.reveal_changed.get_connections().size() != 1: errors.append("repeat refresh duplicated reveal binding")
		map.set_cutaway_preview(true, true)
		if map.cutaway_active_count() != 2: errors.append("native preview lost nested sections")
		for volume in volumes:
			if volume.roof().transparency != 1.0 or volume.roof().cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON: errors.append("reveal changed structural roof shadow")
		map.set_cutaway_preview(false, true)
		var player := scene.get("_player") as EmberPlayer
		volumes[0].body_entered.emit(player)
		if map.cutaway_active_count() != 1 or not volumes[0].is_revealed(): errors.append("player entry did not reveal native roof")
		await create_timer(0.25).timeout
		if not is_equal_approx(volumes[0].roof().transparency, 1.0): errors.append("native roof fade did not finish")
		volumes[0].body_exited.emit(player)
		await create_timer(0.25).timeout
		if map.cutaway_active_count() != 0 or not is_zero_approx(volumes[0].roof().transparency): errors.append("player exit did not restore roof")
		scene.free()
	Fixture.verify(_state, saved, errors)
	if not errors.is_empty():
		printerr("FAIL native cutaway: ", "; ".join(errors))
		quit(1)
		return
	print("PASS native cutaway; saved nested roofs, reveal/fade/shadows/reopen without sandbox/JSON")
	quit(0)
