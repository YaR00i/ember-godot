extends SceneTree
const Fixture=preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
var errors: Array[String]=[]
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func _initialize() -> void:
	var source=load("res://content/world_terrains/diorama_readability_study.res").working_copy()
	var baseline: PackedInt32Array=source.heights.duplicate()
	var carved:=Fixture.chiselled_rock_source(source)
	var result=carved.source
	check(result.validation_errors().is_empty(),"valid edited Source")
	check(source.heights==baseline,"input unchanged")
	check(result.heights==Fixture.chiselled_rock_source(source).source.heights,"deterministic cuts")
	check(carved.changed_columns>50,"visible source edits, not normals only")
	check(carved.max_cut_m<=0.375 and carved.peak_before_m==carved.peak_after_m,"bounded cuts, peak retained")
	for channel in ["top_materials","base_materials","cap_depths","water_levels"]:
		check(source.get(channel)==result.get(channel),"unchanged "+channel)
	for i in source.width*source.depth:
		if source.top_materials[i]!=1:check(result.heights[i]==baseline[i],"non-rock unaffected")
		else:check(result.heights[i]>0 and result.heights[i]<=baseline[i],"stone footprint retained, subtractive sculpt")
	var path: String="user://rock-planes-fixture.res"
	check(ResourceSaver.save(result,path)==OK,"Source saves")
	var reopened=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened!=null and reopened.heights==result.heights and reopened.top_materials==source.top_materials,"reopened Source matches")
	print("ROCK_PLANES_TEST ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
