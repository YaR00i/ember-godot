extends SceneTree
## HUD queries must preserve live legacy HP, normalization and item recovery.
const Fixture = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
var errors: Array[String] = []

func _init() -> void:
	Fixture.prepare(self, "user://ember-tests/member-view-%d" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label)

func run() -> void:
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	var leader := EmberPartyState.LEADER_ID
	for hp_value in [-20.0, 5.4, 99999.0]:
		state.hp = hp_value
		var view := state.party_member_view(leader)
		check(view.hp == clampi(roundi(hp_value), 0, view.maxHp), "legacy HP is clamped and immediately visible")
		check(state.hp == view.hp and state.max_hp == view.maxHp, "compatibility HP remains synchronized")
	state.party.mira.level = 4
	state.party.mira.hp = 99999
	state.party.mira.mp = -10
	var view := state.party_member_view("mira")
	check(view.level == 4 and view.hp == view.maxHp and view.mp == 0, "direct member edits are normalized before display")
	check(view == EmberPartyState.member_view(state.party, "mira", state._items()), "view includes the canonical derived statistics")
	view.equipment.weapon = "view-only-edit"
	check(state.party.mira.equipment.weapon != "view-only-edit", "returned view does not alias persistent equipment")
	state.equipment["retired_slot"] = "recovered_fixture_item"
	var before := int(state.inventory.get("recovered_fixture_item", 0))
	for i in 5: state.party_member_view(leader)
	check(int(state.inventory.get("recovered_fixture_item", 0)) == before + 1, "repeated HUD reads recover retired equipment exactly once")
	state.hp = -1
	check(state.party_member_view("unknown").is_empty() and state.hp == 0, "unknown hero remains empty after compatibility sync")
	state.free()
	print("PARTY_MEMBER_VIEW ", JSON.stringify({"pass": errors.is_empty(), "errors": errors}))
	quit(0 if errors.is_empty() else 1)
