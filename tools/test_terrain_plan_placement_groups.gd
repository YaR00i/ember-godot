extends "res://tools/test_terrain_plan_placement.gd"
var _groups_checked := false

func prepare(source: Resource, input: Resource, budget := 4000) -> RefCounted:
	var legacy := super.prepare(source,input,budget)
	if _groups_checked: return legacy
	_groups_checked = true
	var grouped: Resource = input.working_copy()
	var values: Dictionary = grouped.regions[0].parameters
	values.pattern = "groups"; values.cluster_strength = 1.0; values.cluster_size_m = 12.0; values.density = 0.65
	var first := super.prepare(source,grouped,4000)
	var repeat := super.prepare(source,grouped,800)
	check(not first.placements.is_empty() and first.placements == repeat.placements,"group planner empty or budget-dependent")
	var plain: Resource = grouped.working_copy(); plain.regions[0].parameters.erase("pattern")
	var ungrouped := super.prepare(source,plain,4000)
	check(first.placements != ungrouped.placements,"groups did not change real planner output")
	var zero: Resource = grouped.working_copy(); zero.regions[0].parameters.cluster_strength = 0.0
	check(super.prepare(source,zero,4000).placements == ungrouped.placements,"zero grouping changed legacy planner output")
	check(Plan.from_data(grouped.data()).data() == grouped.data(),"group recipe roundtrip")
	var delta: Dictionary = first.finalize(_map.get_node("Props"))
	check(not delta.is_empty(),first.error)
	if not delta.is_empty():
		Grove.apply_delta(delta,true)
		check(_map.get_node("Props").get_child_count() == first.placements.size(),"group Apply differs from preview")
		for member in delta.plan.object_layers.grove:
			var prop := _map.get_node("Props").get_node(NodePath(member.id)) as EmberVoxelProp
			check(Grove.fingerprint(prop,_map,first._frame) == member.expected,"group Apply pose differs")
		Grove.apply_delta(delta,false)
		check(_map.get_node("Props").get_child_count() == 0,"group delta undo lost baseline")
		for prop in delta.added:
			if is_instance_valid(prop) and prop.get_parent() == null: prop.free()
	print("PLACEMENT_GROUP_PLANNER ","PASS" if errors.is_empty() else "FAIL"," count=",first.placements.size()," errors=",errors)
	return legacy

func _run() -> void:
	var values := Plan.Influence.PLACEMENT_DEFAULTS.duplicate(true)
	values.model_ids = PackedStringArray(["tree_a","tree_b"])
	var old_values := values.duplicate(true)
	values.pattern = "groups"; values.cluster_strength = 1.0; values.cluster_size_m = 24.0
	var noise := Plan.Influence.placement_group_noise(values)
	var changed := 0; var common := 0
	var bounds := Rect2i(0,0,64,64)
	for y in 11:
		for x in 11:
			var cell := Vector2i(x,y)
			var plain := Plan.Influence.grove_candidate(bounds,old_values,cell)
			var grouped := Plan.Influence.grove_candidate(bounds,values,cell,noise)
			check(grouped == Plan.Influence.grove_candidate(bounds,values,cell,noise),"group candidate unstable")
			if grouped != plain: changed += 1
			if not plain.is_empty() and not grouped.is_empty(): common += 1; check(plain == grouped,"group altered candidate pose/model")
			check(Plan.Influence.grove_candidate(bounds,values,cell) == plain,"group fields leaked into legacy grove")
	check(changed > 0 and common > 0,"group field has no effect")
	for density in [0.0,1.0]:
		values.density = density
		for y in 11:
			for x in 11:
				check(Plan.Influence.grove_candidate(bounds,values,Vector2i(x,y),noise) == Plan.Influence.grove_candidate(bounds,values,Vector2i(x,y)),"density endpoint changed")
	values.density = 0.6; values.cluster_strength = 0.0
	check(Plan.Influence.placement_group_noise(values) == null,"zero strength creates sampler")
	values.cluster_strength = 1.0; values.seed = 2147483646
	check(Plan.Influence.placement_group_noise(values) != null,"maximum seed rejected")
	for spec in [["pattern","bad"],["cluster_strength",NAN],["cluster_strength",1.1],["cluster_size_m",INF],["cluster_size_m",7.0]]:
		var invalid := values.duplicate(true); invalid[spec[0]] = spec[1]
		check(not Plan.Influence.parameter_error(invalid,"placement").is_empty(),"invalid group field accepted: "+str(spec[0]))
	var panel := LakePanel.new(); root.add_child(panel)
	values.seed = 7; values.cluster_size_m = 24.0
	var choices: Array[Dictionary] = [{"id":"tree_a","title":"Дерево A"},{"id":"tree_b","title":"Дерево B"}]
	panel.open_placement(bounds,values,choices)
	check(panel.parameters().pattern == "groups" and panel.parameters().cluster_strength == 1.0 and panel.parameters().cluster_size_m == 24.0,"group UI roundtrip")
	panel.size = Vector2(302,560); await process_frame
	check(panel.get_combined_minimum_size().x <= 302,"group controls overflow dock")
	panel.set_ready("Готово"); panel._cluster_fields.cluster_size_m.value = 25.0
	check(panel.get_apply_button().disabled,"group scale left stale Apply enabled")
	panel.set_ready("Готово"); panel._cluster_fields.cluster_strength.value = 50.0
	check(panel.get_apply_button().disabled,"group strength left stale Apply enabled")
	panel.set_ready("Готово"); panel._placement_pattern.select(0); panel._placement_pattern.item_selected.emit(0)
	check(panel.get_apply_button().disabled and not panel.parameters().has("pattern") and not panel._cluster_controls.visible,"uniform switch not compatible/stale")
	panel.open_grove(bounds,old_values,choices)
	check(not panel._cluster_grid.visible and not panel.parameters().has("pattern"),"group controls leaked into legacy grove")
	panel.open_placement(bounds,old_values,choices)
	check(panel._placement_pattern.selected == 0 and not panel._cluster_controls.visible and panel.parameters() == old_values,"old placement UI changed recipe")
	panel.free()
	print("PLACEMENT_GROUP_MATH_UI ","PASS" if errors.is_empty() else "FAIL"," changed=",changed," common=",common," errors=",errors)
	await super._run()
