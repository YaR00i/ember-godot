extends SceneTree
const Patch=preload("res://scripts/ember_grass_patch.gd")
const Policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd")
class QuietMap extends EmberMapLoader:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
class Cover extends Patch:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _world_area()->Rect2:return Rect2(Vector2(-32,-32),Vector2(64,64))
class Focus extends Node3D:
	var detail_policy=Policy.new()
	var anchor:=Vector3.ZERO
	var active:=true
	func editor_detail_active()->bool:return active
	func detail_world_anchor()->Vector3:return anchor
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var map:=QuietMap.new();root.add_child(map)
	var patch:=Cover.new();map.add_child(patch);patch._ensure_visual()
	var focus:=Focus.new();map.add_child(focus)
	var shader:=Shader.new();shader.code="shader_type spatial; uniform bool world_detail_fade_enabled; uniform vec3 world_detail_anchor; uniform vec2 world_detail_fade_range; uniform bool ember_anomaly_prepared;"
	var material:=ShaderMaterial.new();material.shader=shader;patch._visual.material_override=material
	patch._visual.show()
	for pair in [[0.0,true],[360.0,true],[416.0,false],[1000.0,false],[0.0,true]]:
		focus.anchor.x=pair[0];patch._update_detail_fade(focus,map)
		check(patch._visual.visible==pair[1],"only fully collapsed patches skip drawing at "+str(pair[0]))
	focus.anchor.x=1000;focus.active=false;patch._update_detail_fade(focus,map)
	check(patch._visual.visible,"disabled distance policy restores drawing")
	focus.active=true;material.set_shader_parameter("ember_anomaly_prepared",true);patch._update_detail_fade(focus,map)
	check(patch._visual.visible,"anomaly keeps its existing deformation path")
	map.free()
	print("DETAIL_FADE_CULLING ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
