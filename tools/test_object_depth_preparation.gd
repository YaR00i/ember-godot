extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Height=preload("res://scripts/ember_material_height.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);push_error(label)
func _initialize():run.call_deferred()
func new_material()->ShaderMaterial:
 var result:=ShaderMaterial.new();result.shader=Solid.solid_depth_shader();result.set_meta("ember_detailed_depth",true);return result
func run():
 Engine.max_fps=0;OS.low_processor_usage_mode=false;OS.low_processor_usage_mode_sleep_usec=0
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 var prop:EmberVoxelProp=load("res://prefabs/voxels/vox_natural_earth_outcrop.tscn").instantiate()
 var mesh:ArrayMesh=prop.get_node("Mesh").mesh
 var roles:PackedStringArray=mesh.get_meta("solid_surface_roles")
 var ids:PackedStringArray=mesh.get_meta("solid_surface_material_ids")
 Materials._bank_height_images.clear()
 var expected:=new_material();Materials.set_terrain_depth_profiles(expected,roles,ids)
 var reference:Dictionary={}
 for key in Materials._bank_height_images:reference[key]=(Materials._bank_height_images[key] as Image).get_data()
 var profiles:PackedByteArray=(expected.get_meta("ember_depth_profiles") as Image).get_data()
 Materials._bank_height_images.clear();Height.clear_cache()
 var prepared:=Materials.depth_preparation(roles,ids)
 var job:=prepared.job as Materials.DepthPreparationJob
 check(not job.recipes.is_empty(),"real outcrop queues missing CPU heights")
 var before:Array=[]
 for source:Texture2D in prepared.sources:before.append(source.get_image().get_data())
 var task:=WorkerThreadPool.add_task(job.run)
 while not WorkerThreadPool.is_task_completed(task):await process_frame
 WorkerThreadPool.wait_for_task_completion(task)
 check(Materials._bank_height_images.is_empty() and Height._images.is_empty(),"worker never publishes shared dictionaries")
 check(job.images.size()==reference.size(),"all height recipes prepared")
 for key in reference:check(job.images.has(key) and job.images[key].get_data()==reference[key],"mipmapped bank layer byte exact: "+key)
 for i in prepared.sources.size():check(prepared.sources[i].get_image().get_data()==before[i],"source texture immutable")
 Materials.publish_depth_preparation(job)
 var actual:=new_material();Materials.set_terrain_depth_profiles(actual,roles,ids)
 check((actual.get_meta("ember_depth_profiles") as Image).get_data()==profiles,"profile lookup byte exact")
 check((Materials.depth_preparation(roles,ids).job as Materials.DepthPreparationJob).recipes.is_empty(),"warm preflight does not queue duplicate work")
 var private_image:=actual.get_meta("ember_depth_profiles") as Image
 check(private_image!=expected.get_meta("ember_depth_profiles"),"editable profile image remains instance-owned")
 check(actual.get_shader_parameter("terrain_depth_profiles")!=expected.get_shader_parameter("terrain_depth_profiles"),"editable GPU lookup remains instance-owned")
 var slot:=-1
 for i in ids.size():
  if not ids[i].is_empty() and profiles.size()>0:slot=i;break
 if slot>=0:
  var draft:=Materials.load_compact_terrain_variant(ids[slot]).duplicate() as EmberCompactTerrainPattern
  draft.depth_mm*=0.5
  Materials.set_terrain_depth_profiles(actual,roles,ids,{ids[slot]:draft})
  check((expected.get_meta("ember_depth_profiles") as Image).get_data()==profiles,"editing one material never modifies another")
  check((actual.get_meta("ember_depth_profiles") as Image).get_data()!=profiles,"amplitude preview remains live")
 prop.free()
 print("OBJECT_DEPTH_PARITY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"layers":reference.size()}))
 quit(0 if errors.is_empty() else 1)
