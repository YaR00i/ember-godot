extends "res://tools/render_water_lightplay.gd"
## W04 native checks for direct pixel highlights, shadow stepping and underwater light.


func image_stats(a: Image,b: Image,threshold := 8) -> Dictionary:
	var significant := 0
	var total := 0.0
	var maximum := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			var difference := maxi(abs(int(ca.r8)-int(cb.r8)),maxi(abs(int(ca.g8)-int(cb.g8)),abs(int(ca.b8)-int(cb.b8))))
			total += difference
			maximum = maxi(maximum,difference)
			if difference > threshold: significant += 1
	return {"significant":significant,"average":total/float(a.get_width()*a.get_height()),"maximum":maximum}


func bright_pixels(image: Image,threshold := 240) -> int:
	var result := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if (int(color.r8)+int(color.g8)+int(color.b8))/3 > threshold: result += 1
	return result


func capture_probe(label: String) -> Image:
	for frame in 18: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://art/water/lightplay/qa/probe-"+label+".png")
	return image


func run() -> void:
	var canonical := Materials.water_material()
	if canonical.get_shader_parameter("layered_water_mix") != 0.0: errors.append("layered water changed W03 by default")
	if canonical.get_shader_parameter("pixel_highlight_mix") != 0.0: errors.append("pixel highlights changed W03 by default")
	if canonical.get_shader_parameter("pixel_highlight_view_dependence") != 1.0: errors.append("highlight camera dependence changed review2 by default")
	if canonical.get_shader_parameter("pixel_highlight_smooth_motion") != 0.0: errors.append("smooth highlight motion changed review2 by default")
	if canonical.get_shader_parameter("pixel_highlight_edge_wobble") != 0.0: errors.append("highlight edge wobble changed review2 by default")
	if canonical.get_shader_parameter("pixel_highlight_travel_speed") != 1.0: errors.append("highlight travel speed changed review2 by default")
	if canonical.get_shader_parameter("pixel_highlight_wobble_speed") != 1.0: errors.append("highlight wobble speed changed review2 by default")
	if canonical.get_shader_parameter("pixel_highlight_cohesion") != 0.0: errors.append("connected highlight patches changed review2 by default")
	if canonical.get_shader_parameter("stylized_shadow_mix") != 0.0: errors.append("shadow stepping changed W03 by default")
	if canonical.get_shader_parameter("underwater_light_mix") != 0.0: errors.append("underwater light changed W03 by default")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280,900)
		root.content_scale_size = Vector2i(1280,900)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/water/lightplay/qa"))
		build()
		camera.size = 6.4
		camera.position = Vector3(8.6,5.6,9.6)
		camera.look_at(Vector3(4.3,1,4.0))
		water.set_shader_parameter("preview_time",3.25)
		water.set_shader_parameter("pixel_highlight_mix",0.0)
		water.set_shader_parameter("stylized_shadow_mix",0.0)
		water.set_shader_parameter("underwater_light_mix",0.0)
		var baseline := await capture_probe("current")
		water.set_shader_parameter("pixel_highlight_mix",1.0)
		var sharp := await capture_probe("sharp")
		var sharp_stats := image_stats(baseline,sharp,24)
		var baseline_bright := bright_pixels(baseline)
		var sharp_bright := bright_pixels(sharp)
		print("WATER_LIGHTPLAY_SHARP significant=",sharp_stats.significant," average=",sharp_stats.average,
			" bright_current=",baseline_bright," bright_sharp=",sharp_bright)
		if sharp_stats.significant < 2000: errors.append("pixel highlight has too little native response")
		if sharp_bright >= baseline_bright: errors.append("pixel highlight did not break up the broad bright lobe")
		water.set_shader_parameter("pixel_highlight_smooth_motion",1.0)
		water.set_shader_parameter("pixel_highlight_edge_wobble",0.10)
		water.set_shader_parameter("pixel_highlight_travel_speed",0.04)
		water.set_shader_parameter("pixel_highlight_wobble_speed",1.15)
		water.set_shader_parameter("pixel_highlight_view_dependence",0.15)
		var wobble := await capture_probe("wobble")
		var wobble_stats := image_stats(sharp,wobble,8)
		print("WATER_LIGHTPLAY_WOBBLE significant=",wobble_stats.significant," average=",wobble_stats.average)
		if wobble_stats.significant < 500: errors.append("smooth highlight motion has too little native response")
		water.set_shader_parameter("pixel_highlight_smooth_motion",0.0)
		water.set_shader_parameter("pixel_highlight_edge_wobble",0.0)
		water.set_shader_parameter("pixel_highlight_travel_speed",1.0)
		water.set_shader_parameter("pixel_highlight_wobble_speed",1.0)
		water.set_shader_parameter("pixel_highlight_view_dependence",1.0)
		water.set_shader_parameter("pixel_highlight_cohesion",1.0)
		var patches := await capture_probe("patches")
		var patch_stats := image_stats(sharp,patches,8)
		print("WATER_LIGHTPLAY_PATCHES significant=",patch_stats.significant," average=",patch_stats.average)
		if patch_stats.significant < 500: errors.append("connected highlight patches have too little native response")
		water.set_shader_parameter("pixel_highlight_cohesion",0.0)
		water.set_shader_parameter("stylized_shadow_mix",1.0)
		var shadow := await capture_probe("shadow")
		var shadow_stats := image_stats(sharp,shadow,8)
		print("WATER_LIGHTPLAY_SHADOW significant=",shadow_stats.significant," average=",shadow_stats.average)
		if shadow_stats.significant < 1000: errors.append("stylized shadow has too little native response")
		# Isolate moving bottom light from the already proven surface animation.
		water.set_shader_parameter("pixel_highlight_mix",0.0)
		water.set_shader_parameter("flow_network_strength",0.0)
		water.set_shader_parameter("wave_strength",0.0)
		water.set_shader_parameter("underwater_light_mix",0.20)
		water.set_shader_parameter("underwater_caustic_strength",0.90)
		water.set_shader_parameter("underwater_depth_range",0.55)
		var caustic_a := await capture_probe("caustic-a")
		water.set_shader_parameter("preview_time",4.25)
		var caustic_b := await capture_probe("caustic-b")
		var caustic_motion := image_stats(caustic_a,caustic_b,8)
		print("WATER_LIGHTPLAY_CAUSTIC_MOTION significant=",caustic_motion.significant," average=",caustic_motion.average)
		if caustic_motion.significant < 500: errors.append("underwater light stopped moving")
		water.set_shader_parameter("preview_time",3.25)
		water.set_shader_parameter("underwater_light_mix",0.0)
		var caustic_disabled := await capture_probe("caustic-disabled")
		var caustic_response := image_stats(caustic_a,caustic_disabled,8)
		print("WATER_LIGHTPLAY_CAUSTIC_RESPONSE significant=",caustic_response.significant," average=",caustic_response.average)
		if caustic_response.significant < 1000: errors.append("underwater light has too little native response")
		scene.queue_free()
		await frames(10)
	for error in errors: push_error(error)
	var checks := "disabled material defaults" if DisplayServer.get_name() == "headless" else "sharp and smoothly deforming highlights, connected patches, hard shadow response and moving screen-space bottom light"
	print("PASS WATER_LIGHTPLAY: "+checks if errors.is_empty() else "FAIL WATER_LIGHTPLAY")
	quit(0 if errors.is_empty() else 1)
