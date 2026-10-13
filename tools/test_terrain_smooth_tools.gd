extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Brush=preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const Parameters=preload("res://addons/ember_import/ember_world_brush_parameters.gd")
const Map=preload("res://scripts/ember_map_loader.gd")
var errors: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func settle(projection) -> bool:
	var deadline:=Time.get_ticks_msec()+60000
	while projection.pending_tile_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	await physics_frame;await physics_frame;await process_frame
	return projection.pending_tile_count()==0
func covered(source,channel: String) -> PackedInt32Array:
	var values:=PackedInt32Array();values.resize(source.width*source.depth)
	for i in values.size():values[i]=source.column_value(channel,i)
	return values
func run() -> void:
	var base:=Fixture.base();var detail:=Fixture.detailed(base)
	check(base.validation_errors().is_empty() and detail.validation_errors().is_empty(),"hand-authored fixtures")
	for channel: String in ["top_materials","base_materials","cap_depths","water_levels","water_materials"]:
		check(base.get(channel)==detail.get(channel),"new brush preserves "+channel)
	check(base.heights!=detail.heights,"material-aware brush adds physical shape")
	check(Fixture.detailed(base).same_terrain_data(detail),"seed repeatability")
	var role_changes: Dictionary={}
	for i in base.heights.size():
		var role:=base.surface_role_for_palette(base.top_materials[i])
		role_changes[role]=int(role_changes.get(role,0))+int(base.heights[i]!=detail.heights[i])
	check(role_changes.get("stone",0)>100 and role_changes.get("sand",0)>100,"stone and sand distinct physical details")
	check(Parameters.active_for("generator",true,false,true,true).has("detail_pattern") and not Parameters.active_for("generator",true,false,true,true).has("detail"),"material detail controls use shared catalogue")
	check(not Parameters.active_for("generator",false,false,true).has("detail_pattern"),"volumetric controls unchanged")
	var map:=Map.new();map.hydrate_legacy_regions=false;map.map_id="smooth-tools-test"
	map.imported_tile_size=1.0;map.compact_ground_style=1;map.compact_terrain=base.working_copy();root.add_child(map)
	var projection=map._visual_surface_projection
	projection.runtime_geometry_cache_enabled=false
	check(await settle(projection),"initial smooth projection")
	var original:=map.compact_terrain.working_copy()
	map.compact_ground_style=0;check(await settle(projection),"voxel view");check(map.compact_terrain.same_terrain_data(original),"voxel switch preserves hand work")
	map.compact_ground_style=1;check(await settle(projection),"smooth view");check(map.compact_terrain.same_terrain_data(original),"smooth switch preserves hand work")
	var history:=UndoRedo.new();var brush:=Brush.new()
	for mode: String in ["raise","lower","smooth","level","generator","paint","water","dry"]:
		var source:=base.working_copy()
		if mode=="smooth":source.heights[66+72*128]+=24
		if mode=="dry":source.water_levels.fill(80);source.water_materials.fill(5)
		map.compact_terrain=source;await settle(projection)
		var before:=source.working_copy();brush.configure({"resource":source,"target":weakref(map)},history,map)
		check(brush.begin(mode,0.8,8,1 if mode=="paint" else 5,80,16,3,71,0,40 if mode=="level" else -99999),"existing tool begin "+mode)
		brush.stamp(Vector2i(66,72));brush.end();check(await settle(projection),"existing tool remesh "+mode)
		check(not source.same_terrain_data(before),"existing tool changes "+mode)
		var after:=source.working_copy()
		history.undo();check(await settle(projection) and source.same_terrain_data(before),"existing tool Undo "+mode)
		history.redo();check(await settle(projection) and source.same_terrain_data(after),"existing tool Redo "+mode)
		var at:=projection.to_global(Vector3(66.25,0,72.25))
		var floor_sample: Dictionary=projection.floor_surface_sample(at)
		var from:=at+Vector3.UP*20.0;var to:=at-Vector3.UP*20.0
		var hit:=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to))
		check(not hit.is_empty() and hit.position.distance_to(floor_sample.position)<0.001,"physical smooth floor "+mode)
		var pick: Dictionary=projection.pick_ground_top(from,to)
		check(not pick.is_empty() and pick.world.distance_to(floor_sample.position)<0.001,"existing brush pick "+mode)
	# All authoring strides keep delta quantisation and dense/section parity.
	for scale: String in ["coarse","medium","detail"]:
		for step: int in [4,8] if scale!="detail" else [1]:
			var dense:=base.working_copy();var sectioned:=base.sectioned_copy()
			for source in [dense,sectioned]:
				var before: EmberTerrainPilotResource=source.working_copy();var owner:=Map.new();owner.compact_terrain=source
				var undo:=UndoRedo.new();var tool:=Brush.new();tool.configure({"resource":source,"target":weakref(owner)},undo,owner)
				check(tool.begin("generator",1.8,24,2,0,16,0,731,0,-99999,scale,"square",step,true),"material stride begin")
				tool.stamp(Vector2i(92,84),Rect2i(64,64,48,48))
				var once:=covered(source,"heights");tool.stamp(Vector2i(92,84),Rect2i(64,64,48,48));check(once==covered(source,"heights"),"same stamp does not accumulate")
				tool.end();var saved: EmberTerrainPilotResource=source.working_copy()
				for i in once.size():
					var delta:=once[i]-base.heights[i]
					check(delta%step==0,"authoring step preserved")
					if not Rect2i(64,64,48,48).has_point(Vector2i(i%128,i/128)):check(delta==0,"selected area preserved")
				check(covered(source,"top_materials")==covered(base,"top_materials"),"painted coverings preserved at each stride")
				undo.undo();check(source.same_terrain_data(before),"material stroke Undo")
				undo.redo();check(source.same_terrain_data(saved),"material stroke Redo")
				undo.free();owner.free()
			check(covered(dense,"heights")==covered(sectioned,"heights"),"dense/section detail parity")
	# Underwater ground and holes stay untouched; shape can be carved down.
	for direction: int in [1,-1]:
		var source:=base.working_copy();source.water_levels[92+84*128]=80;source.water_materials[92+84*128]=5
		source.heights[91+83*128]=0;source.top_materials[91+83*128]=0;source.cap_depths[91+83*128]=0
		var before:=source.working_copy();var owner:=Map.new();owner.compact_terrain=source
		var undo:=UndoRedo.new();var tool:=Brush.new();tool.configure({"resource":source,"target":weakref(owner)},undo,owner)
		tool.begin("generator",1.8,12,2,0,16,0,731,direction,-99999,"detail","circle",1,true);tool.stamp(Vector2i(92,84));tool.end()
		check(source.heights[92+84*128]==before.heights[92+84*128] and source.heights[91+83*128]==0,"underwater/hole preserved")
		for i in source.heights.size():check(source.heights[i]>=before.heights[i] if direction==1 else source.heights[i]<=before.heights[i],"direction respected")
		undo.free();owner.free()
	map.compact_terrain=detail.working_copy();check(await settle(projection),"final detail")
	check(projection.save_document("user://smooth-tools-reopen.res")==OK and projection.reopen_document("user://smooth-tools-reopen.res"),"Save/Reopen")
	check(await settle(projection) and projection.document.same_terrain_data(detail),"saved detail and hand work")
	history.free();map.queue_free();await process_frame
	print("SMOOTH_TOOLS ","PASS" if errors.is_empty() else "FAIL"," existing8/material/strides/dense-sectioned/physics/pick/Undo/Save changes=",role_changes," ",errors)
	quit(0 if errors.is_empty() else 1)
