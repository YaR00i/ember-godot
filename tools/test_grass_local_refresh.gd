extends SceneTree
const Patch=preload("res://scripts/ember_grass_patch.gd")
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
var errors:Array[String]=[]
var patches:Array[Node]=[]
var map:EmberMapLoader
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("GRASS_REFRESH_FAIL ",label)
func _initialize()->void:run.call_deferred()
func settle()->void:
	var deadline:=Time.get_ticks_msec()+30000
	var quiet:=0
	while Time.get_ticks_msec()<deadline:
		var busy:bool=map._visual_surface_projection.pending_tile_count()>0
		for p in patches:busy=busy or p._dirty or p._rebuilding
		quiet=0 if busy else quiet+1
		if quiet>=3:return
		await process_frame
	check(false,"scatter did not settle")
func run()->void:
	var source:=Terrain.new();source.width=256;source.depth=128;source.height_limit=192
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.GREEN,Color.TAN]);source.palette_surface_roles=PackedStringArray(["","grass","sand"]);source.palette_material_ids=PackedStringArray(["","cartoon_grass","cartoon_sand"])
	for channel in Terrain.Sections.CHANNELS:
		var values:Variant=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(source.width*source.depth);values.fill(24 if channel=="heights" else 1 if channel in ["top_materials","base_materials"] else 3 if channel=="cap_depths" else 0);source.set(channel,values)
	source=source.sectioned_copy()
	map=EmberMapLoader.new();map.name="Map";map.compact_terrain=source;map.compact_ground_style=1;map.world_look=0
	var props:=Node3D.new();props.name="Props";map.add_child(props)
	for y in 2:
		for x in 4:
			var p:=Patch.new();p.name="Patch_%d_%d"%[x,y];p.painted_only=true;p.density_cells={Vector2i(8,8):64};p.position=Vector3(x*64,0,y*64);props.add_child(p);patches.append(p)
	root.add_child(map);await settle()
	var before:Dictionary={};var transforms:Dictionary={}
	for p in patches:
		check(p._visual!=null and p._visual.multimesh.instance_count>0,"initial scatter "+str(p.name));before[p]=p.detail_generations+p.detail_disk_hits
		transforms[p]=p._visual.multimesh
	var projection=map._visual_surface_projection;var source_index:=source.column_index(32,32)
	projection.apply_columns(PackedInt32Array([source_index]),PackedInt32Array([25]),PackedByteArray([1]),PackedInt32Array([0]),PackedByteArray([0]))
	await settle()
	var rebuilt:Array[String]=[]
	for p in patches:
		if p.detail_generations+p.detail_disk_hits!=before[p]:rebuilt.append(str(p.name))
	check(not rebuilt.is_empty() and rebuilt.size()<=4,"local sculpt only refreshes nearby patches")
	for p in patches:
		if p.position.x>=128:check(p._visual.multimesh==transforms[p],"far scatter retained "+str(p.name))
	var after_sculpt:Dictionary={}
	for p in patches:after_sculpt[p]=p.detail_generations+p.detail_disk_hits
	var grid_before:int=projection.tile_revision(Vector2i.ZERO)
	var painted:=PackedInt32Array();var heights:=PackedInt32Array();var tops:=PackedByteArray();var waters:=PackedInt32Array();var colors:=PackedByteArray()
	for y in range(31,38):
		for x in range(31,38):
			var i:=source.column_index(x,y);painted.append(i);heights.append(projection.document.column_value("heights",i));tops.append(2);waters.append(0);colors.append(0)
	projection.apply_columns(painted,heights,tops,waters,colors);await settle()
	check(projection.tile_revision(Vector2i.ZERO)==grid_before,"paint retains brush-grid revision")
	check(patches[0].detail_generations+patches[0].detail_disk_hits>after_sculpt[patches[0]],"paint still refreshes local grass")
	check(patches[0]._visual.multimesh.instance_count==0,"grass no longer occupies repainted sand")
	for p in patches:
		if p.position.x>=128:check(p.detail_generations+p.detail_disk_hits==after_sculpt[p],"paint keeps distant patches")
	var before_reopen:Dictionary={}
	for p in patches:before_reopen[p]=p.detail_generations+p.detail_disk_hits
	var next:Resource=projection.document.working_copy();next.write_columns(PackedInt32Array([source_index]),PackedInt32Array([26]),PackedByteArray([2]),PackedInt32Array([0]),PackedByteArray([0]))
	check(projection.open_document(next),"same-size source restore opens");await settle()
	check(patches[0].detail_generations+patches[0].detail_disk_hits>before_reopen[patches[0]],"restore refreshes affected scatter")
	check(patches[3].detail_generations+patches[3].detail_disk_hits==before_reopen[patches[3]],"restore preserves distant scatter")
	var existing:Dictionary={}
	projection._surface_tile_revisions=PackedInt32Array()
	for p in patches:existing[p]=p._visual.multimesh;p._surface_stamp=[]
	await settle()
	for p in patches:check(p._visual.multimesh==existing[p],"empty tool cache initializes without rescatters")
	print("GRASS_LOCAL_REFRESH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"patches":patches.size(),"rebuilt":rebuilt}))
	map.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
