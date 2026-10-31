extends SceneTree
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var scope:=Node3D.new();root.add_child(scope)
 var look:=Node3D.new();scope.add_child(look)
 var sun:=DirectionalLight3D.new();sun.name="AnyName";look.add_child(sun)
 var meadow:=Node3D.new();scope.add_child(meadow)
 for i in 25000:meadow.add_child(Node3D.new())
 var moon:=DirectionalLight3D.new();meadow.add_child(moon)
 check(EmberVoxelProp._first_depth_sun(scope)==scope.find_children("*","DirectionalLight3D",true,false)[0],"same first unowned light in nested preorder")
 var legacy:Array=[];var fast:Array=[]
 for i in 31:
  var t:=Time.get_ticks_usec();scope.find_children("*","DirectionalLight3D",true,false);legacy.append(Time.get_ticks_usec()-t)
  t=Time.get_ticks_usec();EmberVoxelProp._first_depth_sun(scope);fast.append(Time.get_ticks_usec()-t)
 legacy.sort();fast.sort()
 check(fast[15]<legacy[15]/2,"25k irrelevant nodes do not dominate first-light search")
 sun.free();check(EmberVoxelProp._first_depth_sun(scope)==moon,"replacement light after free")
 moon.free();check(EmberVoxelProp._first_depth_sun(scope)==null,"missing light")
 var internal:=DirectionalLight3D.new();scope.add_child(internal,false,Node.INTERNAL_MODE_FRONT)
 var found:=scope.find_children("*","DirectionalLight3D",true,false)
 check(EmberVoxelProp._first_depth_sun(scope)==(found[0] if not found.is_empty() else null),"internal light follows native search semantics")
 scope.free()
 print("DEPTH_SUN_SEARCH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"legacy_median_us":legacy[15],"first_median_us":fast[15]}))
 quit(0 if errors.is_empty() else 1)
