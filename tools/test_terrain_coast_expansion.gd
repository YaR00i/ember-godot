extends SceneTree
## Partial section completion and an editable sea use the existing terrain/plan/history.
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Gen=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Compose=preload("res://addons/ember_import/ember_terrain_plan_composition.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Selection=preload("res://addons/ember_import/ember_compact_section_selection.gd")
const Editor=preload("res://addons/ember_import/ember_world_editor.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("COAST_FAIL ",label)
func _initialize()->void:run.call_deferred()
func compose(source:Terrain,plan:Resource)->RefCounted:
	var job:=Compose.new()
	check(job.begin(source,plan),"begin composition: "+job.error)
	while job.candidate!=null and not job.finished and job.error.is_empty():job.step(2000)
	check(job.error.is_empty(),"composition: "+job.error)
	return job
func fixture()->Terrain:
	var s:=Terrain.new();s.width=384;s.depth=400;s.origin_y=-32;s.height_limit=128
	s.palette=PackedColorArray([Color.TRANSPARENT,Color.BROWN,Color.GREEN,Color.TAN,Color.GREEN,Color.BLUE,Color.GRAY])
	s.palette_surface_roles=PackedStringArray(["","soil","grass","sand","grass","","stone"])
	s.palette_material_ids=PackedStringArray(["","soil_grain","cartoon_grass","cartoon_sand","cartoon_grass","","cartoon_stone"])
	for channel in Terrain.Sections.CHANNELS:
		var values:Variant=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(s.width*s.depth);values.fill(40 if channel=="heights" else 2 if channel in ["top_materials","base_materials"] else 3 if channel=="cap_depths" else 0)
		s.set(channel,values)
	s.water_flow.resize(24*25);s.water_flow.fill(Vector2(0.2,0.4))
	s.column_material_overrides[384*399+8]={4:3}
	return s.sectioned_copy()
func run()->void:
	var source:=fixture();var original:=source.working_copy()
	check(Selection.occupied(source,Vector2i(0,1)) and not Selection.complete(source,Vector2i(0,1)),"partial address is occupied but can be completed")
	var p:Dictionary=Math.DEFAULTS.duplicate(true);p.merge(Math.PLAINS_DEFAULTS,true)
	p.merge({"profile":"plains","sea_m":0.0,"land_m":0.6,"relief_m":0.6,"land_shape":"mainland","terrain_sampling":"fine16"},true)
	var job:=Gen.new();check(job.begin(source,Rect2i(0,24,24,24),p,true),"partial completion begin")
	while not job.finished:job.step(2000)
	var land:Terrain=job.candidate
	check(land.validation_errors().is_empty() and land.width==384 and land.depth==768,"completed dimensions/validation")
	var kept:=land.dense_window(Rect2i(0,0,384,400));var old:=source.dense_window(Rect2i(0,0,384,400))
	check(kept.same_terrain_data(old),"partial completion retains columns, overrides and flow")
	for x in [0,8,192,383]:check(land.column_value("heights",land.column_index(x,400))==40,"join at actual 25m edge")
	check(source.same_terrain_data(original),"generation input immutable")
	var plan:=Plan.new();plan.upgrade_local_layers()
	var points:=PackedVector2Array([Vector2(18,25),Vector2(15,36),Vector2(17,47.99)])
	var params:Dictionary=Plan.Influence.COAST_DEFAULTS.duplicate();params.terrain_sampling="fine16"
	plan.regions=[{"id":"sea","name":"Море","kind":"coast","enabled":true,"bounds":Plan.Influence.coast_bounds(points,params,Vector2i(24,48)),"points_m":points,"parameters":params}]
	var sea:=compose(land,plan)
	if sea.candidate==null:quit(1);return
	check(sea.candidate.validation_errors().is_empty() and sea.output_plan.validation_errors(Vector2i(24,48)).is_empty(),"sea/provenance validate")
	var i:=land.column_index(22*16,36*16)
	check(sea.candidate.column_value("water_levels",i)==32 and sea.candidate.column_value("heights",i)<32,"sea uses original world datum and has a bed")
	check(is_zero_approx(Plan.Influence.existing_water_level_m(sea.candidate)),"existing sea default accounts for negative origin")
	for x in range(21*16,24*16):check(sea.candidate.column_value("heights",land.column_index(x,400))==land.column_value("heights",land.column_index(x,399)),"coast matches original profile without a second ridge")
	var repeated:=compose(sea.candidate,sea.output_plan)
	check(repeated.candidate.same_terrain_data(sea.candidate),"repeat does not accumulate")
	var off:Resource=sea.output_plan.working_copy();off.regions[0].enabled=false
	check(compose(sea.candidate,off).candidate.same_terrain_data(land),"disable restores original land and authored flow")
	var moved:Resource=sea.output_plan.working_copy();moved.regions[0].points_m=PackedVector2Array([Vector2(19,25),Vector2(19,36),Vector2(19,47.99)])
	moved.regions[0].bounds=Plan.Influence.coast_bounds(moved.regions[0].points_m,params,Vector2i(24,48))
	var moved_job:=compose(sea.candidate,moved)
	check(moved_job.candidate.column_value("water_levels",land.column_index(16*16,36*16))==0,"moving coast restores the previous wet area")
	var shifted:Resource=sea.output_plan.translated(Vector2i(24,0))
	check(shifted.regions[0].points_m[0]==points[0]+Vector2(24,0),"expansion translates coastline controls")
	var invalid:Resource=plan.working_copy();invalid.schema_version=11
	check(not invalid.validation_errors().is_empty(),"coast requires schema 12")
	invalid=plan.working_copy();invalid.regions[0].parameters.depth_m=NAN
	check(not invalid.validation_errors().is_empty(),"invalid depth rejected")
	var manual:Terrain=sea.candidate.working_copy();manual.write_columns(PackedInt32Array([i]),PackedInt32Array([sea.candidate.column_value("heights",i)+1]),PackedByteArray([sea.candidate.column_value("top_materials",i)]),PackedInt32Array([32]),PackedByteArray([5]))
	var protected_job:=compose(manual,off)
	check(protected_job.candidate.column_value("heights",i)==manual.column_value("heights",i),"manual land edits survive disabled sea")
	history_checks(land,sea,plan)
	print("COAST_EXPANSION_TEST ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"generator_step_us":job.worst_step_us,"coast_step_us":sea.worst_step_us}))
	await process_frame;quit(0 if errors.is_empty() else 1)

func history_checks(land:Terrain,sea:RefCounted,plan:Resource)->void:
	var sea_index: int=plan.regions.find_custom(func(r):return r.get("kind")=="coast")
	var params:Dictionary=plan.regions[sea_index].parameters
	# Native controls + the normal editor command/history/save path on a fixture.
	var panel=load("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd").new();root.add_child(panel)
	panel.open_influence(plan.regions[sea_index].bounds,params,"coast")
	check(panel.parameters().water_m==0.0 and panel._coast_grid.visible,"coast controls accept zero sea level")
	panel._coast_fields.depth_m.value=1.5;check(panel.parameters().depth_m==1.5,"depth control")
	var frame:=Node3D.new();root.add_child(frame)
	var dir:="user://ember-tests/coast-expansion-"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	frame.scene_file_path=dir.path_join("scene.tscn")
	var map:=EmberMapLoader.new();map.name="Map";frame.add_child(map);map.owner=frame
	ResourceSaver.save(land,dir.path_join("terrain.res"));map.compact_terrain=ResourceLoader.load(dir.path_join("terrain.res"),"",ResourceLoader.CACHE_MODE_IGNORE);map.authored_size_blocks=Vector2i(land.width/16,land.depth/16)
	map.set_meta(Plan.META,plan)
	var history:=UndoRedo.new();var editor:=Editor.new();root.add_child(editor);editor.scene=frame
	editor.sessions.configure(history,func()->int:
		var packed:=PackedScene.new();var code:=packed.pack(frame)
		return ResourceSaver.save(packed,frame.scene_file_path) if code==OK else code)
	editor.sessions.recovery_directory=dir.path_join("recovery")
	var draft:Dictionary=editor.sessions.open_map(map,frame)
	var context:={"draft":draft,"version":draft.resource.working_copy(),"candidate":sea.candidate,"output_plan":sea.output_plan,"plan_version":plan.data(),"validated_sections":sea.validated_sections,"layout":editor.Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"editor applies sea")
	history.undo();check(draft.resource.same_terrain_data(land),"Undo restores land")
	history.redo();check(draft.resource.same_terrain_data(sea.candidate),"Redo restores sea")
	check(editor.sessions.save_all(frame),"save: "+editor.sessions.error)
	var reopened:Node=(ResourceLoader.load(frame.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_terrain.same_terrain_data(sea.candidate) and Plan.same(Plan.read(reopened.get_node("Map")),sea.output_plan),"fresh reopen retains land, sea and editable plan")
	var change:Resource=sea.output_plan.working_copy();change.regions[sea_index].parameters.depth_m=1.5
	check(editor.commit_terrain_plan(map,change).is_empty(),"edit saved settings")
	editor.sessions.discard(frame);check(Plan.same(Plan.read(map),sea.output_plan) and draft.resource.same_terrain_data(sea.candidate),"discard restores saved sea")
	reopened.free();history.clear_history();editor.sessions.entries.clear();editor.sessions.save_scene=Callable();editor.free();history.free();panel.free();frame.free()
