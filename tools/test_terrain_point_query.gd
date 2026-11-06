extends SceneTree
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Rules=preload("res://scripts/prototypes/ember_terrain_surface_rules.gd")
var errors:Array[String]=[]
var samples:=0
var max_error:=0.0
func _initialize()->void:run.call_deferred()
func run()->void:
 for shape in 3:
  var source:=Terrain.new();source.width=96;source.depth=96;source.origin_y=-7
  source.heights.resize(96*96);source.top_materials.resize(96*96)
  var rules:Dictionary={}
  for z in 96:
   for x in 96:
    source.heights[x+z*96]=20 if shape==0 else 10+(x+z)/8 if shape==1 else 12+(x/13)%3*7+(z/19)%2*9
    source.top_materials[x+z*96]=(x/17+z/23)%3
    if shape==2 and x%4==0:rules[Vector2i(x,z)]=Rules.protect_code(0.7) if z%3==0 else Rules.round_code(0.6,1 if z%2==0 else 2)
  source.surface_rules=Rules.changed({},rules)
  for document in [source,source.sectioned_copy()]:
   var projection:=TerrainProjection.new();projection.document=document
   var full:Dictionary={}
   for p:Vector2 in [Vector2.ZERO,Vector2(0.25,0.75),Vector2(31.6,32.8),Vector2(63.999,63.001),Vector2(64.2,64.8),Vector2(95.9,95.1)]:
    var key:=Vector2i(floori(p.x/64),floori(p.y/64))
    if not full.has(key):
     var begin:=key*64
     full[key]=Smooth.field(document,Rect2i(begin,Vector2i(mini(64,96-begin.x),mini(64,96-begin.y))))
    var expected:=Smooth.sample(full[key],p)
    var prepared:=TerrainProjection.PointQueryJob.new(document,Vector2i(p.floor()))
    prepared.run()
    if absf(Smooth.sample(prepared.result,p)-expected)>0.00001:errors.append("snapshot point/full mismatch "+str(p))
    for repeat in 2:
     var actual:float=projection._smooth_height(p)
     max_error=maxf(max_error,absf(expected-actual));samples+=1
     if absf(expected-actual)>0.00001:errors.append("point/full mismatch "+str(p))
   # The existing column revision invalidates both large and point query caches.
   projection.document=source.working_copy();projection.document.heights.fill(50)
   projection.document.surface_rules={};projection._column_revision+=1;projection._smooth_fields.clear()
   if absf(projection._smooth_height(Vector2(31.6,32.8))-43.0)>0.00001:errors.append("revised source height")
   projection.document.heights.fill(60);projection._column_revision+=1;projection._smooth_fields.clear()
   if absf(projection._smooth_height(Vector2(31.6,32.8))-53.0)>0.00001:errors.append("same-source revision height")
   projection.free()
 # Real async publication must reject stale data and join a cancelled task.
 var live:=TerrainProjection.new();live.ground_style=1;live.set_process(false);root.add_child(live)
 live.document=Terrain.new();live.document.width=32;live.document.depth=32
 live.document.heights.resize(32*32);live.document.heights.fill(20)
 live.document.top_materials.resize(32*32)
 var target:=Vector3(12.3,0,13.7)
 if not await live.prepare_floor_query(target):errors.append("async query readiness")
 if absf(live.floor_surface_sample(target).position.y-20.0)>0.00001:errors.append("async query surface")
 live.document.heights.fill(30);live._column_revision+=1
 if absf(live._smooth_height(Vector2(target.x,target.z))-30.0)>0.00001:errors.append("async cached height after revision")
 live._smooth_fields.clear()
 live._query_point.clear()
 process_frame.connect(func():live._column_revision+=1,CONNECT_ONE_SHOT)
 if await live.prepare_floor_query(target):errors.append("stale async query published")
 live._query_point.clear()
 process_frame.connect(func():live._cancel_mesh_lods(),CONNECT_ONE_SHOT)
 if await live.prepare_floor_query(target):errors.append("cancelled async query published")
 if not live._query_point_tasks.is_empty():errors.append("async query task not joined")
 live.free()
 print("TERRAIN_POINT_QUERY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"samples":samples,"max_error":max_error,"cases":"flat/slope/steps+mixed palette+surface rules,dense/sectioned,edges/seam,repeat/revision,async/stale/cancel"}))
 quit(0 if errors.is_empty() else 1)
