extends SceneTree
## Exploration party projection: one leader/controller, three visible companions,
## a safe trail mode and a bounded lively formation mode.

const Followers := preload("res://scripts/ember_party_followers.gd")
const SANDBOX_SCENE := preload("res://scenes/agent_sandbox.tscn")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var errors: Array[String] = []
	var toggle_micros := 0
	var leader_switch_micros := 0
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress != null:
		progress.persistence_enabled = false
		progress.restore_enabled = false
		progress.reset_new_game()
	var sandbox := SANDBOX_SCENE.instantiate()
	root.add_child(sandbox)
	await process_frame
	await physics_frame
	var player := sandbox.get_node_or_null("Player") as EmberPlayer
	var followers := sandbox.get_node_or_null("PartyFollowers")
	var toggle := sandbox.find_child("PartyFollowModeButton", true, false) as Button
	if player == null or followers == null or toggle == null:
		errors.append("exploration scene lost leader/followers/toggle wiring")
	else:
		var initial: Dictionary = followers.view_state()
		if int(initial.get("count", 0)) != 3:
			errors.append("persistent four-person party did not project three companions")
		if str(initial.get("activeHeroId", "")) != "protagonist":
			errors.append("new exploration did not start with the protagonist as leader")
		for hero_id in ["mira", "orik", "sena"]:
			var follower := followers.get_node_or_null("PartyFollower_%s" % hero_id)
			var label := follower.get_node_or_null("Status") as Label3D if follower != null else null
			if follower == null or label == null or not label.text.contains("HP"):
				errors.append("%s has no visible exploration body/status" % hero_id)
		var formation_targets := [followers.target_for(0), followers.target_for(1), followers.target_for(2)]
		if formation_targets[0].distance_to(formation_targets[1]) < player.tile_size * 0.5:
			errors.append("formation did not spread companions around the leader trail")
		var progress_signal_count := 0
		var count_progress_signal := func() -> void: progress_signal_count += 1
		progress.progress_changed.connect(count_progress_signal)
		var toggle_started := Time.get_ticks_usec()
		for probe in 40:
			followers.toggle_mode()
		toggle_micros = Time.get_ticks_usec() - toggle_started
		progress.progress_changed.disconnect(count_progress_signal)
		if progress_signal_count != 0:
			errors.append("formation toggle still fans out through gameplay progress listeners")
		if toggle_micros > 100000:
			errors.append("40 presentation-only formation toggles took %d us" % toggle_micros)
		var leader_started := Time.get_ticks_usec()
		for probe in 40:
			progress.next_exploration_leader()
		leader_switch_micros = Time.get_ticks_usec() - leader_started
		if leader_switch_micros > 100000:
			errors.append("40 live leader switches took %d us" % leader_switch_micros)
		var tab_event := InputEventKey.new()
		tab_event.physical_keycode = KEY_TAB
		tab_event.pressed = true
		# This scene is mounted as a fixture rather than SceneTree.current_scene,
		# so route the same event through its world-level input owner explicitly.
		sandbox.call("_input", tab_event)
		await process_frame
		var protagonist_follower := followers.get_node_or_null("PartyFollower_protagonist") as Node3D
		var mira_follower := followers.get_node_or_null("PartyFollower_mira") as Node3D
		if player.controlled_hero_id != "mira" or progress.exploration_leader_id != "mira":
			errors.append("Tab did not switch the live exploration leader to Mira")
		elif protagonist_follower == null or not protagonist_follower.visible or mira_follower == null or mira_follower.visible:
			errors.append("Tab did not exchange the leader and follower models")
		elif not str(player.call("_health_text")).begins_with("Мира"):
			errors.append("live HUD did not change to the newly controlled hero")
		var protagonist_hp := int(progress.party_member_view("protagonist").get("hp", 0))
		var mira_hp := int(progress.party_member_view("mira").get("hp", 0))
		player.apply_damage(2.0)
		if (
			int(progress.party_member_view("mira").get("hp", 0)) != mira_hp - 2
			or int(progress.party_member_view("protagonist").get("hp", 0)) != protagonist_hp
		):
			errors.append("exploration damage did not follow the currently controlled hero")
		followers.set_mode(Followers.MODE_TRAIN)
		for step in 104:
			player.global_position.z -= 0.5
			await physics_frame
		var train_targets := [followers.target_for(0), followers.target_for(1), followers.target_for(2)]
		var leader_xz := Vector2(player.global_position.x, player.global_position.z)
		var d0 := leader_xz.distance_to(Vector2(train_targets[0].x, train_targets[0].z))
		var d1 := leader_xz.distance_to(Vector2(train_targets[1].x, train_targets[1].z))
		var d2 := leader_xz.distance_to(Vector2(train_targets[2].x, train_targets[2].z))
		if not (d0 < d1 and d1 < d2):
			errors.append("train mode does not preserve ordered spacing on the leader trail (%.2f/%.2f/%.2f)" % [d0, d1, d2])
		if not toggle.text.contains("Паровозик"):
			errors.append("mode toggle does not visibly name the active train mode")
		followers.toggle_mode()
		if str(followers.view_state().get("mode", "")) != Followers.MODE_FORMATION:
			errors.append("party mode toggle did not return to formation")
		if player.party_followers != followers:
			errors.append("existing player does not route the party mode shortcut")
		var old_position := player.global_position
		progress.set_active_hero_ids(["mira"], false)
		if int(followers.view_state().get("count", -1)) != 0 or player.controlled_hero_id != "mira":
			errors.append("solo Mira retained phantom followers or wrong leader")
		progress.set_active_hero_ids(["mira", "orik"], false)
		if int(followers.view_state().get("count", -1)) != 1:
			errors.append("same-leader membership change failed to rebuild followers")
		if "--capture-active" in OS.get_cmdline_user_args():
			await _capture_active("world")
			var inventory_ui := sandbox.get_node("CanvasLayer/InventoryUI") as EmberInventoryUi
			inventory_ui.open()
			await _capture_active("inventory")
			inventory_ui.close()
		progress.next_exploration_leader()
		progress.set_active_hero_ids(["mira"], false)
		if player.controlled_hero_id != "mira" or progress.next_exploration_leader() != "mira" or player.global_position != old_position:
			errors.append("removed leader/solo Tab moved player or selected absent hero")
	sandbox.free()
	if not errors.is_empty():
		printerr("FAIL party followers")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS party followers")
	print("  Tab swaps the live leader model/HUD while one CharacterBody remains")
	print("  40 presentation-only mode toggles: %d us" % toggle_micros)
	print("  40 live leader switches: %d us" % leader_switch_micros)
	print("  formation lives around the safe trail; train replays ordered positions")
	quit(0)


func _capture_active(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "user://ember-tests/active-party-capture-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join("pair-%s.png" % label)
	var error := root.get_texture().get_image().save_png(path)
	print("CAPTURE active party: ", ProjectSettings.globalize_path(path), " error=", error)
