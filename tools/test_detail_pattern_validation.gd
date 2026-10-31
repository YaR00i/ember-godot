extends SceneTree
const Bake=preload("res://scripts/ember_detail_pattern_bake.gd")
class CountedGeometry extends EmberVoxelModelResource:
	var validation_calls:=0
	func validation_errors()->Array[String]:
		validation_calls+=1
		return super.validation_errors()
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("DETAIL_PATTERN_VALIDATION_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var preset:Resource=load("res://content/editor/voxel_stamps/vox_detail_wheat.tres").duplicate()
	var geometry:=CountedGeometry.new()
	for property:Dictionary in preset.geometry.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			geometry.set(property.name,EmberVoxelModelResource.copy_authoring_value(preset.geometry.get(property.name)))
	preset.geometry=geometry
	var host:=Node.new();root.add_child(host)
	var first:Dictionary=await Bake.prepare(preset,host)
	check(not first.has("error") and first.get("variants",[]).size()>0,"real wheat prepares")
	var before:=geometry.validation_calls
	var started:=Time.get_ticks_usec()
	var second:Dictionary=await Bake.prepare(preset,host)
	var hot_us:=Time.get_ticks_usec()-started
	check(second.get("key")==first.get("key") and second.get("variants")==first.get("variants"),"warm request reuses all three meshes")
	check(geometry.validation_calls==before,"unchanged warm request does not rescan every voxel")
	var parts:=geometry.voxel_part_ids.duplicate()
	check(not parts.is_empty(),"wheat exercises ownership validation")
	if not parts.is_empty():
		geometry.voxel_part_ids[0]=geometry.merge_parts.size()+1
		check(not Bake.validation_errors(preset).is_empty(),"in-place ownership edit invalidates cached validation without a signal")
		geometry.voxel_part_ids=parts
	var palette:=geometry.palette.duplicate();geometry.palette.resize(1)
	check(not Bake.validation_errors(preset).is_empty(),"invalid palette never reuses a valid result")
	geometry.palette=palette
	var groups:=geometry.voxel_groups.duplicate(true)
	geometry.voxel_groups.append({"id":"validation_probe","indices":PackedInt32Array([0])})
	check(Bake.validation_errors(preset).is_empty(),"valid nested edit validates")
	geometry.voxel_groups[-1].indices[0]=geometry.voxels.size()
	check(not Bake.validation_errors(preset).is_empty(),"in-place nested dictionary edit invalidates the saved snapshot")
	geometry.voxel_groups=groups
	var kind:int=preset.kind;preset.kind=1
	check(not Bake.validation_errors(preset).is_empty(),"unsupported preset kind does not alias the cache")
	preset.kind=kind
	check(Bake.validation_errors(preset).is_empty(),"restored source validates")
	print("DETAIL_PATTERN_VALIDATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"warm_us":hot_us,"cold_validation_calls":before,"validation_calls":geometry.validation_calls}))
	host.free();quit(0 if errors.is_empty() else 1)
