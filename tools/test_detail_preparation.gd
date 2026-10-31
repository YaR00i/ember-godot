extends SceneTree
const Patch = preload("res://scripts/ember_grass_patch.gd")
const Preparation = preload("res://scripts/ember_detail_preparation.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
class SlowRead extends "res://scripts/prototypes/ember_derived_data_cache.gd":
	func read(key:String)->Dictionary:
		OS.delay_msec(80)
		return super.read(key)
class ProbePatch extends "res://scripts/ember_grass_patch.gd":
	var endpoint_mesh_requests:=0
	var outside_signature_calls:=0
	func _surface_signature(projection:Node3D)->Array:
		if not Preparation.for_projection(projection).in_budget_turn():outside_signature_calls+=1
		return super._surface_signature(projection)
	func prepared_coloured_look_mesh(look:int,slot:int)->ArrayMesh:
		if look!=0:endpoint_mesh_requests+=1
		return super.prepared_coloured_look_mesh(look,slot)
var errors: Array[String] = []
var map: EmberMapLoader
var patches: Array[Node] = []
var source: Resource
var mask := {Vector2i(8,8):160.0,Vector2i(9,8):120}
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label); printerr("DETAIL_PREPARATION_FAIL ",label)
func settle() -> void:
	var deadline := Time.get_ticks_msec()+30000
	var quiet := 0
	while Time.get_ticks_msec()<deadline:
		var busy: bool = map._visual_surface_projection.pending_tile_count()>0 or not map._visual_surface_projection._look_pending.is_empty()
		for patch in patches: busy=busy or patch._dirty or patch._rebuilding
		quiet=0 if busy else quiet+1
		if quiet>=3: return
		await process_frame
	check(false,"preparation settles")
func open_map() -> void:
	map=EmberMapLoader.new(); map.name="Map"; map.compact_terrain=source.working_copy(); map.compact_ground_style=1
	var props:=Node3D.new(); props.name="Props"; map.add_child(props); patches=[]
	for i in 4:
		var patch:=ProbePatch.new(); patch.name="Patch%d"%i; patch.painted_only=true; patch.density_cells=mask.duplicate()
		patch.position=Vector3((i%2)*64,0,(i/2)*64); props.add_child(patch); patches.append(patch)
	root.add_child(map); await settle()
func buffers() -> Array:
	var result: Array=[]
	# The headless dummy renderer does not retain MultiMesh buffers. Compare
	# exact CPU transforms here; native Forward+ checks the uploaded buffers.
	for patch in patches: result.append(patch._detail_transform_cache[patch._look].duplicate())
	return result
func close_map() -> void:
	map.queue_free(); await process_frame; await process_frame
func run() -> void:
	Preparation.cache_root="user://ember-tests/detail-preparation-%d"%Time.get_ticks_usec()
	source=Terrain.new(); source.width=128; source.depth=128; source.height_limit=192
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.GREEN]); source.palette_surface_roles=PackedStringArray(["","grass"]); source.palette_material_ids=PackedStringArray(["","cartoon_grass"])
	for channel in Terrain.Sections.CHANNELS:
		var values: Variant=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(source.width*source.depth); values.fill(24 if channel=="heights" else 1 if channel in ["top_materials","base_materials"] else 3 if channel=="cap_depths" else 0); source.set(channel,values)
	source=source.sectioned_copy()
	await open_map()
	var expected: Dictionary={0:buffers()}
	for patch in patches:check(patch.outside_signature_calls==0,"cold surface signatures stay inside the shared preparation budget")
	for patch in patches: check(patch.detail_generations==1 and patch._visual.multimesh.instance_count>0,"cold generation")
	for look in [1,2,0]:
		for patch in patches: patch.set_world_look(look)
		await settle()
		if look==0: check(buffers()==expected[0],"look return exact")
		else: expected[look]=buffers()
	await close_map(); await open_map()
	for patch in patches: check(patch.detail_disk_hits==1 and patch.detail_generations==0,"fresh node uses disk scatter")
	for patch in patches:check(patch.endpoint_mesh_requests==0,"disk hit never prepares footprint endpoints")
	check(buffers()==expected[0],"reopen buffers byte exact")
	for look in [1,2,0]:
		for patch in patches: patch.set_world_look(look)
		await settle(); check(buffers()==expected[look],"cached look byte exact %d"%look)
	var p=patches[0]
	p.density_cells={Vector2i(8,8):0}; await settle(); check(p._visual.multimesh.instance_count==0,"mask change rejects old scatter")
	p.density_cells=mask.duplicate(); await settle(); check(buffers()==expected[0],"mask undo reuses exact scatter")
	var projection=map._visual_surface_projection
	var i: int=projection.document.column_index(32,32)
	projection.apply_columns(PackedInt32Array([i]),PackedInt32Array([28]),PackedByteArray([1]),PackedInt32Array([0]),PackedByteArray([0])); await settle()
	check(buffers()[0]!=expected[0][0],"surface change rejects persisted scatter")
	var after_surface: Array=buffers()[0]
	p.scatter_seed+=1; await settle(); check(buffers()[0]!=after_surface,"seed rejects old scatter")
	p.scatter_seed-=1; await settle(); check(buffers()[0]==after_surface,"seed undo restores exact scatter")
	p.tuft_size=1.25; await settle(); check(buffers()[0]!=after_surface,"size rejects old scatter")
	p.tuft_size=1.0; await settle(); check(buffers()[0]==after_surface,"size undo restores exact scatter")
	var full: Dictionary={}
	for y in 16:
		for x in 16: full[Vector2i(x,y)]=200.0
	p.density_cells=full; await process_frame; p.density_cells={Vector2i(8,8):0}; await settle()
	check(p._visual.multimesh.instance_count==0,"cancelled work cannot publish old mask")
	var context=Preparation.for_projection(projection)
	var bad:=Transform3D.IDENTITY; bad.origin.x=INF
	context.write("bad-finite",{0:[bad]},func():return false)
	context._finish_cache_writes(true)
	check(context.read("bad-finite").is_empty(),"non-finite cached transform rejected")
	context.disk.write("bad-type",{"looks":{0:[Vector3.ZERO]}},func():return false)
	check(context.read("bad-type").is_empty(),"wrong cached payload rejected")
	# Close actual GrassPatch coroutines while their read is still pending.
	# A generic host test alone cannot catch a stale rebuild resuming after exit.
	var slow:=SlowRead.new()
	for field:String in ["directory","magic","format_version","extension","max_bytes","packaged_directory","packaged_for_directory"]:slow.set(field,context.disk.get(field))
	context.disk=slow
	p._detail_transform_cache.clear();p._detail_cache_key=0;p._dirty=true
	var preview_read_deadline:=Time.get_ticks_msec()+5000
	while context._cache_reads.is_empty() and Time.get_ticks_msec()<preview_read_deadline:await process_frame
	map.compact_material_gray_preview=true
	p.set_material_light(map.compact_material_light_mode,true)
	await settle()
	check(p._visual.material_override.get_shader_parameter("material_gray_preview")==true,"material edit during cache IO survives publication")
	var generations_before_light:int=p.detail_generations
	map.compact_material_gray_preview=false;p.set_material_light(map.compact_material_light_mode,false)
	await settle()
	check(p.detail_generations==generations_before_light,"settled light edit does not regenerate scatter")
	p._dirty=true
	var role_deadline:=Time.get_ticks_msec()+5000
	while not p._material_role_binding and Time.get_ticks_msec()<role_deadline:await process_frame
	check(p._material_role_binding,"actual patch awaits saved material checks")
	var profile:=load("res://content/terrain_materials/cartoon_grass.tres").duplicate() as EmberCompactTerrainPattern
	profile.grass_light_low=0.73;p.refresh_shared_material(profile,"cartoon_grass")
	await settle()
	var light_image:Image=p._visual.material_override.get_meta("ember_grass_light_image")
	check(is_equal_approx(light_image.get_pixel(1,0).r,0.73),"material profile edit during role IO survives publication")
	p.refresh_shared_material()
	for patch in patches:
		patch._detail_transform_cache.clear();patch._detail_cache_key=0;patch._dirty=true
	var read_deadline:=Time.get_ticks_msec()+5000
	while context._cache_reads.is_empty() and Time.get_ticks_msec()<read_deadline:await process_frame
	check(not context._cache_reads.is_empty(),"actual patch has an in-flight cache read")
	await close_map()
	check(context._released and context._cache_reads.is_empty(),"map exit joins readers without late rebuilds")
	print("DETAIL_PREPARATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"hits":context.hits}))
	quit(0 if errors.is_empty() else 1)
