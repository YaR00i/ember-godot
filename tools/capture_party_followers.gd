extends SceneTree
## Reproducible Forward+ captures for the two exploration party modes.

const SANDBOX_SCENE := preload("res://scenes/agent_sandbox.tscn")
const FORMATION_OUTPUT := "user://party_followers_formation.png"
const MIRA_LEADER_OUTPUT := "user://party_followers_mira_leader.png"
const TRAIN_OUTPUT := "user://party_followers_train.png"


func _init() -> void:
	root.size = Vector2i(1600, 900)
	_capture_and_quit.call_deferred()


func _capture_and_quit() -> void:
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
	if player == null or followers == null:
		printerr("FAIL party followers capture: runtime wiring missing")
		quit(1)
		return
	for step in 80:
		player.global_position += Vector3(0.32, 0.0, -0.44)
		await physics_frame
	followers.set_mode("formation")
	for frame in 24:
		await process_frame
	var error := root.get_texture().get_image().save_png(FORMATION_OUTPUT)
	if error != OK:
		printerr("FAIL formation capture: ", error_string(error))
		quit(1)
		return
	progress.set_exploration_leader("mira")
	for frame in 12:
		await process_frame
	error = root.get_texture().get_image().save_png(MIRA_LEADER_OUTPUT)
	if error != OK:
		printerr("FAIL Mira leader capture: ", error_string(error))
		quit(1)
		return
	followers.set_mode("train")
	for step in 42:
		player.global_position += Vector3(-0.08, 0.0, -0.5)
		await physics_frame
	for frame in 12:
		await process_frame
	error = root.get_texture().get_image().save_png(TRAIN_OUTPUT)
	if error != OK:
		printerr("FAIL train capture: ", error_string(error))
		quit(1)
		return
	print("PASS Forward+ party formation capture: ", ProjectSettings.globalize_path(FORMATION_OUTPUT))
	print("PASS Forward+ live Mira leader capture: ", ProjectSettings.globalize_path(MIRA_LEADER_OUTPUT))
	print("PASS Forward+ party train capture: ", ProjectSettings.globalize_path(TRAIN_OUTPUT))
	sandbox.free()
	quit(0)
