@tool
extends RefCounted
## Thin painted foliage, built once. Same GrassPatch/MultiMesh/material owners; no voxel source.
const PATTERN_PATH = "res://content/terrain_materials/meadow_daisy_cover.tres"
const SETS = [
	["Ромашки",PATTERN_PATH],
	["Жёлтые лютики","res://content/terrain_materials/meadow_buttercup_cover.tres"],
	["Сиреневые соцветия","res://content/terrain_materials/meadow_lilac_cover.tres"],
	["Маки","res://content/terrain_materials/meadow_poppy_cover.tres"],
	["Васильки","res://content/terrain_materials/meadow_cornflower_cover.tres"],
	["Пшеница","res://content/terrain_materials/meadow_wheat_cover.tres"]
]
const SHAPE_LABELS = ["Ромашки","Лютики · чашечки","Луговые соцветия","Маки · чашечки","Васильки","Пшеница · колосья"]
static var _meshes: Dictionary = {}

static func validation_errors(pattern: EmberCompactTerrainPattern) -> Array[String]:
	if pattern == null: return ["Не выбран рисунок цветущей травы."]
	var errors := pattern.validation_errors()
	if pattern.albedo_texture == null: errors.append("Выберите атлас растения.")
	return errors

static func mesh(pattern: EmberCompactTerrainPattern = null) -> ArrayMesh:
	var shape := pattern.flower_shape if pattern != null else 0
	if _meshes.has(shape): return _meshes[shape]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(Color(1,0,0,1))
	# One reusable cluster: three rooted plants, each with its own stem, leaves and head.
	# Placement/size/seed still belong to GrassPatch, not to a second scatter system.
	for spec in [
		[Vector3(-0.068,0,0.035),0.235,Vector2(-0.018,0.012),0.042,Vector3(-0.15,0.2,0.12)],
		[Vector3(0.037,0,-0.043),0.298,Vector2(0.021,-0.009),0.048,Vector3(0.22,1.1,-0.18)],
		[Vector3(0.071,0,0.067),0.203,Vector2(-0.010,-0.016),0.037,Vector3(-0.31,2.6,0.24)]
	]:
		var root: Vector3 = spec[0] + Vector3.DOWN*0.014
		var height: float = spec[1]; var bend: Vector2 = spec[2]
		if shape == 1: height *= 0.80
		if shape == 2: height *= 1.18
		if shape == 3: height *= 1.35
		if shape == 4: height *= 1.50
		if shape == 5:
			# A rooted reed and crossed ear contours use the same material/wind
			# and scatter as other plants; no voxel mesh or per-stalk node.
			height *= 2.7
			_reed(surface,root,height,bend*2)
			_leaf(surface,_stem_point(root,height,bend*2,0.35),spec[4].y,0.15)
			_leaf(surface,_stem_point(root,height,bend*2,0.58),spec[4].y+2.8,0.12)
			_ear(surface,_stem_point(root,height,bend*2,1),0.17,0.022,spec[4].y)
			continue
		_stem(surface,root,height,bend)
		_leaf(surface,_stem_point(root,height,bend,0.34),spec[4].y+0.6,0.095)
		_leaf(surface,_stem_point(root,height,bend,0.53),spec[4].y+3.2,0.080)
		if shape == 2:
			# Several four-petal florets on attached side stalks form a small meadow inflorescence.
			for floret in 5:
				var angle: float = spec[4].y+floret*2.4
				var branch := Vector2.from_angle(angle)*(0.020 if floret<4 else 0.009)
				var anchor := _stem_point(root,height,bend,0.60+floret*0.09)
				_stem(surface,anchor,0.017,branch)
				_head(surface,_stem_point(anchor,0.017,branch,1),0.022-floret*0.0007,Basis.from_euler(Vector3(0.25,angle,0.18)),0.20)
		else:
			var radius := float(spec[3])*(0.82 if shape==1 else 1.22 if shape==3 else 0.9 if shape==4 else 1.0)
			_head(surface,_stem_point(root,height,bend,1),radius,Basis.from_euler(spec[4]),0.43 if shape==1 else 0.30 if shape==3 else 0.12 if shape==4 else -1.0)
	# Index complete attributes, retaining the atlas seams and triangle order.
	surface.index()
	var result: ArrayMesh = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd").object_mesh(surface.commit()).mesh
	_meshes[shape] = result
	return result

static func _reed(surface:SurfaceTool,root:Vector3,height:float,bend:Vector2)->void:
	for side in 2:
		var across:=Vector3.RIGHT if side==0 else Vector3.BACK
		for band in 2:
			var lower:=_stem_point(root,height,bend,band/2.0)
			var upper:=_stem_point(root,height,bend,(band+1)/2.0)
			_quad(surface,PackedVector3Array([lower-across*0.0018,lower+across*0.0018,upper+across*0.001,upper-across*0.001]),PackedVector2Array([Vector2(.25,.5),Vector2(.25,.5),Vector2(.25,.5),Vector2(.25,.5)]),Vector3.BACK if side==0 else Vector3.RIGHT)

static func _ear(surface:SurfaceTool,root:Vector3,height:float,width:float,yaw:float)->void:
	for side in 3:
		var angle:=yaw+side*PI/3.0
		var across:=Vector3(cos(angle),0,sin(angle))*width
		var tip:=root+Vector3(0.012,height,0)
		_quad(surface,PackedVector3Array([root-across,root+across,tip+across,tip-across]),PackedVector2Array([Vector2(.5,1),Vector2(1,1),Vector2(1,0),Vector2(.5,0)]),Vector3(-sin(angle),0,cos(angle)))

static func _stem_point(root: Vector3, height: float, bend: Vector2, t: float) -> Vector3:
	return root + Vector3(bend.x*t*t,height*t,bend.y*t*t)

static func _stem(surface: SurfaceTool, root: Vector3, height: float, bend: Vector2) -> void:
	# A narrow triangular tube reads as a stem from every angle, including overhead.
	for band in 3:
		var t0 := band/3.0; var t1 := (band+1)/3.0
		var lower := _stem_point(root,height,bend,t0); var upper := _stem_point(root,height,bend,t1)
		for side in 3:
			var a := Vector2.from_angle(side*TAU/3.0); var b := Vector2.from_angle((side+1)*TAU/3.0)
			var r0 := lerpf(0.0018,0.0009,t0); var r1 := lerpf(0.0018,0.0009,t1)
			var points := PackedVector3Array([lower+Vector3(a.x,0,a.y)*r0,lower+Vector3(b.x,0,b.y)*r0,upper+Vector3(b.x,0,b.y)*r1,upper+Vector3(a.x,0,a.y)*r1])
			var uv := PackedVector2Array([Vector2(0.25,0.5),Vector2(0.25,0.5),Vector2(0.25,0.5),Vector2(0.25,0.5)])
			_quad(surface,points,uv,Vector3(a.x+b.x,0,a.y+b.y).normalized())

static func _leaf(surface: SurfaceTool, origin: Vector3, angle: float, length_m: float) -> void:
	var along := Vector3(cos(angle),0,sin(angle)); var across := Vector3(-along.z,0,along.x)
	for band in 2:
		var points := PackedVector3Array(); var uv := PackedVector2Array()
		for p in [Vector2(-1,band/2.0),Vector2(1,band/2.0),Vector2(1,(band+1)/2.0),Vector2(-1,(band+1)/2.0)]:
			points.append(origin+along*(p.y*length_m)+across*(p.x*length_m*0.39)+Vector3.UP*(sin(p.y*PI)*0.018+p.y*0.018))
			uv.append(Vector2((p.x+1)*0.25,0.95-p.y*0.90))
		_quad(surface,points,uv,(Vector3.UP-along*0.2).normalized())

static func _head(surface: SurfaceTool, center: Vector3, radius: float, tilt: Basis, cup := -1.0) -> void:
	# Curved radial surface: each painted head exists once, with a real outline in side view.
	for segment in 12:
		var a := Vector2.from_angle(segment*TAU/12.0); var b := Vector2.from_angle((segment+1)*TAU/12.0)
		var inner_a := Vector3(a.x*radius*0.32,(0.002 if cup<0 else radius*0.05),a.y*radius*0.32)
		var inner_b := Vector3(b.x*radius*0.32,(0.002 if cup<0 else radius*0.05),b.y*radius*0.32)
		var outer_a := Vector3(a.x*radius,(0.010 if cup<0 else radius*cup),a.y*radius)
		var outer_b := Vector3(b.x*radius,(0.010 if cup<0 else radius*cup),b.y*radius)
		var normal := tilt*Vector3.UP
		_triangle(surface,PackedVector3Array([center,center+tilt*inner_b,center+tilt*inner_a]),PackedVector2Array([Vector2(0.75,0.5),_head_uv(b*0.32),_head_uv(a*0.32)]),normal)
		_quad(surface,PackedVector3Array([center+tilt*inner_a,center+tilt*inner_b,center+tilt*outer_b,center+tilt*outer_a]),PackedVector2Array([_head_uv(a*0.32),_head_uv(b*0.32),_head_uv(b),_head_uv(a)]),normal)

static func _head_uv(point: Vector2) -> Vector2:
	return Vector2(0.75+point.x*0.25,0.5+point.y*0.5)

static func _triangle(surface: SurfaceTool, points: PackedVector3Array, uv: PackedVector2Array, normal: Vector3) -> void:
	surface.set_normal(normal)
	for i in 3:
		surface.set_uv(uv[i]); surface.add_vertex(points[i])

static func _quad(surface: SurfaceTool, points: PackedVector3Array, uv: PackedVector2Array, normal: Vector3) -> void:
	for index in [0,2,1,0,3,2]:
		surface.set_normal(normal); surface.set_uv(uv[index]); surface.add_vertex(points[index])

static func bind(material: ShaderMaterial, pattern: EmberCompactTerrainPattern, slot: int) -> void:
	material.set_shader_parameter("flower_atlas",pattern.albedo_texture)
	material.set_shader_parameter("flower_tint",pattern.base_color)
	material.set_shader_parameter("flower_palette_slot",float(slot))
