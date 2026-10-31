extends SceneTree
## Array transport parity and cancellation of the existing terrain preparation.
## Fixtures only; author maps, Source, history and storage are not changed.
const Correspondence=preload("res://scripts/ember_anomaly_correspondence.gd")
const Bake=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
class Host extends Node:
	var valid:=true
	func anomaly_preparation_valid()->bool:return valid
	func invalidate()->void:valid=false
var errors:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func run()->void:
	for count in [1,513,4099]:
		var points:=PackedVector3Array();var normals:=PackedVector3Array()
		for i in count:
			points.append(Vector3(i*0.13,-i*0.07,float(i%17)))
			normals.append(Vector3(sin(i),cos(i),0.3).normalized())
		var a:=[];a.resize(Mesh.ARRAY_MAX);a[Mesh.ARRAY_VERTEX]=points;a[Mesh.ARRAY_NORMAL]=normals
		var b:=a.duplicate();b[Mesh.ARRAY_VERTEX]=normals;b[Mesh.ARRAY_NORMAL]=points
		var expected:=PackedFloat32Array();expected.resize(Correspondence.WIDTH*ceili(float(count*4)/Correspondence.WIDTH)*4)
		for i in count:
			var channels:=[points[i],normals[i],normals[i],points[i]]
			for channel in 4:
				var v:Vector3=channels[channel];var offset:int=(i*4+channel)*4
				expected[offset]=v.x;expected[offset+1]=v.y;expected[offset+2]=v.z
		check(Correspondence._aligned_values(a,b,count).to_byte_array()==expected.to_byte_array(),"aligned transport and padding match old layout count%d"%count)
	var source:=EmberTerrainPilotResource.new();source.width=64;source.depth=64
	source.palette=PackedColorArray([Color.TRANSPARENT,Color(0.4,0.3,0.2)])
	for key in ["heights","top_materials","base_materials","cap_depths","water_levels","water_materials"]:source.get(key).resize(4096)
	for z in 64:
		for x in 64:source.heights[x+z*64]=8+(x+z)/4
	source.top_materials.fill(1);source.base_materials.fill(1);source.cap_depths.fill(1)
	var before:=source.working_copy();var bounds:=Rect2i(0,0,64,64)
	var field:=Smooth.field(source,bounds)
	var base:ArrayMesh=Smooth.build(source,bounds,true,false,field).terrain
	var low:ArrayMesh=Bake.faceted(base,field,8,source).mesh
	var host:=Host.new();root.add_child(host)
	var expected:=Bake._anomaly_arrays(func():return false,base.surface_get_arrays(0),low.surface_get_arrays(0),source,field,bounds)
	var result:Dictionary=await Bake.anomaly_carrier(base,low,source,field,bounds,host)
	check(result.size()==3,"worker prepares all three endpoints")
	for look in result:
		var reference:=ArrayMesh.new();reference.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,expected[look])
		check(result[look].surface_get_arrays(0)==reference.surface_get_arrays(0),"worker and direct arrays identical look%d"%look)
	host.invalidate.call_deferred()
	check((await Bake.anomaly_carrier(base,low,source,field,bounds,host)).is_empty(),"stale host never publishes worker result")
	check(source.same_terrain_data(before),"worker leaves authored terrain unchanged")
	host.free();await process_frame
	print("ANOMALY_PREPARATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
