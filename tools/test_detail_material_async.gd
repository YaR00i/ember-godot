extends SceneTree
const Prep=preload("res://scripts/ember_detail_preparation.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
class Host extends Node:
 var _detail_priority_pending:=false
class SlowDigest extends Prep.MaterialDigestJob:
 func run()->void:
  OS.delay_msec(80);super.run()
class Context extends Prep:
 var fixture_path:String
 var slow:=false
 var sync_reads:=0
 func _new_material_digest_job()->Prep.MaterialDigestJob:return SlowDigest.new()
 func _saved_material_pattern(path:String)->EmberCompactTerrainPattern:
  sync_reads+=1
  if slow:OS.delay_msec(80)
  return super._saved_material_pattern(path)
 func material_patterns(_roles:PackedStringArray,ids:PackedStringArray)->Dictionary:
  var pattern:=_saved_material_pattern(fixture_path)
  _material_saved[ids[1]]=_saved_material_patterns.get(fixture_path,{}) if pattern!=null else {}
  return {ids[1]:pattern}
 func _material_role_paths(_roles:PackedStringArray,ids:PackedStringArray)->Dictionary:return {ids[1]:fixture_path}
var errors:Array[String]=[]
var finished:=false
var bound:=false
var cancel:=false
var roles:=PackedStringArray(["","grass"])
var ids:=PackedStringArray(["","qa_grass"])
var palette:=PackedColorArray([Color.TRANSPARENT,Color.GREEN])
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("DETAIL_MATERIAL_ASYNC_FAIL ",label)
func _initialize()->void:run.call_deferred()
func bind(context:Context,material:ShaderMaterial,host:Node)->void:
 if context.has_method("bind_saved_material_roles_async"):
  bound=await context.bind_saved_material_roles_async(material,roles,ids,palette,host,func():return cancel)
 else:
  context.bind_saved_material_roles(material,roles,ids,palette);bound=true
 finished=true
func wait_done()->void:
 var deadline:=Time.get_ticks_msec()+3000
 while not finished and Time.get_ticks_msec()<deadline:await process_frame
 check(finished,"consumer converges")
func queued(context:Context,material:ShaderMaterial,host:Node,state:Dictionary)->void:
 state.bound=await context.bind_saved_material_roles_async(material,roles,ids,palette,host,func():return false)
 state.done=true
func run()->void:
 Engine.max_fps=240
 var folder:="user://qa-material-async-%d"%OS.get_process_id();DirAccess.make_dir_recursive_absolute(folder)
 var path:=folder.path_join("preset.tres")
 var saved=load("res://content/terrain_materials/cartoon_grass.tres").duplicate()
 saved.base_color=Color.GREEN;check(ResourceSaver.save(saved,path)==OK,"save fixture")
 var context:=Context.new();context.fixture_path=path
 var host:=Host.new();root.add_child(host)
 var projection:=Node3D.new();root.add_child(projection);context.projection_ref=weakref(projection)
 context._frame_tree=weakref(self);process_frame.connect(context._queue_budget_frame)
 var warm:=Materials.compact_flower_material();context.bind_saved_material_roles(warm,roles,ids,palette)
 context.slow=true;context.sync_reads=0
 var material:=Materials.compact_flower_material();var start:=Time.get_ticks_usec()
 bind(context,material,host)
 var producer:=Time.get_ticks_usec()-start
 check(producer<20000,"cached material admission does not block on file checks")
 var frames_seen:=0;var deadline:=Time.get_ticks_msec()+3000
 while not finished and Time.get_ticks_msec()<deadline:
  await process_frame;frames_seen+=1
 check(finished and bound,"binding completes")
 check(frames_seen>=3,"frames continue during slow worker file checks")
 check(context.sync_reads==0,"unchanged saved digest avoids synchronous file hashing and caller copies")
 check(context._material_digest_job==null,"delivery releases the single digest slot")
 context.slow=false
 saved.base_color=Color.BLUE;saved.grass_light_low=0.73;check(ResourceSaver.save(saved,path)==OK,"replace saved preset in same second")
 var changed:=Materials.compact_flower_material()
 finished=false;bind(context,changed,host);await wait_done()
 check(bound and context._saved_material_patterns[path].source.base_color==Color.BLUE,"changed saved bytes invalidate private template")
 check(is_equal_approx((changed.get_meta("ember_grass_light_image") as Image).get_pixel(1,0).r,0.73),"changed file appears in bound profile pixels")
 DirAccess.remove_absolute(path)
 var removed:=Materials.compact_flower_material()
 finished=false;bind(context,removed,host);await wait_done()
 check(bound and not is_equal_approx((removed.get_meta("ember_grass_light_image") as Image).get_pixel(1,0).r,0.73),"removed preset falls back without stale profile pixels")
 check(ResourceSaver.save(saved,path)==OK,"recreate saved fixture")
 finished=false;bind(context,Materials.compact_flower_material(),host);await wait_done();check(bound,"recreated preset binds")
 cancel=true;finished=false;bind(context,Materials.compact_flower_material(),host)
 check(finished and not bound and context._material_digest_job==null,"pre-cancel admits no worker")
 cancel=false;finished=false;bind(context,Materials.compact_flower_material(),host)
 check(context._material_digest_job!=null,"one material job admitted")
 var active=context._material_digest_job
 var second:=Host.new();root.add_child(second);var state:Dictionary={}
 queued(context,Materials.compact_flower_material(),second,state)
 check(context._material_digest_job==active and not state.get("done",false),"second consumer waits for the single bounded slot")
 context._cancel_patch(host)
 check(finished and not bound,"patch cancellation wakes consumer before worker IO finishes")
 check(context._material_digest_job==active,"running cancelled job retains its slot until joined")
 var end:=Time.get_ticks_msec()+3000
 while not state.get("done",false) and Time.get_ticks_msec()<end:await process_frame
 check(state.get("done",false) and state.get("bound",false),"waiting consumer progresses after cancelled IO joins")
 finished=false;bind(context,Materials.compact_flower_material(),host)
 var closing:Dictionary={};queued(context,Materials.compact_flower_material(),second,closing)
 context._release()
 check(finished and not bound and closing.get("done",false) and not closing.get("bound",true),"teardown cancels running and queued consumers")
 check(context._material_digest_job==null and context._budget_waiters.is_empty(),"teardown joins digest worker and clears owned waiters")
 host.free();second.free();projection.free();DirAccess.remove_absolute(path)
 print("DETAIL_MATERIAL_ASYNC ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"producer_us":producer,"frames":frames_seen}))
 quit(0 if errors.is_empty() else 1)
