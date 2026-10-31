extends SceneTree
## Explicit first static-import recipe. Original GLB is read-only, edits are protected.
const Import=preload("res://addons/ember_import/ember_voxel_mesh_import.gd")
const External=preload("res://scripts/ember_external_mesh_surface.gd")
const Store=preload("res://addons/ember_import/ember_voxel_model_store.gd")
const ID="vox_external_coastal_rock"
const ORIGINAL="res://content/mesh_models/coastal_rock/source.glb"
func _initialize()->void:run.call_deferred()
func run()->void:
 var start:=Time.get_ticks_msec()
 var path:="res://content/voxel_models/"+ID+".tres"
 var previous:EmberVoxelModelResource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) if FileAccess.file_exists(path) else null
 var result:=Import.plan(ORIGINAL,ID,previous)
 if result.has("error"):printerr("EXTERNAL_IMPORT_REFUSED ",result.error);quit(1);return
 var source:EmberVoxelModelResource=result.source
 if previous!=null:
  source.display_name=previous.display_name;source.tags=previous.tags;source.material=previous.material.duplicate(true)
 var key:String=(result.original_hash+External.CONTRACT).sha256_text().left(16)
 var folder:="res://content/mesh_models/coastal_rock/prepared/"+key
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
 for look in ["detailed","low_poly"]:
  var mesh:ArrayMesh=result[look];var mesh_path:=folder.path_join(look+".res")
  if ResourceSaver.save(mesh,mesh_path,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
  mesh.take_over_path(mesh_path)
 source.external_surface={"version":1,"original":ORIGINAL,"original_hash":result.original_hash,"detailed":folder.path_join("detailed.res"),"low_poly":folder.path_join("low_poly.res"),"voxel_baseline":External.fingerprint(source)}
 var packed:=EmberVoxelPrefab.prepare_resource(source)
 if packed==null:printerr("EXTERNAL_IMPORT_INVALID ",source.validation_errors());quit(1);return
 var node:=packed.instantiate()
 var mesh:ArrayMesh=node.get_node("Mesh").mesh
 var canonical_path:=folder.path_join("voxel-boundary.res")
 assert(ResourceSaver.save(mesh,canonical_path,ResourceSaver.FLAG_COMPRESS)==OK);mesh.take_over_path(canonical_path)
 var shape:Shape3D=node.get_node("Collision/Shape").shape
 var shape_path:=folder.path_join("collision.res")
 assert(ResourceSaver.save(shape,shape_path,ResourceSaver.FLAG_COMPRESS)==OK);shape.take_over_path(shape_path)
 var detached:=PackedScene.new();assert(detached.pack(node)==OK);node.free()
 var saved:=Store.install_prepared_asset(source,detached,path,"res://prefabs/voxels/"+ID+".tscn")
 if not saved.get("ok",false):printerr("EXTERNAL_IMPORT_SAVE ",saved);quit(1);return
 print("EXTERNAL_IMPORT ",JSON.stringify({"pass":true,"triangles":result.triangles,"low_triangles":result.low_poly.get_faces().size()/3,"grid":str(result.grid),"palette":source.palette.size(),"ms":Time.get_ticks_msec()-start}))
 quit()
