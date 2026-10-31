@tool
extends EditorPlugin
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Mesher=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Cache=preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
var errors:Array[String]=[]
var directory:="user://ember-tests/editor-surface-%d"%OS.get_process_id()
func _enter_tree()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("EDITOR_SURFACE_FAIL ",label)
func frame()->void:await get_tree().process_frame
func fixture(width:int)->Resource:
	var source:=Terrain.new();source.width=width;source.depth=128;source.height_limit=128
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.GREEN,Color.BROWN,Color.BLUE])
	source.palette_surface_roles=PackedStringArray(["","grass","soil",""])
	source.palette_material_ids=PackedStringArray(["","cartoon_grass","cartoon_soil",""])
	for channel in Terrain.Sections.CHANNELS:
		var data:Variant=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray();data.resize(width*128)
		data.fill(32 if channel=="heights" else 1 if channel=="top_materials" else 2 if channel=="base_materials" else 3 if channel=="cap_depths" else 0);source.set(channel,data)
	for y in 128:
		for x in width:
			var i:=x+y*width;source.heights[i]+=int(sin(x*0.19)*4+cos(y*0.13)*3)
			if x%17<5:source.top_materials[i]=2
			if x>width/2:source.water_levels[i]=39;source.water_materials[i]=3
	return source
func open(source:Resource)->Node:
	var projection:=TerrainProjection.new();projection.ground_style=1;projection.smooth_material_blend_enabled=true
	# This fixture compares full-detail publication; the saved editor camera
	# must not downgrade it mid-check. Residency has its own focused checks.
	projection.detail_policy.enabled=false
	projection.runtime_geometry_cache_directory=directory;projection.water_mesh_step=8;projection.water_volume_sides=true
	get_tree().root.add_child(projection);check(projection.open_document(source),"fixture opens")
	check(projection._publication_budget_us()==12000,"initial opening uses bounded startup budget")
	await settle(projection)
	check(projection._publication_budget_us()==4000,"settled projection restores interactive budget")
	return projection
func settle(projection:Node)->void:
	var deadline:=Time.get_ticks_msec()+30000
	while projection.pending_tile_count()>0:
		if Time.get_ticks_msec()>deadline:check(false,"fixture settles");return
		await frame()
func snapshot(projection:Node)->Dictionary:
	var result:Dictionary={}
	for key in projection._tiles:
		var tile:Node=projection._tiles[key]
		result[key]=[Cache.mesh_arrays(tile.get_node("Ground").mesh),Cache.mesh_arrays(tile.get_node("Water").mesh),tile.get_node("GroundPhysics/Shape").shape.get_faces(),projection._smooth_fields.get(key,{}),projection._editor_surface_layouts.get(key,{})]
	return result
func mesh_equivalent(actual:Array,expected:Array)->bool:
	if actual.size()!=expected.size():return false
	for channel in actual.size():
		if actual[channel]==expected[channel]:continue
		# Removing a redundant GPU pack keeps exact CPU vertices/UV/colours.
		# Legacy packed normals/tangents differ by at most one quantization step.
		if channel not in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT] or actual[channel].size()!=expected[channel].size():return false
		for i in actual[channel].size():
			var difference:float=(actual[channel][i]-expected[channel][i]).length() if channel==Mesh.ARRAY_NORMAL else absf(actual[channel][i]-expected[channel][i])
			if difference>0.0001:return false
	return true
func equivalent(actual:Dictionary,expected:Dictionary)->bool:
	if actual.size()!=expected.size():return false
	for key in expected:
		if not actual.has(key):return false
		if not mesh_equivalent(actual[key][0],expected[key][0]) or not mesh_equivalent(actual[key][1],expected[key][1]):return false
		for channel in [2,3,4]:
			if actual[key][channel]!=expected[key][channel]:return false
	return true
func looks(projection:Node)->Dictionary:
	var result:Dictionary={}
	for look in [0,1,2,0]:
		projection.set_world_look(look)
		var deadline:=Time.get_ticks_msec()+30000
		while not projection._look_pending.is_empty() and Time.get_ticks_msec()<deadline:await frame()
		var geometry:Dictionary={}
		for key in projection._tiles:
			geometry[key]=Cache.mesh_arrays(projection._tiles[key].get_node("Ground").mesh)
		result[look]=geometry
	return result
func run()->void:
	if not ProjectSettings.globalize_path("res://").contains("ember-rock-pilot-6e8b1bee"):return
	Engine.max_fps=60;OS.low_processor_usage_mode=false
	var guard:=TerrainProjection.new();guard._startup_budget_allowed=true
	guard.begin_live_brush();check(guard._publication_budget_us()==4000,"brush interrupts startup budget")
	guard.end_live_brush();check(guard._publication_budget_us()==4000,"release cannot restore startup budget")
	guard.free()
	var report:Dictionary={}
	for sectioned in [false,true]:
		var source:Resource=fixture(448 if sectioned else 128)
		if sectioned:source=source.sectioned_copy()
		var expected:Dictionary={}
		for key:Vector2i in source.tile_keys(64):
			var built:Dictionary=Mesher.build_tile(source,key.x*64,key.y*64,64,8,true,PackedVector4Array(),{},false,false,true,true)
			expected[key]=[Cache.mesh_arrays(built.terrain),Cache.mesh_arrays(built.water),built.collision_faces,built.smooth_field,built.smooth_layout]
		var cold:Node=await open(source);var cold_data:=snapshot(cold);var cold_profile:Dictionary=cold.profile_snapshot()
		check(cold_profile.get("editor_prepare_jobs",0)>0,"cold CPU worker "+str(sectioned))
		check(cold_profile.get("editor_publication_steps",0)>0,"bounded publication phases "+str(sectioned))
		check(cold_profile.get("editor_prepare_us",0)>0,"workers complete without early script failure "+str(sectioned))
		check(equivalent(cold_data,expected),"cold vertices/UV/colours/collision/field/layout exact; packed normal tolerance "+str(sectioned))
		var cold_looks:Dictionary=await looks(cold)
		cold.free();await frame()
		var warm:Node=await open(source);var warm_profile:Dictionary=warm.profile_snapshot()
		check(warm_profile.get("editor_surface_cache_hits",0)==expected.size(),"warm prepared cache "+str(sectioned))
		check(equivalent(snapshot(warm),expected),"warm vertices/UV/collision/field/layout exact; packed normal tolerance "+str(sectioned))
		check(await looks(warm)==cold_looks,"three cached looks exact "+str(sectioned))
		report[str(sectioned)]={"cold":cold_profile,"warm":warm_profile}
		var i:int=source.column_index(30,30)
		warm.apply_columns(PackedInt32Array([i]),PackedInt32Array([40]),PackedByteArray([2]),PackedInt32Array([0]),PackedByteArray([0]));await frame()
		var old_visible:=snapshot(warm)
		var job_deadline:=Time.get_ticks_msec()+5000
		var staged:=false
		while Time.get_ticks_msec()<job_deadline and not staged:
			for record:Dictionary in warm._editor_surface_jobs.values():
				staged=staged or record.has("publication")
			if not staged:await frame()
		check(staged,"new edit overlaps an uncommitted publication "+str(sectioned))
		check(snapshot(warm)==old_visible,"partial publication stays invisible with old collision/field "+str(sectioned))
		warm.apply_columns(PackedInt32Array([i]),PackedInt32Array([35]),PackedByteArray([1]),PackedInt32Array([0]),PackedByteArray([0]));await settle(warm)
		var actual:=snapshot(warm)
		for key in actual:
			var built:Dictionary=Mesher.build_tile(warm.document,key.x*64,key.y*64,64,8,true,PackedVector4Array(),{},false,false,true,true)
			check(mesh_equivalent(actual[key][0],Cache.mesh_arrays(built.terrain)) and actual[key][2]==built.collision_faces,"latest edit wins "+str(sectioned)+str(key))
		warm.begin_live_brush()
		var before_builds:int=warm.profile_snapshot().tile_builds
		var visible_during_stroke:=false
		var live_started:=Time.get_ticks_msec();var step:=0
		while Time.get_ticks_msec()-live_started<2000 and not visible_during_stroke:
			warm.apply_columns(PackedInt32Array([i]),PackedInt32Array([36+step%24]),PackedByteArray([2]),PackedInt32Array([0]),PackedByteArray([0]))
			await frame()
			visible_during_stroke=visible_during_stroke or warm.profile_snapshot().tile_builds>before_builds
			step+=1
		report[str(sectioned)].live={"visible_before_release":visible_during_stroke,"first_update_ms":Time.get_ticks_msec()-live_started,"inputs":step}
		check(visible_during_stroke,"continuous input publishes before release "+str(sectioned))
		warm.end_live_brush();await settle(warm)
		# Discard/open may arrive after uploads but before the atomic attachment.
		warm.apply_columns(PackedInt32Array([i]),PackedInt32Array([60]),PackedByteArray([1]),PackedInt32Array([0]),PackedByteArray([0]))
		staged=false;job_deadline=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<job_deadline and not staged:
			for record:Dictionary in warm._editor_surface_jobs.values():staged=staged or record.has("publication")
			if not staged:await frame()
		check(staged,"open overlaps prepared resources "+str(sectioned))
		check(warm.open_document(source),"open cancels partial publication "+str(sectioned));await settle(warm)
		check(equivalent(snapshot(warm),expected),"discarded prepared resources never attach "+str(sectioned))
		warm.free();await frame()
		if not sectioned:
			var cache:=Cache.new();cache.directory=directory;cache.disk.directory=directory
			var key:String=cache.tile_key(source,Vector2i.ZERO,0,["editor-top-v1",true],PackedVector4Array(),{})
			var malformed:Dictionary=cache.disk.read(key);check(not malformed.is_empty(),"prepared cache record exists")
			malformed.field.heights[0]=NAN;cache.disk.write(key,malformed,func():return false)
			var recovered:Node=await open(source)
			check(recovered.profile_snapshot().get("editor_surface_cache_invalid",0)>0 and equivalent(snapshot(recovered),expected),"invalid field cache safely recomputes exact surface")
			recovered.free();await frame()
	report.pass=errors.is_empty();report.errors=errors
	FileAccess.open("C:/Users/novos/Documents/Codex/2026-10-25/ember-terrain-publication-study/fixture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("EDITOR_SURFACE_PREPARATION ",JSON.stringify({"pass":report.pass,"errors":errors}));get_tree().quit(0 if report.pass else 1)
