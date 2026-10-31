extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Patch=preload("res://scripts/ember_grass_patch.gd")
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class Foreground extends Patch:
 func _terrain_scatter_job(_projection:Node3D,_cells:Dictionary,_absolute:Vector2i,_unit:float,_seed:int,_size:float,_jitter:float,_variation:float,_yaw:float)->RefCounted:return null
class PhysicalCandidate extends Node3D:
 var authoring_preview:WeakRef
 var projection:Node3D
 var outside_budget:=0
 func record_budget()->void:
  if projection!=null and not Preparation.for_projection(projection).in_budget_turn():outside_budget+=1
 func surface_floor_bounds()->AABB:return AABB(Vector3.ONE*-1000,Vector3.ONE*2000)
 func surface_floor_sample(_point:Vector3)->Dictionary:
  record_budget();return {"solid":false}
class PartialCandidate extends PhysicalCandidate:
 var area:Rect2
 func surface_floor_bounds()->AABB:return AABB(Vector3(area.position.x,-1000,area.position.y),Vector3(area.size.x,2000,area.size.y))
 func surface_floor_sample(point:Vector3)->Dictionary:
  record_budget()
  if not area.has_point(Vector2(point.x,point.z)):return {"solid":false}
  return {"solid":true,"position":Vector3(point.x,500,point.z),"normal":Vector3.UP,"material_role":"grass","object":self}
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);printerr("DETAIL_WORKER_PARITY_FAIL ",label)
func _initialize():run.call_deferred()
func run():
 Engine.max_fps=0;OS.low_processor_usage_mode=false;OS.low_processor_usage_mode_sleep_usec=0
 if DisplayServer.get_name()!="headless":DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Preparation.cache_root=""
 var source=Fixture.detailed(Fixture.base())
 source.origin_y=7
 for z in range(48,56):
  for x in range(48,56):
   var index:int=source.column_index(x,z);source.heights[index]=0;source.cap_depths[index]=0
 for z in range(60,70):
  for x in range(60,70):source.water_levels[source.column_index(x,z)]=100
 source=source.sectioned_copy()
 check(source.validation_errors().is_empty(),"valid source fixture")
 if not errors.is_empty():quit(1);return
 var map:=EmberMapLoader.new();map.compact_terrain=source;map.compact_ground_style=1
 map.transform=Transform3D(Basis(Vector3.UP,0.3).scaled(Vector3(1.1,0.8,1.2)),Vector3(13,7,-9))
 var pairs:Array=[];var cells:Dictionary={}
 for z in 16:
  for x in 16:cells[Vector2i(x,z)]=64.0
 for case in 3:
  var pair:Array=[]
  for threaded in [false,true]:
   var patch=Patch.new() if threaded else Foreground.new()
   patch.painted_only=true;patch.scatter_seed=20261029;patch.density_cells=cells
   patch.detail_kind=3 if case==1 else 0;patch.detail_variation=0.4;patch.detail_jitter=0.9;patch.detail_yaw=180.0
   if case==1:patch.cover_pattern=load(preload("res://scripts/ember_flowered_grass.gd").PATTERN_PATH)
   check(patch.validation_errors().is_empty(),"valid detail fixture %d"%case)
   patch.transform=Transform3D(Basis(Vector3.UP,0.4).scaled(Vector3(0.8,1.0,0.9)),Vector3(24,0,24) if case<2 else Vector3(100,0,88))
   map.add_child(patch);pair.append(patch)
  pairs.append(pair)
 root.add_child(map)
 var deadline:=Time.get_ticks_msec()+90000
 while Time.get_ticks_msec()<deadline:
  var busy:bool=map._visual_surface_projection.pending_tile_count()>0
  for pair in pairs:
   for patch in pair:busy=busy or patch._dirty or patch._rebuilding
  if not busy:break
  await process_frame
 for i in pairs.size():
  var pair:Array=pairs[i]
  check(not pair[1]._rebuilding and not pair[1]._dirty,"worker settles %d"%i)
  for look in 3:
   check(pair[0]._detail_transform_cache.has(look) and pair[1]._detail_transform_cache.has(look),"both paths publish look %d/%d"%[i,look])
   check(var_to_bytes(pair[0]._detail_transform_cache.get(look,[]))==var_to_bytes(pair[1]._detail_transform_cache.get(look,[])),"byte-exact placement %d/%d"%[i,look])
 var context=Preparation.for_projection(map._visual_surface_projection)
 if context.terrain_jobs_started==0:
  print("WORKER_PARITY_FIXTURE ",{"source_errors":source.validation_errors(),"style":map.compact_ground_style,"pending":map._visual_surface_projection.pending_tile_count(),"ground_style":map._visual_surface_projection.ground_style,"sample_patch":{"dirty":pairs[0][1]._dirty,"rebuilding":pairs[0][1]._rebuilding,"resident":pairs[0][1]._detail_resident,"area":pairs[0][1]._world_area(),"document":map._visual_surface_projection.document!=null}})
 check(context.terrain_jobs_started>=3 and context._terrain_jobs.is_empty(),"worker path ran and admissions released")
 var jobs_before:int=context.terrain_jobs_started
 var physical:=PhysicalCandidate.new();physical.projection=map._visual_surface_projection;map.add_child(physical);physical.add_to_group(&"ember_solid_surface")
 for patch in pairs[0]:patch.scatter_seed+=1
 var fallback_deadline:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<fallback_deadline and (pairs[0][0]._dirty or pairs[0][0]._rebuilding or pairs[0][1]._dirty or pairs[0][1]._rebuilding):await process_frame
 check(context.terrain_jobs_started==jobs_before,"physical candidates retain the foreground query path")
 for look in 3:check(var_to_bytes(pairs[0][0]._detail_transform_cache[look])==var_to_bytes(pairs[0][1]._detail_transform_cache[look]),"physical candidate fallback stays exact %d"%look)
 physical.free()
 var partial:=PartialCandidate.new();partial.projection=map._visual_surface_projection;partial.area=pairs[0][0]._world_area();partial.area.size*=0.4
 map.add_child(partial);partial.add_to_group(&"ember_solid_surface")
 jobs_before=context.terrain_jobs_started
 for patch in pairs[0]:patch.scatter_seed+=1
 fallback_deadline=Time.get_ticks_msec()+20000
 while Time.get_ticks_msec()<fallback_deadline and (pairs[0][0]._dirty or pairs[0][0]._rebuilding or pairs[0][1]._dirty or pairs[0][1]._rebuilding):await process_frame
 check(context.terrain_jobs_started>jobs_before,"clear cells still use the worker when an object covers part of a patch")
 check(partial.outside_budget==0,"worker completion resumes foreground surface queries only inside the preparation budget")
 for look in 3:check(var_to_bytes(pairs[0][0]._detail_transform_cache[look])==var_to_bytes(pairs[0][1]._detail_transform_cache[look]),"mixed object/terrain placement and ordering stay byte exact %d"%look)
 var preview:=Node.new();map.add_child(preview);partial.authoring_preview=weakref(preview)
 jobs_before=context.terrain_jobs_started
 for patch in pairs[0]:patch.scatter_seed+=1
 fallback_deadline=Time.get_ticks_msec()+20000
 while Time.get_ticks_msec()<fallback_deadline and (pairs[0][0]._dirty or pairs[0][0]._rebuilding or pairs[0][1]._dirty or pairs[0][1]._rebuilding):await process_frame
 check(context.terrain_jobs_started==jobs_before,"live object previews keep the exact foreground path")
 for look in 3:check(var_to_bytes(pairs[0][0]._detail_transform_cache[look])==var_to_bytes(pairs[0][1]._detail_transform_cache[look]),"preview fallback placement stays byte exact %d"%look)
 var projection=map._visual_surface_projection;var transform:Transform3D=projection.transform
 projection.ground_style=0
 check(pairs[0][1]._terrain_scatter_job(projection,cells,Vector2i.ZERO,16.0,1,1.0,0.9,0.4,180.0)==null,"blocky ground keeps its original physical sampler")
 projection.ground_style=1;projection.basis=Basis(Vector3.RIGHT,0.2)
 check(pairs[0][1]._terrain_scatter_job(projection,cells,Vector2i.ZERO,16.0,1,1.0,0.9,0.4,180.0)==null,"tilted ground keeps the scene query path")
 projection.transform=transform
 print("DETAIL_WORKER_PARITY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"jobs":context.terrain_jobs_started}))
 map.free();await process_frame;quit(0 if errors.is_empty() else 1)
