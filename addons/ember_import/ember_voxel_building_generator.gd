@tool
extends RefCounted
## Exterior massing. One canonical source and the existing convex-part look path.
const Geometry = preload("res://addons/ember_import/ember_voxel_generator_geometry.gd")
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const DENSITY := 16
const MAX_STORAGE_CELLS := 2_097_152

static func fields() -> Array[Dictionary]:
	return [
		{"key":"width_m","title":"Ширина, м","min":3.0,"max":6.5,"step":0.25,"type":"float"},
		{"key":"depth_m","title":"Глубина, м","min":3.0,"max":5.5,"step":0.25,"type":"float"},
		{"key":"floors","title":"Этажи","min":1,"max":2},
		{"key":"floor_height_m","title":"Высота этажа, м","min":2.25,"max":3.0,"step":0.25,"type":"float"},
		{"key":"roof_height_m","title":"Высота крыши, м","min":0.75,"max":1.5,"step":0.25,"type":"float"},
		{"key":"overhang_m","title":"Свес крыши, м","min":0.125,"max":0.5,"step":0.125,"type":"float"},
		{"key":"wall_color","title":"Стены","type":"color"},
		{"key":"roof_color","title":"Кровля","type":"color"},
		{"key":"timber_color","title":"Деревянные детали","type":"color"},
	]

static func normalize(parameters: Dictionary) -> Dictionary:
	var result := {"width_m":4.5,"depth_m":3.5,"floors":1,"floor_height_m":2.75,"roof_height_m":1.25,"overhang_m":0.25,
		"wall_color":Color("e2d2ac"),"roof_color":Color("775247"),"timber_color":Color("4c4035"),"density":DENSITY}
	for field in fields():
		var value: Variant = parameters.get(field.key,result[field.key])
		if field.get("type","")=="color":
			if value is Color and is_finite(value.r) and is_finite(value.g) and is_finite(value.b): result[field.key]=Color(value,1.0)
		elif (value is float or value is int) and is_finite(float(value)):
			var step: float = field.get("step",1.0)
			var number: float = clampf(snappedf(float(value),step),field.min,field.max)
			result[field.key]=number if field.get("type","")=="float" else int(number)
	return result

static func build(parameters: Dictionary, _seed: int, _color: Color, material: Dictionary, title: String, model_id: String) -> Dictionary:
	var settings := normalize(parameters)
	var width := roundi(settings.width_m*DENSITY); var depth := roundi(settings.depth_m*DENSITY)
	var floor_height := roundi(settings.floor_height_m*DENSITY)
	var eave := 4 + floor_height*int(settings.floors)
	var roof_height := roundi(settings.roof_height_m*DENSITY); var overhang := roundi(settings.overhang_m*DENSITY)
	var margin := overhang+2
	var height := eave+roof_height+3
	var grid := Vector3i(ceili(float(width+margin*2)/DENSITY)*DENSITY,height,ceili(float(depth+margin*2)/DENSITY)*DENSITY)
	if grid.x*grid.y*grid.z>MAX_STORAGE_CELLS:
		return {"error":"Дом превышает бюджет сетки. Уменьшите ширину, глубину или высоту."}
	var source := EmberVoxelModelResource.new()
	source.model_id=model_id; source.display_name=title; source.voxels_per_block=DENSITY
	source.size_blocks=Vector3i(grid.x/DENSITY,ceili(float(height)/DENSITY),grid.z/DENSITY); source.height_voxels=height
	source.tags=PackedStringArray(["generated","building","coastal_house","godot-native"])
	source.material=material.duplicate(true)
	source.palette=PackedColorArray([Color.TRANSPARENT,settings.wall_color,settings.roof_color,settings.timber_color,Color("727570"),Color("779a9b")])
	source.voxels.resize(grid.x*grid.y*grid.z); source.voxel_part_ids.resize(source.voxels.size())
	var x0 := float((grid.x-width)/2); var z0 := float((grid.z-depth)/2)
	var x1 := x0+width; var z1 := z0+depth; var middle := (x0+x1)*0.5
	var slope := float(roof_height)/(width*0.5)
	var parts: Array[Dictionary]=[]
	box(parts,Vector3(x0-1,0,z0-1),Vector3(x1+1,4,z1+1),4,"Каменное основание")
	var house := bounds_planes(Vector3(x0,4,z0),Vector3(x1,eave+roof_height,z1))
	house.append(Plane(Vector3(-slope,1,0).normalized(),(eave-slope*x0)/sqrt(1+slope*slope)))
	house.append(Plane(Vector3(slope,1,0).normalized(),(eave+slope*x1)/sqrt(1+slope*slope)))
	parts.append({"planes":house,"slot":1,"title":"Стены и фронтоны"})
	for side in 2:
		var lo := x0-overhang if side==0 else middle
		var hi := middle if side==0 else x1+overhang
		var gradient := slope if side==0 else -slope
		var intercept := eave-gradient*(x0 if side==0 else x1)+3
		var roof := bounds_planes(Vector3(lo,eave-slope*overhang-1,z0-overhang),Vector3(hi,eave+roof_height+3,z1+overhang))
		var n := Vector3(-gradient,1,0).normalized()
		roof.append(Plane(n,intercept/sqrt(1+gradient*gradient)))
		roof.append(Plane(-n,(-intercept+3)/sqrt(1+gradient*gradient)))
		parts.append({"planes":roof,"slot":2,"title":"Скат крыши %d"%(side+1)})
	for x in [x0,x1-2]:
		for z in [z0,z1-2]: box(parts,Vector3(x-1,4,z-1),Vector3(x+3,eave,z+3),3,"Угловая стойка")
	for level in range(1,int(settings.floors)+1):
		var y := 4+level*floor_height-2
		box(parts,Vector3(x0-1,y,z0-1),Vector3(x1+1,y+2,z1+1),3,"Пояс фасада %d"%level)
	for level in int(settings.floors):
		var y := 4+level*floor_height+floor_height*0.38
		for fraction in [0.23,0.77]:
			var x := lerpf(x0,x1,fraction)
			box(parts,Vector3(x-6,y,z0-2),Vector3(x+6,y+16,z0+1),3,"Рама окна")
			box(parts,Vector3(x-4,y+2,z0-3),Vector3(x+4,y+14,z0-1),5,"Стекло окна")
		for side in 2:
			var x := x0-2 if side==0 else x1-1
			var z := (z0+z1)*0.5
			box(parts,Vector3(x,y,z-6),Vector3(x+3,y+16,z+6),3,"Боковая рама")
			box(parts,Vector3(x-1 if side==0 else x+2,y+2,z-4),Vector3(x+1 if side==0 else x+4,y+14,z+4),5,"Боковое стекло")
	box(parts,Vector3(middle-8,4,z0-3),Vector3(middle+8,35,z0+1),3,"Дверная рама")
	box(parts,Vector3(middle-6,4,z0-4),Vector3(middle+6,33,z0-2),3,"Дверь · внешний объём")
	var guides: Array[PackedVector3Array]=[]
	for part in parts:
		var directions:=PackedVector3Array()
		for plane: Plane in part.planes: directions.append(plane.normal)
		guides.append(directions); source.merge_parts.append(part.title)
		paint(source,grid,part,source.merge_parts.size())
	var roles:=PackedStringArray();var ids:=PackedStringArray();roles.resize(source.palette.size());ids.resize(source.palette.size())
	source.solid_surface={"version":1,"parts":guides,"occupancy":Solid.occupancy_hash(source.voxels),"roles":roles,"material_ids":ids}
	var errors:=source.validation_errors()
	if not errors.is_empty():return {"error":errors[0]}
	return {"geometry":source,"parameters":settings}

static func bounds_planes(lo: Vector3, hi: Vector3) -> Array[Plane]:
	return Geometry.bounds_planes(lo, hi)

static func box(parts: Array[Dictionary], lo: Vector3, hi: Vector3, slot: int, title: String) -> void:
	parts.append({"planes":bounds_planes(lo,hi),"slot":slot,"title":title})

static func paint(source: EmberVoxelModelResource, grid: Vector3i, part: Dictionary, id: int) -> void:
	Geometry.paint_convex_part(source, grid, part, id)
