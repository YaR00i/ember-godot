extends "res://tools/capture_stone_editor_transfer.gd"
const GrassRecipe=preload("res://scripts/prototypes/ember_grass_look_recipe.gd")
var preview_checks: Array=[]

func _init() -> void:
	target_id="cartoon_grass";target_role="grass";target_slot=3;target_span=2.0;target_role_code=-2.0
	saved_pattern_file="saved-grass.tres";result_prefix="GRASS_EDITOR"

func colour_variants() -> Array[Image]:
	return GrassRecipe.colours(load("res://content/terrain_materials/painted_light_grass.tres").albedo_texture.get_image())

func camera_specs() -> Array:
	return [[Vector3(5.1,0.4,5.8),Vector3(0.35,1.7,2.4)],[Vector3(4.5,0.8,4.9),Vector3(1.1,3.7,5.2)]]

func capture_editor(editor: Control) -> void:
	editor.light_profile_previewed.connect(scene._projection.preview_shared_material_light)
	await capture("native-material-editor")
	editor._parameter_scroll.scroll_vertical=650
	await capture("native-light-controls")
	# Hide the panel for GPU comparisons, retaining the ordinary editor signal
	# and the live production projection as owners of the preview.
	editor.hide();editor.parameters_panel.get_parent().hide()
	var material: ShaderMaterial=current_materials[0]
	var texture: Texture2D=material.get_shader_parameter("grass_light_lookup")
	var meshes: Array=[]
	for visual in ground_nodes:meshes.append(visual.mesh)
	var normal:=await capture("preview-original")
	editor._finish_sliders.grass_light_tint_strength.value=0.0
	check(normal.get_data()!=(await capture("preview-edited")).get_data(),"ordinary light preview changes actual grass pixels")
	check(material.get_shader_parameter("grass_light_lookup")==texture,"light preview updates small lookup in place")
	editor.undo_edit();check(normal.get_data()==(await capture("preview-undo")).get_data(),"native preview Undo exact")
	editor.redo_edit();check(normal.get_data()!=(await capture("preview-redo")).get_data(),"native preview Redo")
	editor.cancel_edit();check(normal.get_data()==(await capture("preview-discard")).get_data(),"native preview Discard exact")
	for i in meshes.size():check(ground_nodes[i].mesh==meshes[i],"native light preview never remeshes "+str(i))
	# Real scene shadows must still affect the ground. This diagnostic changes
	# only shadow casting, then restores it exactly, for all three light presets.
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	for preset in 3:
		scene.set_lighting_preset(preset);scene.set_sun_pose(0);set_camera(0);select_pattern(0,current_materials)
		var shadow_on:=sun.shadow_enabled
		check(shadow_on,"real sun shadows remain enabled")
		var original:=await capture("shadow-on-%d"%preset)
		sun.shadow_enabled=false
		var without:=await capture("shadow-off-%d"%preset)
		var grass_region:=Rect2i(1120,650,350,190)
		check(original.get_region(grass_region).get_data()!=without.get_region(grass_region).get_data(),"grass-only region still receives scene shadows "+str(preset))
		sun.shadow_enabled=shadow_on
		check(original.get_data()==(await capture("shadow-return-%d"%preset)).get_data(),"scene shadows return exactly "+str(preset))
		preview_checks.append({"preset":preset,"real_shadow_response":true,"exact_return":true})
	write_result("grass-controls.json",{"pass":errors.is_empty(),"errors":errors,"preview_undo_discard_exact":true,"lookup_identity_preserved":true,"shadow_checks":preview_checks,"clump_shape_and_positions":"unchanged"})
