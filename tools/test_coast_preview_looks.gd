extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Preview=preload("res://addons/ember_import/ember_compact_map_extension_preview.gd")
const MeshBuilder=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Bake=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("COAST_LOOK_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var source=Fixture.base().dense_window(Rect2i(0,0,64,64))
	var map:=EmberMapLoader.new();map.compact_terrain=source;map.compact_ground_style=1;map.world_look=2
	root.add_child(map)
	var projection=map._visual_surface_projection
	var candidate=source.working_copy();var heights:PackedInt32Array=candidate.heights;heights[32+32*64]+=4;candidate.heights=heights
	var preview:=Preview.new();map.add_child(preview)
	check(preview.show_area(map,candidate,Rect2i(0,0,64,64)),"preview opens")
	for look in [2,0,1,2]:
		map.world_look=look
		var deadline:=Time.get_ticks_msec()+20000
		await process_frame
		while (preview._look.x!=look or not preview._pending.is_empty() or not preview._announced) and Time.get_ticks_msec()<deadline:await process_frame
		check(preview._announced and preview._pending.is_empty(),"look ready "+str(look))
		var actual:Array=[];var tiles:=0
		for tile in preview.get_children(true):
			if not String(tile.name).begins_with("PreviewTile_"):continue
			tiles+=1
			for child in tile.get_children(true):
				if child is MeshInstance3D and child.mesh.get_surface_count()>0:actual=child.mesh.surface_get_arrays(0);break
		var expected:Dictionary=MeshBuilder.build_tile(candidate,0,0,64,projection.water_mesh_step,projection.water_volume_sides,PackedVector4Array(),{},false,false,look!=2,projection.smooth_material_blend_enabled)
		var mesh:ArrayMesh=expected.terrain
		if look==1:mesh=Bake.faceted(mesh,expected.smooth_field).mesh
		check(tiles==1 and actual==mesh.surface_get_arrays(0),"preview matches committed geometry "+str(look))
	check(projection.document.same_terrain_data(source),"preview leaves source intact")
	preview.clear_preview();preview.queue_free();await process_frame
	check(projection._editor_hidden_edge_keys.is_empty(),"Cancel restores hidden original tiles")
	print("COAST_PREVIEW_LOOKS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	map.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
