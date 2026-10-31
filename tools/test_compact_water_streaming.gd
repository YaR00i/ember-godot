extends SceneTree
## Same request/prepare/commit seam as the real startup participant. Optional
## --regions-script=<frozen old owner> reproduces the former whole-world batch.
const Regions=preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Extent=preload("res://tools/test_water_runtime_extent.gd")
var failures:Array[String]=[]
var records:Array=[]
var fields:RefCounted
var legacy:=false
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func select(point:Vector2)->void:
	if fields.has_method("configure_preparation"):
		fields.configure_preparation(true,PackedVector2Array([point]),768.0,1600.0,128.0)
func batch()->bool:
	var deadline:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline:
		if fields.prepare() and fields.gpu_ready():
			fields.commit()
			records.append(fields.stats.duplicate())
			return true
		await process_frame
	check(false,"water batch deadline")
	return false
func ready()->bool:
	return fields.required_ready() if fields.has_method("required_ready") else fields.ready
func settle()->void:
	for i in 8:
		if ready():return
		if not await batch():return
	check(ready(),"required water must eventually become ready")
func part(size:Vector2i)->Terrain:
	var result:=Extent.DenseGuard.new();result.width=size.x;result.depth=size.y;result.height_limit=32
	result.palette=PackedColorArray([Color.TRANSPARENT,Color.SANDY_BROWN,Color.SKY_BLUE])
	for channel in preload("res://scripts/prototypes/ember_terrain_sections.gd").CHANNELS:
		var values=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(size.x*size.y);result.set(channel,values)
	for z in size.y:
		for x in size.x:
			var i:=x+z*size.x
			result.heights[i]=4 if z<160 else 9
			result.top_materials[i]=1;result.base_materials[i]=1;result.cap_depths[i]=1
			if z<160:result.water_levels[i]=8;result.water_materials[i]=2
	return result

func run()->void:
	var script:Script=Regions
	for argument in OS.get_cmdline_args()+OS.get_cmdline_user_args():
		if argument.begins_with("--regions-script="):
			script=load(argument.trim_prefix("--regions-script="));legacy=true
	fields=script.new();fields.cache_directory=""
	var source:=Extent.DenseGuard.new();source.schema_version=Terrain.SECTION_SCHEMA_VERSION
	source.width=9216;source.depth=9216;source.height_limit=32
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.SANDY_BROWN,Color.SKY_BLUE])
	# Three required wet cores at the actual 24th-section boundary. The distant
	# sea and isolated inland lake remain part of GLOBAL connectivity, not startup.
	for key in [Vector2i(21,23),Vector2i(22,23),Vector2i(23,23),Vector2i.ZERO,Vector2i(12,12)]:
		source.sections[key]=part(Vector2i(384,384))
	var dry:Terrain=part(Vector2i(384,384));dry.water_materials.fill(0);dry.water_levels.fill(0)
	source.sections[Vector2i(5,5)]=dry
	check(source.validation_errors().is_empty(),"sparse large wet/dry fixture validates: "+str(source.validation_errors()))
	var start:=Vector2(22.5*384,23*384+150)
	select(start);fields.request(source,1)
	check(not ready(),"unprepared required water cannot permit startup")
	var cold:=Time.get_ticks_msec()
	await batch()
	check(fields.regions.size()==2,"first publication contains two fields, not the whole map")
	check(not ready(),"first partial publication cannot fake startup readiness")
	check(not fields.regions.has(Vector2i(5,5)),"dry distant region creates no dense field")
	if legacy:
		fields.close();print("WATER_STREAMING_RED ",JSON.stringify({"pass":failures.is_empty(),"failures":failures,"first_batch":records}));quit(1);return
	await settle()
	var cold_ms:=Time.get_ticks_msec()-cold
	check(fields.regions.size()==3 and fields.stats.required_regions==3,"only three necessary wet regions satisfy 48m startup")
	check(not fields.regions.has(Vector2i.ZERO) and not fields.regions.has(Vector2i(12,12)),"far sea/lake is not densely preloaded")
	var seam:=Vector2i(23*384,23*384+155)
	var a:Dictionary=fields.regions[Vector2i(22,23)]
	var b:Dictionary=fields.regions[Vector2i(23,23)]
	for entry:Dictionary in [a,b]:entry.sea.advance(1.5,2.8,8.0,10.0,-0.35,6.0)
	var left:Dictionary=a.sea.sample(seam-a.window.position,false)
	var right:Dictionary=b.sea.sample(seam-b.window.position,false)
	check(not left.is_empty() and not right.is_empty() and absf(left.height-right.height)<0.0002,"incremental publication preserves the real last-section sea seam")
	check(fields.sample(Vector2i(9216,8990),false).is_empty(),"missing outer halo stays absent")
	var shader:=Shader.new();shader.code="shader_type spatial; uniform float shore_field_available=0.0;"
	var material:=ShaderMaterial.new();material.shader=shader
	fields.bind(material,null,Vector2.ZERO)
	check(material.get_shader_parameter("shore_field_available")==null or material.get_shader_parameter("shore_field_available")==0.0,"far base retains existing no-field fallback")
	check(b.water.get_shader_parameter("shore_field_available")==1.0,"prepared near material enables its real shore field")
	# Arrival invalidates readiness; release and return cannot rely on stale checks.
	select(Vector2(100,150));check(not ready(),"arrival waits for its actual fields")
	await settle();check(fields.regions.size()==1 and fields.regions.has(Vector2i.ZERO),"departed wet fields are released")
	select(Vector2(12*384+150,12*384+150));await settle()
	check(fields.regions.size()==1 and fields.sample(Vector2i(12*384+150,12*384+150),false).is_empty(),"interior sparse lake never becomes ocean")
	select(start);await settle();check(fields.regions.size()==3,"return reconstructs required released fields")
	# Cancel an in-flight arrival by changing the observer, then an author edit.
	select(Vector2(100,150));fields.prepare();select(start)
	check(fields.cancelled(),"departed in-flight preparation is cancelled")
	var edited:=source.working_copy()
	for key:Vector2i in edited.sections:
		var part:Terrain=edited.sections[key].working_copy();part.water_materials.fill(0);part.water_levels.fill(0);edited.sections[key]=part
	fields.request(edited,2);check(not ready(),"new revision cannot inherit old readiness")
	await settle()
	check(fields.regions.is_empty() and fields.stats.required_regions==0,"dry edited world publishes no dense fields")
	check(fields.source==fields._document and fields._committed_revision==2,"stale worker never publishes the old source")
	check(source.sections[Vector2i.ZERO].water_materials.count(2)>0,"author source stays unchanged")
	fields.close()
	print("WATER_STREAMING ",JSON.stringify({"pass":failures.is_empty(),"failures":failures,"cold_required_ms":cold_ms,"required_wet":3,"batches":records}))
	quit(0 if failures.is_empty() else 1)
