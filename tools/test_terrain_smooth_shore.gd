extends SceneTree
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Smooth = preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const PilotProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const WaterLOD = preload("res://scripts/prototypes/ember_terrain_water_lod.gd")
const SharedLOD = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
var errors: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message); printerr("FAIL ",message)

func fixture() -> EmberTerrainPilotResource:
	var source := Terrain.new(); source.width=130; source.depth=80; source.height_limit=192
	source.origin_y=7
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.BROWN,Color.AQUA,Color.BLUE])
	for channel: String in Terrain.Sections.CHANNELS:
		var data = PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		data.resize(source.width*source.depth); data.fill(1 if channel in ["top_materials","base_materials","cap_depths"] else 0)
		source.set(channel,data)
	for z in source.depth:
		for x in source.width:
			var i := x+z*source.width
			source.heights[i]=maxi(4,roundi((16+x*0.25+sin(z*0.12)*10)/4.0)*4)
			if source.heights[i]<32: source.water_levels[i]=32; source.water_materials[i]=2
	return source

func water_arrays(generated: Dictionary) -> Array:
	return generated.water.surface_get_arrays(0) if generated.water.get_surface_count()>0 else []
func vertices(generated: Dictionary) -> PackedVector3Array:
	var arrays := water_arrays(generated)
	return arrays[Mesh.ARRAY_VERTEX] if not arrays.is_empty() else PackedVector3Array()
func seam(generated: Dictionary, at: float) -> Dictionary:
	var result := {}
	var arrays := water_arrays(generated)
	var ps: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in ps.size():
		if is_equal_approx(ps[i].x,at): result[Vector3(roundf(ps[i].x*10000),roundf(ps[i].y*10000),roundf(ps[i].z*10000))]=roundi(cs[i].a*255)
	return result

func run() -> void:
	var source := fixture(); var before := source.working_copy()
	check(source.validation_errors().is_empty(),"fixture")
	var left := MeshBuilder.build_tile(source,0,0,64,0,false,PackedVector4Array(),{},false,true,true)
	var right := MeshBuilder.build_tile(source,64,0,64,0,false,PackedVector4Array(),{},false,true,true)
	var ps := vertices(left); var arrays := water_arrays(left)
	check(not ps.is_empty(),"shore water present")
	var fractional := 0; var extended := 0; var contact := 0
	for i in ps.size():
		var point := ps[i]
		check(absf(point.y-39.02)<0.00001,"physical level and origin preserved")
		var floor_height := Smooth.sample(left.smooth_field,Vector2(point.x,point.z))
		check(floor_height<=39.00005,"water does not overdraw dry ground")
		if absf(point.x-roundf(point.x))>0.0001 or absf(point.z-roundf(point.z))>0.0001:
			fractional+=1; check(absf(floor_height-39.0)<0.00005,"shore meets exact physical ground contour")
		if arrays[Mesh.ARRAY_COLOR][i].a<=0.001: contact+=1
		var x := clampi(floori(point.x),0,source.width-1); var z := clampi(floori(point.z),0,source.depth-1)
		if source.water_materials[x+z*source.width]==0: extended+=1
	check(fractional>10 and contact>10,"continuous intersections and zero shoreline depth")
	check(extended>10,"filtered bank collar fills old mask gaps")
	check(seam(left,64)==seam(right,64) and not seam(left,64).is_empty(),"tile seams: positions and depth metadata")
	var sectioned := source.sectioned_copy()
	var section_right := MeshBuilder.build_tile(sectioned,64,0,64,0,false,PackedVector4Array(),{},false,true,true)
	var section_ps := vertices(section_right); var right_ps := vertices(right)
	check(section_ps.size()==right_ps.size(),"section water count")
	if section_ps.size()==right_ps.size():
		for i in section_ps.size(): check(section_ps[i].distance_to(right_ps[i])<0.00002,"section/dense shoreline geometry")
	check(left.collision_faces==Smooth.build(source,Rect2i(0,0,64,64)).collision_faces,"ground collision unchanged")
	check(source.same_terrain_data(before),"source channels unchanged")
	# Coarse water, volume walls and swash keep the previous rectangle path.
	var legacy := MeshBuilder.build_tile(source,0,0,64)
	for point: Vector3 in vertices(legacy):check(point.x==roundf(point.x) and point.z==roundf(point.z),"legacy rectangle geometry preserved")
	var volume := MeshBuilder.build_tile(source,0,0,64,1,true,PackedVector4Array(),{},false,false,true)
	var old_volume := MeshBuilder.build_tile(source,0,0,64,1,true)
	check(vertices(volume)==vertices(old_volume),"volume-water geometry preserved")
	var projection := PilotProjection.new(); projection.ground_style=1
	check(projection._geometry_policy().has("smooth-shore-v1"),"smooth cache invalidated")
	projection.ground_style=0
	check(not projection._geometry_policy().has("smooth-shore-v1"),"legacy cache policy preserved")
	projection.free()
	# Existing LOD protects shoreline metadata/edges even with indexed triangles.
	var lod := WaterLOD.build(arrays,Rect2i(0,0,64,64))
	if lod.has("lods"):
		for indices: PackedInt32Array in lod.lods.values():
			check(SharedLOD.boundary(arrays[Mesh.ARRAY_VERTEX],indices)==SharedLOD.boundary(arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_INDEX]),"far water boundary preserved")
	# A deliberately dry low depression cannot inherit nearby water intent.
	var dry := source.working_copy()
	for z in range(12,20):
		for x in range(12,20):dry.heights[x+z*dry.width]=8;dry.water_levels[x+z*dry.width]=0;dry.water_materials[x+z*dry.width]=0
	var depression := MeshBuilder.build_tile(dry,0,0,64,0,false,PackedVector4Array(),{},false,false,true)
	var depression_points := vertices(depression)
	for i in range(0,depression_points.size(),3):
		var center := (depression_points[i]+depression_points[i+1]+depression_points[i+2])/3.0
		check(not Rect2(12,12,8,8).has_point(Vector2(center.x,center.z)),"dry low depression not flooded")
	# A second authored water level remains local and never spreads into ocean.
	var multiple := source.working_copy()
	for z in range(12,24):
		for x in range(100,112):
			var i := x+z*multiple.width;multiple.heights[i]=48;multiple.water_levels[i]=64;multiple.water_materials[i]=3
	var lake := MeshBuilder.build_tile(multiple,64,0,64,0,false,PackedVector4Array(),{},false,false,true)
	var lake_points := vertices(lake); var high_count := 0
	for point: Vector3 in lake_points:
		if point.y>60:
			high_count+=1;check(absf(point.y-71.02)<0.00002,"local lake level")
			check(point.x>=100 and point.x<=112 and point.z>=12 and point.z<=24,"lake does not flood dry low terrain")
	check(high_count>100,"local lake drawn")
	print("SMOOTH_SHORE ","PASS" if errors.is_empty() else "FAIL"," fractional=",fractional," collar_vertices=",extended," ",errors)
	quit(0 if errors.is_empty() else 1)
