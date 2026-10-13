extends SceneTree
const Generation=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Forms=preload("res://scripts/prototypes/ember_terrain_surface_form_math.gd")
const PARAMS={"profile":"hills","seed":71,"sea_m":1.25,"land_m":0.9,"relief_m":2.5,"feature_m":11.0,"shore_m":2.4,"land_fraction":0.86}
var errors: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func run() -> void:
	var base=load("res://content/world_terrains/cartoon_generated_base.res")
	var detail=load("res://content/world_terrains/cartoon_generated_detail.res")
	check(base.validation_errors().is_empty() and detail.validation_errors().is_empty(),"generated sources valid")
	var source=load("res://content/world_terrains/cartoon_ground_study.res")
	var original=source.working_copy();var job:=Generation.new()
	check(job.begin(source,Rect2i(0,0,24,16),PARAMS),"existing generator accepts area")
	while not job.finished:job.step(900)
	var generated=job.candidate.dense_window(Rect2i(0,0,384,256))
	check(base.heights==generated.heights,"large landform comes from existing generator unchanged")
	check(source.same_terrain_data(original),"existing authored fixture untouched")
	check(base.top_materials==detail.top_materials,"baseline/detail same material layout")
	check(base.water_levels==detail.water_levels and base.water_materials==detail.water_materials,"water intent preserved")
	var max_dry:=0;var changed:=0
	for i in base.heights.size():
		var delta: int=abs(detail.heights[i]-base.heights[i])
		if base.water_levels[i]>0:check(delta==0,"underwater floor preserved")
		else:max_dry=maxi(max_dry,delta)
		if delta>0:changed+=1
	check(changed>1000 and max_dry<24,"finish changes local volume, not large hills")
	for role: String in ["grass","soil","sand","stone"]:
		var slot: int=detail.palette_surface_roles.find(role)
		check(slot>0 and detail.top_materials.count(slot)>100,"generated surface includes "+role)
	var art:=Image.load_from_file("res://content/terrain_materials/textures/cartoon_rock.png")
	var a:=Forms.new();a.configure(731,art,3.2)
	var b:=Forms.new();b.configure(731,art,3.2)
	var another:=Forms.new();another.configure(732,art,3.2)
	var variant:=false
	for p: Vector2 in [Vector2(1.2,3.4),Vector2(5.7,7.9),Vector2(12.2,9.3)]:
		for role: String in ["stone","sand","soil","grass"]:
			check(a.offset_m(p,role)==b.offset_m(p,role),"surface seed reproducible")
			if a.offset_m(p,role)!=another.offset_m(p,role):variant=true
	check(variant,"surface seed changes details independently")
	check(ResourceSaver.save(detail,"user://cartoon-generated-reopen.res")==OK,"generated Resource Save")
	var reread=ResourceLoader.load("user://cartoon-generated-reopen.res","",ResourceLoader.CACHE_MODE_IGNORE)
	check(reread.same_terrain_data(detail),"generated Resource Reopen")
	var scene=load("res://scenes/compact_cartoon_generated_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	var map:=scene.get_node("Map") as EmberMapLoader
	var before: PackedInt32Array=detail.heights.duplicate()
	var keyboard:=InputEventKey.new();keyboard.keycode=KEY_B;keyboard.pressed=true
	for version in 3:
		var projection=map._visual_surface_projection
		var deadline:=Time.get_ticks_msec()+60000
		while projection.pending_tile_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
		check(projection.pending_tile_count()==0,"generated mesh ready")
		await physics_frame;await physics_frame
		check(map.compact_terrain==(base if version==1 else detail),"B swaps existing Resource")
		for p: Vector2 in [Vector2(3.2,4.5),Vector2(7.7,9.1),Vector2(12.2,8.4),Vector2(16.5,10.2),Vector2(20.6,13.3)]:
			var ray:=PhysicsRayQueryParameters3D.create(Vector3(p.x,20,p.y),Vector3(p.x,-2,p.y))
			var hit:=root.world_3d.direct_space_state.intersect_ray(ray)
			var sample=projection.floor_surface_sample(Vector3(p.x,0,p.y))
			var pick=projection.pick_ground_top(ray.from,ray.to)
			check(not hit.is_empty() and hit.position.distance_to(sample.position)<0.001,"generated physics/floor agree")
			check(not pick.is_empty() and pick.world.distance_to(sample.position)<0.001,"generated brush/floor agree")
		if version<2:scene._unhandled_input(keyboard)
	check(detail.heights==before,"comparison leaves generated source unchanged")
	scene.queue_free();await process_frame
	print("CARTOON_GENERATED ","PASS" if errors.is_empty() else "FAIL"," changed_columns=",changed," max_offset_m=",float(max_dry)/16.0," ",errors)
	quit(0 if errors.is_empty() else 1)
