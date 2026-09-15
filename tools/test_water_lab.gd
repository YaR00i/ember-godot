extends SceneTree
## Targeted owner/UI/export checks for the isolated Water Lab scene.

var errors := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	var source := load("res://materials/ember_voxel_surface_water.tres") as ShaderMaterial
	var source_travel = source.get_shader_parameter("pixel_highlight_travel_speed")
	var lab := (load("res://scenes/water_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	for frame in 20:
		await process_frame
	check(lab.water != source, "Water Lab edits the canonical material instance")
	check(lab.controls.size() >= 40, "Water Lab is missing consolidated shore controls")
	check(lab.get_node_or_null("BeachStep00") != null, "Water Lab has no stepped voxel beach")
	check(lab.get_node_or_null("HarbourWall") != null, "Water Lab has no hard reflecting wall")
	var shore := lab.get_node_or_null("SystemicShoreResponse") as MeshInstance3D
	check(shore != null and shore.mesh is ArrayMesh, "Water Lab has no systemic shore response")
	if shore != null and shore.mesh is ArrayMesh:
		var arrays := shore.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		check(not uvs.is_empty() and uvs.size() == uv2s.size(), "Water Lab shore has no boundary metadata")
		var has_approach := false
		var has_runup := false
		var has_wall := false
		for uv in uvs:
			has_approach = has_approach or uv.x >= 2.0
			has_runup = has_runup or uv.x < -0.25
			has_wall = has_wall or uv.y > 0.5
		check(has_approach, "shore response cannot approach from open water")
		check(has_runup, "beach response cannot run over land")
		check(has_wall, "hard-bank response is not classified")
	check("water_shore_wave_state" in lab.beach_foam.shader.code, "beach foam is not sampled from the transformed visible water wave")
	check("standing_contact" in lab.wall_foam.shader.code, "hard wall has no persistent water contact edge")
	check(lab.get_node_or_null("ShoreBottomStep00") != null and lab.get_node_or_null("ShoreBottomStep03") != null and lab.get_node_or_null("MidBottom") != null and lab.get_node_or_null("DeepBottom") != null, "Water Lab has no real stepped depth")
	check((lab.get_node("ShoreBottomStep00") as MeshInstance3D).position.y > (lab.get_node("ShoreBottomStep03") as MeshInstance3D).position.y, "shore shoal does not descend toward the basin")
	check((lab.get_node("ShoreBottomStep03") as MeshInstance3D).position.y > (lab.get_node("MidBottom") as MeshInstance3D).position.y, "mid basin is not below the shore shoal")
	check((lab.get_node("MidBottom") as MeshInstance3D).position.y > (lab.get_node("DeepBottom") as MeshInstance3D).position.y, "deep floor is not below the mid basin")
	check(is_equal_approx(lab.water.get_shader_parameter("scene_depth_mix"), 1.0), "Water Lab still paints depth from ordinary plane UVs")
	check(is_equal_approx(lab.water.get_shader_parameter("shallow_opacity"), 0.48), "Water Lab shallow water is still opaque paint")
	check(is_equal_approx(lab.water.get_shader_parameter("deep_opacity"), 0.68), "Water Lab deep water lost the transparent depth ramp")
	check("visible_floor_depth" in lab.water.shader.code, "Water Lab shader does not measure the real floor distance")
	var shelf_color := ((lab.get_node("ShoreBottomStep00") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	var mid_color := ((lab.get_node("MidBottom") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	var deep_color := ((lab.get_node("DeepBottom") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	check(shelf_color == mid_color and mid_color == deep_color, "depth zones are still pre-painted as different floor colours")
	var rock_contact := lab.get_node_or_null("RockCollisionModel/RockWaterContact/CollisionWaterline_RockShape/ContactRipple") as MeshInstance3D
	check(rock_contact != null and rock_contact.mesh is QuadMesh, "water object has no collision-derived contact-wave reaction")
	check(lab.rock_water_contact.collision_contact_count() == 1, "rock collision did not intersect the waterline")
	check(lab.rock_contact_material.get_shader_parameter("flow_reaction_enabled") == true, "rock still uses the unrelated generic contact ring")
	check(float(lab.rock_contact_material.get_shader_parameter("contact_line_width")) < 0.04, "object contact seam is not the thin lab version")
	check(float(lab.rock_contact_material.get_shader_parameter("reaction_line_width")) < 0.05, "object response wave is not the thin readable lab version")
	var rock_quad := rock_contact.mesh as QuadMesh
	check(rock_quad.size.x > 1.0 and rock_quad.size.y > 0.9, "rock response quad has no automatic anti-clipping margin")
	check("contact_seam" in lab.rock_contact_material.shader.code, "shared contact shader has no stable actor/object intersection seam")
	check((lab.get_node("BeachStep00") as Node3D).position.z > 2.5, "beach zone still overlaps the centre pier")
	check((lab.get_node("HarbourWall") as Node3D).position.z < -2.5, "wall zone still overlaps the centre pier")
	check(is_zero_approx((lab.get_node("PierBoard00") as Node3D).position.z), "pier is not centred in the quiet gap")
	check(lab.pier_water_contact.collision_contact_count() == 2, "wet/dry filtering did not leave exactly two offshore supports")
	check(lab.pier_contact_materials.size() == 14, "pier contact owner did not derive all board and support collision footprints")
	var wet_pier_a := lab.get_node_or_null("PierCollisionModel/PierWaterContact/CollisionWaterline_PierPost02Shape") as Node3D
	var wet_pier_b := lab.get_node_or_null("PierCollisionModel/PierWaterContact/CollisionWaterline_PierPost03Shape") as Node3D
	var dry_pier_a := lab.get_node_or_null("PierCollisionModel/PierWaterContact/CollisionWaterline_PierPost00Shape") as Node3D
	var deck_contact := lab.get_node_or_null("PierCollisionModel/PierWaterContact/CollisionWaterline_PierBoard09Shape") as Node3D
	check(wet_pier_a != null and wet_pier_a.visible and wet_pier_b != null and wet_pier_b.visible, "offshore supports have no automatic waterline reaction")
	check(dry_pier_a != null and not dry_pier_a.visible, "dry landward support received a water reaction")
	check(deck_contact != null and not deck_contact.visible, "dry bridge deck received a water reaction")
	var pier_coordinates := {}
	for contact_anchor in [wet_pier_a, wet_pier_b]:
		var ripple := contact_anchor.get_node("ContactRipple") as MeshInstance3D
		var material := (ripple.mesh as QuadMesh).material as ShaderMaterial
		check(material.get_shader_parameter("flow_reaction_enabled") == true, "pier support uses an unrelated static ring")
		var normalized_footprint := material.get_shader_parameter("object_half_extent") as Vector2
		check(is_equal_approx(normalized_footprint.x, normalized_footprint.y), "square support waterline became asymmetric")
		check(float(material.get_shader_parameter("reaction_distance")) > normalized_footprint.x, "pier response cannot split around the narrow support")
		check((ripple.mesh as QuadMesh).size.x > 0.16 + 0.38, "pier response quad clips the automatic outer wave")
		pier_coordinates[material.get_shader_parameter("object_coordinate")] = true
	check(pier_coordinates.has(Vector2(-1.8, -0.75)) and pier_coordinates.has(Vector2(-1.8, 0.75)), "pier support contacts are not world-aligned with the posts")
	check("crest_response" in lab.pier_contact_materials[0].shader.code, "static obstacle response does not strengthen when a shared crest arrives")
	check(lab.ship_water_contact.collision_contact_count() == 1, "moving hull has no collision-derived waterline")
	check(lab.ship_water_contact.wake_sample_count() > 0, "moving hull did not leave shared water history")
	check(is_equal_approx(lab.water.get_shader_parameter("shore_effect_strength"), 0.68), "shore prototype is not enabled")
	check(lab.water.get_shader_parameter("shore_geometry_driven") == true, "fixed-coordinate shore paint still overlaps systemic foam")
	check(is_equal_approx(lab.water.get_shader_parameter("shore_wave_transform"), 1.0), "depth-driven wave transformation is not enabled in Water Lab")
	check(is_equal_approx(lab.water.get_shader_parameter("shore_refraction_strength"), 0.86), "Water Lab lost the near-shore crest turn")
	check(is_equal_approx(lab.water.get_shader_parameter("shore_break_threshold"), 0.78), "Water Lab lost the H/depth break threshold")
	check(is_equal_approx(lab.water.get_shader_parameter("shore_break_distance"), 3.20), "physical breaker cannot use the full stepped shoal")
	check(is_equal_approx(lab.water.get_shader_parameter("shore_runup_speed"), 0.38), "runup is no longer a travelling continuation of the breaker")
	check("water_break_factor" in lab.beach_foam.shader.code and "dominant_wave_phase" in lab.beach_foam.shader.code and "front_distance" in lab.beach_foam.shader.code, "foam is not derived from breaking and one crest front")
	var water_mesh := (lab.get_node("EditableWater") as MeshInstance3D).mesh
	var water_arrays := water_mesh.surface_get_arrays(0)
	var water_uvs: PackedVector2Array = water_arrays[Mesh.ARRAY_TEX_UV]
	var water_uv2s: PackedVector2Array = water_arrays[Mesh.ARRAY_TEX_UV2]
	check(not water_uv2s.is_empty() and water_uv2s.size() == water_uvs.size(), "Water Lab water has no shore distance/direction metadata")
	var has_beach_water := false
	var has_wall_water := false
	var depth_bands := {}
	for uv in water_uvs:
		has_beach_water = has_beach_water or uv.y > 0.0
		has_wall_water = has_wall_water or uv.y < 0.0
		depth_bands[snappedf(uv.x, 0.01)] = true
	check(has_beach_water and has_wall_water, "Water Lab water cannot distinguish beach from reflecting wall")
	check(depth_bands.size() >= 6, "water mesh does not carry the real stepped depth profile")
	check(is_equal_approx(lab.water.get_shader_parameter("shore_reflection_strength"), 0.76), "hard-wall reflected wave is not readable")
	check(is_equal_approx(lab.water.get_shader_parameter("visual_wave_height"), 0.04), "restrained visual displacement is not enabled in the lab candidate")
	check(is_equal_approx(lab.water.get_shader_parameter("underwater_caustic_wave_link"), 1.0), "bottom light is not fully derived from the shared wave")
	check(is_equal_approx(lab.water.get_shader_parameter("underwater_caustic_width"), 0.35), "bottom light lost its focused connected bands")
	check(is_equal_approx(lab.water.get_shader_parameter("underwater_light_mix"), 0.58), "bottom light is not visible in the lab candidate")
	check("mixing the whole screen sample" in lab.water.shader.code, "bottom light regressed to repainting the entire water body")
	lab._apply_volume_water()
	check(is_equal_approx(lab.water.get_shader_parameter("visual_wave_height"), 0.04), "volume A/B button did not enable restrained displacement")
	lab._apply_flat_water()
	check(is_equal_approx(lab.water.get_shader_parameter("visual_wave_height"), 0.0), "flat A/B button did not restore exact plane parity")
	lab._apply_synced()
	check(is_equal_approx(lab.water.get_shader_parameter("layered_water_mix"), 0.4), "synced preset lost the saved layered-water balance")
	check(is_equal_approx(lab.water.get_shader_parameter("wave_natural_mix"), 0.49), "synced preset lost the user's mixed wave composition")
	check(is_equal_approx(lab.water.get_shader_parameter("wave_direction_degrees"), 180.0), "synced preset lost the user's shoreward direction")
	check(is_equal_approx(lab.water.get_shader_parameter("wave_length"), 3.71), "synced preset lost the user's wave length")
	check(is_equal_approx(lab.water.get_shader_parameter("wave_strength"), 0.225), "synced preset lost the user's wave strength")
	check(is_equal_approx(lab.water.get_shader_parameter("flow_network_strength"), 0.16), "synced preset lost the saved Review2 network")
	check(is_equal_approx(lab.water.get_shader_parameter("pixel_highlight_mix"), 1.0), "synced preset lost the saved Review2 highlights")
	check((lab.water.get_shader_parameter("wave_shadow_tone") as Color).get_luminance() < (lab.water.get_shader_parameter("wave_crest_tone") as Color).get_luminance(), "wave value hierarchy is inverted")
	check((lab.water.get_shader_parameter("underwater_caustic_color") as Color).g > (lab.water.get_shader_parameter("underwater_caustic_color") as Color).b, "underwater caustic is not warm green")
	var selected_tint = lab.water.get_shader_parameter("water_tint")
	lab._apply_shore_readable_waves()
	check(is_equal_approx(lab.water.get_shader_parameter("wave_natural_mix"), 1.0), "shore profile still mixes the conflicting Review2 field")
	check(is_equal_approx(lab.water.get_shader_parameter("wave_direction_degrees"), 180.0), "shore profile is not aimed at the demonstration bank")
	check(is_equal_approx(lab.water.get_shader_parameter("wave_direction_spread"), 9.0), "shore profile lost its coherent narrow direction spread")
	check(lab.water.get_shader_parameter("water_tint") == selected_tint, "shore profile overwrote selected water colour")
	lab._apply_lake_waves()
	check(is_equal_approx(lab.water.get_shader_parameter("wave_direction_spread"), 38.0), "lake profile did not widen wave directions")
	check(is_equal_approx(lab.water.get_shader_parameter("wind_ripple_strength"), 0.58), "lake profile did not add wind ripple")
	check(lab.water.get_shader_parameter("water_tint") == selected_tint, "wave profile overwrote selected water color")
	lab._apply_coast_waves()
	check(is_equal_approx(lab.water.get_shader_parameter("wave_crest_sharpness"), 0.76), "coast profile did not sharpen crests")
	lab._apply_river_waves()
	check(is_equal_approx(lab.water.get_shader_parameter("wave_speed"), 0.66), "river profile did not increase downstream motion")
	lab._apply_sea_waves()
	check(is_equal_approx(lab.water.get_shader_parameter("wave_grouping"), 0.58), "sea profile lost wave groups")
	lab._apply_reference()
	check(is_equal_approx(lab.water.get_shader_parameter("layered_water_mix"), 1.0), "reference preset did not enable layered water")
	check(is_equal_approx(lab.water.get_shader_parameter("flow_network_strength"), 0.0), "reference preset still paints the old surface network")
	lab._apply_physical()
	check(is_equal_approx(lab.water.get_shader_parameter("pixel_highlight_mix"), 0.0), "physical preset still uses the painted crest mask")
	check(is_equal_approx(lab.water.get_shader_parameter("layered_water_mix"), 0.0), "physical comparison still uses layered art tones")
	check(is_equal_approx(lab.water.get_shader_parameter("reflection_pixel_strength"), 0.0), "physical preset quantizes wave normals")
	check(is_equal_approx(lab.water.get_shader_parameter("wave_strength"), 0.08), "physical preset has unexpected wave slope")
	check(is_equal_approx(lab.water.get_shader_parameter("surface_roughness"), 0.22), "physical preset has unexpected highlight width")
	check(is_equal_approx(lab.water.get_shader_parameter("highlight_strength"), 0.24), "physical preset has unexpected dielectric response")
	check(lab.FIELD_SIZE.x >= 22.0 and lab.FIELD_SIZE.y >= 15.0, "expanded Water Lab field became cramped again")
	var view_to_camera: Vector3 = (lab.camera.position - lab.CAMERA_FOCUS).normalized()
	var physical_half: Vector3 = (lab.sun.basis.z.normalized() + view_to_camera).normalized()
	var required_slope := Vector2(-physical_half.x / physical_half.y, -physical_half.z / physical_half.y)
	check(required_slope.length() < 0.2, "fixed Water Lab sun cannot produce a physical highlight in the default view")
	lab._apply_standing()
	check(is_equal_approx(lab.water.get_shader_parameter("pixel_highlight_view_dependence"), 0.15), "standing comparison remains too camera-dependent")
	check(is_equal_approx(lab.water.get_shader_parameter("pixel_highlight_travel_speed"), 0.02), "standing comparison is not nearly stationary")
	check(is_equal_approx(lab.water.get_shader_parameter("pixel_highlight_threshold"), 0.991), "standing comparison is not sharp")
	lab._apply_review2()
	check(is_equal_approx(lab.water.get_shader_parameter("wave_natural_mix"), 0.0), "Review2 comparison no longer selects its exact legacy wave field")
	lab._apply_reference()
	lab._apply_values({"wave_grouping":0.37, "pixel_highlight_travel_speed":0.37, "pixel_highlight_edge_wobble":0.14})
	check(is_equal_approx(lab.water.get_shader_parameter("pixel_highlight_travel_speed"), 0.37), "live travel edit did not reach shader")
	check(is_equal_approx((lab.controls.wave_grouping.spin as SpinBox).value, 0.37), "live wave edit did not refresh numeric control")
	var exported: Dictionary = lab.export_settings()
	check(exported.has("pixel_highlight_travel_speed") and is_equal_approx(exported.pixel_highlight_travel_speed, 0.37), "export missed edited travel speed")
	check(exported.has("pixel_highlight_mix"), "consolidated export lost hidden highlight mode")
	check(exported.has("underwater_light_mix"), "consolidated export lost hidden bottom-light blend")
	check(exported.has("scene_depth_mix") and is_equal_approx(exported.scene_depth_mix, 1.0), "export lost real floor-depth sampling")
	check(exported.has("underwater_caustic_width"), "export lost bottom-light band width")
	check(exported.has("shore_runup_distance"), "consolidated export lost shore runup")
	check(exported.has("shore_wave_transform"), "export lost depth-driven shore transformation")
	check(exported.has("visual_wave_height"), "consolidated export lost the displacement A/B value")
	lab._apply_values({"shore_runup_distance":1.37, "shore_foam_width":0.19, "wave_speed":0.57})
	check(is_equal_approx(lab.beach_foam.get_shader_parameter("shore_runup_distance"), 1.37), "beach foam did not receive live runup edits")
	check(is_equal_approx(lab.wall_foam.get_shader_parameter("shore_foam_width"), 0.19), "wall contact did not receive live foam edits")
	check(is_equal_approx(lab.wall_foam.get_shader_parameter("shore_reflection_strength"), 0.76), "wall overlay drifted from reflected-wave strength")
	check(is_equal_approx(lab.beach_foam.get_shader_parameter("wave_speed"), 0.57), "shore overlays drift from the shared wave clock")
	check(is_equal_approx(
		lab.beach_foam.get_shader_parameter("wave_natural_mix"),
		lab.water.get_shader_parameter("wave_natural_mix")
	), "shore response lost the visible wave composition")
	check(is_equal_approx(
		lab.beach_foam.get_shader_parameter("wave_direction_spread"),
		lab.water.get_shader_parameter("wave_direction_spread")
	), "shore response lost the visible wave spread")
	check(is_equal_approx(lab.rock_contact_material.get_shader_parameter("wave_speed"), 0.57), "rock reaction drifts from the shared wave clock")
	for material in lab.pier_contact_materials:
		check(is_equal_approx(material.get_shader_parameter("wave_speed"), 0.57), "pier reaction drifts from the shared wave clock")
	check(typeof(exported.pixel_highlight_color) == TYPE_STRING, "exported color is not portable text")
	var parsed = JSON.parse_string(JSON.stringify(exported))
	check(parsed is Dictionary and parsed.size() == exported.size(), "export is not valid JSON")
	lab._reset_original()
	check(is_equal_approx(lab.water.get_shader_parameter("pixel_highlight_travel_speed"), source_travel), "reset did not restore original value")
	check(is_equal_approx(source.get_shader_parameter("pixel_highlight_travel_speed"), source_travel), "Water Lab mutated canonical source")
	var fixed_sun_basis: Basis = lab.sun.basis
	lab.orbit.x += PI * 0.5
	lab._update_camera()
	check(lab.sun.basis.is_equal_approx(fixed_sun_basis), "orbiting Water Lab moved its world sun")
	lab.queue_free()
	await process_frame
	for error in errors:
		push_error(error)
	print("PASS WATER_LAB: terrain-driven shore response, object contacts, shared waves, controls and portable export" if errors.is_empty() else "FAIL WATER_LAB")
	quit(0 if errors.is_empty() else 1)
