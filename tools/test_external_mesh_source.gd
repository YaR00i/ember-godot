extends SceneTree
## Source ownership/protection regression. Writes only user://.
const External=preload("res://scripts/ember_external_mesh_surface.gd")
const Import=preload("res://addons/ember_import/ember_voxel_mesh_import.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("EXTERNAL_SOURCE_FAIL ",label)
func _initialize()->void:
 var source:EmberVoxelModelResource=load("res://content/voxel_models/vox_external_coastal_rock.tres")
 check(source.validation_errors().is_empty() and External.pristine(source),"published source pristine and valid")
 var before:=FileAccess.get_sha256(source.external_surface.original)
 var changed:=source.duplicate_model()
 var i:=0
 while i<changed.voxels.size() and changed.voxels[i]==0:i+=1
 changed.voxels[i]=0
 check(not External.pristine(changed),"sculpt invalidates original display")
 check(Import.plan(source.external_surface.original,source.model_id,changed).has("error"),"reprepare refuses sculpt before any publication")
 var painted:=source.duplicate_model();painted.palette[1]=Color.MAGENTA
 check(not External.pristine(painted),"paint invalidates original display")
 var assigned:=source.duplicate_model();assigned.solid_surface.material_ids[1]="cartoon_stone"
 check(not External.pristine(assigned),"material assignment invalidates original display")
 var optical:=source.duplicate_model();optical.material={"shader":"changed"}
 check(not External.pristine(optical),"material profile changes invalidate original display")
 var native:=source.duplicate_model();native.external_surface={}
 check(Import.plan(source.external_surface.original,source.model_id,native).has("error"),"import cannot replace a native voxel owner")
 var invalid:=source.duplicate_model();invalid.external_surface.original="res://content/../bad.glb"
 check(not invalid.validation_errors().is_empty(),"reject escaping source path")
 var path:="user://external-source-roundtrip.tres"
 check(ResourceSaver.save(source,path)==OK,"save original provenance")
 var disk:EmberVoxelModelResource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
 check(External.pristine(disk) and disk.external_surface==source.external_surface,"fresh reopen preserves original display/provenance")
 check(ResourceSaver.save(changed,path)==OK,"save sculpted derivative")
 disk=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
 check(not External.pristine(disk) and disk.voxels==changed.voxels,"fresh reopen preserves modified derivative")
 check(FileAccess.get_sha256(source.external_surface.original)==before,"GLB never rewritten")
 print("EXTERNAL_SOURCE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
 quit(0 if errors.is_empty() else 1)
