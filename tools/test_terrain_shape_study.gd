extends SceneTree
const Fixture=preload("res://scripts/prototypes/ember_terrain_shape_fixture.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
var errors: Array[String]=[]
var measurements: Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func run() -> void:
	var source:=Fixture.source();var before:=source.working_copy()
	var legacy: GDScript
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		legacy=GDScript.new();legacy.source_code=FileAccess.get_file_as_string(args[0])
		check(legacy.reload()==OK,"frozen previous smoothing code loads")
	check(source.validation_errors().is_empty(),"fixture validation")
	var fields: Dictionary={};var original: Dictionary={}
	var started:=Time.get_ticks_usec()
	for z in 2:
		for x in 2:
			var key:=Vector2i(x,z);var bounds:=Rect2i(key*64,Vector2i(64,64))
			fields[key]=Smooth.controlled_field(source,bounds,Fixture.profile())
			original[key]=Smooth.field(source,bounds)
			check(original[key].heights==Smooth.field(source,bounds,3).heights,"legacy default remains exact")
			if legacy!=null:check(original[key].heights==legacy.field(source,bounds).heights,"default exact against previous slice code")
			var mesh:=Smooth.build(source,bounds,true,true,fields[key])
			check(mesh.collision_faces==mesh.terrain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"same rendered/physical triangles")
	measurements["four_tile_field_and_mesh_ms"]=(Time.get_ticks_usec()-started)/1000.0
	measurements["frozen_baseline_checked"]=legacy!=null
	var seam_error:=0.0;var normal_error:=0.0
	for i in range(1,128):
		var zkey:=0 if i<64 else 1;var xkey:=zkey
		seam_error=maxf(seam_error,absf(Smooth.corner(fields[Vector2i(0,zkey)],64,i)-Smooth.corner(fields[Vector2i(1,zkey)],64,i)))
		normal_error=maxf(normal_error,Smooth.normal(fields[Vector2i(0,zkey)],64,i).distance_to(Smooth.normal(fields[Vector2i(1,zkey)],64,i)))
		seam_error=maxf(seam_error,absf(Smooth.corner(fields[Vector2i(xkey,0)],i,64)-Smooth.corner(fields[Vector2i(xkey,1)],i,64)))
	measurements["max_height_seam_voxels"]=seam_error;measurements["max_normal_seam"]=normal_error
	check(seam_error<0.0001 and normal_error<0.0001,"tile height and normal continuity")
	# Inside the protected crown, preserve the actual 2.25m source plane even
	# next to its drop. Uniform weak filtering is the diagnostic alternative.
	var point:=Vector2(32.0,19.0)
	var baseline:=Smooth.sample(original[Vector2i.ZERO],point)/16.0
	var protected:=Smooth.sample(fields[Vector2i.ZERO],point)/16.0
	var weak:=Smooth.sample(Smooth.field(source,Rect2i(0,0,64,64),1),point)/16.0
	measurements["plateau_lip_m"]={"A":baseline,"B":protected,"C":weak,"source":2.25}
	check(absf(protected-2.25)<0.00001 and absf(baseline-2.25)>0.01,"protected plateau retains its plane near lip")
	var crest:=Vector2(92,60)
	var crest_a:=Smooth.sample(original[Vector2i(1,0)],crest)/16.0
	var crest_b:=Smooth.sample(fields[Vector2i(1,0)],crest)/16.0
	measurements["crest_m"]={"A":crest_a,"B":crest_b}
	check(crest_b>crest_a+0.06,"protected ridge retains source-scale break")
	var material_copy:=source.working_copy();material_copy.top_materials.fill(3)
	check(Smooth.controlled_field(material_copy,Rect2i(0,0,64,64),Fixture.profile()).heights==fields[Vector2i.ZERO].heights,"shape independent of material")
	var profile:=Fixture.profile(0.0,1,false,false)
	var flat:=Smooth.controlled_field(source,Rect2i(0,0,64,64),profile)
	check(is_equal_approx(Smooth.corner(flat,32,19),36.0),"zero strength preserves source corner plane")
	var job:=Smooth.FieldJob.new(source,Rect2i(0,0,64,64),3,Fixture.profile())
	while not job.finished:job.step(100)
	check(job.result.heights==fields[Vector2i.ZERO].heights,"budgeted and direct math exact")
	check(source.same_terrain_data(before),"derived fields never mutate Source")
	var path:="user://ember-tests/shape-source.res";DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(ResourceSaver.save(source,path)==OK,"ordinary Source save")
	var restored=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.same_terrain_data(source),"Source reopen exact, no shape metadata")
	var file:=FileAccess.open("user://shape-test.json",FileAccess.WRITE);file.store_string(JSON.stringify(measurements,"\t"));file.close()
	print("TERRAIN_SHAPE_METRICS ",JSON.stringify(measurements))
	print("TERRAIN_SHAPE_TEST ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
