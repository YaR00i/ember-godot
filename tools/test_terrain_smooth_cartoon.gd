extends SceneTree
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Mesher=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const PilotProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Map=preload("res://scripts/ember_map_loader.gd")
const Brush=preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const Pattern=preload("res://scripts/ember_compact_terrain_pattern.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const Cache=preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
var errors: Array[String]=[]

func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: errors.append(message);printerr("FAIL ",message)
func settle(projection) -> bool:
	var deadline:=Time.get_ticks_msec()+90000
	while projection.pending_tile_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	await physics_frame;await physics_frame;await process_frame
	return projection.pending_tile_count()==0
func fixture() -> EmberTerrainPilotResource:
	var source:=Terrain.new();source.width=130;source.depth=130;source.height_limit=512
	source.palette=PackedColorArray([Color.TRANSPARENT,Color("765b42"),Color("789257")])
	source.palette_surface_roles=PackedStringArray(["","soil","grass"])
	var count:=source.width*source.depth
	for channel: String in ["heights","top_materials","base_materials","cap_depths","water_levels","water_materials"]:source.get(channel).resize(count)
	# PackedArray getters resize shared arrays; assign explicit arrays for certainty.
	source.heights.resize(count);source.top_materials.resize(count);source.base_materials.resize(count);source.cap_depths.resize(count)
	source.water_levels.resize(count);source.water_materials.resize(count)
	source.top_materials.fill(2);source.base_materials.fill(1);source.cap_depths.fill(2)
	for z in source.depth:
		for x in source.width:source.heights[x+z*source.width]=32+x+z
	return source
func digest(mesh: ArrayMesh) -> String:
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array().hex_encode().sha256_text()

func run() -> void:
	var source:=fixture();check(source.validation_errors().is_empty(),"fixture validation")
	var before:=source.heights.duplicate()
	var left:=Smooth.field(source,Rect2i(0,0,64,64));var right:=Smooth.field(source,Rect2i(64,0,64,64))
	for z in range(12,53):
		check(absf(Smooth.corner(left,64,z)-Smooth.corner(right,64,z))<0.00001,"height seam")
		check(Smooth.normal(left,64,z).distance_to(Smooth.normal(right,64,z))<0.00001,"normal seam")
	check(absf(Smooth.sample(left,Vector2(30.25,29.75))-91.0)<0.0001,"affine ramp height")
	var dense_mesh:=Mesher.build_tile(source,64,64,64,0,false,PackedVector4Array(),{},false,false,true)
	var sectioned=source.sectioned_copy()
	var section_mesh:=Mesher.build_tile(sectioned,64,64,64,0,false,PackedVector4Array(),{},false,false,true)
	check(digest(dense_mesh.terrain)==digest(section_mesh.terrain),"dense/section geometry equality")
	var points: PackedVector3Array=dense_mesh.collision_faces
	check(points==(dense_mesh.terrain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array),"mesh/collision exact triangles")
	check(source.heights==before,"meshing mutated source")
	var cache:=Cache.new();cache.directory="user://smooth-cartoon-cache-test"
	var old_key:=cache.tile_key(source,Vector2i(1,1),0,[0,false,false,false,false,0],PackedVector4Array(),{})
	var smooth_key:=cache.tile_key(source,Vector2i(1,1),0,[0,false,false,false,false,1],PackedVector4Array(),{})
	check(old_key!=smooth_key,"style cache keys distinct")
	cache.write_geometry(smooth_key,dense_mesh)
	var cached:=cache.read_geometry(smooth_key)
	check(not cached.is_empty() and digest(cached.terrain)==digest(dense_mesh.terrain),"smooth cache exact geometry")
	check(cached.terrain.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]==dense_mesh.terrain.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2],"smooth cache material slots")
	var empty:=source.working_copy();empty.heights.fill(0);empty.cap_depths.fill(0)
	var empty_mesh:=Mesher.build_tile(empty,0,0,64,0,false,PackedVector4Array(),{},false,false,true)
	var empty_key:=cache.tile_key(empty,Vector2i.ZERO,1,[1],PackedVector4Array(),{})
	cache.write_geometry(empty_key,empty_mesh)
	check(not cache.read_geometry(empty_key).is_empty(),"empty smooth cache read")
	var map:=Map.new();map.hydrate_legacy_regions=false;map.map_id="smooth_cartoon_test"
	map.compact_ground_style=1;map.compact_terrain=source;map.imported_tile_size=16.0
	root.add_child(map)
	var projection=map._visual_surface_projection as PilotProjection
	check(projection!=null and projection.ground_style==1,"MapLoader smooth style")
	if projection==null:quit(1);return
	projection.runtime_geometry_cache_enabled=false;projection.runtime_ground_lod_enabled=false
	check(await settle(projection),"initial projection settle")
	var at:=Vector3(63.25,0,62.75)
	var expected:=projection.floor_surface_sample(at)
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(at.x,500,at.z),Vector3(at.x,0,at.z))
	var hit:=root.world_3d.direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.position.distance_to(expected.position)<0.001,"query/physics height")
	var pick:=projection.pick_ground_top(ray.from,ray.to)
	check(not pick.is_empty() and pick.world.distance_to(expected.position)<0.001,"brush pick/surface height")
	var grid:=projection._build_navigation_grid()
	check(grid.heights[1+grid.width]==78,"navigation samples smooth physical surface")
	var tile:=projection.get_node("TerrainTile_1_1/Ground") as MeshInstance3D
	var mesh_before:=digest(tile.mesh)
	var history:=UndoRedo.new();var brush:=Brush.new()
	brush.configure({"resource":source,"target":weakref(map)},history,map)
	check(brush.begin("raise",0.0625,16,2,0,1,0,7,0,-99999,"detail","circle",1),"native brush begin")
	brush.stamp(Vector2i(59,59));brush.end()
	check(await settle(projection),"brush settle")
	check(digest(tile.mesh)!=mesh_before,"diagonal neighbour remeshed inside halo")
	check(source.heights!=before,"brush edits source")
	history.undo();check(await settle(projection),"undo settle");check(source.heights==before,"Undo exact source")
	check(digest(tile.mesh)==mesh_before,"Undo exact neighbour mesh")
	history.redo();check(await settle(projection),"redo settle");check(source.heights!=before,"Redo source")
	brush.begin("paint",0.0625,1,1,0,1,0,7,0);brush.stamp(Vector2i(63,63));brush.end()
	check(await settle(projection),"material brush settle");check(source.top_materials[source.column_index(63,63)]==1,"paint source material")
	check(projection.save_document("user://smooth_cartoon_probe.res")==OK,"terrain save")
	check(projection.reopen_document("user://smooth_cartoon_probe.res"),"terrain reopen")
	check(await settle(projection),"reopened projection settle")
	var packed:=PackedScene.new();check(packed.pack(map)==OK,"scene pack")
	check(ResourceSaver.save(packed,"user://smooth_cartoon_probe.tscn")==OK,"scene save")
	var loaded:=load("user://smooth_cartoon_probe.tscn") as PackedScene
	var reopened=loaded.instantiate();check(reopened.compact_ground_style==1,"saved map style");reopened.free()
	var pattern:=Pattern.new();pattern.role_id="grass";pattern.pixels.resize(256)
	pattern.albedo_texture=load("res://content/terrain_materials/textures/cartoon_grass.png")
	check(pattern.albedo_texture!=null and pattern.validation_errors().is_empty(),"PNG field validation")
	check(ResourceSaver.save(pattern,"user://smooth_cartoon_pattern.tres")==OK,"PNG Resource save")
	var reloaded=ResourceLoader.load("user://smooth_cartoon_pattern.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded.albedo_texture!=null and reloaded.albedo_texture.get_width()==1254,"PNG Resource reopen")
	var dialog:=Dialog.new();root.add_child(dialog);await process_frame
	dialog.pattern_path_override="user://smooth_cartoon_pattern.tres"
	check(dialog.open_role("grass"),"existing material dialog open")
	dialog._remove_texture();check(dialog._draft.albedo_texture==null,"remove PNG draft")
	dialog.undo_edit();check(dialog._draft.albedo_texture!=null,"PNG Undo")
	dialog.redo_edit();check(dialog._draft.albedo_texture==null,"PNG Redo")
	dialog.cancel_edit();check(ResourceLoader.load("user://smooth_cartoon_pattern.tres","",ResourceLoader.CACHE_MODE_IGNORE).albedo_texture!=null,"Cancel preserves PNG")
	dialog.queue_free();history.free();map.queue_free();await process_frame
	print("SMOOTH_CARTOON ","PASS" if errors.is_empty() else "FAIL", " ",errors)
	quit(0 if errors.is_empty() else 1)
