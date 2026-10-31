extends SceneTree
## Lowering through a material cap must preserve valid Source, preview and history.
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message);printerr("FAIL material cap: ",message)
static func fixture(size: int) -> Terrain:
	var source := Terrain.new()
	source.width = size;source.depth = size;source.height_limit = 64;source.origin_y = -3
	source.palette = PackedColorArray([Color.TRANSPARENT,Color.GREEN,Color.BROWN])
	for channel in Terrain.Sections.CHANNELS:
		var values = PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(size*size)
		values.fill(24 if channel == "heights" else 16 if channel == "cap_depths" else 1 if channel == "top_materials" else 2 if channel == "base_materials" else 0)
		source.set(channel,values)
	source.cap_depths[source.column_index(size/2,size/2)] = 4
	return source
func edit_case(sectioned: bool, broad := false) -> void:
	var source := fixture(256 if broad else 32)
	if sectioned: source = source.sectioned_copy()
	var label := ("sectioned" if sectioned else "dense")+(" broad" if broad else "")
	var original := source.working_copy()
	var map := EmberMapLoader.new()
	var projection := EmberTerrainPilotProjection.new()
	root.add_child(projection)
	check(projection.open_document(source),label+" open")
	projection.set_process(false)
	map._visual_surface_projection = projection
	var history := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"target":weakref(map),"resource":source},history,map)
	var center := Vector2i(source.width/2,source.depth/2)
	check(brush.begin("level",8.0 if broad else 0.125,1,1,0,16,0,7,0,source.origin_y+8,"medium" if broad else "detail","square"),label+" begin")
	brush.stamp(center)
	check(source.validation_errors().is_empty(),label+" live Source validates")
	check(projection.document.validation_errors().is_empty(),label+" live preview validates")
	check(source.same_terrain_data(projection.document),label+" live Source equals preview")
	var index := source.column_index(center.x+1,center.y)
	check(source.column_value("heights",index) == 8 and source.column_value("cap_depths",index) == 8,label+" actual target and bounded cap")
	check(source.column_value("cap_depths",source.column_index(center.x,center.y)) == 4,label+" thinner cap preserved")
	brush.end()
	var edited := source.working_copy()
	check(source.column_value("base_materials",index) == 2 and source.column_value("top_materials",index) == 1,label+" material ids retained")
	history.undo()
	check(source.same_terrain_data(original) and projection.document.same_terrain_data(original),label+" Undo restores height and full depth")
	history.redo()
	check(source.same_terrain_data(edited) and projection.document.same_terrain_data(edited),label+" Redo restores edited height and depth")
	var path := "user://brush-cap-%s.res" % label.replace(" ","-")
	check(ResourceSaver.save(source,path) == OK,label+" save")
	var reopened := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	check(reopened != null and reopened.validation_errors().is_empty() and reopened.same_terrain_data(edited),label+" fresh reopen validates and matches")
	check(brush.begin("level",0.125,1,1,0,16,0,7,0,source.origin_y+2,"detail","square"),label+" discarded edit begins")
	brush.stamp(center)
	check(source.validation_errors().is_empty(),label+" second lowering validates")
	brush.cancel()
	check(source.same_terrain_data(edited) and projection.document.same_terrain_data(edited),label+" cancel restores full depth")
	reopened = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	check(reopened.same_terrain_data(edited),label+" discard never changes saved data")
	history.clear_history();history.free();map._visual_surface_projection = null;map.free();projection.free()
func triangle_area(points:PackedVector3Array) -> float:
	var area:=0.0
	for i in range(0,points.size(),3):area+=(points[i+1]-points[i]).cross(points[i+2]-points[i]).length()*0.5
	return area

func side_case(sectioned:bool) -> void:
	const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
	var source:=fixture(32);source.palette.append(Color.RED)
	for z in 32:
		for x in 32:source.heights[x+z*32]=24 if x>=16 else 4;source.cap_depths[x+z*32]=4
	var cells:Dictionary={}
	for z in 32:
		for x in 32:cells[Vector2i(x,z)]=255
	source.surface_rules=source.SurfaceRules.changed({},cells)
	if sectioned:source=source.sectioned_copy()
	var original:=source.working_copy();var map:=EmberMapLoader.new();var projection:=EmberTerrainPilotProjection.new()
	root.add_child(projection);check(projection.open_document(source),"side open")
	projection.set_process(false);map._visual_surface_projection=projection
	var history:=UndoRedo.new();var brush:=Brush.new();brush.configure({"target":weakref(map),"resource":source},history,map)
	for style in [0,2]:
		projection.ground_style=1;projection.world_look=style
		var pick:Dictionary=projection.pick_ground_top(Vector3(0,8,16.5),Vector3(32,8,16.5),true)
		check(not pick.is_empty() and pick.normal.x< -0.5 and pick.cell.x==16,"side ray targets wall in look%d"%style)
		if pick.is_empty():continue
		var before_mesh:Dictionary=Smooth.build_arrays(source,Rect2i(12,12,9,9))
		check(brush.begin("paint",0.125,1,3,0,16,0,7,0),"side brush begins")
		brush.stamp_surface(pick);brush.end()
		var index:=source.column_index(16,16)
		check(not source.side_overrides(index).is_empty(),"side stored at wall height")
		check(source.column_value("top_materials",index)==original.column_value("top_materials",index) and source.column_value("heights",index)==24,"top and shape preserved")
		check(source.validation_errors().is_empty() and source.same_terrain_data(projection.document),"side Source/preview validate and match")
		var after_mesh:Dictionary=Smooth.build_arrays(source,Rect2i(12,12,9,9))
		check(before_mesh.arrays[Mesh.ARRAY_COLOR]!=after_mesh.arrays[Mesh.ARRAY_COLOR],"detail side attributes change")
		check(before_mesh.smooth_field.heights==after_mesh.smooth_field.heights,"paint never changes physical heightfield")
		check(absf(triangle_area(before_mesh.collision_faces)-triangle_area(after_mesh.collision_faces))<0.001,"paint band split preserves surface area")
		var captured:Dictionary=Smooth.build_arrays(source,Rect2i(12,12,9,9),false,true,{},true)
		check(captured.layout.side_paint,"painted bands reject corner-only height reuse")
		var slot_found:=false
		for color:Color in after_mesh.arrays[Mesh.ARRAY_COLOR]:
			if roundi(color.a*255.0)==3:slot_found=true;break
		check(slot_found,"new material reaches detailed mesh")
		var detailed:Dictionary=Smooth.publish_arrays(after_mesh)
		var plain_low:Dictionary=preload("res://scripts/prototypes/ember_terrain_look_bake.gd").faceted(detailed.terrain,after_mesh.smooth_field)
		var painted_low:Dictionary=preload("res://scripts/prototypes/ember_terrain_look_bake.gd").faceted(detailed.terrain,after_mesh.smooth_field,8,source)
		var low_arrays:Array=painted_low.mesh.surface_get_arrays(0);var plain_arrays:Array=plain_low.mesh.surface_get_arrays(0)
		check(low_arrays[Mesh.ARRAY_VERTEX]==plain_arrays[Mesh.ARRAY_VERTEX] and low_arrays[Mesh.ARRAY_NORMAL]==plain_arrays[Mesh.ARRAY_NORMAL],"low paint preserves geometry/normals and carrier topology")
		var min_paint:=INF;var max_paint:=-INF
		for v in low_arrays[Mesh.ARRAY_VERTEX].size():
			var color:Color=low_arrays[Mesh.ARRAY_COLOR][v];var slots:Vector2=low_arrays[Mesh.ARRAY_TEX_UV][v];var third:Vector2=low_arrays[Mesh.ARRAY_TEX_UV2][v]
			var slot:int=roundi((slots.x if color.r>0.9 else slots.y if color.g>0.9 else third.x)*255.0)
			if slot==3:min_paint=minf(min_paint,low_arrays[Mesh.ARRAY_VERTEX][v].y);max_paint=maxf(max_paint,low_arrays[Mesh.ARRAY_VERTEX][v].y)
		check(min_paint>=4 and max_paint<=12 and max_paint-min_paint>=1,"low paint occupies the requested world-height band instead of a collapsed strip")
		var edited:=source.working_copy();history.undo();check(source.same_terrain_data(original) and source.same_terrain_data(projection.document),"side Undo")
		history.redo();check(source.same_terrain_data(edited) and source.same_terrain_data(projection.document),"side Redo")
		var path:="user://side-paint-%s.res"%str(sectioned)
		check(ResourceSaver.save(source,path)==OK,"side save")
		var reopened=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		check(reopened!=null and reopened.same_terrain_data(edited) and reopened.validation_errors().is_empty(),"side fresh reopen")
		check(brush.begin("paint",0.125,1,2,0,16,0,7,0),"side Cancel begin");brush.stamp_surface(pick);brush.cancel()
		check(source.same_terrain_data(edited) and source.same_terrain_data(projection.document),"side Cancel/Discard")
		history.undo();history.clear_history()
	history.free();map._visual_surface_projection=null;map.free();projection.free()

func side_look_capture() -> void:
	const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
	const Look=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
	const Mesher=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
	if not ProjectSettings.globalize_path("res://").contains("ember-rock-pilot-"):quit(1);return
	var full=load("res://content/world_terrains/landscape_compact.res")
	var source=full.dense_window(Rect2i(96,608,64,64))
	var detailed:Dictionary=Smooth.build(source,Rect2i(0,0,64,64))
	var low:Dictionary=Look.faceted(detailed.terrain,detailed.smooth_field,8,source)
	var viewport:=SubViewport.new();viewport.size=Vector2i(800,700);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var mesh_node:=MeshInstance3D.new();viewport.add_child(mesh_node)
	var shader:=Shader.new();shader.code="shader_type spatial; render_mode unshaded,cull_disabled; uniform vec4 palette[256]; void fragment(){ int a=int(round(UV.x*255.0)); int b=int(round(UV.y*255.0)); int c=int(round(UV2.x*255.0)); ALBEDO=palette[a].rgb*COLOR.r+palette[b].rgb*COLOR.g+palette[c].rgb*COLOR.b; }"
	var material:=ShaderMaterial.new();material.shader=shader
	var palette:PackedColorArray=source.palette.duplicate();palette.resize(256);material.set_shader_parameter("palette",palette);mesh_node.material_override=material
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	var high:float=source.origin_y+source.column_value("heights",source.column_index(32,32))
	camera.size=maxf(100,high*1.3);camera.far=3000;camera.position=Vector3(-120,high+50,140);camera.look_at(Vector3(28,high*0.5,32))
	var captures:Array=[]
	for look in 3:
		mesh_node.mesh=[detailed.terrain,low.mesh,Mesher.build_tile(source,0,0,64).terrain][look]
		for frame in 5:await process_frame
		await RenderingServer.frame_post_draw
		var path:="user://terrain-side-look-%d-%d.png"%[OS.get_process_id(),look];viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(path));captures.append(ProjectSettings.globalize_path(path))
	print("TERRAIN_SIDE_LOOK ",JSON.stringify({"captures":captures,"renderer":RenderingServer.get_current_rendering_method()}));quit()

func run() -> void:
	if "--side-look-capture" in OS.get_cmdline_user_args():await side_look_capture();return
	if "--side-only" in OS.get_cmdline_user_args():
		side_case(false);side_case(true)
		print("TERRAIN_SIDE ",JSON.stringify({"pass":failures.is_empty(),"failures":failures}));quit(0 if failures.is_empty() else 1);return
	edit_case(false)
	edit_case(true)
	edit_case(false,true)
	# Direct Resource/projection writers share the same existing invariant.
	var source := fixture(32)
	var indices := PackedInt32Array([0])
	source.write_columns(indices,PackedInt32Array([8]),PackedByteArray([1]),PackedInt32Array([0]),PackedByteArray([0]))
	check(source.validation_errors().is_empty() and source.cap_depths[0] == 8,"direct Resource write clips depth")
	var projection := EmberTerrainPilotProjection.new()
	root.add_child(projection);projection.open_document(fixture(32));projection.set_process(false)
	projection.apply_heights(indices,PackedInt32Array([8]))
	check(projection.document.validation_errors().is_empty() and projection.document.cap_depths[0] == 8,"direct projection write clips depth")
	projection.free()
	source = fixture(32)
	projection = EmberTerrainPilotProjection.new()
	root.add_child(projection);projection.open_document(source);projection.set_process(false)
	var revision := projection.column_revision()
	source.cap_depths[0] = 3
	projection.apply_columns(indices,PackedInt32Array([24]),PackedByteArray([1]),PackedInt32Array([0]),PackedByteArray([0]),source)
	check(projection.document.cap_depths[0] == 3 and projection.column_revision() == revision+1,"depth-only history refreshes preview")
	projection.free()
	var report := {"pass":failures.is_empty(),"failures":failures,"display_server":DisplayServer.get_name()}
	var file := FileAccess.open("user://brush-material-depth-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("BRUSH_MATERIAL_DEPTH ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
