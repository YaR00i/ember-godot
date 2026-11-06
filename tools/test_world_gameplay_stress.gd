extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Grass=preload("res://scripts/ember_grass_patch.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Hoshi=preload("res://scripts/ember_hoshi_visual.gd")
const STRESS_TUFT_SIZE:=1.25
const HARVEST_SCENES:=["res://prefabs/items/fruit_tree.scn","res://prefabs/items/berry_bush.scn","res://prefabs/items/cuttable_grass.scn"]
const POPULATION_SCENES:=["res://prefabs/voxels/vox_coastal_house.tscn","res://prefabs/voxels/vox_fan_lantern_paper.tscn","res://prefabs/items/physical_crates.tscn"]
# Each worker owns a detached CPU image. No viewport/scene access leaves main.
class NpcCapture extends RefCounted:
 var image:Image
 var path:String
 var timing:Dictionary
 var task_id:int=-1
 var error:int=ERR_BUSY
 var encode_write_us:int=0
 func write()->void:
  var began:=Time.get_ticks_usec()
  error=image.save_png(path)
  encode_write_us=Time.get_ticks_usec()-began
var npc_captures:Array[NpcCapture]=[]
var OUT:=""
var POP:=""
var LARGE_SOURCE:=""
var cache_path:=""
var sandbox:="user://ember-tests/world-gameplay-%d" % OS.get_process_id()
var input_hashes:Dictionary={}
var saved_paths:Array[String]=[]
var run_mode:="full"
var hub_hero_stress:=OS.get_environment("EMBER_HERO_HUB_STRESS")=="1"
var errors:Array[String]=[]
var progress:Dictionary={"mode":"native live gameplay 576m main-copy, expanded production mechanics, sphere disabled","manual_acceptance":"OPEN","pass_scope":"correctness only; measured performance is reported separately","performance_gate":"OPEN: native 120FPS includes wall-frame tails"}
# Native Forward+ only. Example user args after --:
# fixture-root=C:/qa/input output=C:/qa/output cache=C:/qa/scatter mode=interactions
func _init()->void:
 var options:Dictionary={}
 for argument in OS.get_cmdline_user_args():
  var pair:=argument.trim_prefix("--").split("=",true,1)
  if pair.size()!=2 or pair[0] not in ["fixture-root","output","cache","mode"] or pair[1].strip_edges().is_empty():
   printerr("Usage: -- fixture-root=<terrain_576.res,population.scn,plan.res directory> output=<directory> [cache=<directory>] [mode=full|interactions|render|cpu|cpu-secondary|cpu-hub]");quit(2);return
  options[pair[0]]=pair[1].replace("\\","/")
 if not options.has("fixture-root") or not options.has("output"):
  printerr("Required: fixture-root and output");quit(2);return
 POP=options["fixture-root"];OUT=options.output;LARGE_SOURCE=POP.path_join("terrain_576.res")
 run_mode=options.get("mode","full")
 if run_mode not in ["full","interactions","render","cpu","cpu-secondary","cpu-hub"]:printerr("Unknown mode: ",run_mode);quit(2);return
 hub_hero_stress=hub_hero_stress or run_mode=="cpu-hub" or OS.get_environment("EMBER_TERRAIN_MAIN_AB")=="1"
 if hub_hero_stress and run_mode not in ["render","cpu-hub"]:printerr("Hub hero stress requires render or cpu-hub mode");quit(2);return
 progress.run_mode=run_mode
 for path:String in [LARGE_SOURCE,POP.path_join("population.scn"),POP.path_join("plan.res"),"res://scenes/landscape_compact.tscn"]:
  if not FileAccess.file_exists(path):printerr("Missing required input: ",path);quit(2);return
  input_hashes[path]=FileAccess.get_sha256(path)
 # A stale disposable project can contain the meshes but lack their native item
 # definitions. WorldItem then exits _ready before group/record registration.
 # Diagnose that missing fixture input before constructing the heavy scene.
 for id:String in ["apple","forest_berry","herb"]:
  var item:=EmberItemCatalog.definition(id)
  var visual_path:=str(item.get("worldScene",""))
  if item.is_empty() or visual_path.is_empty() or not ResourceLoader.exists(visual_path):
   printerr("Missing production item definition/worldScene: ",id," at ",EmberItemCatalog.native_path(id)," worldScene=",visual_path);quit(2);return
  if EmberItemCatalog.icon_definition(id).is_empty():
   printerr("Missing production item icon: ",id);quit(2);return
 for path:String in [Hoshi.AVATAR_PATH,Hoshi.MOTION_PATH]:
  if not ResourceLoader.exists(path):printerr("Private Hoshi is required: ",path);quit(2);return
 if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus":
  printerr("Requires native Forward+ (run --rendering-driver vulkan --rendering-method forward_plus)");quit(2);return
 if ProjectSettings.get_setting("physics/3d/physics_engine","")!="Jolt Physics":
  printerr("Requires the production Jolt Physics backend");quit(2);return
 if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))!=OK:printerr("Cannot create output directory");quit(2);return
 cache_path=options.get("cache",OUT.path_join("scatter-cache"))
 var isolated:=Fixture.prepare(self,sandbox)
 if isolated.error!=OK:printerr("Cannot isolate test storage");quit(2);return
 run.call_deferred()
func verify_sources()->void:
 for path:String in input_hashes:check(FileAccess.get_sha256(path)==input_hashes[path],"Source bytes unchanged: "+path)
 progress.source_hashes=input_hashes
func finish(scene:Node)->void:
 await drain_npc_captures()
 verify_sources()
 if is_instance_valid(scene):scene.queue_free();await frames(3)
 verify_sources()
 progress.pass=errors.is_empty();progress.errors=errors
 FileAccess.open(OUT.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(progress))
 print("ACTIVE_WORLD_PHASES_DONE ",JSON.stringify({"mode":run_mode,"pass":progress.pass,"errors":errors}))
 quit(0 if errors.is_empty() else 1)
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("QA_RUNTIME576_FAIL ",label)
func record(label:String)->void:
 progress.phase=label;progress.errors=errors
 FileAccess.open(OUT.path_join("runtime576-progress.json"),FileAccess.WRITE).store_string(JSON.stringify(progress))
 print("QA_RUNTIME576_STAGE ",label," ",JSON.stringify(progress.get(label,{})))
func frames(n:int)->void:
 for i in n:await process_frame
func stats(values:Array)->Dictionary:
 var sorted:Array=values.duplicate();sorted.sort()
 if sorted.is_empty():return {}
 var n:int=sorted.size();var over:=0
 for value in sorted:
  if float(value)>8.333333:over+=1
 return {"count":n,"median":sorted[int((n-1)*0.5)],"p95":sorted[int((n-1)*0.95)],"p99":sorted[int((n-1)*0.99)],"max":sorted[n-1],"over_8_33_ms_percent":100.0*float(over)/float(n)}
func grass_status(scene:Node)->Dictionary:
 var result:Dictionary={"patches":0,"resident":0,"pending":0,"instances":0,"grass_instances":0,"flowers":0,"wheat":0}
 var grass_root:Node=scene.get_node("Map/ContinuousMeadow")
 for patch in grass_root.get_children():
  result.patches+=1
  if patch._detail_resident:result.resident+=1
  if patch.detail_preparation_pending():result.pending+=1
  if patch._visual!=null and patch._visual.multimesh!=null:
   var count:int=patch._visual.multimesh.instance_count;result.instances+=count
   if patch.detail_kind==0:result.grass_instances+=count
   elif patch.detail_kind==3:result.flowers+=count
   elif patch.detail_kind==2:result.wheat+=count
 return result
func wait_grass(scene:Node,label:String)->bool:
 var deadline:=Time.get_ticks_msec()+240000;var stable:=-1;var last:=0;var current:Dictionary={}
 while Time.get_ticks_msec()<deadline:
  var now:=Time.get_ticks_msec()
  if now-last>1000:
   current=grass_status(scene);last=now
   if current.pending==0 and current.instances>0:
    if stable<0:stable=now
   else:stable=-1
   if stable>=0 and now-stable>2500:
    progress[label]=current;record(label);return true
   if now%15000<1100:progress[label]=current;record(label+"_waiting")
  await process_frame
 progress[label]=current;check(false,"runtime grass readiness "+label);return false
func water_summary(scene:Node)->Dictionary:
 var water:Node=scene.get_node_or_null("PlanarReflection")
 if water==null:return {"available":false}
 var fields=water._water_regions
 var values:Dictionary={"available":true,"prepared":water._prepared,"status":water.startup_preparation_status()}
 if fields==null:return values
 values.ready=fields.ready;values.required_ready=fields.required_ready();values.bounded=fields._bounded();values.required=fields._required.size();values.wanted=fields._wanted.size();values.checked=fields._checked.size();values.pending=fields.has_pending_preparation();values.committed=fields.regions.size();values.worker_alive=fields._thread.is_alive() if fields._thread.is_started() else false
 values.upload_cursor=fields._upload_cursor;values.upload_total=fields._upload_keys.size()
 values.projection_committed=scene.get_node("Map")._visual_surface_projection._water_regions.size()
 var scalar_stats:Dictionary={}
 for key in fields.stats:
  var value=fields.stats[key]
  if value is int or value is float or value is bool or value is String:scalar_stats[str(key)]=value
 values.stats=scalar_stats
 var detail:Dictionary={}
 for property in fields.get_property_list():
  var name:String=property.name
  if not ("required" in name or "request" in name or "pending" in name or "region" in name or "build" in name or "upload" in name or "candidate" in name or "active" in name):continue
  var value=fields.get(name)
  if value is Dictionary or value is Array or value is PackedVector2Array or value is PackedStringArray:detail[name]={"count":value.size()}
  elif value is int or value is float or value is bool or value is String:detail[name]=value
 values.counters=detail
 return values
func wait_water(scene:Node,label:String)->bool:
 var deadline:=Time.get_ticks_msec()+90000;var last:=0
 while Time.get_ticks_msec()<deadline:
  var water:Node=scene.get_node_or_null("PlanarReflection")
  if is_instance_valid(water) and water._water_regions!=null and water._prepared and water._water_regions.required_ready() and water.startup_preparation_status().get("ready",false):
   progress[label]=water_summary(scene);record(label);return true
  if Time.get_ticks_msec()-last>15000:
   progress[label]=water_summary(scene);record(label+"_waiting");last=Time.get_ticks_msec()
  await process_frame
 progress[label]=water_summary(scene);check(false,"required live water readiness "+label);record(label);return false
var route:PackedVector3Array=[]
func needs_automatic_route()->bool:return true
func make_route(map:Node,anchor:Vector3,east:Vector3)->void:
 var target:=anchor+east*1536.0
 var grid:=AStarGrid2D.new();var cell:=32.0
 var lo:=Vector2(anchor.x,anchor.z).min(Vector2(target.x,target.z))-Vector2(640,640)
 var hi:=Vector2(anchor.x,anchor.z).max(Vector2(target.x,target.z))+Vector2(640,640)
 var low:=Vector2i(floori(lo.x/cell),floori(lo.y/cell));var high:=Vector2i(ceili(hi.x/cell),ceili(hi.y/cell))
 grid.region=Rect2i(low,high-low+Vector2i.ONE);grid.cell_size=Vector2(cell,cell);grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;grid.update()
 for weak in map._object_details.values():
  var prop=weak.get_ref()
  if not is_instance_valid(prop):continue
  for shape:CollisionShape3D in prop.find_children("*","CollisionShape3D",true,false):
   if shape.disabled or shape.shape==null:continue
   var bounds:AABB=shape.global_transform*shape.shape.get_debug_mesh().get_aabb()
   var r:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(16.0)
   for z in range(floori(r.position.y/cell),ceili(r.end.y/cell)+1):
    for x in range(floori(r.position.x/cell),ceili(r.end.x/cell)+1):
     var id:=Vector2i(x,z)
     if grid.is_in_boundsv(id):grid.set_point_solid(id)
 var start_id:=Vector2i(roundi(anchor.x/cell),roundi(anchor.z/cell));var end_id:=Vector2i(roundi(target.x/cell),roundi(target.z/cell))
 grid.set_point_solid(start_id,false);grid.set_point_solid(end_id,false)
 var points:=grid.get_point_path(start_id,end_id)
 for point in points:route.append(Vector3(point.x,0,point.y))
 check(route.size()>2,"collision-aware route exists")
 progress.route_points=route.size();progress.route_obstacles="actual prop collision shapes, actor margin 1m";record("route_ready")
func steer(actor:EmberPlayer,direction:Vector3)->void:
 var yaw:float=actor.camera_rig.yaw
 var axis:=Vector2(direction.x*cos(yaw)-direction.z*sin(yaw),direction.x*sin(yaw)+direction.z*cos(yaw)).normalized()
 for item in [["move_east",axis.x],["move_west",-axis.x],["move_south",axis.y],["move_north",-axis.y]]:
  if item[1]>0.001:Input.action_press(item[0],item[1])
  else:Input.action_release(item[0])
func walk_leg(scene:Node,label:String,action:String,direction:Vector3,target_distance:float,correctness:bool)->void:
 var actor:EmberPlayer=scene._player
 var map:EmberMapLoader=scene.get_node("Map")
 var projection:Node=map._visual_surface_projection
 var start:=actor.global_position;var started:=Time.get_ticks_usec();var prior:=started
 var wall:Array=[];var gpu:Array=[];var traces:Array=[];var checker:Array=[];var missing:=0;var pending:=0;var floor_missing:=0;var last_progress:=started
 var min_gap:=INF;var max_gap:=-INF
 var points:=route.duplicate()
 if action=="move_west":points.reverse()
 var waypoint:=1;var movement_check:=started;var movement_position:=actor.global_position
 while waypoint<points.size() and Time.get_ticks_usec()-started<70000000:
  var toward:Vector3=points[waypoint]-actor.global_position;toward.y=0
  if toward.length()<8.0:waypoint+=1;continue
  steer(actor,toward)
  await process_frame
  var now:=Time.get_ticks_usec();wall.append(float(now-prior)/1000.0);prior=now
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
  var check_start:=Time.get_ticks_usec()
  var status:Dictionary={}
  if correctness:
   status=required_status(scene);missing=maxi(missing,status.absent_buffers);pending=maxi(pending,status.missing)
   if status.absent_buffers>0 and not progress.has(label+"_first_missing"):progress[label+"_first_missing"]=status
   var support:Dictionary=projection.floor_surface_sample(actor.global_position)
   if not support.get("solid",false) or not support.get("physics_ready",false):floor_missing+=1
   if support.get("solid",false):
    var gap:float=actor.global_position.y-support.position.y;min_gap=minf(min_gap,gap);max_gap=maxf(max_gap,gap)
    if gap< -0.25:floor_missing+=1
  checker.append(float(Time.get_ticks_usec()-check_start)/1000.0)
  traces.append({"frame":Engine.get_process_frames(),"wall_ms":wall[-1],"gpu_ms":gpu[-1],"checker_ms":checker[-1],"coverage":status,"object":map._object_detail_profile.duplicate(),"cache_read_us":preload("res://scripts/ember_detail_preparation.gd").for_projection(projection).disk.read_us,"cache_write_us":preload("res://scripts/ember_detail_preparation.gd").for_projection(projection).disk.write_us,"read_worker_us":preload("res://scripts/ember_detail_preparation.gd").for_projection(projection).cache_read_worker_us,"read_jobs":preload("res://scripts/ember_detail_preparation.gd").for_projection(projection).cache_read_jobs_started})
  if now-last_progress>10000000:
   progress[label+"_running"]={"metres":(actor.global_position-start).dot(direction)/16.0,"seconds":float(now-started)/1000000.0};record(label+"_running");last_progress=now
 for key in ["move_east","move_west","move_south","move_north"]:Input.action_release(key)
 var travelled:float=(actor.global_position-start).dot(direction)
 check(waypoint==points.size(),"actual long route reaches endpoint "+label)
 if correctness:check(missing==0 and floor_missing==0,"every-frame coverage/support "+label)
 progress[label]={"mode":"correctness" if correctness else "timing","distance_m":travelled/16.0,"wall_ms":stats(wall),"gpu_ms":stats(gpu),"checker_ms":stats(checker),"missing":missing,"pending_flags":pending,"floor_missing":floor_missing,"frames":wall.size(),"start":var_to_str(start),"end":var_to_str(actor.global_position)}
 progress[label].actual_foot_gap_raw={"min":min_gap,"max":max_gap}
 FileAccess.open(OUT.path_join(label+"-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(traces));record(label)
 if waypoint!=points.size():quit(1);return
 await frames(3)

func anchor_buffers(grass_root:Node)->Dictionary:
 var result:Dictionary={}
 for patch in grass_root.get_children():
  if patch._detail_resident and patch._visual!=null and patch._visual.multimesh!=null:result[patch.name]=hash(patch._visual.multimesh.buffer)
 return result

func reset_anchor(scene:Node,anchor:Vector3)->void:
 scene._player.global_position=anchor;scene._player.velocity=Vector3.ZERO
 scene._player.camera_rig.reset_follow_height()
 await frames(30);await wait_grass(scene,"anchor_ready")

var coverage_bins:Dictionary={}
var coverage_index_count:=-1
var marker_buffers:Dictionary={}
var marker_distances:Dictionary={}
var coverage_patches:Array[Node]=[]
var coverage_areas:Dictionary={}
func required_status(scene:Node)->Dictionary:
 var projection:Node3D=scene.get_node("Map")._visual_surface_projection
 var anchor:Vector3=projection.detail_world_anchor()
 var focus:=Vector2(anchor.x,anchor.z)
 var missing:=0;var required:=0;var sleeping:=0;var building:=0;var examples:Array=[]
 var absent:=0;var retained:=0;var absent_names:Array=[];var nearest_absent:=INF
 if coverage_index_count!=coverage_patches.size():
  coverage_bins.clear();coverage_index_count=coverage_patches.size()
  for patch in coverage_patches:
   var area:Rect2=coverage_areas[patch]
   for z in range(floori(area.position.y/64.0),floori(area.end.y/64.0)+1):
    for x in range(floori(area.position.x/64.0),floori(area.end.x/64.0)+1):
     var bin_key:=Vector2i(x,z)
     if not coverage_bins.has(bin_key):coverage_bins[bin_key]={}
     coverage_bins[bin_key][patch]=true
 var radius:float=projection.detail_policy.detail_fade_end_m*16.0
 var wanted:Dictionary={}
 for z in range(floori((focus.y-radius)/64.0),floori((focus.y+radius)/64.0)+1):
  for x in range(floori((focus.x-radius)/64.0),floori((focus.x+radius)/64.0)+1):
   var bin_key:=Vector2i(x,z)
   if coverage_bins.has(bin_key):wanted.merge(coverage_bins[bin_key])
 for patch in wanted:
  var area:Rect2=coverage_areas[patch]
  if focus.distance_to(focus.clamp(area.position,area.end))>projection.detail_policy.detail_fade_end_m*16.0:continue
  required+=1
  var visual=patch._visual
  var published:bool=is_instance_valid(visual) and visual.multimesh!=null and visual.multimesh.mesh!=null and visual.material_override!=null
  if not published:
   absent+=1;absent_names.append(str(patch.name));nearest_absent=minf(nearest_absent,focus.distance_to(focus.clamp(area.position,area.end))/16.0)
  if patch._dirty or patch._rebuilding:
   if published:retained+=1
   missing+=1
   if examples.size()<3:examples.append({"name":patch.name,"kind":patch.detail_kind,"rebuilding":patch._rebuilding})
   if not patch._detail_resident:sleeping+=1
   elif patch._rebuilding:building+=1
 return {"required":required,"missing":missing,"absent_buffers":absent,"rebuilding_with_buffer":retained,"absent_names":absent_names,"nearest_absent_m":nearest_absent if absent>0 else -1.0,"sleeping":sleeping,"building":building,"examples":examples}
func align_legacy_fixture_items(scene:Node)->void:
 # Replacing the main terrain does not move its authored props automatically.
 # Repair buried active legacy items before persistence/timing;keep XZ and count.
 var map:EmberMapLoader=scene.get_node("Map")
 var recovery=scene.get_node("WorldRecovery")
 var changes:Array=[]
 for item in get_nodes_in_group("ember_world_item_bodies"):
  if not scene.is_ancestor_of(item) or not item.authored_pickup or not item.is_item_available() or item.is_carried():continue
  if item.progress_state==null or item.combat_suspended or int(item.progress_state.world_items.get(item.pickup_id,{}).get("count",0))<=0:continue
  var original:Transform3D=item._authored_transform
  check(await map._visual_surface_projection.prepare_floor_query(original.origin),"legacy fixture floor query prepared")
  var sample:Dictionary=map.surface_floor_sample(original.origin)
  check(sample.get("solid",false),"active legacy fixture item has terrain: "+str(item.pickup_id))
  if not sample.get("solid",false):continue
  var bottom:float=item._carry_visual_bottom*original.basis.get_scale().y
  if original.origin.y+bottom>=float(sample.position.y)-0.1:continue
  var corrected:=original;corrected.origin.y=float(sample.position.y)+0.2-bottom
  item.freeze=true;item.linear_velocity=Vector3.ZERO;item.angular_velocity=Vector3.ZERO
  item._authored_transform=corrected;item.global_transform=corrected
  scene._world_item_placements[item.pickup_id]=item.placement_settings();item.capture_progress()
  item._physics_support_requested=false;item._waiting_for_world=true;item.refresh_availability()
  recovery._register_body(item)
  changes.append({"id":item.pickup_id,"original":original.origin,"corrected":corrected.origin,"floor":sample.position})
 progress.fixture_legacy_support={"changes":changes,"scope":"runtime fixture adaptation after source replacement;no authored scene/save schema changes"}
 record("fixture_legacy_support")

func run()->void:
 var fixture_started:=Time.get_ticks_msec()
 preload("res://scripts/ember_detail_preparation.gd").cache_root=cache_path
 Engine.max_fps=0;OS.low_processor_usage_mode=false;OS.low_processor_usage_mode_sleep_usec=0
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);root.size=Vector2i(2560,1440)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 var source=load(LARGE_SOURCE)
 var scene:Node=load("res://scenes/landscape_compact.tscn").instantiate()
 scene.sandbox_storage_root=sandbox
 var map:EmberMapLoader=scene.get_node("Map")
 var author:Resource=map.compact_terrain
 if source==null or author==null:
  check(false,"large source and authored map available");quit(1);return
 source.palette=author.palette;source.palette_surface_roles=author.palette_surface_roles;source.palette_material_ids=author.palette_material_ids
 map.compact_terrain=source
 progress.large_source={"width":source.width,"depth":source.depth,"sectioned":source.is_sectioned(),"style_after_assignment":map.compact_ground_style,"limit":map.smooth_column_limit()}
 record("large_source")
 if map.compact_ground_style!=1:
  check(false,"large Source accepted by runtime smooth-ground consumer");progress.pass=false;progress.errors=errors
  FileAccess.open(OUT.path_join("runtime576-result.json"),FileAccess.WRITE).store_string(JSON.stringify(progress));scene.free();quit(1);return
 map.position=Vector3.ZERO;map.authored_size_blocks=Vector2i(576,576)
 map.get_node("WorldAnomaly").enabled=false
 var region:Node3D=map.get_node("Regions/PlayerStart")
 region.position=Vector3(264*16,16,264*16)-map.get_node("Regions").position
 var props:Node=map.get_node("Props")
 var population:Node=load(POP.path_join("population.scn")).instantiate();var props_count:=0
 for prop in population.get_children():
  population.remove_child(prop);prop.owner=null;props.add_child(prop);prop.owner=scene;props_count+=1
 population.free();map.set_meta(Plan.META,load(POP.path_join("plan.res")))
 var grass_root:=Node3D.new();grass_root.name="ContinuousMeadow";map.add_child(grass_root);grass_root.owner=scene
 var mask:Dictionary={};var flower_mask:Dictionary={};var wheat_mask:Dictionary={}
 for z in 16:
  for x in 16:mask[Vector2i(x,z)]=64.0;flower_mask[Vector2i(x,z)]=10.0;wheat_mask[Vector2i(x,z)]=8.0
 var covers:Array=[load("res://content/terrain_materials/meadow_daisy_cover.tres"),load("res://content/terrain_materials/meadow_buttercup_cover.tres"),load("res://content/terrain_materials/meadow_lilac_cover.tres")]
 var wheat:Resource=load("res://tools/fixtures/detail_wheat_preset.tres")
 var counts:Dictionary={"grass":0,"flowers":0,"wheat":0}
 for z in range(0,576,4):
  for x in range(0,576,4):
   var crop:bool=x%96>=88 and z%96>=64 and z%96<80
   var patch:Node3D=Grass.new();patch.name="Patch_%d_%d"%[x,z];patch.position=Vector3(x*16,0,z*16);patch.painted_only=true;patch.scatter_seed=20261029;patch.density_cells=wheat_mask if crop else mask
   if crop:patch.detail_kind=2;patch.detail_preset=wheat;counts.wheat+=1
   else:
    patch.tuft_size=STRESS_TUFT_SIZE
    counts.grass+=1
   grass_root.add_child(patch);patch.owner=scene
   if not crop and (x/4+z/4)%4==0:
    var flower:Node3D=Grass.new();flower.name="Flowers_%d_%d"%[x,z];flower.position=patch.position;flower.painted_only=true;flower.detail_kind=3;flower.cover_pattern=covers[(x/16+z/16)%3];flower.density_cells=flower_mask;flower.scatter_seed=20261030
    flower.tuft_size=STRESS_TUFT_SIZE
    grass_root.add_child(flower);flower.owner=scene;counts.flowers+=1
 progress.coverage={"props_added":props_count,"patches":counts,"grass_density_m2":64,"flower_density_m2":10,"wheat_density_m2":8,"wind":"disabled; production EmberGrassPatch","scatter_cache":"fresh streaming verification output directory"}
 # Configure the final size before startup. Resizing after npc_visibility would
 # dirty every ready grass/flower patch and visibly rebuild it behind the camera.
 progress.vegetation_size={"scale":STRESS_TUFT_SIZE,"changed_stress_patches":counts.grass+counts.flowers,"grass_density_m2":64,"flower_density_m2":10,"wheat_density_m2":8}
 check(props_count==859 and counts.grass==20448 and counts.flowers==5112 and counts.wheat==288,"original dense full field and population")
 progress.fixture_build_elapsed_ms=Time.get_ticks_msec()-fixture_started;record("fixture_built")
 var started:=Time.get_ticks_msec();root.add_child(scene);current_scene=scene
 var deadline:=started+480000;var last:=started
 while not scene._startup_complete and Time.get_ticks_msec()<deadline:
  if Time.get_ticks_msec()-last>15000:
   progress.startup_status=scene._startup_status();progress.startup_elapsed_ms=Time.get_ticks_msec()-started;progress.startup_player=is_instance_valid(scene._player);progress.startup_grass=grass_status(scene);progress.startup_terrain={"tiles":map._visual_surface_projection._tiles.size(),"pending":map._visual_surface_projection.pending_tile_count(),"overviews":map._visual_surface_projection._overviews.size()};progress.startup_water=water_summary(scene);record("startup_wait");last=Time.get_ticks_msec()
  await process_frame
 progress.startup_elapsed_ms=Time.get_ticks_msec()-started
 check(scene._startup_complete,"576m main-copy reaches ordinary gameplay")
 if not scene._startup_complete:
  progress.pass=false;progress.errors=errors;FileAccess.open(OUT.path_join("runtime576-result.json"),FileAccess.WRITE).store_string(JSON.stringify(progress));quit(1);return
 await wait_water(scene,"water_focus_initial")
 var water:Node=scene.get_node_or_null("PlanarReflection")
 var fields=water._water_regions if is_instance_valid(water) else null
 var expected_sections:int=source.sections.size()
 var wet_keys:Dictionary={}
 for key in source.sections:
  var part=source.sections[key]
  if part.water_materials.count(0)==part.water_materials.size():continue
  for i in part.water_materials.size():
   if part.water_materials[i]>0 and part.water_levels[i]>part.heights[i]:wet_keys[key]=true;break
 var missing_near_wet:Array=[]
 var player_local:Vector3=map._visual_surface_projection.to_local(scene._player.global_position)
 var player_region:=Vector2i(floori(player_local.x/384.0),floori(player_local.z/384.0))
 for key in wet_keys:
  if fields!=null and fields._required.has(key) and (not fields.regions.has(key) or not map._visual_surface_projection._water_regions.has(key)):missing_near_wet.append(str(key))
 var sections:Array=[]
 for key in [Vector2i.ZERO,Vector2i(23,23)]:
  var part_exists:bool=source.sections.has(key)
  var entry:Dictionary=fields.regions.get(key,{}) if fields!=null else {}
  var core:Rect2i=entry.get("core",Rect2i())
  var window:Rect2i=entry.get("window",Rect2i())
  var shore:Texture2D=entry.get("shore")
  var height:Texture2D=entry.get("height")
  var bounds_ok:bool=part_exists if entry.is_empty() else core.position==Vector2i.ZERO if key==Vector2i.ZERO else core.end==Vector2i(source.width,source.depth)
  var texture_ok:bool=entry.is_empty() or shore!=null and height!=null and shore.get_width()==window.size.x and shore.get_height()==window.size.y and height.get_width()==window.size.x and height.get_height()==window.size.y
  var published:bool=entry.is_empty() or map._visual_surface_projection._water_regions.has(key)
  sections.append({"key":str(key),"source_present":part_exists,"wet":wet_keys.has(key),"region_present":not entry.is_empty(),"core":str(core),"window":str(window),"bounds_ok":bounds_ok,"textures_ok":texture_ok,"projection_published":published,"shore_distance":fields.shore_distance(Vector2(core.position)+Vector2(0.5,0.5)) if fields!=null and not entry.is_empty() else -1})
  check(bounds_ok and texture_ok and published,"water coverage valid through "+str(key))
 var status:Dictionary=water.startup_preparation_status() if is_instance_valid(water) else {}
 var committed_count:int=fields.regions.size() if fields!=null else -1
 progress.water={"status":status,"prepared":water._prepared if is_instance_valid(water) else false,"ready":fields.ready if fields!=null else false,"source_sections":expected_sections,"wet_sections":wet_keys.size(),"player_region":str(player_region),"missing_required_wet_regions":missing_near_wet,"required_ready":fields.required_ready() if fields!=null else false,"required_regions":fields._required.size() if fields!=null else -1,"wanted_regions":fields._wanted.size() if fields!=null else -1,"committed_regions":committed_count,"projection_regions":map._visual_surface_projection._water_regions.size(),"source_dimensions":str(Vector2i(fields.source.width,fields.source.depth)) if fields!=null and fields.source!=null else "","flow_size":str(Vector2i(fields.flow_texture.get_width(),fields.flow_texture.get_height())) if fields!=null and fields.flow_texture!=null else "none","phase_present":fields!=null and fields.phase_texture!=null,"boundary_regions":sections}
 check(status.get("ready",false) and water._prepared and fields!=null and fields.required_ready() and missing_near_wet.is_empty() and map._visual_surface_projection._water_regions.size()==committed_count,"existing wet water regions committed for full source")
 progress.water_counters_initial=water_summary(scene);record("water")
 var actor:EmberPlayer=scene._player
 check(is_instance_valid(actor) and actor.is_physics_processing(),"real gameplay player and physics")
 progress.grass_near_initial=grass_status(scene)
 for patch in grass_root.get_children():
  if patch.global_position.distance_to(actor.global_position)<64*16:
   coverage_patches.append(patch);coverage_areas[patch]=patch._world_area()
 progress.required_at_reveal=required_status(scene)
 check(progress.required_at_reveal.missing==0,"all potentially visible vegetation ready at reveal")
 await wait_grass(scene,"initial_settle")
 await align_legacy_fixture_items(scene)
 var anchor:Vector3=actor.global_position
 var state:EmberExploreState=actor.progress_state
 check(state.storage_root==sandbox,"isolated production save storage")
 if state.storage_root!=sandbox:
  printerr("Refusing to enable persistence outside the test sandbox");scene.queue_free();quit(2);return
 state.persistence_enabled=true
 state.saved.connect(func(path:String):saved_paths.append(path))
 await populate(scene,anchor)
 await populate_harvest(scene,anchor)
 scene._refresh_world_items()
 if not audit_harvest_bindings(scene,"after_refresh"):
  await finish(scene);return
 await population_ready(scene)
 await wait_grass(scene,"population_grass_ready")
 var original_buffers:=anchor_buffers(grass_root)
 check(original_buffers.size()>100,"initial resident marker set")
 coverage_patches.clear();coverage_areas.clear()
 for patch in grass_root.get_children():coverage_patches.append(patch);coverage_areas[patch]=patch._world_area()
 progress.probe_patch_count=coverage_patches.size()
 var yaw:float=actor.camera_rig.yaw
 var east:=Vector3(cos(yaw),0,-sin(yaw))
 if needs_automatic_route():
  make_route(map,anchor,east)
  if route.size()<3:quit(1);return
 else:
  progress.route_mode="manual controls;automated walking route not required";record("manual_route_not_required")
 var preparation=preload("res://scripts/ember_detail_preparation.gd").for_projection(map._visual_surface_projection)
 progress.preparation_budget_us=preparation.frame_budget_us()


 await npc_visibility(scene)
 if not audit_harvest_bindings(scene,"before_timing") or not errors.is_empty():
  await finish(scene);return
 await accept_world(scene,anchor)
 await finish(scene)

func walk_clean(scene:Node,label:String,action:String)->void:
 var actor:EmberPlayer=scene._player
 await frames(2)
 var camera:=root.get_camera_3d()
 progress[label+"_camera"]={"fov":camera.fov,"viewport":str(camera.get_viewport().size),"scale":camera.get_viewport().scaling_3d_scale,"near":camera.near,"far":camera.far,"transform":var_to_str(camera.global_transform)}
 check(is_equal_approx(camera.fov,actor.camera_rig.fov) and camera.get_viewport().size==Vector2i(2560,1440) and is_equal_approx(camera.get_viewport().scaling_3d_scale,1.0),"real camera native "+label)
 var values:=PackedFloat64Array();values.resize(16000)
 var frames_seen:=PackedInt64Array();frames_seen.resize(16000)
 var started:=Time.get_ticks_usec();var prior:=started;var count:=0
 var stalls:Array=[]
 var unix_offset:=Time.get_unix_time_from_system()-Time.get_ticks_usec()/1000000.0
 var points:=route.duplicate()
 if action=="move_west":points.reverse()
 var waypoint:=1
 while waypoint<points.size() and Time.get_ticks_usec()-started<70000000 and count<16000:
  var toward:Vector3=points[waypoint]-actor.global_position;toward.y=0
  if toward.length()<8.0:waypoint+=1;continue
  steer(actor,toward);await process_frame
  var now:=Time.get_ticks_usec();values[count]=float(now-prior)/1000.0;prior=now
  if values[count]>100.0:stalls.append({"start_us":now-int(values[count]*1000),"end_us":now,"unix_end":unix_offset+now/1000000.0,"wall_ms":values[count]})
  frames_seen[count]=Engine.get_process_frames();count+=1
 for action_name in ["move_east","move_west","move_south","move_north"]:Input.action_release(action_name)
 var times:Array=[]
 for i in count:times.append(values[i])
 check(waypoint==points.size(),"clean route complete "+label)
 progress[label]={"wall_ms":stats(times),"frames":count,"mode":"minimal; viewport GPU timers off; no coverage checker","stalls":stalls,"systems":population_status(scene)}
 FileAccess.open(OUT.path_join(label+"-raw.bin"),FileAccess.WRITE).store_var({"count":count,"times":values,"frames":frames_seen})
 record(label);await frames(3)

func tree_physics(scene:Node)->Dictionary:
 var values:Dictionary={}
 for prop in scene.get_node("Map/Props").get_children():
  if prop is EmberVoxelProp and prop.model_id in ["vox_painted_oak","vox_painted_birch"]:
   var shape:Shape3D=prop.authoring_collision_shape()
   values[str(prop.name)]=[prop.object_detail_base().get_instance_id(),shape.get_instance_id() if shape!=null else 0,var_to_str(prop.global_transform)]
 return values
func accept_world(scene:Node,anchor:Vector3)->void:
 var map=scene.get_node("Map")
 var actor=scene._player
 var grass_root=map.get_node("ContinuousMeadow")
 var preparation=preload("res://scripts/ember_detail_preparation.gd").for_projection(map._visual_surface_projection)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),false)
 progress.environment={"instance_uniform_slots":ProjectSettings.get_setting("rendering/limits/global_shader_variables/buffer_size"),"pipeline_cache_save_mb":ProjectSettings.get_setting("rendering/rendering_device/pipeline_cache/save_chunk_size_mb"),"pipeline_cache_enabled":ProjectSettings.get_setting("rendering/rendering_device/pipeline_cache/enable",true),"physics_backend":ProjectSettings.get_setting("physics/3d/physics_engine","missing"),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"physics_hz":Engine.physics_ticks_per_second,"taa":root.use_taa,"scale":root.scaling_3d_scale,"viewport":str(root.size)}
 progress.tree_physics_before=tree_physics(scene)
 var collision_types:Dictionary={}
 for tile:Node3D in map._visual_surface_projection._tiles.values():
  var kind:String=tile.get_node("GroundPhysics/Shape").shape.get_class();collision_types[kind]=int(collision_types.get(kind,0))+1
 progress.collision_types=collision_types
 progress.vegetation_size.foreground_budget_us=preparation.frame_budget_us()
 progress.comparison_scope="Expanded gameplay load; report measured wall times, no inherited performance PASS"
 map.set_runtime_shadow_lod_enabled(true);map.set_runtime_physics_activity_enabled(true)
 for visual in population_visuals:visual._animation_full_rate=visual.important_character
 if run_mode=="cpu-hub":
  await wait_grass(scene,"crowd_live_ready")
  await cpu_hub_comparison(scene)
  return
 if run_mode in ["cpu","cpu-secondary"]:
  await wait_grass(scene,"crowd_live_ready")
  await cpu_comparison(scene)
  return
 if run_mode in ["full","render"]:
  await wait_grass(scene,"crowd_live_ready")
  if OS.get_environment("EMBER_TERRAIN_MAIN_AB")=="1":
   var helper_path:=OS.get_environment("EMBER_TERRAIN_MAIN_AB_SCRIPT")
   if helper_path.is_empty() or not ResourceLoader.exists(helper_path):
    check(false,"explicit disposable terrain comparison helper required")
    return
   await load(helper_path).new().run(self,scene)
   progress.population_final=population_status(scene)
   progress.validation_scope="terrain render integration on full main-copy workload; old authoritative physics retained, no source migration"
   return
  if hub_hero_stress:
   await compare_secondary_policy(scene)
  if not OS.get_environment("EMBER_GRASS_COMPARE_MESH").is_empty():
   await compare_grass_meshes(scene)
   progress.population_final=population_status(scene)
   progress.validation_scope="same-process ordinary grass mesh comparison only; clean movement already measured separately"
   return
  await sample_live_crowd(scene)
  actor.camera_rig.fov=40.0;await reset_anchor(scene,anchor)
  await walk_clean(scene,"larger_out40","move_east")
  await wait_grass(scene,"larger_far_settle");actor.camera_rig.fov=70.0
  await walk_clean(scene,"larger_back70","move_west")
 if run_mode=="render":
  progress.validation_scope="render-path regression: same dense population, native FOV40/70 live and clean moving routes; unchanged interactions/cold coverage/release-return not repeated"
  progress.population_final=population_status(scene)
  check(progress.population_final.fallen==0,"all population supported after render routes")
  return
 await interaction_phase(scene,anchor)
 if run_mode=="interactions":
  progress.movement_skipped=true
  progress.validation_scope="production interactions and identical full population/cameras; moving coverage/release/return not run"
  progress.population_final=population_status(scene)
  return
 if not errors.is_empty():return
 await reset_anchor(scene,anchor)
 var yaw:float=actor.camera_rig.yaw
 var east:=Vector3(cos(yaw),0,-sin(yaw))
 for mode:String in ["correctness"]:
  if mode=="correctness":preparation.disk.directory=OUT.path_join("cold-details")
  await reset_anchor(scene,anchor)
  actor.camera_rig.fov=40.0
  var before_buffers:=anchor_buffers(grass_root)
  marker_buffers.clear();marker_distances.clear()
  for name:String in before_buffers:
   var patch:Node=grass_root.get_node(name)
   marker_buffers[name]=patch._visual.multimesh.buffer.duplicate()
   marker_distances[name]=map._visual_surface_projection.detail_policy.distance_m(map._visual_surface_projection._local_detail_area(patch._world_area()))
  await walk_leg(scene,mode+"_out40","move_east",east,1536.0,mode=="correctness")
  await wait_grass(scene,mode+"_far_settle")
  var released:=0
  for name:String in before_buffers:
   var patch:Node=grass_root.get_node(name)
   if not patch._detail_resident and patch._detail_transform_cache.is_empty() and (patch._visual==null or patch._visual.multimesh==null):released+=1
  progress[mode+"_release"]={"initial":before_buffers.size(),"released":released,"static_bytes":OS.get_static_memory_usage(),"video_bytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),"height_entries":preload("res://scripts/ember_voxel_surface_materials.gd")._bank_height_images.size(),"height_bytes":preload("res://scripts/ember_voxel_surface_materials.gd").depth_cache_bytes()}
  check(released==before_buffers.size(),"all marked initial grass actually released "+mode)
  actor.camera_rig.fov=70.0
  await walk_leg(scene,mode+"_back70","move_west",-east,1536.0,mode=="correctness")
  progress[mode+"_return_error_m"]=actor.global_position.distance_to(anchor)/16.0
  await reset_anchor(scene,anchor)
  var returned:=anchor_buffers(grass_root);var exact:=0
  for name:String in before_buffers:
   if returned.get(name,-1)==before_buffers[name]:exact+=1
  progress[mode+"_return"]={"original":before_buffers.size(),"exact":exact,"static_bytes":OS.get_static_memory_usage(),"video_bytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),"height_entries":preload("res://scripts/ember_voxel_surface_materials.gd")._bank_height_images.size(),"height_bytes":preload("res://scripts/ember_voxel_surface_materials.gd").depth_cache_bytes()}
  var mismatches:Array=[]
  for name:String in before_buffers:
   if returned.get(name,-1)==before_buffers[name]:continue
   var patch:Node=grass_root.get_node(name);var entry:Dictionary={"name":name,"resident":patch._detail_resident,"dirty":patch._dirty,"rebuilding":patch._rebuilding,"position":var_to_str(patch.global_position)}
   if patch._visual!=null and patch._visual.multimesh!=null:
    var current:PackedFloat32Array=patch._visual.multimesh.buffer;var initial:PackedFloat32Array=marker_buffers[name]
    entry.initial_size=initial.size();entry.return_size=current.size();entry.differences=[]
    for j in mini(current.size(),initial.size()):
     if current[j]!=initial[j] and entry.differences.size()<12:entry.differences.append({"index":j,"before":initial[j],"after":current[j]})
    FileAccess.open(OUT.path_join(mode+"-mismatch-"+name+".bin"),FileAccess.WRITE).store_var({"before":initial,"after":current})
   mismatches.append(entry)
  var unused_band:=0
  for entry:Dictionary in mismatches:
   entry.initial_distance_m=marker_distances[entry.name]
   entry.prepare_m=map._visual_surface_projection.detail_policy.detail_prepare_m
   entry.return_distance_m=map._visual_surface_projection.detail_policy.distance_m(map._visual_surface_projection._local_detail_area(grass_root.get_node(entry.name)._world_area()))
   if not entry.resident and entry.return_distance_m>entry.prepare_m and entry.initial_distance_m>entry.prepare_m:unused_band+=1
  progress[mode+"_return"].unused_hysteresis_band=unused_band
  progress[mode+"_mismatches"]=mismatches
  check(exact+unused_band==before_buffers.size(),"same-anchor required buffers exact after real unload "+mode)
  record(mode+"_returned")

 verify_harvest_state(scene,"after_release_return")
 progress.population_final=population_status(scene)
 check(progress.population_final.npcs==32 and progress.population_final.crates==16,"unchanged combined population survives all routes")
 check(progress.population_final.fallen==0,"no population fell through streamed floor")
 progress.tree_physics_after=tree_physics(scene)
 check(progress.tree_physics_before==progress.tree_physics_after,"source and collision unchanged across all routes")
 # Static render snapshots already validated; this repeat checks changed moving scheduling.
var population_actors:Array[CharacterBody3D]=[]
var population_visuals:Array=[]
var population_crates:Array=[]
var population_lamps:Array=[]
class PopulationActor extends CharacterBody3D:
 var age:=0.0
 var animation_age:=0.0
 var animation_slot:=0
 var animation_phase_offset:=0.0
 var animation_cycle:=PackedStringArray(["idle","walk","run"])
 var animation_clip:="idle"
 var simulation_essential:=false
 var allow_runtime_sleep:=true
 var measure_calls:=false
 var measured_usec:=0
 var measured_calls:=0
 func runtime_simulation_required()->bool:
  if simulation_essential or not allow_runtime_sleep:return true
  var player:=get_parent().get("_player") as Node3D
  if not is_instance_valid(player):return true
  var margin:=64.0*16.0
  if global_position.distance_squared_to(player.global_position)<=margin*margin:return true
  var camera:=get_viewport().get_camera_3d()
  if camera==null:return true
  # Passive stress crowd only: retain a generous shadow/view margin. Production
  # AI must also account for quests, combat and other active simulation demands.
  for plane:Plane in camera.get_frustum():
   if plane.distance_to(global_position+Vector3.UP*11.84)>margin:return false
  return true
 func _physics_process(dt:float)->void:
  var started:int=Time.get_ticks_usec() if measure_calls else 0
  age+=dt
  animation_age+=dt
  animation_clip=animation_cycle[(floori((animation_age+animation_phase_offset)/5.0)+animation_slot)%animation_cycle.size()]
  var speed:=19.2 if animation_clip=="walk" else 48.0 if animation_clip=="run" else 0.0
  velocity.x=sin(age*0.65)*speed;velocity.z=cos(age*0.65)*speed
  velocity.y=0.0 if is_on_floor() else velocity.y-156.8*dt
  move_and_slide()
  if measure_calls:measured_usec+=Time.get_ticks_usec()-started;measured_calls+=1
class PopulationVisual extends "res://scripts/ember_hoshi_visual.gd":
 func _select_motion()->String:
  var requested:String=actor.animation_clip
  return requested if motion.has_animation(requested) else super._select_motion()
class MeasuredHoshi extends PopulationVisual:
 var measure_calls:=false
 var measured_usec:=0
 var measured_calls:=0
 func _process(dt:float)->void:
  if not measure_calls:super._process(dt);return
  var started:=Time.get_ticks_usec()
  super._process(dt)
  measured_usec+=Time.get_ticks_usec()-started;measured_calls+=1
func populate(scene:Node,anchor:Vector3)->void:
 var began:=Time.get_ticks_msec()
 check(await Hoshi.prepare_resources(scene),"population resources prepared before reveal")
 # Begin native background resource work while NPCs are attached frame by frame.
 for path:String in HARVEST_SCENES:
  check(ResourceLoader.load_threaded_request(path,"PackedScene")==OK,"harvest resource request: "+path)
 var population_packs:Array=await prepare_scene_packs(POPULATION_SCENES)
 if population_packs.size()!=POPULATION_SCENES.size():return
 var animation_cycle:=PackedStringArray(["idle","walk","run"])
 for clip:String in ["talk","sit","dance"]:
  if Hoshi._motion_library.has_animation(clip):animation_cycle.append(clip)
 progress.population_animation_cycle=animation_cycle
 var map:EmberMapLoader=scene.get_node("Map");var props:=map.get_node("Props")
 var yaw:float=scene._player.camera_rig.yaw
 var east:=Vector3(cos(yaw),0,-sin(yaw));var north:=Vector3(-east.z,0,east.x)
 var house_scene:PackedScene=population_packs[0]
 for i in 4:
  var point:Vector3=anchor+east*(18+i*22)*16+north*-22*16
  check(await map._visual_surface_projection.prepare_floor_query(point),"house floor query prepared")
  var at:Vector3=map.safe_spawn_world(point)
  var house=house_scene.instantiate();house.name="PopulationHouse_%d"%i;house.position=at
  props.add_child(house);house.owner=scene
  await process_frame
 var lamp_scene:PackedScene=population_packs[1]
 for i in 8:
  var point:Vector3=anchor+east*(i*12)*16+north*(10 if i%2==0 else -10)*16
  check(await map._visual_surface_projection.prepare_floor_query(point),"lamp floor query prepared")
  var at:Vector3=map.safe_spawn_world(point)
  var lamp=lamp_scene.instantiate();lamp.name="PopulationLamp_%d"%i;lamp.position=at
  props.add_child(lamp);lamp.owner=scene;population_lamps.append(lamp)
  await process_frame
 # Seven independent hub heroes plus the existing player make eight important
 # Hoshi rigs. This does not expand the persistent party or invent hero IDs.
 for i in (39 if hub_hero_stress else 32):
  var column:float=float(i%8)*2.0-7.0
  var row:float=[-5.0,-3.0,3.0,5.0,7.0][floori(i/8.0)]
  var point:Vector3=anchor+east*column*16.0+north*row*16.0
  check(await map._visual_surface_projection.prepare_floor_query(point),"NPC floor query prepared")
  var at:Vector3=map.safe_spawn_world(point)
  var actor:=PopulationActor.new();actor.name="PopulationNPC_%02d"%i;actor.position=at+Vector3.UP*0.1;actor.age=i*0.618
  actor.animation_slot=i;actor.animation_phase_offset=float(i)*0.113;actor.animation_cycle=animation_cycle
  actor.simulation_essential=hub_hero_stress and i>=32
  actor.collision_layer=2;actor.collision_mask=1|4
  var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.height=23.68;capsule.radius=3.2
  shape.shape=capsule;shape.position.y=11.84;actor.add_child(shape);scene.add_child(actor)
  var visual=make_population_visual();actor.add_child(visual)
  visual.important_character=hub_hero_stress and i>=32
  check(visual.setup(actor,16.0),"native population Hoshi loaded "+str(i))
  if visual.loaded:
   check(visual.skeleton.get_bone_count()==136,"original 136-bone Hoshi rig "+str(i))
   visual.age=float(i)*0.618
   visual.motion.advance(float(i%11)*0.071)
  population_actors.append(actor);population_visuals.append(visual)
  await process_frame
 var item_bodies_before:=0
 for body in get_nodes_in_group("ember_world_item_bodies"):
  if scene.is_ancestor_of(body):item_bodies_before+=1
 var kit=(population_packs[2] as PackedScene).instantiate()
 for i in 16:
  var item=kit.get_node("SturdyCrate").duplicate()
  item.name="PopulationCrate_%02d"%i;item.pickup_id="population_qa_crate_%02d"%i
  item.progress_state=scene._player.progress_state;item.return_radius=0.0
  var point:Vector3=anchor+east*(8+(i%4)*20)*16+north*(-5-floori(i/4.0)*2)*16
  check(await map._visual_surface_projection.prepare_floor_query(point),"crate floor query prepared")
  item.position=map.safe_spawn_world(point)+Vector3.UP*8
  props.add_child(item);population_crates.append(item)
  await process_frame
 kit.free()
 # Match WorldCanvas startup: all authored bodies must exist before records
 # restore/move them and trigger the scene's world-item reconciliation.
 for item in population_crates:item.register_authored_item();item.restore_progress()
 await process_frame
 var item_bodies_after:=0
 for body in get_nodes_in_group("ember_world_item_bodies"):
  if scene.is_ancestor_of(body):item_bodies_after+=1
 progress.population_body_admission={"before":item_bodies_before,"after":item_bodies_after,"expected_added":population_crates.size()}
 check(item_bodies_after==item_bodies_before+population_crates.size(),"population crates have exactly one physical body each")
 map.refresh_omni_shadow_focus(anchor)
 progress.population_prepare_ms=Time.get_ticks_msec()-began
 progress.population_initial=population_status(scene);record("population_spawned")
func make_population_visual()->Node3D:
 return MeasuredHoshi.new() if run_mode in ["cpu","cpu-secondary"] else PopulationVisual.new()
func population_status(scene:Node)->Dictionary:
 var map:EmberMapLoader=scene.get_node("Map");var fallen:=0;var waiting:=0
 for actor in population_actors:
  if not is_instance_valid(actor) or actor.global_position.y < -100:fallen+=1
 for item in population_crates:
  if not is_instance_valid(item) or item.global_position.y < -100:fallen+=1
  elif item._waiting_for_world:waiting+=1
 var recovery=scene.get_node_or_null("WorldRecovery")
 var local_shadows:=0
 for lamp in population_lamps:
  for light in lamp.find_children("*","OmniLight3D",true,false):
   if light.shadow_enabled:local_shadows+=1
 return {"npcs":population_actors.size(),"crates":population_crates.size(),"houses":4,"lamps":population_lamps.size(),"local_shadows":local_shadows,"fallen":fallen,"waiting_items":waiting,"pending_body_support":recovery._pending_support.size() if recovery!=null else -1,"physics_suspended":map._physics_activity_suspended.size(),"shadow_proxies":map._runtime_shadow_props.size(),"ground_tiles":map._visual_surface_projection._tiles.size(),"active_anchors":map.runtime_physics_anchors().size()}
func population_ready(scene:Node)->void:
 var deadline:=Time.get_ticks_msec()+90000;var quiet:=0
 var map:EmberMapLoader=scene.get_node("Map")
 while Time.get_ticks_msec()<deadline:
  var status:=population_status(scene)
  var ready:bool=status.pending_body_support==0 and status.waiting_items==0 and map._visual_surface_projection.pending_tile_count()==0 and map.object_detail_profile().pending==0
  quiet=quiet+1 if ready else 0
  if quiet>=8:progress.population_ready=status;record("population_ready");return
  await process_frame
 check(false,"population preparation converges")
 record("population_timeout")

var fruit_trees:Array[Node3D]=[]
var berry_bushes:Array[Node3D]=[]
var cuttable_tufts:Array[Node3D]=[]
var harvest_packs:Array[PackedScene]=[]
var harvest_ids:Dictionary={}
var harvest_requests:Dictionary={}
var harvest_expected:Dictionary={}
var harvest_inventory:Dictionary={}

func ground_at(map:EmberMapLoader,point:Vector3)->Vector3:
 var sample:Dictionary=map.surface_floor_sample(point)
 check(sample.get("solid",false),"gameplay placement has real terrain "+str(point))
 if sample.get("solid",false):point.y=sample.position.y
 return point

func prepare_scene_packs(paths:Array)->Array[PackedScene]:
 var result:Array[PackedScene]=[]
 for path:String in paths:
  if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
   if ResourceLoader.load_threaded_request(path,"PackedScene")!=OK:
    check(false,"scene background resource request: "+path);return []
 for path:String in paths:
  while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:await process_frame
  if ResourceLoader.load_threaded_get_status(path)!=ResourceLoader.THREAD_LOAD_LOADED:
   check(false,"scene background resource ready: "+path);return []
  var packed:=ResourceLoader.load_threaded_get(path) as PackedScene
  if packed==null:check(false,"background resource is a scene: "+path);return []
  result.append(packed)
 return result

func populate_harvest(scene:Node,anchor:Vector3)->void:
 var map:EmberMapLoader=scene.get_node("Map")
 var props:Node=map.get_node("Props")
 var yaw:float=scene._player.camera_rig.yaw
 var east:=Vector3(cos(yaw),0,-sin(yaw));var north:=Vector3(-east.z,0,east.x)
 harvest_packs=await prepare_scene_packs(HARVEST_SCENES)
 if harvest_packs.size()!=HARVEST_SCENES.size():return
 var packs:Array=harvest_packs
 var centres:Array[Vector3]=[]
 for i in 32:
  var group:=i/8
  var column:=i%4
  var row:=i%8/4
  # Four stations on the same 96m route. Full-size assets and open approaches;
  # nearest interaction centres are 4m apart, with no objects in the east corridor.
  var along:=float(group)*24.0+8.0+float(column)*6.0-9.0
  for kind in 3:
   var lateral:float=[12.0+float(row)*8.0,-14.0-float(row)*6.0,-5.0-float(row)*4.0][kind]
   var requested_point:Vector3=anchor+(east*along+north*lateral)*16.0
   check(await map._visual_surface_projection.prepare_floor_query(requested_point),"harvest floor query prepared")
   var at:=ground_at(map,requested_point)
   for prior:Vector3 in centres:
    check(Vector2(at.x,at.z).distance_to(Vector2(prior.x,prior.z))>=64.0-0.01,"harvest interaction centres at least 4m apart")
   centres.append(at)
   var prop:Node3D=(packs[kind] as PackedScene).instantiate()
   var key:="stress_gameplay_%d_%03d" % [kind,i]
   prop.name=["StressFruitTree_","StressBerryBush_","StressCuttableGrass_"][kind]+str(i)
   prop.position=(props as Node3D).to_local(at)
   if kind==0:
    prop.dropped_flag_id=key+"_dropped"
    var pickup:Node=prop.get_node("ApplePickup")
    pickup.pickup_id=key+"_apple";pickup.available_flag_id=prop.dropped_flag_id;pickup.map_id=scene.map_id
    harvest_ids[pickup.pickup_id]=prop.dropped_flag_id
    fruit_trees.append(prop)
   elif kind==1:
    prop.completion_flag_id=key+"_harvested";berry_bushes.append(prop)
   else:
    prop.revealed_flag_id=key+"_revealed"
    var pickup:Node=prop.get_node("HiddenPickup")
    pickup.pickup_id=key+"_herb";pickup.available_flag_id=prop.revealed_flag_id;pickup.map_id=scene.map_id
    harvest_ids[pickup.pickup_id]=prop.revealed_flag_id
    cuttable_tufts.append(prop)
   var requested:Dictionary={"kind":kind,"flag_id":key+["_dropped","_harvested","_revealed"][kind]}
   if kind!=1:
    requested.pickup_id=key+("_apple" if kind==0 else "_herb")
    requested.item_id="apple" if kind==0 else "herb"
   harvest_requests[str(prop.name)]=requested
   props.add_child(prop);prop.owner=scene
   # One complete gameplay object per frame; no indivisible group of 24 queries.
   await process_frame
 check(fruit_trees.size()==32 and berry_bushes.size()==32 and cuttable_tufts.size()==32,"complete production harvest population")
 progress.harvest_layout={"fruit_trees":32,"berry_bushes":32,"cuttable_grass":32,"groups":4,"minimum_interaction_spacing_m":4,"original_asset_scale":true}
 record("harvest_spawned")

func audit_harvest_bindings(scene:Node,label:String)->bool:
 var state:EmberExploreState=scene._player.progress_state
 var rows:Array=[];var invalid:Array[String]=[]
 var all:Array=[];all.append_array(fruit_trees);all.append_array(berry_bushes);all.append_array(cuttable_tufts)
 for prop:Node3D in all:
  var requested:Dictionary=harvest_requests.get(str(prop.name),{})
  var kind:int=requested.get("kind",-1)
  var flag_id:String=prop.get("dropped_flag_id" if kind==0 else "completion_flag_id" if kind==1 else "revealed_flag_id")
  var row:Dictionary={"node":str(prop.get_path()),"requested":requested,"actual_flag_id":flag_id,"flag_present":state.flags.has(flag_id),"flag_value":state.flags.get(flag_id,false)}
  var valid:bool=flag_id==str(requested.get("flag_id","")) and not bool(state.flags.get(flag_id,false))
  if kind!=1:
   var body:=prop.get_node_or_null("ApplePickup" if kind==0 else "HiddenPickup")
   row.body_exists=is_instance_valid(body)
   if is_instance_valid(body):
    var record_value:Dictionary=state.world_items.get(body.pickup_id,{})
    row.actual_pickup_id=body.pickup_id;row.actual_available_flag_id=body.available_flag_id;row.actual_item_id=body.item_id
    row.body_group=body.is_in_group("ember_world_item_bodies");row.record_present=state.world_items.has(body.pickup_id);row.record=record_value.duplicate(true)
    row.progress_matches=body.progress_state==state;row.visible=body.visible;row.frozen=body.freeze
    valid=valid and body.pickup_id==requested.get("pickup_id","") and body.available_flag_id==flag_id and body.item_id==requested.get("item_id","") and row.body_group and row.progress_matches
    valid=valid and not record_value.is_empty() and int(record_value.get("count",-1))==1 and record_value.get("itemId","")==body.item_id and not body.visible
   else:valid=false
  else:
   row.in_interact_group=prop.is_in_group("ember_interact")
   row.fruit_visible=prop.get_node("Berries").visible
   valid=valid and row.in_interact_group and row.fruit_visible
  row.valid=valid;rows.append(row)
  if not valid:invalid.append(str(prop.name))
 var path:=OUT.path_join("harvest-bindings-"+label+".json")
 FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"storage_root":state.storage_root,"world_records":state.world_items.size(),"bindings":rows,"invalid":invalid}))
 progress["harvest_bindings_"+label]={"report":path,"instances":rows.size(),"invalid":invalid,"world_records":state.world_items.size()}
 check(invalid.is_empty(),"requested IDs and registered harvest records "+label)
 record("harvest_bindings_"+label)
 return invalid.is_empty()

func world_pickup(id:String)->Node3D:
 for body in get_nodes_in_group("ember_world_item_bodies"):
  if body.pickup_id==id and not body.is_queued_for_deletion():return body
 return null

func harvest_status(scene:Node)->Dictionary:
 var state:EmberExploreState=scene._player.progress_state
 var result:Dictionary={"apples":0,"herbs":0,"available":0,"invisible":0,"frozen":0,"waiting":0,"tombstones":0,"missing_records":0,"whole_trees":0,"whole_bushes":0,"uncut_tufts":0}
 for id:String in harvest_ids:
  if not state.world_items.has(id):result.missing_records+=1
  elif int(state.world_items.get(id,{}).get("count",-1))==0:result.tombstones+=1
  var body:=world_pickup(id)
  if body==null:continue
  if body.item_id=="apple":result.apples+=1
  else:result.herbs+=1
  if body.is_item_available():result.available+=1
  if not body.visible:result.invisible+=1
  if body.freeze:result.frozen+=1
  if body._waiting_for_world:result.waiting+=1
 for tree in fruit_trees:
  if tree.get_node("HangingFruit").visible:result.whole_trees+=1
 for bush in berry_bushes:
  if bush.get_node("Berries").visible:result.whole_bushes+=1
 for tuft in cuttable_tufts:
  if tuft.get_node("PileVisual").visible:result.uncut_tufts+=1
 result.active_anchors=scene.get_node("Map").runtime_physics_anchors().size()
 return result

func drain_npc_captures()->void:
 for capture:NpcCapture in npc_captures:
  while not WorkerThreadPool.is_task_completed(capture.task_id):await process_frame
  check(WorkerThreadPool.wait_for_task_completion(capture.task_id)==OK,"NPC capture worker joined")
  check(capture.error==OK,"NPC screenshot saved: "+capture.path)
  capture.timing.encode_write_us=capture.encode_write_us
  capture.timing.error=capture.error
  if not progress.has("capture_timings"):progress.capture_timings=[]
  progress.capture_timings.append(capture.timing)
 npc_captures.clear()

func npc_visibility(scene:Node)->void:
 var rig=scene._player.camera_rig
 progress.npc_visibility=[]
 for fov:float in [40.0,70.0]:
  rig.fov=fov
  await frames(12)
  var camera:Camera3D=root.get_camera_3d()
  var centres:=0;var mesh_bounds:=0;var processing:=0;var rows:Array=[]
  var planes:=camera.get_frustum()
  for visual in population_visuals:
   var center:Vector3=visual.actor.global_position+Vector3.UP*visual.height_m*visual.unit*0.5
   var inside:=camera.is_position_in_frustum(center)
   var intersects:=false
   for mesh:MeshInstance3D in visual.avatar.find_children("*","MeshInstance3D",true,false):
    if not mesh.is_visible_in_tree() or mesh.mesh==null:continue
    var box:AABB=mesh.global_transform*mesh.get_aabb()
    var clipped:=false
    for plane:Plane in planes:
     var outside:=true
     for corner in 8:
      if plane.distance_to(box.get_endpoint(corner))<=0.0:outside=false;break
     if outside:clipped=true;break
    if not clipped:intersects=true;break
   if inside:centres+=1
   if intersects:mesh_bounds+=1
   if visual.is_processing() and visual.actor.is_physics_processing():processing+=1
   rows.append({"name":visual.actor.name,"center_in_frustum":inside,"mesh_bounds_intersect":intersects,"position":var_to_str(visual.actor.global_position),"bones":visual.skeleton.get_bone_count(),"clip":visual.motion.current_animation})
  # Bound retained images to two. Finish all writes before clean frame timings.
  if npc_captures.size()>=2:await drain_npc_captures()
  await RenderingServer.frame_post_draw
  var readback_began:=Time.get_ticks_usec()
  var image:=root.get_texture().get_image()
  var readback_us:=Time.get_ticks_usec()-readback_began
  var capture:=NpcCapture.new()
  capture.image=image;capture.path=OUT.path_join("npc_draw_fov%d.png" % int(fov))
  capture.timing={"fov":fov,"frame":Engine.get_process_frames(),"readback_us":readback_us,"width":image.get_width(),"height":image.get_height(),"scope":"diagnostic readback on main; PNG encode/write on worker, outside clean timing"}
  var enqueue_began:=Time.get_ticks_usec()
  capture.task_id=WorkerThreadPool.add_task(capture.write,false,"NPC visibility PNG")
  capture.timing.enqueue_us=Time.get_ticks_usec()-enqueue_began
  npc_captures.append(capture)
  check(camera==rig._cam and is_equal_approx(camera.fov,fov),"actual NPC draw camera FOV "+str(fov))
  check(image.get_width()==2560 and image.get_height()==1440 and is_equal_approx(root.scaling_3d_scale,1.0),"native NPC draw resolution")
  check(processing==population_actors.size(),"all population controllers and visuals active")
  if fov==70.0:check(centres>=16,"at least sixteen actual Hoshi centres on screen at FOV70")
  progress.npc_visibility.append({"fov":camera.fov,"centres_in_frustum":centres,"mesh_bounds_intersect":mesh_bounds,"processing":processing,"actors":rows})
 await drain_npc_captures()
 progress.harvest_whole=harvest_status(scene)
 check(progress.harvest_whole.whole_trees==32 and progress.harvest_whole.whole_bushes==32 and progress.harvest_whole.uncut_tufts==32 and progress.harvest_whole.invisible==64,"all new gameplay objects whole before clean movement")
 record("npc_visibility")

func camera_state(_scene:Node)->Dictionary:
 var camera:=root.get_camera_3d()
 return {"fov":camera.fov,"viewport":str(camera.get_viewport().size),"scale":camera.get_viewport().scaling_3d_scale,"near":camera.near,"far":camera.far,"transform":var_to_str(camera.global_transform)}

func cpu_comparison(scene:Node)->void:
 # Diagnostic ablations only: models, density, camera and physical bodies remain.
 # No diagnostic result is a gameplay performance/streaming acceptance.
 progress.pass_scope="CPU attribution and exact restoration only; diagnostic ablations are not gameplay FPS"
 progress.cpu_scope={"npc_controller":"fixture CharacterBody3D move_and_slide, not production AI","npc_animation":"production Hoshi pose/morph/secondary bones","world_off":"script callbacks outside player/NPC subtrees; engine/timers/coroutines remain","monitor_note":"Performance monitors can lag by one second; use warm intervals; never subtract GPU from wall"}
 var actor:EmberPlayer=scene._player
 var rig=actor.camera_rig;rig.fov=70.0
 await frames(90)
 await wait_grass(scene,"cpu_ready")
 var grass_before:=grass_status(scene)
 var saved_callbacks:Array=[]
 var nodes:Array[Node]=[scene]
 while not nodes.is_empty():
  var node:Node=nodes.pop_back()
  if node==actor or (node is CharacterBody3D and population_actors.has(node)):continue
  for child:Node in node.get_children():nodes.append(child)
  if node.get_script()!=null and (node.is_processing() or node.is_physics_processing()):
   saved_callbacks.append({"node":node,"idle":node.is_processing(),"physics":node.is_physics_processing()})
 var poses:Array=[]
 for npc in population_actors:poses.append({"pose":npc.global_transform,"velocity":npc.velocity,"age":npc.age})
 var visual_flags:Array=[]
 for visual in population_visuals:visual_flags.append(visual.is_processing())
 var blink_bindings:Array=[];var springs:Array=[]
 for visual in population_visuals:
  blink_bindings.append(visual.blink_targets.duplicate())
  for modifier in visual.skeleton.find_children("*","SpringBoneSimulator3D",true,false):
   springs.append({"node":modifier,"active":modifier.active,"mutable_axes":modifier.mutable_bone_axes})
 progress.cpu_rigs={"npcs":population_visuals.size(),"bones_each":population_visuals[0].skeleton.get_bone_count(),"spring_simulators":springs.size(),"blink_bindings_each":blink_bindings[0].size()}
 progress.cpu_callbacks=[]
 for row:Dictionary in saved_callbacks:
  progress.cpu_callbacks.append({"node":str(row.node.get_path()),"script":str(row.node.get_script().resource_path),"idle":row.idle,"physics":row.physics})
 progress.cpu_initial={"population":population_status(scene),"grass":grass_before,"camera":camera_state(scene)}
 var phases:Array[String]=["full_A","npc_motion_off","full_B","npc_animation_off","full_C","npc_both_off","full_D","world_callbacks_off","full_E","npc_blink_off","full_F","npc_secondary_off","full_G"]
 if run_mode=="cpu-secondary":phases.assign(["full_A","native_cached_axes","full_B"])
 progress.cpu_rigs.cached_axes=springs.filter(func(row):return not row.mutable_axes).size()
 for label:String in phases:
  for row:Dictionary in saved_callbacks:
   row.node.set_process(row.idle and label!="world_callbacks_off")
   row.node.set_physics_process(row.physics and label!="world_callbacks_off")
  for index in population_actors.size():
   var npc=population_actors[index]
   npc.set_physics_process(label not in ["npc_motion_off","npc_both_off"])
   npc.global_transform=poses[index].pose;npc.velocity=poses[index].velocity;npc.age=poses[index].age
   npc.reset_physics_interpolation()
   population_visuals[index].set_process(visual_flags[index] and label not in ["npc_animation_off","npc_both_off"])
   population_visuals[index].blink_targets=[] if label=="npc_blink_off" else blink_bindings[index]
  for row:Dictionary in springs:
   row.node.active=row.active and label!="npc_secondary_off"
   var mutable_axes:bool=false if label=="native_cached_axes" else row.mutable_axes
   if row.node.mutable_bone_axes!=mutable_axes:row.node.mutable_bone_axes=mutable_axes
  # Monitors update at a coarser cadence than frames. Settle after each switch.
  var warm_until:=Time.get_ticks_msec()+1600
  while Time.get_ticks_msec()<warm_until:await process_frame
  progress["cpu_"+label]=await cpu_sample(scene,false)
  record("cpu_"+label)
 for row:Dictionary in saved_callbacks:
  row.node.set_process(row.idle);row.node.set_physics_process(row.physics)
 for index in population_actors.size():
  population_actors[index].set_physics_process(true)
  population_visuals[index].set_process(visual_flags[index])
  population_actors[index].measure_calls=true
  population_visuals[index].measure_calls=true
  population_visuals[index].blink_targets=blink_bindings[index]
 for row:Dictionary in springs:row.node.active=row.active
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 EngineDebugger.profiler_enable("visual",true)
 await frames(100)
 progress.cpu_scopes=await cpu_sample(scene,true)
 record("cpu_scopes")
 for index in population_actors.size():
  population_actors[index].measure_calls=false;population_visuals[index].measure_calls=false
 EngineDebugger.profiler_enable("visual",false)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),false)
 # Native script profiler is a separate interval; its overhead is not FPS evidence.
 # --debug is required. Never disable an uninitialised local scripts profiler.
 if OS.is_debug_build() and run_mode=="cpu":
  print("CPU_SCRIPT_PROFILE_BEGIN")
  EngineDebugger.profiler_enable("scripts",true)
  await frames(180)
  EngineDebugger.profiler_enable("scripts",false)
  print("CPU_SCRIPT_PROFILE_END")
 var callbacks_restored:=true
 for row:Dictionary in saved_callbacks:
  callbacks_restored=callbacks_restored and row.node.is_processing()==row.idle and row.node.is_physics_processing()==row.physics
 for index in population_actors.size():
  callbacks_restored=callbacks_restored and population_actors[index].is_physics_processing() and population_visuals[index].is_processing()==visual_flags[index]
  callbacks_restored=callbacks_restored and population_visuals[index].blink_targets==blink_bindings[index]
 for row:Dictionary in springs:callbacks_restored=callbacks_restored and row.node.active==row.active and row.node.mutable_bone_axes==row.mutable_axes
 var grass_after:=grass_status(scene)
 progress.cpu_restored={"callbacks":callbacks_restored,"population":population_status(scene),"grass":grass_after,"camera":camera_state(scene)}
 check(callbacks_restored,"all diagnostic callback switches restored")
 check(grass_before.instances==grass_after.instances and grass_before.patches==grass_after.patches,"CPU diagnostic preserves vegetation density and buffers")
 check(population_status(scene).fallen==0 and population_actors.size()==32,"all NPC/crates remain after CPU diagnostic")
 check(root.size==Vector2i(2560,1440) and is_equal_approx(root.scaling_3d_scale,1.0),"CPU native resolution retained")
 record("cpu_restored")

func cpu_sample(scene:Node,scoped:bool)->Dictionary:
 var rows:Array=[];var wall:Array=[];var physics:Array=[];var process_cpu:Array=[]
 var gpu:Array=[];var render_cpu:Array=[];var motion_cost:Array=[];var visual_cost:Array=[]
 var started:=Time.get_ticks_usec();var previous:=started
 var old_motion:=0;var old_visual:=0
 if scoped:
  for npc in population_actors:old_motion+=npc.measured_usec
  for visual in population_visuals:old_visual+=visual.measured_usec
 var tick_start:=Engine.get_physics_frames()
 while rows.size()<240 or Time.get_ticks_usec()-started<3000000:
  await process_frame
  var now:=Time.get_ticks_usec();var elapsed:=float(now-previous)/1000.0;previous=now
  var physics_ms:=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
  var process_ms:=Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
  wall.append(elapsed);physics.append(physics_ms);process_cpu.append(process_ms)
  var row:Dictionary={"frame":Engine.get_process_frames(),"wall_ms":elapsed,"physics_monitor_ms":physics_ms,"process_monitor_ms":process_ms}
  if scoped:
   var motion_sum:=0;var visual_sum:=0
   for npc in population_actors:motion_sum+=npc.measured_usec
   for visual in population_visuals:visual_sum+=visual.measured_usec
   var motion_ms:=float(motion_sum-old_motion)/1000.0;var visual_ms:=float(visual_sum-old_visual)/1000.0
   motion_cost.append(motion_ms);visual_cost.append(visual_ms);old_motion=motion_sum;old_visual=visual_sum
   gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
   render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
   row.npc_motion_ms=motion_ms;row.npc_visual_ms=visual_ms
  rows.append(row)
 var result:Dictionary={"wall_ms":stats(wall),"physics_monitor_ms":stats(physics),"process_monitor_ms":stats(process_cpu),"seconds":float(Time.get_ticks_usec()-started)/1000000.0,"physics_ticks":Engine.get_physics_frames()-tick_start,"visible_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"population":population_status(scene)}
 if scoped:
  result.npc_motion_per_render_frame_ms=stats(motion_cost);result.npc_visual_per_render_frame_ms=stats(visual_cost)
  result.gpu_ms=stats(gpu);result.render_cpu_ms=stats(render_cpu)
  result.scope="inclusive synchronous call scopes; native deferred skeleton/physics/render work may fall outside; scopes are not additive exclusive CPU"
 var file_index:=int(progress.get("cpu_sample_index",0));progress.cpu_sample_index=file_index+1
 var path:=OUT.path_join("cpu-sample-%02d.json"%file_index)
 FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(rows));result.frames_path=path
 return result

func cpu_hub_comparison(scene:Node)->void:
 progress.pass_scope="CPU hub attribution and restoration only; diagnostic cuts are not gameplay FPS"
 var all_visuals:Array=population_visuals.duplicate()
 all_visuals.append(scene._player._hoshi_visual)
 var visuals:Array=[];var springs:Array=[];var poses:Array=[];var callbacks:Array=[]
 for visual in all_visuals:
  var important:bool=visual.important_character or visual._animation_lod.is_party_visual(visual.actor)
  visuals.append({"node":visual,"important":important,"idle":visual.is_processing()})
  for spring in visual._animation_lod._springs:springs.append({"node":spring,"important":important,"active":spring.active})
 for actor in population_actors:poses.append({"pose":actor.global_transform,"velocity":actor.velocity,"age":actor.age,"physics":actor.is_physics_processing()})
 var nodes:Array[Node]=[scene]
 while not nodes.is_empty():
  var node:Node=nodes.pop_back()
  if node==scene._player or (node is CharacterBody3D and population_actors.has(node)):continue
  for child:Node in node.get_children():nodes.append(child)
  if node.get_script()!=null and (node.is_processing() or node.is_physics_processing()):
   callbacks.append({"node":node,"idle":node.is_processing(),"physics":node.is_physics_processing()})
 var before_grass:=grass_status(scene);var before_camera:=camera_state(scene)
 progress.cpu_hub_callbacks=[]
 for row in callbacks:
  progress.cpu_hub_callbacks.append({"node":str(row.node.get_path()),"script":row.node.get_script().resource_path,"group":hub_callback_group(row.node),"idle":row.idle,"physics":row.physics})
 progress.cpu_hub_scope={"ordinary_controller":"32 fixture move_and_slide callbacks, not production AI","ordinary_visual":"32 production Hoshi manual pose/morph callbacks, springs already inactive","important_secondary":"eight authored native spring solvers only","important_visual":"eight visual callbacks plus springs; skin/geometry retained","world_callbacks":"scripts outside player/population subtrees; native/timers remain","additivity":"counterfactual differences overlap; do not add them or subtract GPU from wall"}
 var phases:Array[String]=["full_A","ordinary_controller_off","full_B","ordinary_visual_off","full_C","important_secondary_off","full_D","important_visual_off","full_E","world_callbacks_off","full_F","all_visuals_off","full_G"]
 var world_groups:=OS.get_environment("EMBER_CPU_HUB_WORLD")=="1"
 if world_groups:phases.assign(["full_A","world_grass_off","full_B","world_map_off","full_C","world_props_off","full_D","world_other_off","full_E"])
 var samples:Dictionary={}
 for label in phases:
  for row in callbacks:
   var off:bool=label=="world_callbacks_off" or label=="world_"+hub_callback_group(row.node)+"_off"
   row.node.set_process(row.idle and not off)
   row.node.set_physics_process(row.physics and not off)
  for index in population_actors.size():
   var actor=population_actors[index];var visual=population_visuals[index]
   actor.set_physics_process(poses[index].physics and not(label=="ordinary_controller_off" and not visual.important_character))
   actor.global_transform=poses[index].pose;actor.velocity=poses[index].velocity;actor.age=poses[index].age
   actor.reset_physics_interpolation()
  for row in visuals:
   var disabled:bool=label=="all_visuals_off" or (label=="ordinary_visual_off" and not row.important) or (label=="important_visual_off" and row.important)
   row.node.set_process(row.idle and not disabled)
  for row in springs:
   row.node.active=row.active and label!="all_visuals_off" and not(row.important and label in ["important_secondary_off","important_visual_off"])
   row.node.reset()
  await create_timer(1.6).timeout
  samples[label]=await cpu_sample(scene,false)
  progress.cpu_hub_samples=samples
  record("hub_"+label)
 var restored:=true
 for row in callbacks:
  row.node.set_process(row.idle);row.node.set_physics_process(row.physics)
  restored=restored and row.node.is_processing()==row.idle and row.node.is_physics_processing()==row.physics
 for index in population_actors.size():population_actors[index].set_physics_process(poses[index].physics)
 for row in visuals:
  row.node.set_process(row.idle);restored=restored and row.node.is_processing()==row.idle
 for row in springs:
  row.node.active=row.active;row.node.reset();restored=restored and row.node.active==row.active
 progress.cpu_hub_restored={"callbacks":restored,"secondary":secondary_policy_status(scene),"grass_before":before_grass,"grass_after":grass_status(scene),"camera_before":before_camera,"camera_after":camera_state(scene),"world_script_callbacks":callbacks.size()}
 check(restored,"all hub diagnostic callbacks and springs restored")
 check(before_camera==camera_state(scene),"hub diagnostic preserves actual camera")
 check(before_grass.patches==grass_status(scene).patches,"hub diagnostic preserves vegetation patches")
 check(secondary_policy_status(scene).ordinary_active_solvers==0 and secondary_policy_status(scene).hero_active_solvers==8,"production eight-hero spring policy restored")
 check(population_actors.size()==39 and population_status(scene).fallen==0,"all39 crowd actors remain supported")
 await sample_live_crowd(scene)
 progress.population_final=population_status(scene)
 progress.validation_scope="same-process40rig CPU hub attribution; no gameplay moving/cold/interaction acceptance"
 record("cpu_hub_restored")

func hub_callback_group(node:Node)->String:
 if node.get_script()==Grass:return "grass"
 if node is EmberMapLoader:return "map"
 if node is EmberVoxelProp:return "props"
 return "other"

func secondary_policy_status(scene:Node)->Dictionary:
 var ordinary:=0;var heroes:=0;var ordinary_active:=0;var heroes_active:=0
 var all_visuals:Array=population_visuals.duplicate()
 for visual in scene._player.find_children("*","Node3D",true,false):
  if visual.get_script()==Hoshi:all_visuals.append(visual)
 for visual in all_visuals:
  var important:bool=visual.important_character or visual._animation_lod.is_party_visual(visual.actor)
  if important:heroes+=1
  else:ordinary+=1
  for spring:SpringBoneSimulator3D in visual._animation_lod._springs:
   if spring.active:
    if important:heroes_active+=1
    else:ordinary_active+=1
 return {"ordinary":ordinary,"heroes":heroes,"ordinary_active_solvers":ordinary_active,"hero_active_solvers":heroes_active}

func compare_secondary_policy(scene:Node)->void:
 var results:Dictionary={}
 for label in ["all_springs","npc_springs_off","all_springs_return"]:
  for visual in population_visuals:
   visual._animation_lod.set_secondary_motion_enabled(label!="npc_springs_off" or visual.important_character)
  await create_timer(1.6).timeout
  results[label]=await cpu_sample(scene,false)
  results[label].secondary=secondary_policy_status(scene)
  record("secondary_"+label)
 for visual in population_visuals:visual._animation_lod.set_secondary_motion_enabled(visual.important_character)
 progress.secondary_compare={"samples":results,"scope":"same scene32 ordinary NPC+8important Hoshi incl player; only NPC spring activity varies; full world callbacks, no render timers; no party roster changes"}
 var status:=secondary_policy_status(scene)
 check(status.ordinary==32 and status.heroes==8,"32 ordinary NPC and eight important heroes present")
 check(status.ordinary_active_solvers==0 and status.hero_active_solvers==8,"springs restricted to eight important heroes")
 progress.secondary_policy=status
 record("secondary_compare")

func compare_grass_meshes(scene:Node)->void:
 var previous:Mesh=load(OS.get_environment("EMBER_GRASS_COMPARE_MESH"))
 var patches:Array=[];var meshes:Array=[];var buffers:Array=[]
 for patch in get_nodes_in_group("ember_grass_patches"):
  if scene.is_ancestor_of(patch) and patch.detail_kind==0 and patch._look==0 and patch._visual!=null and patch._visual.multimesh!=null:
   patches.append(patch);meshes.append(patch._visual.multimesh.mesh);buffers.append(patch._visual.multimesh.buffer)
 var results:Dictionary={}
 for label in ["current8","previous28","current8-return"]:
  for i in patches.size():patches[i]._visual.multimesh.mesh=previous if label=="previous28" else meshes[i]
  await sample_live_crowd(scene)
  results[label]=progress.live_crowd.duplicate(true)
 for i in patches.size():check(patches[i]._visual.multimesh.buffer==buffers[i],"mesh comparison preserves instance buffer")
 progress.grass_mesh_compare={"patches":patches.size(),"samples":results,"scope":"same live scene and materials; ordinary mesh only"}
 record("grass_mesh_compare")

func sample_live_crowd(scene:Node)->void:
 # Live actors, physics and automatic saves stay enabled. Keep render timers
 # separate from the clean moving route; do not derive CPU time as wall minus GPU.
 progress.hidden_support=hidden_support_snapshot(scene)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 EngineDebugger.profiler_enable("visual",true)
 await frames(20)
 var wall:Array=[];var gpu:Array=[];var render_cpu:Array=[];var process_cpu:Array=[];var physics_cpu:Array=[]
 var previous:=Time.get_ticks_usec()
 for index in 180:
  await process_frame
  var now:=Time.get_ticks_usec();wall.append(float(now-previous)/1000.0);previous=now
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
  render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
  process_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
  physics_cpu.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
 var camera:Camera3D=root.get_camera_3d()
 progress.live_crowd={"scope":"live full workload at the start cohort; diagnostic timers enabled; not the clean moving sample","fov":camera.fov,"viewport":str(root.size),"scale":root.scaling_3d_scale,"wall_ms":stats(wall),"gpu_ms":stats(gpu),"render_cpu_ms":stats(render_cpu),"process_monitor_ms":stats(process_cpu),"physics_monitor_ms":stats(physics_cpu),"visible_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"population":population_status(scene),"harvest":harvest_status(scene)}
 EngineDebugger.profiler_enable("visual",false)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),false)
 record("live_crowd")

func hidden_support_snapshot(scene:Node)->Dictionary:
 # Counterfactual sets only: never remove bodies or alter the measured policy.
 var map:EmberMapLoader=scene.get_node("Map")
 var projection=map._visual_surface_projection
 var recovery=scene.get_node("WorldRecovery")
 var other_points:Array[Vector3]=[];var inactive:=0;var all_inactive:=0
 for row:Dictionary in recovery._origins.values():
  var body:PhysicsBody3D=row.body.get_ref()
  if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion() or body.get_world_3d()!=map.get_world_3d():continue
  if recovery._unavailable_world_item(body):
   all_inactive+=1
   if harvest_ids.has(str(body.pickup_id)):inactive+=1
   continue
  other_points.append(body.global_position)
 other_points.append(scene._player.global_position)
 if is_instance_valid(scene._player.party_followers):
  for follower:Node3D in scene._player.party_followers._followers:
   if is_instance_valid(follower):other_points.append(follower.global_position)
 var without:Dictionary={}
 for point:Vector3 in other_points:
  var local:Vector3=projection.to_local(point)
  var centre:=Vector2i(floori(local.x/64.0),floori(local.z/64.0))
  for z in range(centre.y-1,centre.y+2):
   for x in range(centre.x-1,centre.x+2):without[Vector2i(x,z)]=true
 var all_support:Dictionary=projection._runtime_support_tiles(root.get_camera_3d())
 var extent:=Vector2i(projection.document.width,projection.document.depth)
 var policy=projection.detail_policy
 var with_wanted:Dictionary=policy.ground_candidates(extent,64,projection.smooth_column_limit,projection._resident_tiles,all_support)
 var without_wanted:Dictionary=policy.ground_candidates(extent,64,projection.smooth_column_limit,projection._resident_tiles,without)
 return {"scope":"current policy vs excluding all closed flag-gated WorldItems; overlapping tiles counted once","unavailable_harvest_bodies":inactive,"all_unavailable_world_items":all_inactive,"with_wanted_fine_tiles":with_wanted.size(),"without_wanted_fine_tiles":without_wanted.size(),"marginal_wanted_fine_tiles":with_wanted.size()-without_wanted.size()}

func physics_frames(n:int)->void:
 for i in n:await physics_frame

func approach(scene:Node,target:Vector3,distance:float)->bool:
 var actor:EmberPlayer=scene._player
 var map:EmberMapLoader=scene.get_node("Map")
 # Select an unoccupied real-floor approach, then keep the player's Jolt body active.
 # Teleports belong only to this untimed mechanics setup, never the moving route.
 var own_shape:=actor.find_children("*","CollisionShape3D",true,false)[0] as CollisionShape3D
 var offset:Transform3D=actor.global_transform.affine_inverse()*own_shape.global_transform
 for index in 16:
  var direction:=Vector3(sin(float(index)*TAU/16.0),0,cos(float(index)*TAU/16.0))
  var at:=ground_at(map,target+direction*distance)
  at.y+=0.2
  map.prepare_physics_destination(at)
  var deadline:=Time.get_ticks_msec()+90000
  while not map.physics_destination_ready(at) and Time.get_ticks_msec()<deadline:await process_frame
  if not map.physics_destination_ready(at):continue
  var query:=PhysicsShapeQueryParameters3D.new();query.shape=own_shape.shape;query.collision_mask=1|2|4;query.exclude=[actor.get_rid()]
  query.transform=Transform3D(actor.global_basis,at)*offset
  if not actor.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():continue
  actor.global_position=at;actor.velocity=Vector3.ZERO;actor.camera_rig.reset_follow_height()
  await physics_frames(3)
  return true
 check(false,"unoccupied interaction approach at "+str(target));return false

func strike(scene:Node,target:Node3D,label:String)->bool:
 if not await approach(scene,target.global_position,28.0):return false
 var actor:EmberPlayer=scene._player
 var direction:Vector3=target.global_position-actor.global_position;direction.y=0
 steer(actor,direction);await physics_frames(2)
 for key in ["move_east","move_west","move_south","move_north"]:Input.action_release(key)
 await physics_frames(24) # Preserve the production 350ms cooldown.
 var saved_before:=saved_paths.size();var started:=Time.get_ticks_usec()
 var hit:=actor.world_strike()
 record_operation("strike "+label,started,saved_before)
 check(hit,"production world_strike "+label)
 await physics_frames(6)
 return hit

func collect(scene:Node,body:Node3D,label:String)->void:
 check(is_instance_valid(body),"physical pickup exists "+label)
 if not is_instance_valid(body):return
 var pickup:EmberInteract=body.get_node("Pickup")
 # Stay within the production interaction reach, but outside the item/NPC
 # collision volume. The old 5-unit shell was inside the herb's occupied space.
 if not await approach(scene,pickup.get_node("Shape").global_position,10.0):return
 check(scene._player._nearest()==pickup,"production nearest selects "+label)
 if scene._player._nearest()!=pickup:return
 var saved_before:=saved_paths.size();var started:=Time.get_ticks_usec()
 scene._player._try_interact()
 record_operation("collect "+label,started,saved_before)
 await physics_frames(4)

func record_operation(label:String,started:int,saved_before:int)->void:
 if not progress.has("operations"):progress.operations=[]
 progress.operations.append({"operation":label,"call_elapsed_ms":float(Time.get_ticks_usec()-started)/1000.0,"autosaves":saved_paths.size()-saved_before,"scope":"synchronous production call including save wait; not exclusive CPU or later tween/physics"})

func interaction_phase(scene:Node,anchor:Vector3)->void:
 var state:EmberExploreState=scene._player.progress_state
 harvest_inventory={"apple":int(state.inventory.get("apple",0)),"forest_berry":int(state.inventory.get("forest_berry",0)),"herb":int(state.inventory.get("herb",0))}
 var before_saves:=saved_paths.size()
 var apple_ids:Array[String]=[];var herb_ids:Array[String]=[]
 for i in 3:
  apple_ids.append("stress_gameplay_0_%03d_apple" % i)
  herb_ids.append("stress_gameplay_2_%03d_herb" % i)
 for i in 2:
  await strike(scene,fruit_trees[i],"fruit tree "+str(i))
  var apple:=world_pickup(apple_ids[i])
  check(apple!=null and apple.visible and not apple.freeze and not fruit_trees[i].get_node("HangingFruit").visible,"tree releases its existing physical apple "+str(i))
  if apple!=null:
   var height:=apple.global_position.y
   await physics_frames(100)
   check(apple.global_position.y<height-8.0,"apple actually falls "+str(i))
   if i==0:await collect(scene,apple,"apple")
 await strike(scene,fruit_trees[0],"repeat tree")
 check(world_pickup(apple_ids[0])==null,"repeat hit does not respawn collected apple")
 var bush:Node3D=berry_bushes[0]
 if await approach(scene,bush.global_position,28.0):
  check(scene._player._nearest()==bush,"nearest selects berry bush")
  if scene._player._nearest()==bush:
   var saved_before:=saved_paths.size();var started:=Time.get_ticks_usec()
   scene._player._try_interact()
   record_operation("collect berries",started,saved_before)
  await physics_frames(3)
  check(not bush.get_node("Berries").visible and not bush.is_in_group("ember_interact"),"berry F hides fruit/prompt")
  var count:=int(state.inventory.get("forest_berry",0));bush.activate_from(scene._player)
  check(int(state.inventory.get("forest_berry",0))==count,"repeat berry activation cannot reward twice")
 for i in 2:
  await strike(scene,cuttable_tufts[i],"cuttable grass "+str(i))
  check(not cuttable_tufts[i].get_node("PileVisual").visible and cuttable_tufts[i].get_node("CutStubble").visible,"cut reveals stubble "+str(i))
  if i==0:await collect(scene,world_pickup(herb_ids[i]),"herb")
 harvest_expected={"apple_ids":apple_ids,"herb_ids":herb_ids}
 verify_harvest_state(scene,"immediately_after_actions")
 check(state.persistence_enabled and saved_paths.size()-before_saves>=7,"real isolated autosaves remain enabled for gameplay actions")
 for path:String in saved_paths:check(path.begins_with(sandbox),"autosave remains in user://ember-tests sandbox")
 progress.interaction_autosaves={"count":saved_paths.size()-before_saves,"paths":saved_paths.duplicate(),"persistence_enabled":state.persistence_enabled}
 record("interaction_phase")
 await reset_anchor(scene,anchor)

func verify_harvest_state(scene:Node,label:String)->void:
 var state:EmberExploreState=scene._player.progress_state
 var apples:Array=harvest_expected.get("apple_ids",[]);var herbs:Array=harvest_expected.get("herb_ids",[])
 check(apples.size()==3 and herbs.size()==3,"mechanics expected IDs available "+label)
 if apples.size()!=3 or herbs.size()!=3:return
 for i in 3:
  var apple_id:String=apples[i];var herb_id:String=herbs[i]
  var apple_record:Dictionary=state.world_items.get(apple_id,{});var herb_record:Dictionary=state.world_items.get(herb_id,{})
  check(not apple_record.is_empty() and not herb_record.is_empty(),"persistent pickup records exist "+label+str(i))
  var apple:=world_pickup(apple_id);var herb:=world_pickup(herb_id)
  check(bool(state.flags.get(fruit_trees[i].dropped_flag_id,false))==(i<2),"independent apple flags "+label+str(i))
  check(fruit_trees[i].get_node("HangingFruit").visible==(i==2),"hanging/drop/collected apple view "+label+str(i))
  check(bool(state.flags.get(cuttable_tufts[i].revealed_flag_id,false))==(i<2),"independent cut flags "+label+str(i))
  check(cuttable_tufts[i].get_node("PileVisual").visible==(i==2) and cuttable_tufts[i].get_node("CutStubble").visible==(i<2),"cut/collected/uncut views "+label+str(i))
  if i==0:
   check(apple==null and herb==null and int(apple_record.get("count",-1))==0 and int(herb_record.get("count",-1))==0,"collected items retain tombstones "+label)
  else:
   check(apple!=null and herb!=null,"uncollected physical items survive "+label+str(i))
   if apple!=null and herb!=null:check(apple.visible==(i==1) and herb.visible==(i==1),"gated item visibility "+label+str(i))
 check(not berry_bushes[0].get_node("Berries").visible and berry_bushes[1].get_node("Berries").visible,"independent harvested and whole bushes "+label)
 for item:String in harvest_inventory:
  var delta:=3 if item=="forest_berry" else 1
  check(int(state.inventory.get(item,0))==int(harvest_inventory[item])+delta,"exact runtime inventory reward "+item+" "+label)
 var status:=harvest_status(scene)
 check(status.whole_trees==30 and status.whole_bushes==31 and status.uncut_tufts==30,"all other authored harvest instances unchanged "+label)
 check(status.apples==31 and status.herbs==31 and status.tombstones==2 and status.available==2 and status.invisible==60,"exact physical pickup population after subset actions "+label)
 progress["harvest_"+label]=status
