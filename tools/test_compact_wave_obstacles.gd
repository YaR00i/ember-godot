extends SceneTree

const Field = preload("res://scripts/prototypes/ember_compact_wave_obstacles.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Phase = preload("res://scripts/prototypes/ember_compact_river_phase.gd")
const Sea = preload("res://scripts/prototypes/ember_compact_sea_swash.gd")
const Pilot = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const SETTINGS := {"wave_speed":0.42, "river_speed":1.1, "wave_height":2.0, "river_mix":0.8,
	"spacing":4.0, "opening":0.3, "sea_period":9.0, "sea_height":2.8, "sea_reach":10.0}

func _initialize() -> void:
	_run.call_deferred()

func fixture(coastal := false) -> EmberTerrainPilotResource:
	var document := Terrain.new()
	document.width = 160
	document.depth = 160
	document.palette = PackedColorArray([Color.TRANSPARENT,Color(0.7,0.6,0.3),Color(0.1,0.7,0.8)])
	for name in ["heights","top_materials","base_materials","cap_depths","water_levels","water_materials"]:
		var values: Variant = document.get(name)
		values.resize(160*160)
		values.fill(4 if name == "heights" else 12 if name == "water_levels" else 2 if name == "water_materials" else 1)
		document.set(name,values)
	if coastal:
		for z in 160:
			for x in range(104,160):
				var i := document.column_index(x,z)
				document.heights[i] = 12 + (x-104)/4
				document.water_materials[i] = 0
				document.water_levels[i] = 0
	else:
		document.water_flow.resize(100)
		document.water_flow.fill(Vector2(0,1))
	return document

func _run() -> void:
	var settings := SETTINGS.duplicate()
	var terrain := fixture()
	var original := terrain.water_levels.duplicate()
	var shapes: Array[Dictionary] = [{"kind":"box","center":Vector2(80,80),"half":Vector2(14,6),"angle":0.3}]
	var shore := Image.create_empty(160,160,false,Image.FORMAT_R8)
	shore.fill(Color(1,0,0,1))
	var field := Field.new()
	field.build(terrain,shapes,Phase.build(terrain),shore,null,settings)
	assert(field.patches.size() == 1)
	assert(field.patches[0].lambda2 <= 0.48*0.48+0.00001)
	while not field.ready:
		field.prepare(5000)
		await process_frame
	assert(terrain.water_levels == original)
	var period: float = field.patches[0].period
	var energy := 0.0
	var maximum := 0.0
	var seam := 0.0
	for z in Field.GRID:
		for x in Field.GRID:
			var a: Color = field.atlas.get_pixel(x,z)
			var b: Color = field.atlas.get_pixel(7*Field.GRID+x,7*Field.GRID+z)
			assert(is_finite(a.r) and is_finite(b.r))
			energy += absf(a.r)
			maximum = maxf(maximum,absf(a.r))
			seam += absf(a.r-b.r)
	assert(energy > 2.0 and maximum < 8.0,"wave must scatter and remain bounded")
	var amplitudes := PackedFloat32Array()
	for point in [Vector2(80,48),Vector2(80,112),Vector2(104,100)]:
		var low := INF
		var high := -INF
		for frame in Field.FRAMES:
			var value: Color = field._baked(0,point,float(frame)*period/Field.FRAMES)
			low = minf(low,value.g)
			high = maxf(high,value.g)
		amplitudes.append((high-low)*0.5)
	print("OBSTACLE amplitudes upstream/lee/side=",amplitudes)
	assert(amplitudes[1]<amplitudes[0] and amplitudes[2]>0.1,"solid must weaken the lee without stopping the lateral wave")
	var off_axis := Vector2(103,96)
	field.advance(2.1,1,1.0)
	assert(field.sample(Vector2(0,0)) == Vector2.ZERO)
	var baked: Vector2 = field.sample(off_axis)
	assert(field.update_us == 0)
	field.advance(2.1,2,1.0)
	var live: Vector2 = field.sample(off_axis)
	assert(baked.distance_to(live)<0.001,"live seek must start at the same baked surface")
	var updates := PackedFloat32Array()
	var differences := PackedFloat32Array()
	for step in range(1,161):
		var time := 2.1+float(step)*0.025
		field.advance(time,2,1.0)
		updates.append(float(field.update_us)/1000.0)
		var actual := field.sample(off_axis)
		field.mode = 1
		var reference := field.sample(off_axis)
		differences.append(actual.distance_to(reference))
		field.mode = 2
		assert(actual.length()<8.0)
	var old_steps: int = field.steps_taken
	for value in field.patches[0].h: assert(is_finite(value) and absf(value)<8.0)
	field.advance(1000.0,2,1.0)
	assert(field.steps_taken == old_steps,"large gaps seek instead of catching up indefinitely")
	field.advance(1.0,2,1.0)
	field.advance(1.0,0,1.0)
	assert(field.sample(off_axis) == Vector2.ZERO)
	field.advance(1.0,1,0.0)
	assert(field.sample(off_axis) == Vector2.ZERO)
	var reused := Field.new()
	reused.build(terrain,shapes,Phase.build(terrain),shore,null,settings)
	assert(reused.ready and reused.cache_hit and reused.signature == field.signature,"unchanged fixed obstacles reuse the disk bake")
	var changed_shapes: Array[Dictionary] = shapes.duplicate(true)
	changed_shapes[0].angle = 1.2
	var changed := Field.new()
	changed.build(terrain,changed_shapes,Phase.build(terrain),shore,null,settings)
	assert(changed.signature != reused.signature)
	var none := Field.new()
	none.build(terrain,[],Phase.build(terrain),shore,null,settings)
	assert(none.ready and none.patches.is_empty())
	updates.sort()
	differences.sort()
	print("OBSTACLE river energy=",energy," max=",maximum," cycle_neighbor_delta=",seam/(Field.GRID*Field.GRID),
		" build_ms=",field.build_us/1000.0," memory_bytes=",field.atlas.get_data().size(),
		" live_p50_ms=",updates[updates.size()/2]," p95_ms=",updates[floori(updates.size()*0.95)],
		" live_baked_p95_delta=",differences[floori(differences.size()*0.95)])
	var sea := Sea.new()
	var coastal := fixture(true)
	sea.build(coastal)
	var sea_shapes: Array[Dictionary] = [{"kind":"circle","center":Vector2(92,80),"radius":8.0}]
	var sea_field := Field.new()
	sea_field.build(coastal,sea_shapes,null,shore,sea,settings)
	while not sea_field.ready:
		sea_field.prepare(5000)
		await process_frame
	assert(sea_field.patches[0].coastal)
	sea_field.advance(3.3,1,1.0)
	var seen := false
	for p in [Vector2(84,80),Vector2(100,68),Vector2(96,92)]:
		seen = seen or absf(sea_field.sample(p).x)>0.001
	assert(seen,"coastal wave must use the same obstacle solver")
	var pilot := Pilot.new()
	root.add_child(pilot)
	assert(pilot.open_document(coastal))
	while pilot.pending_tile_count()>0: await process_frame
	var revision := pilot.column_revision()
	pilot.set_sea_swash(sea)
	sea.advance(3.3,2.8,9.0,10.0,0.0,12.0)
	var point := Vector3(100,0,68)
	var before: Dictionary = pilot.water_surface_sample(point)
	pilot.set_wave_obstacles(sea_field)
	var after: Dictionary = pilot.water_surface_sample(point)
	assert(is_equal_approx(after.position.y-before.position.y,sea_field.sample(Vector2(point.x,point.z)).x))
	assert(pilot.column_revision()==revision)
	pilot.set_wave_obstacles(null)
	assert(is_equal_approx(pilot.water_surface_sample(point).position.y,before.position.y))
	print("OBSTACLE sea correction/query/removal PASS")
	if DisplayServer.get_name() != "headless": await _gpu(field)
	pilot.queue_free()
	print("COMPACT_WAVE_OBSTACLES PASS")
	quit()

func _gpu(field: RefCounted) -> void:
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader").get_slice("void fragment()",0)+"""
void fragment() {
 vec4 wave = obstacle_wave_sample(water_point * 16.0, preview_time);
 ALBEDO=vec3(0.0); ALPHA=1.0;
 EMISSION=vec3(wave.r*.2+.5, wave.g*.2+.5, water_world_position.y*.2+.5);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wave_height_voxels",0.0)
	material.set_shader_parameter("preview_time",2.1)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size=Vector2(160,160)
	mesh.subdivide_width=39
	mesh.subdivide_depth=39
	plane.mesh=mesh
	plane.position=Vector3(80,0,80)
	plane.material_override=material
	viewport.add_child(plane)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=160
	viewport.add_child(camera)
	camera.position=Vector3(80,200,80)
	camera.look_at(Vector3(80,0,80),Vector3(0,0,-1))
	camera.make_current()
	field.advance(2.1,1,1.0)
	field.bind(material,Vector2.ZERO)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var baked := viewport.get_texture().get_image()
	field.advance(2.1,2,1.0)
	field.bind(material,Vector2.ZERO)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var live := viewport.get_texture().get_image()
	var difference := 0.0
	var variation := 0.0
	var vertex_variation := 0.0
	var vertex_error := 0.0
	for z in range(60,196):
		for x in range(60,196):
			difference += absf(baked.get_pixel(x,z).r-live.get_pixel(x,z).r)
			variation += absf(baked.get_pixel(x,z).r-baked.get_pixel(62,62).r)
			vertex_variation += absf(baked.get_pixel(x,z).b-baked.get_pixel(62,62).b)
			vertex_error += absf(baked.get_pixel(x,z).b-baked.get_pixel(x,z).r)
	assert(difference/(136*136)<0.004 and variation>3.0,"real GPU must show the same scattered height in both modes")
	assert(vertex_variation>3.0 and vertex_error/(136*136)<0.015,"actual vertex height must use the sampled correction")
	print("OBSTACLE GPU baked/live mean_delta=",difference/(136*136)," variation=",variation," vertex_error=",vertex_error/(136*136))
	viewport.queue_free()
