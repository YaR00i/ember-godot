extends RefCounted
## Near-view meshes derived from provider-owned oak18 supports. Source is still
## EmberVoxelModelResource; no production renderer/collider or second generator.
const Provider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Profiles = preload("res://scripts/ember_voxel_material_profiles.gd")
const Rounded = preload("res://scripts/ember_tree_rounded_geometry.gd")

static func branches(structure: Dictionary) -> Array:
	var result: Array = []
	for line: Dictionary in structure.lines:
		var id := int(line.branch_id)
		if id == result.size():
			result.append({"id": id, "parent": line.parent_id, "attachment": line.parent_t,
				"order": line.order, "path": [line.start], "radii": [float(line.r0)]})
		result[id].path.append(line.finish)
		result[id].radii.append(float(line.r1))
	return result

static func point_at(branch: Dictionary, t: float) -> Vector3:
	var at: float = clampf(t, 0, 1) * (branch.path.size() - 1)
	var index := mini(floori(at), branch.path.size() - 2)
	return (branch.path[index] as Vector3).lerp(branch.path[index + 1], at - index)

static func wood_mesh(layout: Array, offset: Vector3, density: float, sectors:=12) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for branch: Dictionary in layout:
		var points: Array = branch.path
		var rings: Array = []
		var previous_u := Vector3.RIGHT
		for i in points.size():
			var a: Vector3 = points[maxi(i - 1, 0)]
			var b: Vector3 = points[mini(i + 1, points.size() - 1)]
			var axis := (b - a).normalized()
			var u := (previous_u - axis * previous_u.dot(axis)).normalized()
			if u.length_squared() < 0.1: u = axis.cross(Vector3.FORWARD).normalized()
			var v := axis.cross(u).normalized()
			previous_u = u
			var slope := (float(branch.radii[maxi(i - 1, 0)]) - float(branch.radii[mini(i + 1, points.size() - 1)])) / maxf(a.distance_to(b), 0.001)
			var ring: Array = []
			for j in sectors:
				var phi := j * TAU / sectors
				var radial := u * cos(phi) + v * sin(phi)
				ring.append({"p": (points[i] + offset + radial * float(branch.radii[i])) / density,
					"n": (radial + axis * slope).normalized()})
			rings.append(ring)
		for i in rings.size() - 1:
			for j in sectors:
				var next := (j + 1) % sectors
				for vertex: Dictionary in [rings[i][j], rings[i + 1][j], rings[i][next],
					rings[i][next], rings[i + 1][j], rings[i + 1][next]]:
					st.set_normal(vertex.n); st.set_color(Color("916044")); st.add_vertex(vertex.p)
		# Tiny terminal cap. Branch bases lie inside their parent and need no disc.
		var center: Vector3 = (points[-1] + offset) / density
		for j in sectors:
			for vertex: Dictionary in [{"p": center, "n": (points[-1] - points[-2]).normalized()},
				rings[-1][(j + 1) % sectors], rings[-1][j]]:
				st.set_normal(vertex.n); st.set_color(Color("916044")); st.add_vertex(vertex.p)
	return st.commit()

static func cards_mesh(layout: Array, offset: Vector3, density: float, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = seed + 73014
	var vertices := PackedVector3Array(); var normals := PackedVector3Array()
	var colours := PackedColorArray(); var uvs := PackedVector2Array()
	var indices := PackedInt32Array(); var roles := PackedFloat32Array()
	var macro_normals := PackedFloat32Array(); var roots: Array = []; var groups := 0
	for branch: Dictionary in layout:
		if branch.order < 0: continue
		groups += 1
		var sites: Array = [0.60, 0.80, 1.0] if branch.order >= 2 else [0.95]
		for t: float in sites:
			var anchor := (point_at(branch, t) + offset) / density
			var growth := (point_at(branch, minf(1.0, t + 0.05)) - point_at(branch, maxf(0.0, t - 0.05))).normalized()
			# Broadleaf fans spread mostly sideways while their stem remains on
			# the real shoot. Full axial rosettes would look like conifer needles.
			var horizontal := Vector3(growth.x, 0, growth.z).normalized()
			if horizontal.length_squared() < 0.1: horizontal = Vector3.RIGHT
			var forward := (horizontal + Vector3.UP * clampf(growth.y * 0.35, 0.08, 0.32)).normalized()
			var across := forward.cross(Vector3.UP).normalized()
			if across.length_squared() < 0.1: across = Vector3.RIGHT
			var up := across.cross(forward).normalized()
			var count := 3 if branch.order >= 2 else 6
			for i in count:
				# The texture's actual stem pixel is anchored on the twig. The
				# diagonal grows outward; rolling gives fixed overlapping fans.
				var roll := lerpf(-0.65, 0.65, float(i) / (count - 1)) + rng.randf_range(-0.18, 0.18)
				var normal := up.rotated(forward, roll)
				var side := forward.cross(normal).normalized()
				var x := (forward + side).normalized()
				var y := (forward - side).normalized()
				var width := rng.randf_range(0.95, 1.30)
				var height := width * rng.randf_range(0.88, 1.10)
				var base := vertices.size()
				var coordinates: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
				var role: Vector4 = Profiles.PROFILES.foliage
				var group_center: Vector3 = (point_at(branch, 0.85) + offset) / density
				for uv: Vector2 in coordinates:
					var point := anchor + x * (uv.x - 0.125) * width + y * (0.93 - uv.y) * height
					var macro := ((point - group_center) * 0.55 + Vector3.UP * 0.9).normalized()
					vertices.append(point); normals.append(normal); colours.append(Color("4f8f50")); uvs.append(uv)
					roles.append_array(PackedFloat32Array([role.x, role.y, role.z, 0]))
					macro_normals.append_array(PackedFloat32Array([macro.x, macro.y, macro.z, float(branch.id)]))
				indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
				roots.append({"branch": branch.id, "t": t, "point": anchor})
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_CUSTOM0] = roles; arrays[Mesh.ARRAY_CUSTOM1] = macro_normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return {"mesh": mesh, "roots": roots, "cards": roots.size(), "triangles": roots.size() * 2, "groups": groups}

static func crown_guides(layout: Array, structure: Dictionary, offset: Vector3, density: float) -> Dictionary:
	var guides := {}
	for group: Dictionary in structure.groups:
		if int(group.get("branch_id",-1))==0:
			var center: Vector3=(group.center+offset)/density
			var extent: Vector3=group.radii/density
			guides[0]={"low":center-extent,"high":center+extent}
	for branch: Dictionary in layout:
		if branch.order != 1: continue
		guides[branch.id] = {"low": Vector3.ONE * INF, "high": Vector3.ONE * -INF}
	for group: Dictionary in structure.groups:
		var id := int(group.get("branch_id", 0))
		if id == 0: continue
		while layout[id].order > 1: id = int(layout[id].parent)
		var center: Vector3 = (group.center + offset) / density
		var extent: Vector3 = group.radii / density
		guides[id].low = (guides[id].low as Vector3).min(center - extent)
		guides[id].high = (guides[id].high as Vector3).max(center + extent)
	for id: int in guides:
		var guide: Dictionary = guides[id]
		guide.center = (guide.low + guide.high) * 0.5
		guide.radii = (guide.high - guide.low) * 0.5
	return guides

static func crown_cards(layout: Array, structure: Dictionary, offset: Vector3, density: float, seed: int, options: Dictionary = {}) -> Dictionary:
	var guides := crown_guides(layout, structure, offset, density)
	var canopy_low:=Vector3.ONE*INF;var canopy_high:=Vector3.ONE*-INF
	if bool(options.get("branch_growth",false)):
		for guide: Dictionary in guides.values():
			canopy_low=canopy_low.min(guide.low);canopy_high=canopy_high.max(guide.high)
	var canopy_center:=(canopy_low+canopy_high)*0.5 if bool(options.get("branch_growth",false)) else Vector3.ZERO
	var canopy_radii:=(canopy_high-canopy_low)*0.5 if bool(options.get("branch_growth",false)) else Vector3.ONE
	var rng := RandomNumberGenerator.new(); rng.seed = seed + 73019
	var vertices := PackedVector3Array(); var normals := PackedVector3Array()
	var colours := PackedColorArray(); var uvs := PackedVector2Array()
	var indices := PackedInt32Array(); var roles := PackedFloat32Array()
	var macro_normals := PackedFloat32Array(); var roots: Array = []
	var us: Array[float] = [0.0,0.5,1.0]
	var vs: Array[float] = [0.0,0.5,0.94,1.0]
	var envelope_cards: bool=bool(options.get("canopy_envelope",false)) and int(structure.parameters.generation_version)==24 and int(structure.parameters.crown_shape)==1
	var needle_sprays: bool=bool(options.get("needle_sprays",false)) and int(structure.parameters.generation_version)==25
	var needle_boughs: bool=needle_sprays and bool(options.get("needle_boughs",false)) and int(structure.parameters.crown_shape)==1
	var supports: Dictionary={}
	if envelope_cards:
		for group: Dictionary in structure.groups:supports[int(group.branch_id)]=group
	for branch: Dictionary in layout:
		if branch.order < 0: continue
		var growth_cards := bool(options.get("branch_growth",false))
		var terminal := int(structure.parameters.get("branch_levels",4))
		if growth_cards and not needle_sprays and (branch.order < (1 if envelope_cards else maxi(2,terminal-1)) or branch.order==0):continue
		var owner := int(branch.id)
		while layout[owner].order > 1: owner = int(layout[owner].parent)
		var guide: Dictionary = guides[owner]
		if needle_sprays and branch.order==0:guide={"center":canopy_center,"radii":canopy_radii}
		var sites: Array = [0.24,0.43,0.62,0.81,1.0] if branch.order == 3 else ([0.20,0.40,0.60,0.80,1.0] if branch.order == 2 else ([0.94,0.97,1.0] if branch.order==0 else [0.38,0.52,0.66,0.80,0.94]))
		var count := 5 if branch.order == 3 else (12 if branch.order==0 else (8 if branch.order==1 else 4))
		if growth_cards:
			sites = [0.20,0.46,0.72,1.0] if branch.order==terminal else [0.42,0.72,1.0]
			count = 2 if branch.order==terminal else 3
			if int(structure.parameters.generation_version) in [22,23,24]:
				sites=[0.32,0.66,1.0];count=2
			if envelope_cards:
				sites=[0.94,1.0] if branch.order==1 else [0.32,0.66,1.0];count=6
			if needle_sprays:
				sites=[0.28,0.36,0.44,0.52,0.60,0.68,0.76,0.84,0.91,0.97,1.0] if branch.order==0 else ([0.15,0.32,0.49,0.66,0.82,1.0] if branch.order==1 else ([0.28,0.54,0.78,1.0] if branch.order==2 else [0.45,0.74,1.0]))
				count=6 if branch.order==0 else (3 if branch.order==1 else 2)
			if needle_boughs and branch.order>0:
				sites=[0.16,0.38,0.60,0.82,1.0] if branch.order==1 else ([0.08,0.52,1.0] if branch.order==2 else [0.10,1.0])
				count=2 if branch.order<=2 else 1
			elif needle_boughs:
				# Close the upper leader gaps without enlarging the needle texture.
				sites=[0.28,0.36,0.44,0.52,0.60,0.68,0.76,0.82,0.87,0.91,0.94,0.97,1.0]
		if options.get("garden_shrub", false):
			sites = [0.50, 0.93]
			count = 1
		for t: float in sites:
			var attachment := (point_at(branch, t) + offset) / density
			var terminal_puff: bool = envelope_cards and branch.order==terminal and is_equal_approx(t,1.0)
			for i in count:
				var tip_cover: bool = terminal_puff and i>=3
				var anchor:=attachment
				var phi := rng.randf() * TAU
				var elevation := rng.randf_range(-0.85,0.95)
				var random_dir := Vector3(cos(phi) * sqrt(1.0-elevation*elevation),elevation,sin(phi) * sqrt(1.0-elevation*elevation))
				if envelope_cards:
					var support_id:=int(branch.id)
					while layout[support_id].order>2:support_id=int(layout[support_id].parent)
					if i%2==0:support_id=owner
					var support: Dictionary=supports[support_id]
					anchor=(support.center+offset)/density+random_dir*(support.radii/density)*0.70
				var target: Vector3 = guide.center + random_dir * guide.radii * 0.70
				var forward := (target-anchor).normalized()
				if growth_cards:
					var growth := (point_at(branch,minf(t+0.08,1.0))-point_at(branch,maxf(t-0.08,0.0))).normalized()
					forward=(growth*0.60+random_dir*0.75+Vector3.UP*0.16).normalized()
				if growth_cards and int(structure.parameters.generation_version)==24:
					forward.y*=0.25;forward=forward.normalized()
				if needle_sprays:
					var growth: Vector3=(point_at(branch,minf(t+0.08,1.0))-point_at(branch,maxf(t-0.08,0.0))).normalized()
					forward=growth.rotated(Vector3.UP,(float(i)-float(count-1)*0.5)*0.42)
					if branch.order>0:forward=(forward-Vector3.UP*((0.22 if needle_boughs else 0.60) if branch.order==1 else 0.35)).normalized()
					else:
						var radial:=Vector3(cos(float(i)*TAU/count+t*17.0),0,sin(float(i)*TAU/count+t*17.0))
						forward=(Vector3.UP+radial*0.35).normalized() if t>=0.97 or i>=4 else (radial-Vector3.UP*0.65).normalized()
				if forward.length_squared() < 0.1: forward = Vector3.UP
				var across := forward.cross(Vector3.UP).normalized()
				if across.length_squared() < 0.1: across = Vector3.RIGHT
				var roll:=rng.randf()*TAU
				if growth_cards and int(structure.parameters.generation_version)==24:roll=sin(roll)*0.42
				if envelope_cards:roll=sin(roll)*0.85
				if needle_sprays:roll=float(i-4)*PI*0.5 if branch.order==0 and i>=4 else (0.0 if branch.order==0 else (float(i)-float(count-1)*0.5)*0.52)
				if tip_cover:
					# Three small fans follow the final shoot segment. The remaining
					# cards still fill its crown support, rather than a hollow shell.
					forward=(point_at(branch,1.0)-point_at(branch,0.92)).normalized()
					forward.y*=0.25;forward=forward.normalized()
					across=forward.cross(Vector3.UP).normalized()
					if across.length_squared()<0.1:across=Vector3.RIGHT
					roll=float(i-4)*0.18
				var normal := across.cross(forward).normalized().rotated(forward, roll)
				var side := forward.cross(normal).normalized()
				var width := rng.randf_range(0.72,1.08)
				if growth_cards:width*=float(options.get("size",0.86))
				if needle_sprays:
					var span: float=(branch.path[-1] as Vector3).distance_to(branch.path[0])/density
					width*=lerpf(1.55,0.20,inverse_lerp(0.25,1.0,t)) if branch.order==0 else clampf(span*0.80,0.28,1.0)
					if needle_boughs and branch.order>0:
						# Basal sprays cover the actual lateral shoot; small terminal
						# sprays finish it without extending a second branch-length.
						width=rng.randf_range(0.94,1.06)*float(options.get("size",0.86))*clampf(span*(0.30 if branch.order==1 else 0.90),0.07,0.78)
						if is_equal_approx(t,1.0):width*=0.30
				if tip_cover:width*=0.65
				var height := width * rng.randf_range(0.90,1.10)
				if needle_sprays and branch.order>0 and t>=0.78:height*=0.60
				if tip_cover:
					anchor=(point_at(branch,0.60+float(i-3)*0.20)+offset)/density-forward*height*0.45
				var tile := rng.randi_range(0,3)
				var base := vertices.size()
				var role: Vector4 = Profiles.PROFILES.foliage
				var root_warp := sin(PI*0.94) * width * 0.16
				if envelope_cards and not tip_cover:
					# Keep the complete patch at its original size; reject a card
					# outside the accepted support envelope instead of stretching it.
					var inside:=true
					for probe in [anchor,anchor+forward*height*0.94-side*width*0.5,anchor+forward*height*0.94+side*width*0.5]:
						if not crown_envelope_contains(probe,structure,offset,density,0.20):inside=false;break
					if not inside:continue
				for v: float in vs:
					for u: float in us:
						# A gently curved card occupies depth; stem UV has a real
						# mesh vertex on the shoot, including after the bend.
						var warp := sin(PI*u)*sin(PI*v)*width*0.16-root_warp
						var point := anchor + side * (u-0.5)*width + forward*(0.94-v)*height + normal*warp
						var macro: Vector3 = ((point-guide.center)/(guide.radii*guide.radii) + Vector3.UP*0.12).normalized()
						if growth_cards:
							var whole:=((point-canopy_center)/(canopy_radii*canopy_radii)+Vector3.UP*0.06).normalized()
							macro=(macro*0.45+whole*0.55).normalized()
						if macro.length_squared()<0.1: macro=Vector3.UP
						vertices.append(point); normals.append(normal); colours.append(Color("4f8f50"))
						uvs.append((Vector2(tile%2,tile/2)+Vector2(u,v).clamp(Vector2.ONE*0.002,Vector2.ONE*0.998))*0.5)
						roles.append_array(PackedFloat32Array([role.x,role.y,role.z,0]))
						macro_normals.append_array(PackedFloat32Array([macro.x,macro.y,macro.z,float(owner)]))
				for row in 3:
					for col in 2:
						var at := base+row*3+col
						indices.append_array(PackedInt32Array([at,at+3,at+1,at+1,at+3,at+4]))
				roots.append({"branch":branch.id,"t":t,"point":anchor,"vertex":base+7,"tile":tile})
				# Derived support description shared by alternative looks; no new RNG or
				# change to the accepted card buffers. Thinning retains this whole record.
				roots[-1]["patch"]={"anchor":anchor,"forward":forward,"side":side,"normal":normal,"width":width,"height":height,"tile":tile,"owner":owner}
				if envelope_cards:roots[-1]["attachment"]=attachment
				if terminal_puff:roots[-1]["tip_priority"]=true
				if tip_cover:roots[-1]["tip_cover"]=true
				if needle_sprays and is_equal_approx(t,1.0):roots[-1]["tip_priority"]=true
				if needle_boughs and branch.order in [1,2] and t==sites[0]:roots[-1]["tip_priority"]=true
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_CUSTOM0] = roles; arrays[Mesh.ARRAY_CUSTOM1] = macro_normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return {"mesh":mesh,"roots":roots,"cards":roots.size(),"triangles":indices.size()/3,"groups":guides.size(),"guides":guides}

static func crown_envelope_contains(point: Vector3,structure: Dictionary,offset: Vector3,density: float,margin:=0.0) -> bool:
	for group: Dictionary in structure.groups:
		var centre: Vector3=(group.center+offset)/density
		var radii: Vector3=group.radii/density+Vector3.ONE*margin
		if ((point-centre)/radii).length_squared()<=1.0:return true
	return false

static func crown_card_sample(full: Dictionary,count: int,start_card:=0) -> ArrayMesh:
	start_card=clampi(start_card,0,full.cards-1)
	count=clampi(count,1,full.cards-start_card)
	var source: Array=full.mesh.surface_get_arrays(0);var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1]:
		var stride:=12*(4 if channel in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1] else 1)
		arrays[channel]=source[channel].slice(start_card*stride,(start_card+count)*stride)
	arrays[Mesh.ARRAY_INDEX]=source[Mesh.ARRAY_INDEX].slice(start_card*36,(start_card+count)*36)
	for i in arrays[Mesh.ARRAY_INDEX].size():arrays[Mesh.ARRAY_INDEX][i]-=start_card*12
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return mesh

static func crown_puff_count(cards: Dictionary) -> int:
	var sites: Dictionary={}
	for root: Dictionary in cards.roots:sites[_crown_site_key(root)]=true
	return sites.size()

static func _crown_site_key(root: Dictionary) -> String:
	return "%d:%d"%[root.branch,roundi(float(root.t)*10000.0)]

static func _crown_site_rank(root: Dictionary) -> int:
	# Stable integer ranking independent of the generator's random stream.
	var rank: int=(int(root.branch)*73856093)^(roundi(float(root.t)*10000.0)*19349663)^73019
	rank &= 0x7fffffff
	rank=((rank^(rank>>16))*73244475)&0x7fffffff
	rank=((rank^(rank>>16))*73244475)&0x7fffffff
	# Opt-in umbrella/needle trials tag terminal puffs. Retain these first
	# within the same density budget; zero and local thinning still apply.
	return (rank^(rank>>16))-(2147483648 if bool(root.get("tip_priority",false)) else 0)

static func crown_leaf_groups(full: Dictionary) -> Dictionary:
	var source: Array=full.mesh.surface_get_arrays(0)
	var result: Dictionary={};var sites: Dictionary={}
	for root: Dictionary in full.roots:
		var start: int=int(root.vertex)-7
		var owner: int=int(source[Mesh.ARRAY_CUSTOM1][start*4+3])
		if not result.has(owner):result[owner]={"low":Vector3.ONE*INF,"high":Vector3.ONE*-INF,"puffs":0,"cards":0}
		result[owner].cards+=1
		var key:=_crown_site_key(root)
		if not sites.has(key):result[owner].puffs+=1;sites[key]=true
		for i in 12:
			result[owner].low=(result[owner].low as Vector3).min(source[Mesh.ARRAY_VERTEX][start+i])
			result[owner].high=(result[owner].high as Vector3).max(source[Mesh.ARRAY_VERTEX][start+i])
	return result

static func thin_crown_cards(full: Dictionary,coverage: float,local_coverage: Dictionary={}) -> Dictionary:
	# Drop whole shoot-attached puffs, not arbitrary individual planes. Rank each
	# puff once within its major crown group: lower density is a nested subset.
	coverage=clampf(coverage,0.0,1.0)
	if coverage==1.0 and local_coverage.values().all(func(value):return float(value)>=1.0):return full
	var source: Array=full.mesh.surface_get_arrays(0)
	var groups: Dictionary={};var sites: Dictionary={}
	for root: Dictionary in full.roots:
		var key:=_crown_site_key(root)
		if sites.has(key):continue
		sites[key]=true
		var vertex: int=int(root.vertex)-7
		var owner: int=int(source[Mesh.ARRAY_CUSTOM1][vertex*4+3])
		if not groups.has(owner):groups[owner]=[]
		groups[owner].append({"key":key,"rank":_crown_site_rank(root)})
	var selected: Dictionary={}
	for owner: int in groups:
		var group: Array=groups[owner]
		group.sort_custom(func(a: Dictionary,b: Dictionary):return a.rank<b.rank if a.rank!=b.rank else a.key<b.key)
		var local_factor:=clampf(float(local_coverage.get(owner,1.0)),0.0,1.0)
		for i in roundi(group.size()*coverage*local_factor):selected[group[i].key]=true
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var channels: Array[int]=[Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1]
	for channel in channels:arrays[channel]=source[channel].slice(0,0)
	var indices:=PackedInt32Array();var roots: Array=[]
	for id in full.roots.size():
		var root: Dictionary=full.roots[id]
		if not selected.has(_crown_site_key(root)):continue
		var start: int=int(root.vertex)-7
		var base: int=arrays[Mesh.ARRAY_VERTEX].size()
		for channel in channels:
			var stride:=4 if channel in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1] else 1
			arrays[channel].append_array(source[channel].slice(start*stride,(start+12)*stride))
		for index in source[Mesh.ARRAY_INDEX].slice(id*36,(id+1)*36):indices.append(base+index-start)
		var kept:=root.duplicate();kept.vertex=base+7;kept.original_card=id;roots.append(kept)
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	if not roots.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	var result:=full.duplicate();result.mesh=mesh;result.roots=roots
	result.cards=roots.size();result.triangles=indices.size()/3;result.puffs=selected.size()
	return result

static func rounded_crown_wood(layout: Array, offset: Vector3, density: float) -> ArrayMesh:
	# The existing union owns large forks; continuous tubes keep fine shoots.
	# Extract only supports wide enough for this field, avoiding detached specks
	# when the old 7.5cm sampler encountered sub-voxel tips.
	var coarse := Rounded.new()
	var fine: Array = []
	var threshold := 0.14*density
	for branch: Dictionary in layout:
		var tail: Array = []; var radii: Array = []
		for i in branch.path.size()-1:
			var a: Vector3=branch.path[i]; var b: Vector3=branch.path[i+1]
			var r0: float=branch.radii[i]; var r1: float=branch.radii[i+1]
			if r0>=threshold:
				var t:=clampf((r0-threshold)/maxf(r0-r1,0.00001),0,1) if r1<threshold else 1.0
				var end:=a.lerp(b,t)
				coarse.wood_lines.append({"a":(a+offset)/density,"b":(end+offset)/density,"r0":r0/density,"r1":lerpf(r0,r1,t)/density})
				if t<1.0:
					var overlap:=maxf(0,t-0.035*density/maxf(a.distance_to(b),0.001))
					tail.append(a.lerp(b,overlap));radii.append(lerpf(r0,r1,overlap))
					tail.append(b);radii.append(r1)
			else:
				if tail.is_empty():tail.append(a);radii.append(r0)
				tail.append(b);radii.append(r1)
		if tail.size()>1:fine.append({"path":tail,"radii":radii})
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if not coarse.wood_lines.is_empty():st.append_from(coarse.smooth_wood(0.05,0.035),0,Transform3D.IDENTITY)
	st.append_from(wood_mesh(fine,offset,density),0,Transform3D.IDENTITY)
	return st.commit()

static func build(seed := 7, version := 18, overrides: Dictionary = {}) -> Dictionary:
	var parameters := Provider.defaults()
	parameters.generation_version = version; parameters.tree_type = 1; parameters.height = 96
	parameters.foliage_style = 3; parameters.foliage_amount = 90
	if version in [20,21,22,23,24,25]: parameters.foliage_amount = 0
	parameters.merge(overrides,true)
	parameters=Provider.normalize(parameters)
	var built := Provider.build(parameters, seed, Color.WHITE, {}, "Branching oak LAB", "branching_oak_lab")
	assert(not built.has("error"))
	return from_built(built,parameters,seed)

static func from_built(built: Dictionary,parameters: Dictionary,seed: int) -> Dictionary:
	var version := int(parameters.generation_version)
	var layout := branches(built.structure)
	var offset := Vector3(built.pivot_bias.x, 0, built.pivot_bias.y)
	return {"source": built.geometry, "structure": built.structure, "pivot_bias": built.pivot_bias,
		"layout": layout, "wood": rounded_crown_wood(layout,offset,parameters.density) if version in [19,20,21,22,23,24,25] else wood_mesh(layout, offset, parameters.density),
		"cards": {} if version in [20,21,22,23,24,25] else (crown_cards(layout,built.structure,offset,parameters.density,seed) if version==19 else cards_mesh(layout, offset, parameters.density, seed)), "parameters": parameters}
