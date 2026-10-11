extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_vn_test_fixture.gd")

func _init() -> void:
	var state := Fixture.prepare(self)
	if state.refused:
		quit.call_deferred(2)
		return
	_run.call_deferred(state)

func _run(state: Dictionary) -> void:
	quit(Fixture.run_library(state, false))
