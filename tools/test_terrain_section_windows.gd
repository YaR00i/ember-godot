extends SceneTree
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
var errors:Array[String]=[]
var templates:Array=[]
func check(ok:bool,why:String)->void:
	if not ok:errors.append(why);push_error(why)
func _initialize()->void:run.call_deferred()
func part(height:int)->Resource:
	var result:=Terrain.new();result.width=384;result.depth=384;result.height_limit=128
	result.palette=PackedColorArray([Color.TRANSPARENT,Color.BROWN,Color.GREEN])
	for channel in Terrain.Sections.CHANNELS:
		var values=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(384*384);values.fill(height if channel=="heights" else 2 if channel=="top_materials" else 1 if channel=="base_materials" else 3 if channel=="cap_depths" else 0)
		result.set(channel,values)
	return result
func world(axis:int)->Resource:
	var result:=Terrain.new();result.schema_version=2;result.width=axis*384;result.depth=axis*384;result.height_limit=128;result.palette=templates[0].palette
	for z in axis:
		for x in axis:result.sections[Vector2i(x,z)]=templates[(x+z)%templates.size()]
	return result
func compare_window(source:Resource,bounds:Rect2i)->void:
	var window:Resource=source.dense_window(bounds)
	for z in bounds.size.y:
		for x in bounds.size.x:
			var at:=bounds.position+Vector2i(x,z)
			for channel in Terrain.Sections.CHANNELS:
				var expected:int=source.column_value(channel,source.column_index(at.x,at.y)) if source.has_column(at.x,at.y) else 0
				check(window.get(channel)[x+z*bounds.size.x]==expected,"addressed window preserves "+channel)
func run()->void:
	for height in [24,28,32,36]:templates.append(part(height))
	var timings:Array=[]
	for axis in [3,6,12,24]:
		var source:Resource=world(axis)
		check(source.validation_errors().is_empty(),"sectioned data extent admitted: "+str(axis*24))
		for bounds in [Rect2i(-7,-9,40,40),Rect2i(370,372,34,36),Rect2i(source.width-38,source.depth-40,49,47)]:
			check(Terrain.Sections.overlapping_sections(source,bounds).size()<=4,"one tile halo only addresses intersecting sections")
			compare_window(source,bounds)
		var began:=Time.get_ticks_usec()
		for i in 40:source.dense_window(Rect2i(140,150,86,86))
		timings.append({"side_m":axis*24,"window_mean_us":(Time.get_ticks_usec()-began)/40.0,"addressed_parts":Terrain.Sections.overlapping_sections(source,Rect2i(140,150,86,86)).size()})
	var large:Resource=world(24)
	large.sections.erase(Vector2i(1,1));compare_window(large,Rect2i(370,372,34,36))
	templates[3].water_flow.resize(24*24);templates[3].water_flow.fill(Vector2(0.3,0.2))
	var flow:Resource=large.dense_window(Rect2i(352,352,64,64))
	for z in 4:
		for x in 4:check(flow.flow_at_cell(x*16,z*16)==large.flow_at_cell(352+x*16,352+z*16),"aligned flow semantics unchanged")
	var invalid:Resource=world(25)
	check(not invalid.validation_errors().is_empty(),"data beyond measured576m remains rejected")
	check(large.validation_errors().is_empty(),"shared payload validates")
	templates[0].heights[0]=999
	check(not large.validation_errors().is_empty(),"validation never caches across calls")
	templates[0].heights[0]=24
	var baseline:Resource=large.working_copy()
	var history:=UndoRedo.new();history.create_action("section edit")
	history.add_do_method(large.write_columns.bind(PackedInt32Array([0]),PackedInt32Array([42]),PackedByteArray([2]),PackedInt32Array([0]),PackedByteArray([0])))
	history.add_undo_method(large.write_columns.bind(PackedInt32Array([0]),PackedInt32Array([24]),PackedByteArray([2]),PackedInt32Array([0]),PackedByteArray([0])))
	history.commit_action()
	check(large.column_value("heights",0)==42 and baseline.column_value("heights",0)==24 and large.column_value("heights",large.column_index(4*384,0))==24,"local edit does not mutate another alias or baseline")
	history.undo();check(large.same_terrain_data(baseline),"Undo restores data")
	history.redo();check(large.column_value("heights",0)==42,"Redo applies data")
	check(ResourceSaver.save(large,"user://section_window_576.res",ResourceSaver.FLAG_COMPRESS)==OK,"576m resource save")
	var reopened:Resource=ResourceLoader.load("user://section_window_576.res","",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened!=null and reopened.same_terrain_data(large) and reopened.validation_errors().is_empty(),"576m save/reopen exact")
	large=baseline.working_copy();check(large.column_value("heights",0)==24,"discard preserves baseline")
	history.free()
	print("TERRAIN_SECTION_WINDOWS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"timings":timings}))
	quit(0 if errors.is_empty() else 1)
