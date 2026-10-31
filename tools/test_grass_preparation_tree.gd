extends SceneTree
## Publishing/releasing derived scatter must not force a rebuild of the
## editor's entire authored scene tree after the patch has entered it.
const Patch=preload("res://scripts/ember_grass_patch.gd")
var late_nodes:=0
func _initialize():run.call_deferred()
func run():
	var map:=EmberMapLoader.new();map.compact_ground_style=1;map.world_look=0
	var terrain:=EmberTerrainPilotResource.new();terrain.width=64;terrain.depth=64
	terrain.palette=PackedColorArray([Color.TRANSPARENT,Color.GREEN]);terrain.palette_surface_roles=PackedStringArray(["","grass"]);terrain.palette_material_ids=PackedStringArray(["","cartoon_grass"])
	for channel in terrain.Sections.CHANNELS:
		var values:Variant=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(4096);values.fill(4 if channel=="heights" else 1 if channel in ["top_materials","base_materials","cap_depths"] else 0);terrain.set(channel,values)
	map.compact_terrain=terrain;root.add_child(map)
	while map._visual_surface_projection.pending_tile_count()>0:await process_frame
	var patches:Array[Node]=[]
	for i in 4:
		var patch:=Patch.new();patch.painted_only=true;patch.density_cells={Vector2i(8,8):64.0};map.add_child(patch);patches.append(patch)
	var on_added:=func(_node:Node):late_nodes+=1
	node_added.connect(on_added)
	var deadline:=Time.get_ticks_msec()+5000;var pending:=true
	while pending and Time.get_ticks_msec()<deadline:
		await process_frame;pending=false
		for patch in patches:pending=pending or patch._dirty or patch._rebuilding
	node_added.disconnect(on_added)
	var count:=0
	for patch in patches:
		if patch._visual!=null and patch._visual.multimesh!=null:count+=patch._visual.multimesh.instance_count
	var passed:=not pending and count>0 and late_nodes==0
	print("GRASS_PREPARATION_TREE ",JSON.stringify({"pass":passed,"late_nodes":late_nodes,"instances":count,"pending":pending}))
	map.free();await process_frame;quit(0 if passed else 1)
