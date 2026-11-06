extends SceneTree
const Patch=preload("res://scripts/ember_grass_patch.gd")
class QuietMap extends EmberMapLoader:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
class Surface extends Node3D:
	var document:=Resource.new()
	var ground_style:=0
	var anchor:=Vector3.ZERO
	var detail_policy=Policy.new()
	func editor_detail_active()->bool:return true
	func detail_world_anchor()->Vector3:return anchor
class Policy extends RefCounted:
	var detail_fade_begin_m:=4.0
	var detail_fade_end_m:=8.0
var errors:Array=[]
func check(value:bool,label:String)->void:
	if not value:errors.append(label)
func _init()->void:call_deferred("run")
func run()->void:
	var map:=QuietMap.new();root.add_child(map)
	var surface:=Surface.new();surface.name="DerivedCompactWorldTerrain";map.add_child(surface)
	var patch=Patch.new();map.add_child(patch);patch.set_process(false)
	var shader:=Shader.new();shader.code="shader_type spatial;uniform bool ember_anomaly_prepared=false;uniform bool world_detail_fade_enabled;uniform vec3 world_detail_anchor;uniform vec2 world_detail_fade_range;"
	var material:=ShaderMaterial.new();material.shader=shader;patch._visual.material_override=material
	patch._update_detail_fade(surface,map)
	check(patch._visual.visible,"native near vegetation visible by default")
	patch.set_detail_render_override(true);patch._update_detail_fade(surface,map)
	check(not patch._visual.visible,"native visibility stays suppressed on unchanged fade cache")
	surface.anchor=Vector3(1000,0,1000);patch._update_detail_fade(surface,map);patch.set_detail_render_override(false)
	check(not patch._visual.visible,"releasing override does not reveal faded distant vegetation")
	surface.anchor=Vector3.ZERO;patch._update_detail_fade(surface,map)
	check(patch._visual.visible,"near native vegetation returns after renderer release")
	var notifications:Array=[];map.detail_scatter_changed.connect(func(node):notifications.append(node.get_instance_id()))
	patch._notify_detail_scatter();check(notifications==[patch.get_instance_id()],"publication notification reaches map consumer")
	patch._detail_resident=true;patch.set_detail_render_override(true);map.remove_child(patch)
	check(not patch._detail_resident and not patch._detail_render_override,"exit releases transient renderer ownership")
	check(notifications.size()==2,"exit notifies consumer before losing map ancestry")
	patch.free();map.free();await process_frame
	print("GRASS_RENDER_OVERRIDE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
