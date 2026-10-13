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

static func grass_tuft_mesh() -> ArrayMesh:
	# Two crossed flat clump silhouettes: a few broad blades read as one shape.
	# Cut the outline into opaque geometry instead of adding alpha overdraw.
	# Same palette/UV contract as SmoothSurface; no extra material renderer.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var outline := PackedVector2Array([
		Vector2(-0.09,0), Vector2(-0.125,0.07), Vector2(-0.074,0.047),
		Vector2(-0.083,0.115), Vector2(-0.038,0.060), Vector2(-0.025,0.14),
		Vector2(0.005,0.070), Vector2(0.035,0.124), Vector2(0.037,0.047),
		Vector2(0.105,0.106), Vector2(0.077,0.031), Vector2(0.128,0.042),
		Vector2(0.10,0)])
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
