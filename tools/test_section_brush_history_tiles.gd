extends "res://tools/test_compact_section_brush_batches.gd"
## A local stroke/history restore must not remesh entire 24m storage sections.
func _run()->void:
	var source:=_flat(768,768).sectioned_copy()
	var baseline:=source.working_copy()
	var map:=EmberMapLoader.new();var scene:=Node3D.new()
	var projection:=EmberTerrainPilotProjection.new();root.add_child(projection)
	assert(projection.open_document(source))
	map._visual_surface_projection=projection
	var history:=UndoRedo.new();var brush:=Brush.new()
	brush.configure({"resource":source,"target":weakref(map)},history,scene)
	assert(brush.begin("lower",3.31,4,1,0,16,0,7,0))
	brush.stamp(Vector2i(382,382));brush.end()
	var edited:=source.working_copy()
	projection._pending.clear();projection._reset_pending_flags()
	history.undo()
	assert(source.same_terrain_data(baseline) and projection.document.same_terrain_data(baseline),"Undo restores all channels")
	assert(projection.pending_tile_count()>0 and projection.pending_tile_count()<=16,"Undo invalidates only the stroke footprint and halo")
	var undo_tiles:=projection.pending_tile_count()
	projection._pending.clear();projection._reset_pending_flags()
	history.redo()
	assert(source.same_terrain_data(edited) and projection.document.same_terrain_data(edited),"Redo restores all channels")
	assert(projection.pending_tile_count()<=16,"Redo bounded footprint")
	projection._pending.clear();projection._reset_pending_flags()
	var point:=Vector2i(100,100);var index:=source.column_index(point.x,point.y)
	var part:Terrain=source.sections[Vector2i.ZERO].working_copy()
	var caps:=part.cap_depths;caps[100+100*384]=1;part.cap_depths=caps
	var bases:=part.base_materials;bases[100+100*384]=2;part.base_materials=bases
	part.column_material_overrides[100+100*384]={4:2}
	brush._apply_parts(source,weakref(map),{Vector2i.ZERO:part},PackedInt32Array([index]))
	assert(projection.document.column_value("cap_depths",index)==1 and projection.document.column_value("base_materials",index)==2,"caps/base restored even when height is unchanged")
	assert(projection.document.sections[Vector2i.ZERO].column_material_overrides[100+100*384]=={4:2},"side material restored")
	assert(projection.pending_tile_count()>0 and projection.pending_tile_count()<=9,"material-only restore invalidates local geometry")
	projection._pending.clear();projection._reset_pending_flags()
	assert(projection.open_document(edited),"session restore")
	assert(projection.document.same_terrain_data(edited),"session restore exact data")
	assert(projection.pending_tile_count()>0 and projection.pending_tile_count()<=9,"Discard invalidates changed tiles instead of a whole section")
	print("SECTION_HISTORY_TILES PASS local Undo/Redo/Discard; caps/base/side restore; undo_tiles=",undo_tiles," discard_tiles=",projection.pending_tile_count())
	history.clear_history();history.free();brush.configure({},null,null);map._visual_surface_projection=null;map.free();scene.free();projection.free();quit()
