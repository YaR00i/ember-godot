extends SceneTree
## GPU regression: solid texels must not age away fresh foam at the waterline.
const Field := preload("res://scripts/prototypes/ember_compact_wave_obstacles.gd")
const Terrain := preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
func _init() -> void: run.call_deferred()
func run() -> void:
	var document := Terrain.new()
	document.width = 160
	document.depth = 160
	for channel in ["heights","water_levels","water_materials"]:
		var values: Variant = document.get(channel)
		values.resize(160*160)
		values.fill(4 if channel == "heights" else 12 if channel == "water_levels" else 2)
		document.set(channel,values)
	var shore := Image.create_empty(160,160,false,Image.FORMAT_R8)
	shore.fill(Color.WHITE)
	var field := Field.new()
	field.build(document,[{"kind":"circle","center":Vector2(80,80),"radius":8.0}],null,shore,null,
		{"wave_speed":0.42,"river_speed":0.0,"wave_height":0.0,"river_mix":0.8,"spacing":4.0,"opening":0.3,"sea_period":9.0,"sea_height":0.0,"sea_reach":10.0},true)
	var patch: Dictionary = field.patches[0]
	var fluid_index: int = patch.boundary[patch.boundary.size()/2]
	var solid_index := -1
	for neighbor in [fluid_index-1,fluid_index+1,fluid_index-33,fluid_index+33]:
		if patch.solid[neighbor] != 0: solid_index = neighbor; break
	assert(solid_index >= 0)
	var cell := (Vector2(fluid_index%33,fluid_index/33) + Vector2(solid_index%33,solid_index/33)) * 0.5
	var point: Vector2 = patch.origin + cell * 4.0
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16,16)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var quad := ColorRect.new()
	quad.size = Vector2(16,16)
	viewport.add_child(quad)
	var shader := Shader.new()
	shader.code = 'shader_type canvas_item; uniform float sea_swash_time=0.0; uniform float preview_time=0.0;\n#include "res://shaders/ember_compact_wave_obstacles.gdshaderinc"\nvoid fragment(){vec4 v=obstacle_wave_sample(vec2(%s,%s),0.0);COLOR=vec4(v.b/8.0,v.g,v.a,1.0);}' % [point.x,point.y]
	var material := ShaderMaterial.new()
	material.shader = shader
	quad.material = material
	field.strength = 1.0
	var observed := []
	var clock := 0.0
	field.advance(clock,2,1.0)
	for mode in [1,2]:
		for age in [0.0,8.0]:
			for i in patch.age.size(): patch.age[i] = age if patch.fluid[i] != 0 else 8.0
			if mode == 1:
				for frame in range(64): field._store_frame(patch,0,frame)
				field.baked_texture = ImageTexture.create_from_image(field.atlas)
				field.mode = 1
			else:
				clock += 0.1
				field.advance(clock,2,1.0)
			field.bind(material,Vector2.ZERO)
			for i in range(3): await process_frame
			await RenderingServer.frame_post_draw
			observed.append(viewport.get_texture().get_image().get_pixel(8,8).r)
	var ok: bool = observed[0] < 0.05 and observed[1] > 0.95 and observed[2] < 0.05 and observed[3] > 0.95
	print("WATER_SAMPLING ",JSON.stringify({"pass":ok,"baked_fresh_old":observed.slice(0,2),"live_fresh_old":observed.slice(2,4)}))
	viewport.free()
	quit(0 if ok else 1)
