extends RefCounted
## Restores the selected 2026-10-12 LAB shape exactly. No production mesher,
## authoring Source/schema, tree generator UI or collision transfer.
const Provider=preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
var cloud_caps: Array[Dictionary]=[]
var leaf_specs: Array[Dictionary]=[]
var wood_lines: Array[Dictionary]=[]
var bark_tone:=Color("916044")
var report: Dictionary={}


func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	var normal := (b-a).cross(c-a).normalized()
	for vertex in [a,b,c]:
		st.set_normal(normal); st.set_color(colour); st.add_vertex(vertex)

func small_leaf(st: SurfaceTool, base: Vector3, axis: Vector3, side: Vector3, length_m: float, width_m: float, colour: Color) -> void:
	var up := side.cross(axis).normalized()
	var rows: Array[Array] = []
	for index in 4:
		var t := float(index)/3.0
		var width := pow(sin(PI*t),0.75)*width_m
		var centre := base+axis*length_m*t+up*(sin(PI*t)*length_m*0.14-t*t*length_m*0.07)
		rows.append([centre-side*width-up*width*0.24,centre+up*width*0.16,centre+side*width-up*width*0.24])
	for index in 3:
		for column in 2:
			triangle(st,rows[index][column],rows[index+1][column],rows[index][column+1],colour)
			triangle(st,rows[index][column+1],rows[index+1][column],rows[index+1][column+1],colour)

func add_smooth_vertex(st: SurfaceTool, point: Vector3, normal: Vector3, uv: Vector2, tone: Color) -> void:
	st.set_normal(normal);st.set_uv(uv);st.set_color(tone);st.add_vertex(point)

func dome_vertex(centre: Vector3, radii: Vector3, theta: float, phi: float, phase: float) -> Dictionary:
	var wobble:=1.0+0.035*sin(phi*3.0+phase)*sin(theta)
	var local:=Vector3(sin(theta)*cos(phi)*radii.x*wobble,cos(theta)*radii.y,sin(theta)*sin(phi)*radii.z*wobble)
	var normal:Vector3=(local/(radii*radii)).normalized()
	return {"point":centre+local,"normal":normal,"uv":Vector2(phi/TAU+phase/TAU,theta/PI)}

func add_dome(st: SurfaceTool, centre: Vector3, radii: Vector3, phase: float, tone: Color) -> void:
	var cutoff:float=-0.12
	var theta_max:=acos(cutoff)
	var rings:=14;var sectors:=48
	for ring in rings:
		for sector in sectors:
			var theta0:=theta_max*float(ring)/rings;var theta1:=theta_max*float(ring+1)/rings
			var phi0:=TAU*float(sector)/sectors;var phi1:=TAU*float(sector+1)/sectors
			var a:=dome_vertex(centre,radii,theta0,phi0,phase)
			var b:=dome_vertex(centre,radii,theta1,phi0,phase)
			var c:=dome_vertex(centre,radii,theta0,phi1,phase)
			var d:=dome_vertex(centre,radii,theta1,phi1,phase)
			for vertex:Dictionary in [a,b,c,c,b,d]:add_smooth_vertex(st,vertex.point,vertex.normal,vertex.uv,tone)
	var bottom:=centre+Vector3.DOWN*radii.y*0.12
	for sector in sectors:
		var a:=dome_vertex(centre,radii,theta_max,TAU*float(sector)/sectors,phase)
		var b:=dome_vertex(centre,radii,theta_max,TAU*float(sector+1)/sectors,phase)
		for point:Vector3 in [bottom,b.point,a.point]:add_smooth_vertex(st,point,Vector3.DOWN,Vector2(0.01,0.95),tone.darkened(0.10))

func select_caps(groups: Array, offset: Vector3) -> Array[Dictionary]:
	var eligible:Array[Dictionary]=[]
	for group:Dictionary in groups:
		if group.along:continue
		var centre:Vector3=(group.center+offset)/16.0
		var radii:Vector3=group.radii/16.0
		radii.x*=1.12;radii.z*=1.12
		radii.y=maxf(radii.y*1.6,minf(radii.x,radii.z)*0.60)
		eligible.append({"centre":centre,"radii":radii})
	eligible.sort_custom(func(a:Dictionary,b:Dictionary):return a.radii.x*a.radii.z>b.radii.x*b.radii.z)
	var selected:Array[Dictionary]=[]
	for cap:Dictionary in eligible:
		var overlaps:=false
		for previous:Dictionary in selected:
			var radius:Vector3=(cap.radii+previous.radii)*0.5
			if ((cap.centre-previous.centre)/radius).length()<1.00:overlaps=true;break
		if not overlaps:selected.append(cap)
		if selected.size()>=14:break
	return selected

func cloud_contains(point: Vector3, cap: Dictionary) -> bool:
	var relative: Vector3 = (point-cap.centre)/cap.radii
	return relative.y >= -0.12 and relative.length_squared() <= 1.0

func prepare_shape(groups: Array, lines: Array, offset: Vector3) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed=39217
	var primary := select_caps(groups,offset)
	for source: Dictionary in primary:
		var cap := source.duplicate(true)
		cap.radii *= Vector3(rng.randf_range(0.94,1.06),rng.randf_range(0.92,1.12),rng.randf_range(0.95,1.05))
		cap.phase=rng.randf()*TAU
		cap.tone=Color("4f8f50").lightened(rng.randf_range(-0.015,0.04))
		cloud_caps.append(cap)
		# Offset lower lobes make a cloud silhouette rather than repeated domes.
		for lobe in 2:
			var phi: float=cap.phase+float(lobe)*2.6+rng.randf_range(-0.5,0.5)
			var satellite := cap.duplicate(true)
			satellite.radii *= rng.randf_range(0.52,0.68)
			satellite.centre += Vector3(cos(phi)*cap.radii.x*0.58,0,sin(phi)*cap.radii.z*0.58)
			satellite.centre.y=cap.centre.y-cap.radii.y*0.12+satellite.radii.y*0.12
			cloud_caps.append(satellite)
	for index in range(0,cloud_caps.size(),3):
		var cap: Dictionary=cloud_caps[index]
		for cluster in rng.randi_range(4,9):
			var phi: float=rng.randf()*TAU
			var radial:=Vector3(cos(phi),0,sin(phi))
			var side:=Vector3(-sin(phi),0,cos(phi))
			var edge: Vector3=dome_vertex(cap.centre,cap.radii,acos(-0.12),phi,cap.phase).point
			# Hide internal rim bunches inside another cloud mass.
			var covered:=false
			for other in cloud_caps.size():
				if other!=index and cloud_contains(edge+Vector3.UP*0.06,cloud_caps[other]): covered=true;break
			if covered:continue
			var count:=rng.randi_range(1,4)
			var length_m: float=minf(cap.radii.x,cap.radii.z)*rng.randf_range(0.24,0.52)
			for leaf in count:
				var anchor: Vector3=edge+side*rng.randf_range(-0.13,0.13)*cap.radii.x+radial*rng.randf_range(-0.04,0.04)
				var axis: Vector3=(Vector3.DOWN+radial*rng.randf_range(0.08,0.35)+side*rng.randf_range(-0.32,0.32)).normalized()
				leaf_specs.append({"base":anchor,"axis":axis,"side":side,"length":length_m*rng.randf_range(0.65,1.20),"width":length_m*rng.randf_range(0.24,0.36),"tone":cap.tone.darkened(rng.randf_range(0.0,0.06))})
	for line: Dictionary in lines:
		wood_lines.append({"a":(line.start+offset)/16.0,"b":(line.finish+offset)/16.0,"r0":float(line.r0)/16.0,"r1":float(line.r1)/16.0})

func smooth_wood(sampling_step := 0.075, blend_radius := 0.07) -> ArrayMesh:
	# Lab surface extraction joins the branch volumes into one rounded surface.
	# It still derives from the generated scaffold, not arbitrary authored voxels.
	var step: float=sampling_step
	var blend: float=blend_radius
	var field: Dictionary={}
	for line: Dictionary in wood_lines:
		var radius: float=maxf(line.r0,line.r1)+blend+step*2.0
		var extent: Vector3=Vector3.ONE*radius
		if line.has("ellipsoid_radii"):extent=line.ellipsoid_radii+Vector3.ONE*(blend+step*2.0)
		var low:=Vector3i(((line.a.min(line.b)-extent)/step).floor())
		var high:=Vector3i(((line.a.max(line.b)+extent)/step).ceil())
		var delta: Vector3=line.b-line.a
		for y in range(low.y,high.y+1):
			for z in range(low.z,high.z+1):
				for x in range(low.x,high.x+1):
					var key:=Vector3i(x,y,z);var point:=Vector3(key)*step
					var t:=clampf((point-line.a).dot(delta)/maxf(delta.length_squared(),0.0001),0,1)
					var distance: float=point.distance_to(line.a+delta*t)-lerpf(line.r0,line.r1,t)
					if line.has("ellipsoid_radii"):
						# Opt-in crown diagnostics reuse the same field/union/extractor.
						# Existing wood capsules retain their original distance path.
						var radii: Vector3=line.ellipsoid_radii
						var local: Vector3=point-line.a
						var k0: float=(local/radii).length()
						var k1: float=(local/(radii*radii)).length()
						distance=k0*(k0-1.0)/k1 if k1>0.00001 else -minf(radii.x,minf(radii.y,radii.z))
					if field.has(key):
						var previous: float=field[key]
						var h:=maxf(blend-absf(previous-distance),0.0)/blend
						distance=minf(previous,distance)-h*h*blend*0.25
					field[key]=distance
	var candidates: Dictionary={}
	for key: Vector3i in field:
		if float(field[key])<=0:
			for x in [0,-1]:
				for y in [0,-1]:
					for z in [0,-1]:candidates[key+Vector3i(x,y,z)]=true
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3i]=[Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(1,1,0),Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(1,1,1),Vector3i(0,1,1)]
	var tetrahedra: Array=[[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]]
	var edges: Array=[[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]
	for cell: Vector3i in candidates:
		var values: Array[float]=[];var gradients: Array[Vector3]=[]
		for corner: Vector3i in corners:
			var key:=cell+corner
			values.append(float(field.get(key,step*3.0)))
			var gradient:=Vector3.ZERO
			for axis in 3:
				var direction:=Vector3i.ZERO;direction[axis]=1
				gradient[axis]=float(field.get(key+direction,step*3.0))-float(field.get(key-direction,step*3.0))
			gradients.append(gradient.normalized())
		for tetra: Array in tetrahedra:
			var points: Array[Dictionary]=[]
			for edge: Array in edges:
				var a: int=tetra[edge[0]];var b: int=tetra[edge[1]]
				if (values[a]<0)==(values[b]<0):continue
				var t:=values[a]/(values[a]-values[b])
				points.append({"p":(Vector3(cell)+Vector3(corners[a]).lerp(Vector3(corners[b]),t))*step,"n":gradients[a].lerp(gradients[b],t).normalized()})
			if points.size()<3:continue
			var centre:=Vector3.ZERO;var normal:=Vector3.ZERO
			for point: Dictionary in points:centre+=point.p;normal+=point.n
			centre/=points.size();normal=normal.normalized()
			var u: Vector3=(points[0].p-centre).normalized();var v:=normal.cross(u).normalized()
			for point: Dictionary in points:point.angle=atan2((point.p-centre).dot(v),(point.p-centre).dot(u))
			points.sort_custom(func(a:Dictionary,b:Dictionary):return a.angle<b.angle)
			for j in range(1,points.size()-1):
				for point: Dictionary in [points[0],points[j+1],points[j]]:add_smooth_vertex(st,point.p,point.n,Vector2.ZERO,bark_tone)
	report["rounded_wood"]={"method":"smooth union of tapered branch volumes, marching tetrahedra","sampling_m":step,"blend_m":blend}
	return st.commit()

func smooth_clouds() -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cap: Dictionary in cloud_caps: add_dome(st,cap.centre,cap.radii,cap.phase,cap.tone)
	return st.commit()

func smooth_leaves() -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for spec: Dictionary in leaf_specs: small_leaf(st,spec.base,spec.axis,spec.side,spec.length,spec.width,spec.tone)
	return st.commit()

func build() -> Dictionary:
	var parameters:=Provider.defaults()
	parameters.generation_version=17;parameters.tree_type=1;parameters.height=96
	parameters.foliage_style=3;parameters.foliage_amount=90;parameters.structure_diversity=65
	var built:=Provider.build(parameters,7,Color.WHITE,{},"Saved smooth oak","smooth_bark_lab_oak")
	assert(not built.has("error"))
	var source_hash: String=built.geometry.voxels.hex_encode().sha256_text()
	assert(source_hash=="7394d61bdfc6754f001a9bde18263817633f36becc6711f0d3e1df55f4334a26")
	prepare_shape(built.structure.groups,built.structure.lines,Vector3(built.pivot_bias.x,0,built.pivot_bias.y))
	var meshes:={"wood":smooth_wood(),"clouds":smooth_clouds(),"leaves":smooth_leaves()}
	assert(source_hash==built.geometry.voxels.hex_encode().sha256_text())
	return {"meshes":meshes,"source":built.geometry,"structure":built.structure,"pivot_bias":built.pivot_bias,
		"cloud_lobes":cloud_caps.size(),"hanging_leaves":leaf_specs.size(),"wood_segments":wood_lines.size(),
		"source_sha256":source_hash,"parameters":parameters}
