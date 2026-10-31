extends SceneTree
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
func legacy(field:Dictionary,p:Vector2)->float:
 var x:=floori(p.x);var z:=floori(p.y);var t:=p-Vector2(x,z)
 var a:=Smooth.corner(field,x,z);var b:=Smooth.corner(field,x+1,z)
 var c:=Smooth.corner(field,x,z+1);var d:=Smooth.corner(field,x+1,z+1)
 return a+(b-a)*t.x+(c-a)*t.y if t.x+t.y<=1.0 else d+(c-d)*(1.0-t.x)+(b-d)*(1.0-t.y)
func _initialize():run.call_deferred()
func run():
 var source=Fixture.detailed(Fixture.base());var mismatches:=0;var count:=0
 for bounds:Rect2i in [Rect2i(0,0,64,64),Rect2i(64,0,64,64),Rect2i(0,64,64,64),Rect2i(64,64,64,64)]:
  var field:=Smooth.field(source,bounds)
  for z in range(bounds.position.y,bounds.end.y):
   for x in range(bounds.position.x,bounds.end.x):
    for offset:Vector2 in [Vector2.ZERO,Vector2(0.25,0.75),Vector2(0.73,0.21),Vector2(0.99,0.99)]:
     var point:=Vector2(x,z)+offset
     if Smooth.sample(field,point)!=legacy(field,point):mismatches+=1
     count+=1
 print("SMOOTH_SAMPLE_PARITY ",JSON.stringify({"pass":mismatches==0,"samples":count,"mismatches":mismatches}))
 quit(0 if mismatches==0 else 1)
