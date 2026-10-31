extends SceneTree
## Cold grass must sample local physical props, independent of distant population.
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Patch = preload("res://scripts/ember_grass_patch.gd")
const Preparation = preload("res://scripts/ember_detail_preparation.gd")
class DistantFloor extends Node3D:
	var authoring_preview: WeakRef
	var calls := 0
	func surface_floor_bounds() -> AABB:
		return AABB(Vector3(10000,0,10000),Vector3.ONE*16)
	func surface_floor_sample(_point: Vector3) -> Dictionary:
		calls += 1
		return {"solid":false}
var errors: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	if not ok: errors.append(label); printerr("GRASS_LOCAL_FAIL ",label)
func run():
	Preparation.cache_root="user://ember-tests/grass-local-%d"%Time.get_ticks_usec()
	var source=Terrain.new();source.width=64;source.depth=64;source.height_limit=192
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.GREEN]);source.palette_surface_roles=PackedStringArray(["","grass"]);source.palette_material_ids=PackedStringArray(["","cartoon_grass"])
	for channel in Terrain.Sections.CHANNELS:
		var values:Variant=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(4096);values.fill(24 if channel=="heights" else 1 if channel in ["top_materials","base_materials"] else 3 if channel=="cap_depths" else 0);source.set(channel,values)
	var map:=EmberMapLoader.new();map.compact_terrain=source;map.compact_ground_style=1;root.add_child(map)
	var floors:Array[DistantFloor]=[]
	for i in 100:
		var floor:=DistantFloor.new();map.add_child(floor);floor.add_to_group(&"ember_solid_surface");floors.append(floor)
	var patch=Patch.new();patch.painted_only=true;patch.scatter_seed=20261029
	var cells:Dictionary={}
	for z in range(4,12):
		for x in range(4,12):cells[Vector2i(x,z)]=64.0
	patch.density_cells=cells;map.add_child(patch)
	var started:=Time.get_ticks_msec();var deadline:=started+30000
	while Time.get_ticks_msec()<deadline and (patch._dirty or patch._rebuilding or patch._visual==null):await process_frame
	check(not patch._dirty and not patch._rebuilding,"cold preparation completes")
	check(patch._detail_transform_cache.get(0,[]).size()>100,"dense fixture produces grass")
	var calls:=0
	for floor in floors:calls+=floor.calls
	check(calls==0,"distant floors are never queried per tuft")
	print("GRASS_LOCAL ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"distant_calls":calls,"elapsed_ms":Time.get_ticks_msec()-started,"tufts":patch._detail_transform_cache.get(0,[]).size()}))
	map.free();await process_frame;quit(0 if errors.is_empty() else 1)
