extends SceneTree
const ProjectionOwner=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Controller=preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")
class Capture extends Controller:
	var fixture_map:EmberMapLoader
	func water_settings_map()->EmberMapLoader:return fixture_map
	func _process(_delta:float)->void:pass
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func draw()->void:
	await process_frame
	await RenderingServer.frame_post_draw
func terrain_fixture()->ProjectionOwner.TerrainResource:
	var source:=ProjectionOwner.TerrainResource.new()
	source.width=8;source.depth=8;source.height_limit=192
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.BROWN,Color.AQUA])
	for channel in source.Sections.CHANNELS:
		var data=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		data.resize(64)
		data.fill(8 if channel=="heights" else 128 if channel=="water_levels" else 2 if channel=="water_materials" else 1 if channel in ["top_materials","base_materials"] else 4)
		source.set(channel,data)
	return source
func settle(projection:ProjectionOwner)->void:
	for i in 600:
		if projection.pending_physics_chunk_count()==0 and projection.pending_runtime_lod_count()==0:return
		await process_frame
	check(false,"projection settles")
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(256,256)
	var scene:=Node3D.new();root.add_child(scene);current_scene=scene
	var projection:=ProjectionOwner.new();scene.add_child(projection);projection.set_process(false)
	var map:=EmberMapLoader.new();map._visual_surface_projection=projection
	var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(0,20,0);camera.rotation_degrees.x=-90;camera.make_current()
	var capture:=Capture.new();capture.fixture_map=map;capture.study_controls=false;scene.add_child(capture)
	capture._prepared=true;capture._water_height=0.0;capture._floor_camera.global_transform=camera.global_transform
	var ground:=MeshInstance3D.new();ground.mesh=PlaneMesh.new();ground.layers=Controller.REFRACTION_PASS_LAYER
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color.RED;ground.material_override=mat;scene.add_child(ground)
	await draw()
	check(capture._floor_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"dry capture disabled")
	var source:=terrain_fixture()
	check(projection.open_document(source),"open wet source");await settle(projection);await draw()
	check(projection.has_visible_water(camera.cull_mask),"real fine publication registers water")
	var dry:=source.working_copy();dry.water_levels.fill(0);dry.water_materials.fill(0)
	check(projection.open_document(dry),"replace with dry source");await settle(projection);await draw()
	check(not projection.has_visible_water(camera.cull_mask),"source replacement clears fine demand")
	var host:=projection._new_tile_host("SyntheticFine")
	var water:=host.get_node("Water") as MeshInstance3D
	water.mesh=PlaneMesh.new();projection._track_water(water)
	# Published after process, immediately before the next draw: no local region exists.
	await draw()
	check(capture._floor_viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"first published fine water wakes capture")
	var pixel:=capture._floor_viewport.get_texture().get_image().get_pixel(128,128)
	check(pixel.r>0.5 and pixel.g<0.1,"first water frame has fresh red floor")
	water.hide();await draw();check(capture._floor_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"hidden water disables capture")
	mat.albedo_color=Color.GREEN
	await draw();water.show();await draw()
	pixel=capture._floor_viewport.get_texture().get_image().get_pixel(128,128)
	check(pixel.g>0.5 and pixel.r<0.1,"return first frame refreshes stale floor")
	camera.position.y=-2;await draw();check(capture._floor_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"underwater rule retained")
	camera.position.y=20;root.size=Vector2i(320,240);capture._floor_viewport.size=root.size;await draw()
	check(capture._floor_viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"above-water return and resize wake capture")
	water.layers=2;camera.cull_mask=1;await draw();check(not projection.has_visible_water(1),"camera layer exclusion")
	water.layers=1
	projection._release_tile_host(host);await draw();check(not projection.has_visible_water(1),"fine release clears demand")
	# Exercise actual overview publication, independently of resident water fields.
	var overview:=projection._new_tile_host("SyntheticOverview")
	var arrays:=PlaneMesh.new().get_mesh_arrays()
	projection._overviews[Vector2i.ZERO]={"node":overview,"data":{"arrays":[],"patches":{},"bounds":Rect2i(0,0,8,8),"grid_size":Vector2i.ONE,"grid":PackedFloat32Array([0.0]),"water_arrays":arrays,"water_patches":{Vector2i.ZERO:Vector2i(0,arrays[Mesh.ARRAY_INDEX].size())}}}
	projection._publish_overview(Vector2i.ZERO,{})
	await draw();check(projection._water_regions.is_empty() and projection.has_visible_water(1) and capture._floor_viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"overview-only water wakes without resident regions")
	projection._publish_overview(Vector2i.ZERO,{Vector2i.ZERO:true});await draw()
	check(not projection.has_visible_water(1),"empty far replacement clears demand")
	projection._publish_overview(Vector2i.ZERO,{});await draw()
	check(projection.has_visible_water(1),"far return restores demand")
	projection._clear_overviews();await draw();check(not projection.has_visible_water(1),"overview clear disables capture")
	scene.remove_child(capture)
	check(not RenderingServer.frame_pre_draw.is_connected(capture._update_floor_capture_demand),"detached controller releases pre-draw callback")
	await draw();capture.free()
	print("WATER_FLOOR_CAPTURE_DEMAND ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	scene.free();map.free();quit(0 if failures.is_empty() else 1)
