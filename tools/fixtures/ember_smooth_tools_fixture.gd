extends RefCounted
## A hand-authored example made with the existing brush, not role_at/generation.
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const Map = preload("res://scripts/ember_map_loader.gd")

static func base() -> EmberTerrainPilotResource:
	var source:=Terrain.new();source.width=128;source.depth=128;source.height_limit=192
	source.palette=PackedColorArray([Color.TRANSPARENT,Color("765b42"),Color("789257"),Color("d8bf7b"),Color("948d7b"),Color("25aacf")])
	source.palette_surface_roles=PackedStringArray(["","soil","grass","sand","stone",""])
	source.palette_material_ids=PackedStringArray(["","cartoon_soil","cartoon_grass","cartoon_sand","cartoon_relief_stone",""])
	for channel: String in Terrain.Sections.CHANNELS:
		var data=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		data.resize(source.width*source.depth)
		data.fill(24 if channel=="heights" else 2 if channel=="top_materials" else 1 if channel=="base_materials" else 3 if channel=="cap_depths" else 0)
		source.set(channel,data)
	var owner:=Map.new();owner.compact_terrain=source
	var history:=UndoRedo.new();var brush:=Brush.new();brush.configure({"resource":source,"target":weakref(owner)},history,owner)
	brush.begin("raise",2.4,16,2,0,16,0,7,0);brush.stamp(Vector2i(65,74));brush.end()
	brush.begin("smooth",2.0,6,2,0,16,0,7,0);brush.stamp(Vector2i(64,73));brush.end()
	brush.begin("paint",2.0,1,3,0,16,0,7,0,-99999,"detail","square")
	for x in [16,48,80,112]:brush.stamp(Vector2i(x,12))
	brush.end()
	brush.begin("paint",1.8,1,4,0,16,0,7,0);brush.stamp(Vector2i(91,84));brush.end()
	brush.begin("paint",0.85,1,1,0,16,0,7,0);brush.stamp(Vector2i(39,86));brush.end()
	history.free();owner.free()
	return source

static func detailed(source: EmberTerrainPilotResource) -> EmberTerrainPilotResource:
	var result:=source.working_copy();var owner:=Map.new();owner.compact_terrain=result
	var history:=UndoRedo.new();var brush:=Brush.new();brush.configure({"resource":result,"target":weakref(owner)},history,owner)
	brush.begin("generator",8.0,12,2,0,16,0,731,0,-99999,"detail","square",1,true)
	brush.stamp(Vector2i(64,64));brush.end()
	history.free();owner.free()
	return result
