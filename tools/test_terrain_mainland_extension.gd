extends SceneTree
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Gen=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("CLEARING_FAIL ",label)
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source:=Terrain.new();source.width=384;source.depth=400;source.height_limit=128;source.origin_y=-32
 source.palette=PackedColorArray([Color.TRANSPARENT,Color.BROWN,Color.GREEN,Color.TAN,Color.GREEN,Color.BLUE,Color.GRAY])
 source.palette_surface_roles=PackedStringArray(["","soil","grass","sand","grass","","stone"])
 source.palette_material_ids=PackedStringArray(["","soil_grain","cartoon_grass","cartoon_sand","cartoon_grass","","cartoon_stone"])
 for channel in Terrain.Sections.CHANNELS:
  var values:Variant=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
  values.resize(source.width*source.depth);values.fill(40 if channel=="heights" else 2 if channel in ["top_materials","base_materials"] else 3 if channel=="cap_depths" else 0)
  source.set(channel,values)
 var original:=source.working_copy();check(source.validation_errors().is_empty(),"fixture validates")
 var p:Dictionary=Math.DEFAULTS.duplicate(true);p.merge(Math.PLAINS_DEFAULTS,true)
 p.merge({"profile":"plains","seed":731,"sea_m":2.0,"land_m":0.6,"relief_m":0.6,"feature_m":18.0,"shore_m":4.0,"land_fraction":0.9,"flat_fraction":0.6,"flat_size_m":12.0,"terrain_sampling":"fine16","terrain_operation":"generate","land_shape":"mainland"},true)
 var job:=Gen.new()
 if not job.begin(source,Rect2i(-24,0,24,24),p,true):
  check(false,"begin west extension: "+job.error);quit(1);return
 while not job.finished:job.step(4000)
 check(job.candidate.validation_errors().is_empty(),"partial edge extent validates after extension")
 check(job.candidate.width==768 and job.candidate.depth==400,"partial south extent stays exactly400")
 var old:=source.sectioned_copy()
 for key:Vector2i in old.sections:
  var kept:Terrain=job.candidate.sections[key+Vector2i.RIGHT]
  for channel in Terrain.Sections.CHANNELS:check(kept.get(channel)==old.sections[key].get(channel),"retained "+channel)
 var continuous:=true
 for x in range(288,384):
  if job.candidate.column_value("heights",job.candidate.column_index(x,231))<=32:continuous=false
 check(continuous,"mainland reaches dry neighbour without island depression")
 check(job.candidate.column_value("top_materials",job.candidate.column_index(383,231))==2,"dry mainland join does not invent sand shore")
 var center_world:float=(job.candidate.origin_y+job.candidate.column_value("heights",job.candidate.column_index(192,192)))/16.0
 check(center_world>=2.6 and center_world<=3.2,"generator height uses world metres with negative origin")
 check(source.same_terrain_data(original),"input unchanged")
 var sampler:=Math.new();var legacy:=p.duplicate(true);legacy.erase("land_shape");sampler.configure(Rect2(0,0,24,24),legacy)
 var island:=Math.new();legacy.land_shape="island";island.configure(Rect2(0,0,24,24),legacy)
 for at in [Vector2.ZERO,Vector2(12,12),Vector2(23,14)]:check(is_equal_approx(sampler.height_m(at),island.height_m(at)),"legacy island exactly preserved")
 var invalid:=p.duplicate(true);invalid.land_shape="wrong";check(not Math.parameter_error(invalid).is_empty(),"unknown land shape rejected")
 var dialog:=preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd").new();root.add_child(dialog)
 dialog.open_plan(Rect2i(0,0,24,24),p)
 check(dialog.parameters().land_shape=="mainland" and not dialog._fields.shore_m.visible,"editor exposes mainland without island coast controls")
 dialog._fields.sea_m.value=0.0;var selected:Dictionary=dialog.parameters()
 check(selected.sea_m==0.0,"mainland UI accepts current zero sea datum")
 var plan:=preload("res://scripts/ember_terrain_plan_resource.gd").new();plan.upgrade_local_layers()
 plan.regions=[{"id":"clearing","name":"Поляна","enabled":true,"kind":"generation","bounds":Rect2i(0,0,24,24),"parameters":selected}]
 check(plan.validation_errors().is_empty() and ResourceSaver.save(plan,"user://mainland-plan-test.tres")==OK,"plan validation/save")
 var reopened:Resource=ResourceLoader.load("user://mainland-plan-test.tres","",ResourceLoader.CACHE_MODE_IGNORE)
 check(reopened.regions[0].parameters.land_shape=="mainland" and reopened.regions[0].parameters.sea_m==0.0,"plan fresh reopen preserves mainland")
 dialog.free()
 print("CLEARING_GENERATOR_TEST ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
