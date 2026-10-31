extends SceneTree
const Creation=preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Builder=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Cache=preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
const Policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd")
class ProbeProjection extends EmberTerrainPilotProjection:
	var restored:Array[Vector2i]=[]
	var restored_before_release:=true
	func _editor_residency_allowed()->bool:return true
	func _publish_overview(key:Vector2i,covered:Dictionary)->void:
		restored.append(key)
		for tile:Vector2i in _tiles:
			if _overview_section(tile)==key:restored_before_release=restored_before_release and not covered.has(tile)
		_overview_dirty.erase(key)
var errors:Array[String]=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("TRAVEL_PREP_FAIL ",label)
func run():
	var policy:=Policy.new();var resident:Dictionary={};var patches:Dictionary={};var missing:=0
	for x in range(264,305):
		policy.anchor=Vector2(x,264)*16
		resident=policy.ground_candidates(Vector2i.ONE*9216,64,1572864,resident,{})
		check(resident.size()<=384,"fine column budget remains bounded")
		var next:Dictionary={}
		for z in range(216,324,12):
			for px in range(216,360,12):
				var area:=Rect2(Vector2(px,z)*16,Vector2.ONE*64).grow(0.35*16)
				var id:=Vector2i(px,z)
				if not policy.detail_resident(area,patches.has(id)):continue
				next[id]=true
				for tz in range(floori(area.position.y/64),floori(area.end.y/64)+1):
					for tx in range(floori(area.position.x/64),floori(area.end.x/64)+1):
						if not resident.has(Vector2i(tx,tz)):missing+=1
		patches=next
	check(missing==0,"every retained painted footprint has preparing ground, including its far corners")
	var creator:=Creation.new();check(creator.prepare_sections("travel",2,1,24),"existing sectioned fixture")
	var source:Resource=creator.source.sectioned_copy()
	for x in [0,64,320,384,704]:
		var job:=Cache.new();job.directory=""
		var work=job.editor_job(source.working_copy(),Vector2i(x/64,0),true,{"step":8,"sides":true,"far_stride":1,"residency_edges":true})
		work.run(func():return false)
		check(not work.result.is_empty(),"worker prepares surface")
		var expected:=Builder.residency_edge_arrays(source,Rect2i(x,0,64,64),work.tile_data.smooth_field)
		check(work.tile_data.residency_edge_arrays==expected,"worker seam matches original global surface at %d"%x)
		var publication:=Builder.EditorTilePublication.new(work.tile_data)
		while not publication.ready:publication.advance()
		check(publication.result.collision.get_faces()==work.tile_data.collision_faces,"exact canonical physics retained")
		if x==0:
			var small=job.editor_job(source.working_copy(),Vector2i.ZERO,true,{"step":8,"sides":true,"far_stride":1})
			small.run(func():return false)
			check(small.tile_data.residency_edge_arrays.is_empty(),"small maps do not prepare unused residency seams")
			check(small.tile_data.collision_faces==work.tile_data.collision_faces,"seam opt-in cannot change physics")
	var projection:=ProbeProjection.new();root.add_child(projection);projection.set_process(false)
	projection.document=source;projection.ground_style=1;projection._reset_pending_flags()
	projection._startup_budget_allowed=false
	check(projection._publication_budget_us()==8000,"travel receives the shared eight ms allowance")
	projection._live_brush_active=true
	check(projection._publication_budget_us()==4000,"brush keeps its four ms interactive limit")
	projection._live_brush_active=false
	projection.detail_policy.anchor=Vector2.ONE*100000
	projection._overviews={Vector2i(0,0):{},Vector2i(1,0):{}}
	for x in 8:
		var tile:=Node3D.new();projection.add_child(tile);projection._tiles[Vector2i(x,0)]=tile
	projection._sync_ground_residency()
	check(projection.restored.is_empty() and projection._tiles.size()==8,"observer retains fine until budgeted replacement")
	projection._poll_overviews(Time.get_ticks_usec(),1000000)
	check(projection.restored.size()==2,"one overview publication per departed region")
	check(projection.restored_before_release,"each region closes its overview holes before releasing its fine tiles")
	check(projection._tiles.is_empty() and projection._resident_tiles.is_empty(),"departed fine tiles released")
	projection._overviews.clear();projection.free();await process_frame
	print("TRAVEL_PREPARATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
