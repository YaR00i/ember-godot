@tool
extends RefCounted
## Layered landform pieces use the same Source, convex guides and material roles as ordinary props.
const Geometry = preload("res://addons/ember_import/ember_voxel_generator_geometry.gd")
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const Rock = preload("res://addons/ember_import/ember_voxel_rock_generator.gd")
const DENSITY := 16
const MAX_STORAGE_CELLS := 524288
const TITLES := ["Травяное плато", "Прямой уступ", "Угловой уступ", "Природный выступ"]

static func fields() -> Array[Dictionary]:
	return [
		{"key":"shape","title":"Форма","options":TITLES,"identity":true},
		{"key":"width_m","title":"Ширина, м","min":2.0,"max":6.0,"step":0.25,"type":"float"},
		{"key":"depth_m","title":"Глубина, м","min":2.0,"max":5.0,"step":0.25,"type":"float"},
		{"key":"height_m","title":"Высота, м","min":0.75,"max":3.0,"step":0.25,"type":"float"},
		{"key":"soil_depth_m","title":"Толщина земли, м","min":0.125,"max":2.0,"step":0.125,"type":"float"},
		{"key":"edge_breakup","title":"Неровность края, %","min":0,"max":100},
		{"key":"form_strength","title":"Природная форма, %","min":0,"max":100},
		{"key":"grass_color","title":"Травяной верх","type":"color"},
		{"key":"soil_color","title":"Земля","type":"color"},
		{"key":"stone_color","title":"Каменное основание","type":"color"},
	]

static func normalize(parameters: Dictionary) -> Dictionary:
	var result := {"shape":0,"width_m":4.5,"depth_m":3.5,"height_m":1.75,
		"soil_depth_m":0.625,"edge_breakup":35,"form_strength":0,"grass_color":Color("738f48"),
		"soil_color":Color("876348"),"stone_color":Color("7c8389"),"density":DENSITY}
	for field in fields():
		var value: Variant = parameters.get(field.key,result[field.key])
		if field.has("options"):
			if value is int or value is float:
				if is_finite(float(value)): result[field.key]=clampi(int(value),0,field.options.size()-1)
		elif field.get("type","")=="color":
			if value is Color and is_finite(value.r) and is_finite(value.g) and is_finite(value.b): result[field.key]=Color(value,1.0)
		elif (value is float or value is int) and is_finite(float(value)):
			var number := clampf(snappedf(float(value),float(field.get("step",1.0))),field.min,field.max)
			result[field.key]=number if field.get("type","")=="float" else int(number)
	# Keep a physical stone footing and the thin grass cap at every allowed height.
	result.soil_depth_m=minf(result.soil_depth_m,result.height_m-0.25)
	return result

static func build(parameters: Dictionary, seed: int, _color: Color, material: Dictionary, title: String, model_id: String) -> Dictionary:
	var settings := normalize(parameters)
	var width := roundi(settings.width_m*DENSITY)
	var depth := roundi(settings.depth_m*DENSITY)
	var height := roundi(settings.height_m*DENSITY)
	var soil := roundi(settings.soil_depth_m*DENSITY)
	var grass := 2
	var grid := Vector3i(ceili(float(width+4)/DENSITY)*DENSITY,height+2,ceili(float(depth+4)/DENSITY)*DENSITY)
	if grid.x*grid.y*grid.z>MAX_STORAGE_CELLS: return {"error":"Уступ превышает бюджет сетки. Уменьшите его размеры."}
	var source := EmberVoxelModelResource.new()
	source.model_id=model_id; source.display_name=title; source.voxels_per_block=DENSITY
	source.size_blocks=Vector3i(grid.x/DENSITY,ceili(float(grid.y)/DENSITY),grid.z/DENSITY)
	source.height_voxels=grid.y
	source.tags=PackedStringArray(["generated","landform","cliff","environment"])
	source.material=material.duplicate(true)
	source.palette=PackedColorArray([Color.TRANSPARENT,settings.stone_color,settings.soil_color,settings.grass_color])
	source.voxels.resize(grid.x*grid.y*grid.z); source.voxel_part_ids.resize(source.voxels.size())
	var x0 := float((grid.x-width)/2); var z0 := float((grid.z-depth)/2)
	var footprints: Array[Dictionary]=[]
	if settings.shape==2:
		var arm_x := floorf(width*0.46); var arm_z := floorf(depth*0.46)
		# Two touching convex arms keep the inward corner open in every look.
		footprints.append({"lo":Vector2(x0,z0),"hi":Vector2(x0+width,z0+arm_z),"corners":[0,1,2],"join_back":true})
		footprints.append({"lo":Vector2(x0,z0+arm_z),"hi":Vector2(x0+arm_x,z0+depth),"corners":[2,3],"join_front":true})
	else:
		footprints.append({"lo":Vector2(x0,z0),"hi":Vector2(x0+width,z0+depth),"corners":[0,1,2,3] if settings.shape==0 else [0,1]})
	var rng := RandomNumberGenerator.new(); rng.seed=maxi(0,seed)
	var guides: Array=[]
	var volumes: Array[Dictionary]=[]
	if settings.shape==3:
		volumes=Rock.landform_parts(Vector3(x0,0,z0),Vector3(x0+width,height,z0+depth),seed,float(settings.form_strength)/100.0,int(settings.edge_breakup))
	for footprint in footprints:
		if settings.shape==3: break
		var cuts := _corner_planes(footprint,rng,float(settings.edge_breakup)/100.0)
		if settings.form_strength>0:
			volumes.append_array(_natural_parts(footprint,cuts,rng,height,soil,float(settings.form_strength)/100.0))
			continue
		for band in [{"lo":0,"hi":height-soil-grass,"slot":1,"title":"Каменное основание"},
			{"lo":height-soil-grass,"hi":height-grass,"slot":2,"title":"Слой земли"},
			{"lo":height-grass,"hi":height,"slot":3,"title":"Травяной верх"}]:
			var lo: Vector2=footprint.lo; var hi: Vector2=footprint.hi
			var planes := Geometry.bounds_planes(Vector3(lo.x,band.lo,lo.y),Vector3(hi.x,band.hi,hi.y))
			planes.append_array(cuts)
			volumes.append({"planes":planes,"slot":band.slot,"title":band.title})
	for volume in volumes:
		var directions := PackedVector3Array()
		for plane: Plane in volume.planes: directions.append(plane.normal)
		guides.append(directions); source.merge_parts.append(volume.title)
		Geometry.paint_convex_part(source,grid,volume,guides.size())
	if settings.shape==3:
		_paint_landform(source,grid,soil,seed,volumes)
	source.solid_surface={"version":1,"parts":guides,"occupancy":Solid.occupancy_hash(source.voxels),
		"roles":PackedStringArray(["","stone","soil","grass"]),
		"material_ids":PackedStringArray(["","cartoon_stone","soil_grain","cartoon_grass"])}
	# A hull face has one material. The existing volume boundary preserves the
	# painted cap/side when several covers share the same natural mass.
	if settings.shape==3:source.solid_surface.topology="volume"
	var errors := source.validation_errors()
	if not errors.is_empty(): return {"error":errors[0]}
	return {"geometry":source,"parameters":settings}


## Paint the already-built mass; changing soil depth never moves its silhouette.
static func _paint_landform(source: EmberVoxelModelResource, grid: Vector3i, soil: int, seed: int, volumes: Array[Dictionary]) -> void:
	var values := source.voxels
	var owners := source.voxel_part_ids
	var tops := PackedInt32Array(); tops.resize(source.merge_parts.size()+1); tops.fill(-1)
	for index in values.size():
		if values[index]>0:
			var y := index/(grid.x*grid.z)
			tops[owners[index]]=maxi(tops[owners[index]],y)
	var noise := FastNoiseLite.new(); noise.seed=maxi(0,seed);noise.frequency=0.045
	for z in grid.z:
		for x in grid.x:
			var top := -1
			for y in range(grid.y-1,-1,-1):
				if values[VoxMesher.cell_index(x,y,z,grid.x,grid.z)]>0: top=y;break
			if top<0:continue
			for y in range(top+1):
				var index := VoxMesher.cell_index(x,y,z,grid.x,grid.z)
				if values[index]==0:continue
				var cap: Plane=volumes[owners[index]-1].planes[-1]
				var terrace_top := mini(tops[owners[index]],floori((cap.d-cap.normal.x*(x+0.5)-cap.normal.z*(z+0.5))/cap.normal.y-0.5))
				var rock_top := maxi(0,terrace_top-soil+roundi(noise.get_noise_2d(x,z)*soil*0.45))
				values[index]=3 if y>=terrace_top-1 else (1 if y<rock_top else 2)
	source.voxels=values

## Three adjoining convex regions give a changing contour and tilted terraces.
## Every region owns its occupied volume; none is a floating decorative shell.
static func _natural_parts(footprint: Dictionary, cuts: Array[Plane], rng: RandomNumberGenerator, height: int, soil: int, strength: float) -> Array[Dictionary]:
	var lo: Vector2=footprint.lo; var hi: Vector2=footprint.hi
	var size := hi-lo; var centre_z := (lo.y+hi.y)*0.5
	var skew := rng.randf_range(-0.22,0.22)*strength
	var u0 := lo.x-absf(skew)*size.y*0.5
	var u1 := hi.x+absf(skew)*size.y*0.5
	var points := [u0,lerpf(u0,u1,rng.randf_range(0.25,0.34)),lerpf(u0,u1,rng.randf_range(0.64,0.75)),u1]
	var left_lean := rng.randf_range(0.10,0.24)*strength
	var right_lean := rng.randf_range(0.06,0.26)*strength
	var front_lean := rng.randf_range(-0.03,0.28)*strength if not footprint.get("join_front",false) else 0.0
	var back_lean := rng.randf_range(0.08,0.32)*strength if not footprint.get("join_back",false) else 0.0
	var front: Array[float]=[]; var back: Array[float]=[]
	for i in 4:
		var inset := rng.randf_range(0.12,0.28) if i in [0,3] else rng.randf_range(-0.04,0.18)
		front.append(lo.y+size.y*inset*strength if not footprint.get("join_front",false) else lo.y)
		inset = rng.randf_range(0.10,0.26) if i in [0,3] else rng.randf_range(-0.04,0.18)
		back.append(hi.y-size.y*inset*strength if not footprint.get("join_back",false) else hi.y)
	var result: Array[Dictionary]=[]
	for region in 3:
		var left: float=points[region]; var right: float=points[region+1]
		var top := height-roundi(height*strength*rng.randf_range(0.10,0.24)) if region!=1 else height
		var local_soil := clampi(roundi(soil*(1.0+rng.randf_range(-0.2,0.2)*strength)),2,top-4)
		var tilt := rng.randf_range(-0.06,0.06)*strength
		var mid := (left+right)*0.5
		var partition := Vector3(1,0,skew)
		var top_axis := Vector3(-tilt,1,-tilt*skew)
		var top_d := float(top)-tilt*(mid+skew*centre_z)
		for band in 3:
			var planes := Geometry.bounds_planes(Vector3(lo.x,0,lo.y),Vector3(hi.x,height,hi.y))
			planes.append_array(cuts)
			planes.append(_unit_plane(-partition,-left-skew*centre_z))
			planes.append(_unit_plane(partition,right+skew*centre_z))
			planes.append(_unit_plane(Vector3(-1,left_lean,0),-lo.x))
			planes.append(_unit_plane(Vector3(1,right_lean,0),hi.x))
			# Stone is broader than soil; the cap follows the soil's contour.
			var lip := strength*3.0 if band>0 else 0.0
			var front_lip := 0.0 if footprint.get("join_front",false) else lip
			var back_lip := 0.0 if footprint.get("join_back",false) else lip
			var slope := (front[region+1]-front[region])/(right-left)
			planes.append(_unit_plane(Vector3(slope,front_lean,slope*skew-1),-front[region]-front_lip+slope*left+slope*skew*centre_z))
			slope = (back[region+1]-back[region])/(right-left)
			planes.append(_unit_plane(Vector3(-slope,back_lean,1-slope*skew),back[region]-back_lip-slope*left-slope*skew*centre_z))
			if band==0:
				planes.append(_unit_plane(top_axis,top_d-local_soil-2))
			elif band==1:
				planes.append(_unit_plane(-top_axis,-top_d+local_soil+2))
				planes.append(_unit_plane(top_axis,top_d-2))
			else:
				planes.append(_unit_plane(-top_axis,-top_d+2))
				planes.append(_unit_plane(top_axis,top_d))
			result.append({"planes":planes,"slot":band+1,"title":["Каменный выступ","Слой земли","Травяная терраса"][band]})
	return result

static func _unit_plane(axis: Vector3, distance: float) -> Plane:
	return Plane(axis.normalized(),distance/axis.length())

static func _corner_planes(footprint: Dictionary, rng: RandomNumberGenerator, roughness: float) -> Array[Plane]:
	var lo: Vector2=footprint.lo; var hi: Vector2=footprint.hi
	var size := hi-lo; var result: Array[Plane]=[]
	var corners := [Vector2(lo.x,lo.y),Vector2(hi.x,lo.y),Vector2(hi.x,hi.y),Vector2(lo.x,hi.y)]
	var outward := [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
	for index in footprint.corners:
		var axis: Vector2=outward[index]
		var cut := minf(size.x,size.y)*(0.16+rng.randf_range(-0.09,0.09)*roughness)
		var n := Vector3(axis.x,0,axis.y).normalized()
		var corner: Vector2=corners[index]
		result.append(Plane(n,n.dot(Vector3(corner.x,0,corner.y))-cut))
	return result
