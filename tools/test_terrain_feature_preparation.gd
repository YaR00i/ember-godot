extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
var errors:Array[String]=[]
var maximum_step_us:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);push_error(label)
func step(material:ShaderMaterial)->bool:
 var began:=Time.get_ticks_usec()
 var result:bool=Materials.prepare_terrain_features_step(material)
 maximum_step_us=maxi(maximum_step_us,Time.get_ticks_usec()-began)
 return result
func ready(material:ShaderMaterial)->bool:
 for frame in 300:
  if step(material):return true
  await process_frame
 return false
func run()->void:
 var first:=Materials.compact_grass_material();var second:=Materials.compact_grass_material()
 var a:=false;var b:=false
 for frame in 300:
  a=step(first);b=step(second)
  if a and b:break
  await process_frame
 check(a and b,"both bindings prepare")
 check(first.shader==second.shader,"coalesced bindings share program")
 check(first.shader.get_meta("ember_feature_values",{}).get("voxel_light_enabled")==false,"snapshot features retained")
 var stale:=Materials.compact_grass_material();stale.set_shader_parameter("voxel_light_anomaly",true)
 var base:=stale.shader
 check(not step(stale),"new variant starts background load")
 stale.set_shader_parameter("voxel_light_enabled",true)
 await process_frame
 check(stale.shader==base,"completion cannot mutate waiting live binding")
 check(await ready(stale),"changed binding prepares its own key")
 check(stale.shader.get_meta("ember_feature_values",{}).get("voxel_light_enabled")==true,"latest features applied")
 var abandoned:=Materials.compact_flower_material();var weak:WeakRef=weakref(abandoned)
 check(not step(abandoned),"dispatch abandoned binding")
 abandoned=null
 check(weak.get_ref()==null,"pending request retains no live material")
 var drain:=Materials.compact_grass_material();drain.set_shader_parameter("voxel_light_enabled",true)
 check(await ready(drain),"new caller makes progress past abandoned generation")
 for frame in 300:
  Materials._poll_terrain_feature_loads()
  if Materials._terrain_feature_loads.is_empty():break
  await process_frame
 check(Materials._terrain_feature_loads.is_empty(),"completed loads drained")
 check(Materials._terrain_feature_generations.is_empty(),"code generation drained")
 var generated:String=first.shader.code
 Materials._terrain_feature_programs.clear()
 var sync:=Materials.compact_grass_material();Materials.refresh_terrain_features(sync)
 check(sync.shader.code==generated,"incremental and synchronous shader code are identical")
 print("TERRAIN_FEATURE_PREPARATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"maximum_step_us":maximum_step_us}))
 quit(0 if errors.is_empty() else 1)
