extends SceneTree
const Water=preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Regions=preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const Sections=preload("res://scripts/prototypes/ember_terrain_sections.gd")
class DenseGuard extends EmberTerrainPilotResource:
	static var windows:Array[Rect2i]=[]
	func dense_window(bounds:Rect2i)->EmberTerrainPilotResource:
		windows.append(bounds)
		assert(bounds.size.x<=Regions.SIZE+2*Regions.HALO and bounds.size.y<=Regions.SIZE+2*Regions.HALO,"whole-map water dense fallback")
		return super.dense_window(bounds)
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func part(size:Vector2i)->DenseGuard:
	var result:=DenseGuard.new();result.width=size.x;result.depth=size.y;result.height_limit=32
	result.palette=PackedColorArray([Color.TRANSPARENT,Color.SANDY_BROWN,Color.SKY_BLUE])
	for channel in Sections.CHANNELS:
		var values=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(size.x*size.y);result.set(channel,values)
	for z in size.y:
		for x in size.x:
			var i:=x+z*size.x
			result.heights[i]=4 if z<160 else 9
			result.top_materials[i]=1;result.base_materials[i]=1;result.cap_depths[i]=1
			if z<160:result.water_levels[i]=8;result.water_materials[i]=2
	return result
func _initialize()->void:run.call_deferred()
func run()->void:
	# Use the actual startup participant without loading or densifying a world.
	var host:=Node3D.new()
	var map:=EmberMapLoader.new();map.name="Map";host.add_child(map)
	var source:=DenseGuard.new();source.schema_version=Terrain.SECTION_SCHEMA_VERSION
	source.width=Sections.MAX_AXIS*Sections.CELLS;source.depth=source.width;source.height_limit=32
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.SANDY_BROWN,Color.SKY_BLUE])
	source.sections[Vector2i.ZERO]=part(Vector2i(16,16))
	source.sections[Vector2i(22,23)]=part(Vector2i(384,384))
	source.sections[Vector2i(23,23)]=part(Vector2i(384,384))
	check(source.validation_errors().is_empty(),"wet sectioned boundary fixture validates")
	map.compact_terrain=source
	var water:=Water.new();host.add_child(water)
	var status:Dictionary=water.startup_preparation_status()
	check(status.text=="Готовим берега и воду" and not status.ready,"576m startup enters real water preparation")
	check(water._study_document(source)==source,"compatibility view preserves sectioned source")
	for extent in [Vector2i(1,1),Vector2i(1152,1152),Vector2i(8448,8448),Vector2i(8832,8832),Vector2i(9216,9216)]:
		check(water.terrain_extent_error(extent).is_empty(),"supported extent "+str(extent))
	for extent in [Vector2i.ZERO,Vector2i(-1,384),Vector2i(9217,9216),Vector2i(9216,9217),Vector2i(9600,9600)]:
		check(not water.terrain_extent_error(extent).is_empty(),"invalid or oversized extent rejected "+str(extent))
	var invalid:=source.working_copy();invalid.sections[Vector2i(24,23)]=source.sections[Vector2i(23,23)]
	check(not invalid.validation_errors().is_empty(),"source owner still rejects an out-of-envelope payload")
	var fields:=Regions.new();fields.cache_directory=""
	fields.request(source,1)
	var deadline:=Time.get_ticks_msec()+30000
	while not fields.prepare() and Time.get_ticks_msec()<deadline:await process_frame
	check(fields.ready,"wet corner regional fields prepare")
	if fields.ready:
		fields.commit()
		check(fields.regions.size()==3,"only authored sections receive regions")
		check(fields.regions.has(Vector2i(23,23)),"24th region in both axes published")
		var last:Dictionary=fields.regions.get(Vector2i(23,23),{})
		if not last.is_empty():
			check(last.core.end==Vector2i(9216,9216),"last core reaches supported boundary")
			check(last.window.end==Vector2i(9312,9312),"outer halo safely extends beyond last core")
			var offset:=Vector2i(23*384,23*384)
			for point in [offset+Vector2i(0,150),offset+Vector2i(383,150),offset+Vector2i(20,159)]:
				check(not fields.sample(point,false).is_empty(),"real sea/shore query at "+str(point))
			check(fields.sample(Vector2i(9216,8990),false).is_empty(),"missing outer halo is not invented water")
			var seam:=Vector2i(23*384,23*384+155)
			var a:Dictionary=fields.regions[Vector2i(22,23)]
			var b:Dictionary=fields.regions[Vector2i(23,23)]
			a.sea.advance(1.5,2.8,8.0,10.0,-0.35,6.0)
			b.sea.advance(1.5,2.8,8.0,10.0,-0.35,6.0)
			var left:Dictionary=a.sea.sample(seam-a.window.position,false)
			var right:Dictionary=b.sea.sample(seam-b.window.position,false)
			check(not left.is_empty() and not right.is_empty() and absf(left.get("height",0.0)-right.get("height",1.0))<0.0002,"shared last-region halo has matching water height")
			water._water_regions=fields;water._prepared=true;water.obstacle_wave_mode=0
			check(water.startup_preparation_status().ready,"finished regional water permits startup readiness")
	check(DenseGuard.windows.size()==3,"worker requested only three bounded dense windows")
	for channel in Sections.CHANNELS:check(source.get(channel).is_empty(),"root channel remains sectioned: "+channel)
	check(source.sections.size()==3,"authored section count preserved")
	fields.close()
	print("WATER_RUNTIME_EXTENT ",JSON.stringify({"pass":failures.is_empty(),"failures":failures,"initial_status":status,"windows":str(DenseGuard.windows),"stats":fields.stats}))
	host.free()
	quit(0 if failures.is_empty() else 1)
