extends SceneTree
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
class Probe extends TerrainProjection:
 func _ready():pass
 func _process(_delta):pass
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var random:=RandomNumberGenerator.new();random.seed=7313
 var policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd")
 for i in 100:
  var basis:=Basis.from_euler(Vector3(random.randf_range(-1,1),random.randf_range(-PI,PI),random.randf_range(-1,1))).scaled(Vector3(random.randf_range(0.2,3),random.randf_range(0.2,3),random.randf_range(-3,-0.2)))
  var transform:=Transform3D(basis,Vector3(random.randf_range(-1000,1000),12,random.randf_range(-1000,1000)))
  var area:=Rect2(Vector2(random.randf_range(-1000,1000),random.randf_range(-1000,1000)),Vector2(-64 if i%2 else 64,-128 if i%3 else 128))
  var low:=Vector2.INF;var high:=-Vector2.INF
  for point:Vector2 in [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]:
   var local:=transform*Vector3(point.x,12,point.y);low=low.min(Vector2(local.x,local.z));high=high.max(Vector2(local.x,local.z))
  var actual:Rect2=policy.local_area(area,transform,12)
  check(actual.position.distance_to(low)<0.002 and actual.end.distance_to(high)<0.002,"native affine bounds preserve rotation/scale/mirror "+str(i))
 for angle in [PI/4,-PI/4]:
  var projection:=Probe.new();root.add_child(projection);projection.rotation.y=angle;projection.position=Vector3(900,12,600)
  projection._detail_observer_valid=true;projection.ground_style=1
  var centre:=projection.to_global(Vector3(128,0,128))
  var area:=Rect2(Vector2(centre.x,centre.z)-Vector2.ONE*64,Vector2.ONE*128)
  var low:=Vector2.INF;var high:=-Vector2.INF
  for point:Vector2 in [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]:
   var local:=projection.to_local(Vector3(point.x,projection.global_position.y,point.y));low=low.min(Vector2(local.x,local.z));high=high.max(Vector2(local.x,local.z))
  projection.detail_policy.anchor=low+Vector2.ONE
  projection.detail_policy.detail_prepare_m=1;projection.detail_policy.detail_release_m=1
  check(projection.detail_area_resident(area,false),"rotated edge remains resident: "+str(angle))
  check(projection.detail_preparation_band(area)==0,"rotated edge has foreground priority: "+str(angle))
  projection._pending_tile_columns=4;projection._pending_tile_rows=4;projection._pending_flags.resize(16);projection._pending_flags.fill(0)
  for z in 4:
   for x in 4:projection._tiles[Vector2i(x,z)]={}
  projection._tiles.erase(Vector2i.ZERO)
  check(not projection.detail_area_ready(area),"missing rotated corner tile blocks ready: "+str(angle))
  projection._tiles.clear();projection.free()
 print("ROTATED_DETAIL_BOUNDS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)

