extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var base:=Fixture.base();var detail:=Fixture.detailed(base)
	if not base.validation_errors().is_empty() or not detail.validation_errors().is_empty():printerr("Invalid fixture");quit(1);return
	for pair in [[base,"base"],[detail,"detail"]]:
		if ResourceSaver.save(pair[0],"res://content/world_terrains/smooth_tools_"+pair[1]+".res")!=OK:quit(1);return
	print("SMOOTH_TOOLS_BUILD PASS old sculpt/paint + material-aware brush");quit()
