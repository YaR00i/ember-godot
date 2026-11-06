extends SceneTree
const Patch=preload("res://scripts/ember_grass_patch.gd")
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class QuietMap extends EmberMapLoader:
 func _ready():pass
 func _process(_dt):pass
class Focus extends TerrainProjection:
 var revision:=0
 func _ready():pass
 func _process(_dt):pass
 func column_revision()->int:return revision
class Cover extends Patch:
 var updates:=0
 var area_queries:=0
 func _world_area()->Rect2:
  area_queries+=1;return super._world_area()
 func _ready():pass
 func _update_detail_patch(map:EmberMapLoader,projection:Node3D):
  updates+=1;_revision=projection.column_revision();_dirty=false;_transform=global_transform;_detail_resident=true
  _update_detail_fade(projection,map)
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var map:=QuietMap.new();root.add_child(map)
 var focus:=Focus.new();focus.name="DerivedCompactWorldTerrain";focus.document=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd").base();focus._detail_observer_valid=true;focus.ground_style=1;map.add_child(focus)
 var patch:=Cover.new();map.add_child(patch);patch._ensure_visual()
 var shader:=Shader.new();shader.code="shader_type spatial; uniform bool world_detail_fade_enabled; uniform vec3 world_detail_anchor; uniform vec2 world_detail_fade_range; uniform bool ember_anomaly_prepared;"
 var material:=ShaderMaterial.new();material.shader=shader;patch._visual.material_override=material
 patch._process(0);var first_queries:int=patch.area_queries
 patch._process(0);check(patch.updates==1,"unchanged resident avoids repeated decision work")
 check(patch.area_queries==first_queries,"unchanged resident avoids another bounds query")
 focus.detail_policy.anchor.x=1000;Preparation.for_projection(focus).invalidate_detail_poll();patch._process(0)
 check(patch.updates==2 and not patch._visual.visible,"observer update refreshes fade and visibility")
 material.set_shader_parameter("ember_anomaly_prepared",true);patch._process(0)
 check(patch.updates==3 and patch._visual.visible,"anomaly material changes cannot hide in a cached observer epoch")
 focus.revision+=1;patch._process(0);check(patch.updates==4,"terrain revision invalidates same-frame resident state")
 patch.position.x+=10;patch._process(0);check(patch.updates==5,"patch transform invalidates cached bounds")
 patch._dirty=true;patch._process(0);check(patch.updates==6,"authoring invalidation still enters update")
 var old_context=Preparation.for_projection(focus)
 Preparation.release_projection(focus);patch._process(0)
 check(patch.updates==7 and patch._detail_context.get_ref()!=old_context,"closed cached context refreshes without skipping first update")
 Preparation.release_projection(focus);map.remove_child(focus);focus.free()
 focus=Focus.new();focus.name="DerivedCompactWorldTerrain";focus.document=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd").base();focus._detail_observer_valid=true;focus.ground_style=1;map.add_child(focus)
 patch._process(0);check(patch.updates==8,"replacement projection cannot reuse an unrelated epoch number")
 Preparation.release_projection(focus);map.free();await process_frame
 print("DETAIL_POLL_EPOCH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
