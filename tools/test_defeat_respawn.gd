extends SceneTree
## Defeat locks explore input; respawn reuses player_start and existing save owner.

const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"
const ExploreState = preload("res://scripts/ember_explore_state.gd")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	_test_state_contract(errors)
	await _test_live_respawn(errors)
	if not errors.is_empty():
		printerr("FAIL defeat/respawn")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS defeat/respawn")
	print("  zero HP -> blocked player + defeat HUD")
	print("  R contract -> player_start + full HP through EmberExploreState")
	print("  inventory/equipment/flags survive through the party/save v2 owner")
	return 0


func _test_state_contract(errors: Array[String]) -> void:
	var state := ExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	state.inventory = {"coin": 23, "herb": 1}
	state.equipment = EmberEquipment.normalize({"body": "mourning_mail"})
	state.flags = {"quest_done": true}
	state.hp = 5.0
	var hit := state.apply_damage(20.0, false)
	if not bool(hit.get("dead", false)) or state.hp != 0.0:
		errors.append("lethal damage did not clamp HP to zero")
	var preserved := {
		"inventory": state.inventory.duplicate(true),
		"equipment": state.equipment.duplicate(true),
		"flags": state.flags.duplicate(true),
	}
	var revived := state.respawn(false)
	if not bool(revived.get("ok", false)) or state.hp != state.max_hp:
		errors.append("respawn did not restore full HP")
	if (
		state.inventory != preserved.inventory
		or state.equipment != preserved.equipment
		or state.flags != preserved.flags
	):
		errors.append("respawn mutated persistent gameplay progress")
	if bool(state.respawn(false).get("ok", true)):
		errors.append("living player was allowed to respawn again")
	state.free()


func _test_live_respawn(errors: Array[String]) -> void:
	var state := root.get_node_or_null("EmberExploreProgress") as ExploreState
	if state == null:
		errors.append("EmberExploreProgress autoload is missing")
		return
	state.persistence_enabled = false
	state.restore_enabled = false
	state.reset_new_game()
	if change_scene_to_file(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox")
		return
	await process_frame
	await process_frame
	# Keep the smoke independent from editor global-class registration order.
	# The packed scene still owns the concrete EmberPlayer implementation.
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	var map := current_scene.get_node_or_null("Map") as EmberMapLoader
	if player == null or map == null:
		errors.append("agent_sandbox lost Player or Map")
		return
	state.inventory = {"coin": 23, "herb": 1}
	state.flags = {"quest_done": true}
	state.hp = 10.0
	player.global_position += Vector3(48.0, 0.0, 32.0)
	var expected_spawn := map.spawn_world() + Vector3(0.0, 6.0, 0.0)
	var hit: Dictionary = player.call("apply_damage", 30.0)
	if not bool(hit.get("dead", false)) or not bool(player.call("is_defeated")):
		errors.append("live player did not enter defeat after lethal damage")
	if not str(player.call("_hud_text")).contains("ПОРАЖЕНИЕ"):
		errors.append("defeat HUD did not expose the R recovery action")
	if not bool(player.call("_ui_blocks_movement")):
		errors.append("defeat did not block explore input")
	player.call("request_respawn")
	await process_frame
	if bool(player.call("is_defeated")) or state.hp != state.max_hp:
		errors.append("live respawn did not restore player and HP")
	var spawn_delta := player.global_position - expected_spawn
	# The CharacterBody may consume one gravity physics tick before this
	# process-frame assertion, so keep the route check exact in X/Z and allow a
	# sub-pixel vertical settle instead of making the smoke timing-dependent.
	if (
		absf(spawn_delta.x) > 0.001
		or absf(spawn_delta.z) > 0.001
		or absf(spawn_delta.y) > 0.5
	):
		errors.append("live respawn did not return to player_start: got %s, expected %s" % [player.global_position, expected_spawn])
	if state.inventory != {"coin": 23, "herb": 1} or state.flags != {"quest_done": true}:
		errors.append("live respawn lost inventory or flags")
