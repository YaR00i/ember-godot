extends SceneTree

const Generation = preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd")
const Planner = preload("res://addons/ember_import/ember_terrain_plan_dialog.gd")
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
var previews := 0
var changes := 0
var applies := 0
var cancels := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var dock := VBoxContainer.new()
	dock.size = Vector2(302, 600)
	var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme
	root.add_child(dock)
	var planner := Planner.new(); dock.add_child(planner)
	var generator := Generation.new(); dock.add_child(generator); generator.hide()
	assert(planner.get_class() == "VBoxContainer" and generator.get_class() == "VBoxContainer")
	var plan := Plan.new()
	plan.regions = [{"id": "first", "name": "Остров", "bounds": Rect2i(0, 0, 24, 24), "parameters": Generation.Math.DEFAULTS.duplicate(true)}]
	planner.show_plan(plan, "first")
	assert(planner.selected_id() == "first")
	assert(not planner._buttons.generate.disabled)
	for i in 5: await process_frame
	assert(planner.get_combined_minimum_size().x <= 302, "narrow planner overflow")
	planner.hide()
	generator.preview_requested.connect(func(_parameters): previews += 1)
	generator.settings_changed.connect(func(): changes += 1)
	generator.apply_requested.connect(func(): applies += 1)
	generator.cancel_requested.connect(func(): cancels += 1)
	generator.open_plan(plan.regions[0].bounds, plan.regions[0].parameters)
	assert(generator._plan_save_button.visible and generator.get_apply_button().disabled)
	for i in 5: await process_frame
	assert(generator.get_combined_minimum_size().x <= 302, "narrow dock overflow")
	assert(generator.get_global_rect().encloses(generator.get_apply_button().get_global_rect()), "footer outside dock")
	generator._preview_button.pressed.emit()
	assert(previews == 1 and generator.get_apply_button().disabled)
	generator.set_ready("Ready")
	generator.get_apply_button().pressed.emit()
	assert(applies == 1 and generator.visible, "owner must close only after successful commit")
	generator._fields.seed.value = 34
	assert(changes > 0 and generator.get_apply_button().disabled)
	generator.cancel_requested.emit(); assert(cancels == 1)
	generator.open_plateau(Rect2i(2, 3, 12, 16), {"height_m": 5.0, "transition_m": 3.0})
	assert(generator.parameters() == {"height_m": 5.0, "transition_m": 3.0})
	assert(not generator._terrain_grid.visible and generator._plateau_grid.visible)
	generator.open_for(Rect2i(24, 0, 48, 48), 4)
	assert(not generator._plateau_grid.visible and not generator._plan_save_button.visible and generator._back_button.visible)
	generator._scroll.scroll_vertical = 10000
	for i in 5: await process_frame
	assert(generator.get_global_rect().encloses(generator.get_apply_button().get_global_rect()))
	dock.free()
	print("TERRAIN_DOCK_PANELS PASS narrow-layout/routes/ready-invalidation/recipe-modes/pinned-footer")
	quit()
