extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Patch=preload("res://scripts/ember_grass_patch.gd")
class Probe extends EmberTerrainPilotProjection:
 var full_queries:=0
 func floor_surface_sample(point:Vector3)->Dictionary:
  full_queries+=1
  return super.floor_surface_sample(point)
var errors:Array[String]=[]
func _initialize():run.call_deferred()
func legacy(projection,center:Vector3,radius:float,unit:float)->bool:
 for i in 8:
  var offset:=Vector2.from_angle(i*TAU/8.0)*radius
  var sample:Dictionary=projection.floor_surface_sample(center+Vector3(offset.x,0,offset.y))
  if not sample.get("solid",false) or sample.get("material_role")=="stone" or absf(sample.position.y-center.y)>0.055*unit:return false
 return true
func run():
 var projection:=Probe.new();root.add_child(projection);projection.set_process(false)
 projection.document=Fixture.detailed(Fixture.base());projection.ground_style=1
 projection.document.origin_y=7
 projection.document.heights[projection.document.column_index(12,12)]=0
 var patch:=Patch.new();root.add_child(patch);patch.set_process(false)
 var mismatches:=0;var probes:=0;var calls:=0;var accepted:=0
 for transform in [Transform3D.IDENTITY,Transform3D(Basis(Vector3.UP,0.7).scaled(Vector3(1.3,0.8,1.1)),Vector3(12,7,-5)),Transform3D(Basis(Vector3.RIGHT,0.2),Vector3(-3,11,4))]:
  projection.transform=transform
  for z in range(-1,projection.document.depth+1,3):
   for x in range(-1,projection.document.width+1,3):
    var point:=projection.to_global(Vector3(x+0.23,0,z+0.67))
    var floor_hit:Dictionary=projection.floor_surface_sample(point)
    point.y=floor_hit.get("position",point).y
    for radius in [0.0,0.035,0.8,2.0]:
     var expected:=legacy(projection,point,radius,1.0)
     projection.full_queries=0
     var actual:bool=patch._footprint_clear(point,radius,projection,1.0)
     calls+=projection.full_queries;probes+=1
     if actual!=expected:mismatches+=1
     if actual:accepted+=1
 if mismatches>0:errors.append("eight-point decisions differ: %d"%mismatches)
 if calls>0:errors.append("grass still constructs full floor query dictionaries: %d"%calls)
 if accepted==0 or accepted==probes:errors.append("fixture must exercise acceptance and rejection")
 print("GRASS_FOOTPRINT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"probes":probes,"accepted":accepted,"full_queries":calls,"mismatches":mismatches}))
 patch.free();projection.free();quit(0 if errors.is_empty() else 1)
