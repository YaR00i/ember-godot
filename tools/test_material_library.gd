extends SceneTree
const Library = preload("res://scripts/ember_material_library.gd")
const STAND = preload("res://scenes/material_library_stand.tscn")
var errors := PackedStringArray()

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func _run() -> void:
	var ids := {}
	for preset in Library.PRESETS:
		check(not ids.has(preset.id),"duplicate preset id")
		ids[preset.id] = true
		var material := Library.create(preset.id)
		check(material != null,"missing preset "+preset.id)
		if material == null: continue
		check(material.resource_path.is_empty(),"instance retains publication path")
		check(material.shader != null,"missing shader")
		check(material.shader.code.contains("ember_material_surface"),"shared material response missing")
		for parameter in Library.PARAMETERS:
			var value = material.get_shader_parameter(parameter)
			check(Library.validate_options({parameter:value}).is_empty(),"bad preset parameter "+preset.id+"/"+parameter)
		var options := {"base_color":Color(0.2,0.4,0.7),"emission_color":Color(0.8,0.1,0.3),"emission_follow_base":false,"emission_energy":2.4,"surface_roughness":0.42,
			"highlight_color":Color(0.9,0.3,0.7),"highlight_color_strength":0.65,
			"iridescence_strength":0.6,"iridescence_frequency":3.0,
			"texture_kind":2,"texture_scale":2.0,"texture_strength":0.04,"texture_relief":0.008}
		var customized := Library.create(preset.id,options)
		var other := Library.create(preset.id)
		check(customized != other and customized != material,"shared material instance")
		for parameter in options:
			check(customized.get_shader_parameter(parameter) == options[parameter],"custom parameter lost")
		customized.set_shader_parameter("emission_energy",3.8)
		check(other.get_shader_parameter("emission_energy") == material.get_shader_parameter("emission_energy"),"neighbor changed")
		check((load(Library.preset_path(preset.id)) as ShaderMaterial).get_shader_parameter("emission_energy") == material.get_shader_parameter("emission_energy"),"preset changed")
		var path: String = "user://material_library_qa_"+preset.id+".tres"
		check(ResourceSaver.save(customized,path) == OK,"save failed")
		var reopened := ResourceLoader.load(path,"ShaderMaterial",ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
		check(reopened != null,"reopen failed")
		if reopened != null:
			for parameter in Library.PARAMETERS:
				var before = customized.get_shader_parameter(parameter)
				var after = reopened.get_shader_parameter(parameter)
				var equal: bool = before.is_equal_approx(after) if before is Color else is_equal_approx(before,after) if before is float else before == after
				check(equal,"save/reopen mismatch "+preset.id+"/"+parameter)
		DirAccess.remove_absolute(path)
	check(Library.create("not_a_preset") == null,"unknown id accepted")
	for invalid in [{"opacity":-1.0},{"surface_roughness":NAN},{"emission_energy":INF},{"arbitrary":true},{"base_color":"red"},{"use_vertex_color":1},{"base_color":Color(2,0,0)},{"emission_color":Color(NAN,0,0)},
		{"texture_kind":4},{"texture_kind":1.5},{"texture_relief":0.2},{"iridescence_frequency":0.0},{"highlight_color_strength":INF}]:
		check(Library.create("matte",invalid) == null,"invalid options accepted")
	var stand := STAND.instantiate()
	root.add_child(stand)
	check(stand.samples.size() == 9,"stand lacks samples")
	check(stand.samples[0].mesh.get_surface_count() > 0,"empty voxel geometry")
	var neighbor: Color = stand.materials[1].get_shader_parameter("base_color")
	stand.select_preset(6)
	stand.controls.base_color.color_changed.emit(Color(0.25,0.5,0.7))
	stand.controls.opacity.value = 0.4
	check(is_equal_approx(stand.materials[6].get_shader_parameter("opacity"),0.4),"native slider not routed")
	check(stand.materials[1].get_shader_parameter("base_color") == neighbor,"stand neighbor changed")
	stand._reset()
	check(stand.materials[6].get_shader_parameter("opacity") == 0.24,"reset failed")
	stand.select_preset(7)
	stand.controls.iridescence_strength.value = 0.6
	stand.controls.highlight_color.color_changed.emit(Color(0.7,0.2,0.9))
	check(is_equal_approx(stand.materials[7].get_shader_parameter("iridescence_strength"),0.6),"iridescence slider not routed")
	stand.select_preset(1)
	stand.controls.texture_kind.item_selected.emit(2)
	stand.controls.texture_relief.value = 0.008
	check(stand.materials[1].get_shader_parameter("texture_kind") == 2,"texture selector not routed")
	stand.set_lighting("night")
	check(not stand.sun.visible and stand.lamp.visible,"night fixture failed")
	stand.set_lighting("back")
	check(stand.sun.visible and not stand.lamp.visible,"backlighting fixture failed")
	stand.queue_free()
	await process_frame
	if errors.is_empty(): print("PASS MATERIAL_LIBRARY: nine presets, validation, immutable originals, independent instances, customized save/reopen, native stand controls, day/night")
	else:
		for error in errors: push_error(error)
	quit(0 if errors.is_empty() else 1)
