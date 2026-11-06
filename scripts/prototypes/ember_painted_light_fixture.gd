extends RefCounted
## Disposable composition from the existing fine16 Source, never an art importer.
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")

static func rock_height(p: Vector2, center: Vector2, radius: Vector2, height: float, angle := -0.23) -> float:
	var q := (p - center).rotated(angle) / radius
	# Broad crown and bevel, steep broken sides. All cuts are Source heights:
	# no displaced render-only silhouette or separate collision approximation.
	var crown := height + 0.08 * q.x - 0.12 * q.y
	# Keep a broad upper plane; bevel only the outside of it, rather than
	# intersecting sloping roofs through the entire centre into a pointed hill.
	crown = minf(crown, height + 1.1 - 1.8 * (q.x + 0.25 * q.y))
	crown = minf(crown, height + 1.0 + 1.6 * q.y)
	crown = minf(crown, height + 0.85 - 1.4 * q.y)
	var side := minf((1.0 - q.x) * 6.5, (0.92 + q.x) * 5.0)
	side = minf(side, (0.92 - q.y) * 4.2)
	side = minf(side, (0.84 + q.y) * 7.0)
	side = minf(side, (1.24 - q.x - q.y) * 4.8)
	side = minf(side, (1.10 + q.x - q.y) * 4.0)
	return maxf(0.0, minf(crown, side))

static func source(width := 96, depth := 96) -> EmberTerrainPilotResource:
	var result := Terrain.new()
	result.width = width; result.depth = depth; result.height_limit = 96
	result.palette = PackedColorArray([Color.TRANSPARENT, Color("979184"), Color("d7c08c"), Color("637841")])
	result.palette_surface_roles = PackedStringArray(["", "stone", "sand", "grass"])
	result.palette_material_ids = PackedStringArray(["", "cartoon_stone", "cartoon_sand", "cartoon_grass"])
	for channel: String in Terrain.Sections.CHANNELS:
		var data = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		data.resize(width * depth); result.set(channel, data)
	for z in depth:
		for x in width:
			var p := Vector2((x + 0.5) / 16.0, (z + 0.5) / 16.0)
			var base := 0.30 + 0.12 * sin(p.y * 0.7) + 0.22 * (1.0 - smoothstep(0.0, 2.4, p.x))
			var rock := rock_height(p, Vector2(1.52, 1.60), Vector2(1.05, 0.92), 2.0, -0.12)
			var front := rock_height(p, Vector2(1.96, 2.80), Vector2(1.03, 0.82), 1.67, 0.16)
			# A visible fracture, wider than the shared smoothing radius; not a
			# micro-detail that would disappear in the physical surface filter.
			var cut := absf(p.x - (1.82 + 0.30 * (p.y - 2.4)))
			front = maxf(0.0, front - 0.10 * (1.0 - smoothstep(0.06, 0.20, cut)))
			rock = maxf(rock, front)
			rock = maxf(rock, rock_height(p, Vector2(0.76, 2.65), Vector2(0.40, 0.55), 0.92, -0.38))
			rock = maxf(rock, rock_height(p, Vector2(2.98, 2.28), Vector2(0.31, 0.59), 1.03, -0.27))
			rock = maxf(rock, rock_height(p, Vector2(0.73, 3.65), Vector2(0.32, 0.30), 0.50))
			rock = maxf(rock, rock_height(p, Vector2(4.65, 1.40), Vector2(0.40, 0.35), 0.56))
			var path := absf(p.x - (3.75 + 0.35 * sin(p.y * 0.9))) < 0.55
			var skirt := rock_height(p, Vector2(2.15, 2.25), Vector2(1.25, 1.08), 1.0) > 0.0
			skirt = skirt or rock_height(p, Vector2(2.85, 2.75), Vector2(0.9, 0.86), 1.0) > 0.0
			var slot := 1 if rock > 0.05 else (2 if path or skirt else 3)
			var i := result.column_index(x, z)
			result.heights[i] = roundi((base + rock) * 16.0)
			result.top_materials[i] = slot; result.base_materials[i] = slot; result.cap_depths[i] = 2
	return result

static func chiselled_rock_source(source) -> Dictionary:
	# Opt-in ordinary-rock LAB. Keep the existing Source and paint ownership;
	# subtract planes/chips from the two large masses, not a visual-only mesh.
	var result=source.working_copy()
	var changed:=0;var max_cut:=0;var peak_before:=0;var peak_after:=0
	for z in source.depth:
		for x in source.width:
			var i: int=source.column_index(x,z)
			if int(source.column_value("top_materials",i))!=1:continue
			var p:=Vector2(x+0.5,z+0.5)/16.0
			var original:=0.0;var carved:=0.0
			for spec in [
				[Vector2(1.52,1.60),Vector2(1.05,0.92),2.0,-0.12],
				[Vector2(1.96,2.80),Vector2(1.03,0.82),1.67,0.16],
				[Vector2(0.76,2.65),Vector2(0.40,0.55),0.92,-0.38],
				[Vector2(2.98,2.28),Vector2(0.31,0.59),1.03,-0.27],
				[Vector2(0.73,3.65),Vector2(0.32,0.30),0.50,-0.23],
				[Vector2(4.65,1.40),Vector2(0.40,0.35),0.56,-0.23]]:
				var h:=rock_height(p,spec[0],spec[1],spec[2],spec[3])
				var front: bool=spec[2]==1.67
				if front:
					var old_cut:=absf(p.x-(1.82+0.30*(p.y-2.4)))
					h=maxf(0.0,h-0.10*(1.0-smoothstep(0.06,0.20,old_cut)))
				original=maxf(original,h)
				var cut:=h
				if spec[2]>=1.67 and h>0.0:
					var q: Vector2=(p-spec[0]).rotated(spec[3])/spec[1]
					var height: float=spec[2]
					# Wide upper bevels leave the crown centre and peak intact.
					cut=minf(cut,height+0.38-0.72*q.x-0.46*q.y)
					cut=minf(cut,height+0.48+0.62*q.x-0.62*q.y)
					# A second diagonal side face, below the broad crown.
					cut=minf(cut,(1.12-0.88*q.x-0.70*q.y)*4.0)
					# One open, piecewise-linear fracture. No noise/displacement map.
					var line:=absf(q.x+(0.22 if front else -0.34)*q.y+(0.10 if front else -0.25))
					var length_mask:=clampf((q.y+0.12)/0.22,0.0,1.0)
					var groove:=maxf(0.0,1.0-line/0.17)*length_mask
					cut-=groove*(0.20+0.28*clampf((q.y-0.35)/0.40,0.0,1.0))
					# A broad triangular chip at the top/front shoulder.
					var chip:=maxf(0.0,1.0-absf(q.x+0.48)/0.30-absf(q.y-0.42)/0.34)
					cut-=chip*0.27
					cut=maxf(h-0.375,maxf(0.0,cut))
				carved=maxf(carved,cut)
			var old: int=source.column_value("heights",i)
			# Preserve the source footprint and quantization. Paint stays exact.
			var removal:=clampi(roundi((original-carved)*16.0),0,6)
			result.heights[i]=old-removal
			if removal>0:changed+=1
			max_cut=maxi(max_cut,removal);peak_before=maxi(peak_before,old);peak_after=maxi(peak_after,result.heights[i])
	return {"source":result,"changed_columns":changed,"max_cut_m":max_cut/16.0,"peak_before_m":peak_before/16.0,"peak_after_m":peak_after/16.0}

static func grass_artwork() -> Image:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var p := Vector2(x / 256.0, y / 256.0)
			var cloud := 0.5 + 0.20 * sin(TAU * p.x) * cos(TAU * p.y) + 0.1 * sin(TAU * (p.y * 2.0 + p.x))
			# Pigment stays quiet. The opt-in light response supplies the strokes.
			var tone := Color("6d8345").lerp(Color("788b4b"), cloud)
			image.set_pixel(x, y, tone)
	image.generate_mipmaps()
	return image

static func grass_tuft_outline() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.09,0), Vector2(-0.125,0.07), Vector2(-0.074,0.047),
		Vector2(-0.083,0.115), Vector2(-0.038,0.060), Vector2(-0.025,0.14),
		Vector2(0.005,0.070), Vector2(0.035,0.124), Vector2(0.037,0.047),
		Vector2(0.105,0.106), Vector2(0.077,0.031), Vector2(0.128,0.042),
		Vector2(0.10,0)])

static func grass_tuft_mesh() -> ArrayMesh:
	# Two crossed flat clump silhouettes: a few broad blades read as one shape.
	# Cut the outline into opaque geometry instead of adding alpha overdraw.
	# Same palette/UV contract as SmoothSurface; no extra material renderer.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var outline := grass_tuft_outline()
	var triangles := Geometry2D.triangulate_polygon(outline)
	for card in 2:
		var angle := float(card) * 1.45
		var across := Vector3(cos(angle),0,sin(angle))
		var height_scale := 1.0 if card == 0 else 0.82
		for tri in range(0,triangles.size(),3):
			# Both faces share up normals and the same ground pigment/light.
			for corner in [0,1,2, 2,1,0]:
				var point := outline[triangles[tri+corner]]
				vertices.append(across*point.x + Vector3.UP*point.y*height_scale)
				# A soft outward normal gives the clump volume without making
				# every little triangle a contrasting low-poly facet.
				normals.append((Vector3.UP + across*signf(point.x)*0.28).normalized())
				colors.append(Color(1,0,0,3.0/255.0))
				uv.append(Vector2(3,3)/255.0); uv2.append(Vector2(3.0/255.0,0))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static var _blade_tufts: Dictionary = {}
static var _grass_cards: ArrayMesh

static func grass_card_mesh() -> ArrayMesh:
	# Accepted card study: offset roots and directions, not a shared crossed centre.
	if _grass_cards != null: return _grass_cards
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(Color(1,0,0,0)); surface.set_uv2(Vector2.ZERO)
	for spec in [[-0.055,-0.035,0.23,0], [0.04,0.03,1.11,1], [-0.03,0.065,2.37,2], [0.065,-0.05,2.92,3]]:
		var across := Vector3(cos(spec[2]),0,sin(spec[2]))
		var base := Vector3(spec[0],0,spec[1])
		var points := [base-across*0.085,base+across*0.085,base+across*0.085+Vector3.UP*0.17,base-across*0.085+Vector3.UP*0.17]
		var cell: int = spec[3]
		var origin := Vector2(cell%2,cell/2)*0.5
		var uv := [origin+Vector2(0,0.5),origin+Vector2(0.5,0.5),origin+Vector2(0.5,0),origin]
		for index in [0,2,1,0,3,2]:
			surface.set_normal((Vector3.UP+across*0.15).normalized())
			surface.set_uv(uv[index]); surface.add_vertex(points[index])
	surface.index(); _grass_cards = surface.commit()
	return _grass_cards

static func grass_card_contour_mesh(atlas: Image) -> ArrayMesh:
	# Bake-only: retain the accepted card planes, artwork UVs and normals.
	# Two triangles per card, with supporting edges around the padded artwork.
	var original := grass_card_mesh().surface_get_arrays(0)
	var indices: PackedInt32Array = original[Mesh.ARRAY_INDEX]
	var output := SurfaceTool.new(); output.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell_size := Vector2i(atlas.get_width()/2,atlas.get_height()/2)
	var covered_area := 0.0
	for card in 4:
		var a: int=indices[card*6]; var b: int=indices[card*6+2]; var c: int=indices[card*6+1]
		var pa: Vector3=original[Mesh.ARRAY_VERTEX][a]
		var pb: Vector3=original[Mesh.ARRAY_VERTEX][b]
		var pc: Vector3=original[Mesh.ARRAY_VERTEX][c]
		var ua: Vector2=original[Mesh.ARRAY_TEX_UV][a]
		var ub: Vector2=original[Mesh.ARRAY_TEX_UV][b]
		var uc: Vector2=original[Mesh.ARRAY_TEX_UV][c]
		var origin := Vector2i(card%2,card/2)*cell_size
		var points := PackedVector2Array()
		for band in 8:
			var y0 := band*cell_size.y/8; var y1 := (band+1)*cell_size.y/8
			var left := cell_size.x; var right := -1
			for y in range(maxi(0,y0-8),mini(cell_size.y,y1+8)):
				for x in cell_size.x:
					if atlas.get_pixel(origin.x+x,origin.y+y).a>0.05:
						left=mini(left,x);right=maxi(right,x)
			if right<0: continue
			left=maxi(0,left-8);right=mini(cell_size.x,right+9)
			points.append_array(PackedVector2Array([Vector2(left,y1),Vector2(right,y1),Vector2(right,y0),Vector2(left,y0)]))
		var hull := Geometry2D.convex_hull(points)
		if hull.size()>1 and hull[0]==hull[-1]: hull.resize(hull.size()-1)
		# Enclose the padded silhouette in one trapezoid, not a many-sided hull.
		# Supporting lines never cut into the artwork; UVs stay in this atlas cell.
		var top := INF; var bottom := -INF
		for point in hull:top=minf(top,point.y);bottom=maxf(bottom,point.y)
		var height := bottom-top
		var left_mean := -INF;var right_mean := INF
		var left_top:=0.0;var left_bottom:=0.0
		var right_top:=float(cell_size.x);var right_bottom:=float(cell_size.x)
		for step in range(-8,9):
			var slope:=step/8.0
			var left:=INF;var right:=-INF
			for point in hull:
				left=minf(left,point.x-slope*(point.y-top))
				right=maxf(right,point.x-slope*(point.y-top))
			var lb:=left+slope*height;var rb:=right+slope*height
			if minf(left,lb)>=0.0 and (left+lb)*0.5>left_mean:
				left_mean=(left+lb)*0.5;left_top=left;left_bottom=lb
			if maxf(right,rb)<=cell_size.x and (right+rb)*0.5<right_mean:
				right_mean=(right+rb)*0.5;right_top=right;right_bottom=rb
		assert(left_mean!=-INF and right_mean!=INF)
		hull=PackedVector2Array([Vector2(left_top,top),Vector2(right_top,top),Vector2(right_bottom,bottom),Vector2(left_bottom,bottom)])
		var triangles := Geometry2D.triangulate_polygon(hull)
		assert(not triangles.is_empty())
		for triangle in range(0,triangles.size(),3):
			covered_area+=absf((hull[triangles[triangle+1]]-hull[triangles[triangle]]).cross(hull[triangles[triangle+2]]-hull[triangles[triangle]]))*0.5/float(cell_size.x*cell_size.y)
		for index in triangles:
			var uv: Vector2 = (Vector2(origin)+hull[index])/Vector2(atlas.get_size())
			var point: Vector3 = pa+(pb-pa)*((uv.x-ua.x)/(ub.x-ua.x))+(pc-pb)*((uv.y-ub.y)/(uc.y-ub.y))
			output.set_normal(original[Mesh.ARRAY_NORMAL][a]);output.set_color(original[Mesh.ARRAY_COLOR][a])
			output.set_uv2(original[Mesh.ARRAY_TEX_UV2][a]);output.set_uv(uv);output.add_vertex(point)
	output.index()
	var mesh := output.commit()
	mesh.set_meta("card_area_fraction",covered_area/4.0)
	return mesh

static func grass_blade_mesh(low_poly := false) -> ArrayMesh:
	# Shared derived tuft, built once per look. Artwork/palette and scatter stay with their owners.
	if _blade_tufts.has(low_poly): return _blade_tufts[low_poly]
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(Color(1,0,0,3.0/255.0))
	surface.set_uv(Vector2(3,3)/255.0); surface.set_uv2(Vector2(3.0/255.0,0))
	# Irregular roots, broad tapered blades and open gaps, rather than two whole-clump cards.
	for spec in [
		[0.15,0.014,0.142,0.024,0.046], [2.47,0.022,0.112,0.027,0.053],
		[4.91,0.011,0.158,0.021,0.036], [1.60,0.027,0.094,0.025,0.059],
		[3.55,0.018,0.133,0.026,0.044], [5.84,0.032,0.105,0.023,0.063],
		[2.95,0.006,0.164,0.020,0.028], [0.82,0.035,0.086,0.029,0.054]
	]:
		var angle: float = spec[0]
		var lean := Vector3(cos(angle),0,sin(angle)); var across := Vector3(-lean.z,0,lean.x)
		var root := lean*float(spec[1]); var height: float = spec[2]
		var width: float = spec[3]; var reach: float = spec[4]
		var normal := (Vector3.UP+lean*0.28).normalized()
		for band in 3:
			var t0 := band/3.0; var t1 := (band+1)/3.0
			var bend0 := maxf(0.0,(t0-0.25)/0.75) if low_poly else t0*t0
			var bend1 := maxf(0.0,(t1-0.25)/0.75) if low_poly else t1*t1
			var base := root+Vector3.UP*(height*t0)+lean*(reach*bend0)
			var top := root+Vector3.UP*(height*t1)+lean*(reach*bend1)
			var half0 := width*0.5*(1.0-t0); var half1 := width*0.5*(1.0-t1)
			var corners := PackedVector3Array([base-across*half0,base+across*half0,top+across*half1,top-across*half1])
			# An actual tip; avoid zero-area faces at the end of every blade.
			var indices := [0,2,1,1,2,0] if band==2 else [0,2,1,0,3,2,1,2,0,2,3,0]
			for index in indices:
				surface.set_normal(normal); surface.add_vertex(corners[index])
	# Share exact position/normal/colour/UV tuples before the first GPU pack.
	# Triangle order and both authored windings stay intact.
	surface.index()
	var mesh := surface.commit()
	_blade_tufts[low_poly] = mesh
	return mesh
