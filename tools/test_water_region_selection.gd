extends SceneTree
## Compare the cached connectivity filter with the original full-source selection.
const Regions=preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func reference(fields:RefCounted,prior:Dictionary)->Dictionary:
	var wanted:Dictionary={};var required:Dictionary={}
	var components:Dictionary=fields._cache.get("components",{}) if fields._cache.get("revision",-1)==fields._revision else {}
	for key:Vector2i in fields._document.sections:
		var part:Terrain=fields._document.sections[key]
		var core:=Rect2i(key*Regions.SIZE,Vector2i(part.width,part.depth))
		var distance:float=fields._distance_to_observers(core)
		if distance>fields._prepare_radius+(fields._prepare_hysteresis if prior.has(key) else 0.0):continue
		if not components.is_empty() and not Regions._window_has_water(components,core.grow(Regions.HALO)):continue
		wanted[key]=true
		if distance<=fields._required_radius:required[key]=true
	return {"wanted":wanted,"required":required}
func _initialize()->void:
	var fields:=Regions.new()
	var source:=Terrain.new();source.schema_version=Terrain.SECTION_SCHEMA_VERSION
	source.width=9216;source.depth=9216
	var components:Dictionary={}
	for z in 24:
		for x in 24:
			var part:=Terrain.new();part.width=384;part.depth=384
			var key:=Vector2i(x,z);source.sections[key]=part
			components[key]={"has_water":key in [Vector2i.ZERO,Vector2i(12,12),Vector2i(23,23)]}
	fields._document=source;fields._revision=1
	# Unknown summaries must stay conservative, including dry-looking source.
	for phase in 4:
		if phase==1:fields._cache={"revision":1,"components":components}
		if phase==2:
			fields._revision=2 # Old connectivity cannot hide newly edited water.
		if phase==3:
			var dry:Dictionary={}
			for key in components:dry[key]={"has_water":false}
			fields._cache={"revision":2,"components":dry}
		for point in [Vector2(10,10),Vector2(768,768),Vector2(4608,4608),Vector2(9215,9215),Vector2(40,40)]:
			for radius in [768.0,1600.0]:
				var prior:Dictionary=fields._wanted.duplicate()
				fields._streaming=true;fields._prepare_observers=PackedVector2Array([point,point+Vector2(240,80)])
				fields._required_radius=768;fields._prepare_radius=radius;fields._prepare_hysteresis=128
				var expected:=reference(fields,prior)
				fields._refresh_selection()
				check(fields._wanted==expected.wanted and fields._required==expected.required,"selection/halo/hysteresis phase%d at%s radius%d"%[phase,point,radius])
		check(phase!=3 or fields._wanted.is_empty(),"edited dry source releases all wanted fields")
	fields.close()
	print("WATER_SELECTION ",JSON.stringify({"pass":failures.is_empty(),"failures":failures,"cases":40}))
	quit(0 if failures.is_empty() else 1)
