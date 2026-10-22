extends SceneTree
## Read-only CPU measurements for the rock form-normal probe. Writes only JSON to
## the output directory given after "--"; no Resource under res:// is saved.
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const SPAN := 2.4

var image: Image

func sample_rgb(uv: Vector2) -> Vector3:
	# Periodic bilinear, texture space in tiles.
	var size := Vector2(image.get_size())
	var p := Vector2(uv.x - floorf(uv.x), uv.y - floorf(uv.y)) * size - Vector2(0.5, 0.5)
	var x0 := int(floorf(p.x)); var y0 := int(floorf(p.y)); var f := p - Vector2(x0, y0)
	var w := image.get_width(); var h := image.get_height()
	var out := Vector3.ZERO
	for corner in [[0, 0, (1 - f.x) * (1 - f.y)], [1, 0, f.x * (1 - f.y)], [0, 1, (1 - f.x) * f.y], [1, 1, f.x * f.y]]:
		var c := image.get_pixel(posmod(x0 + corner[0], w), posmod(y0 + corner[1], h))
		out += Vector3(c.r, c.g, c.b) * corner[2]
	return out * 255.0

func axis_uv(p: Vector3, axis: int) -> Vector2:
	var q := p / SPAN
	return Vector2(q.z, q.y) if axis == 0 else (Vector2(q.x, q.z) if axis == 1 else Vector2(q.x, q.y))

func weights(n: Vector3, sharp: float) -> Vector3:
	var a := n.abs()
	var w := Vector3(pow(a.x, sharp), pow(a.y, sharp), pow(a.z, sharp))
	return w / maxf(w.x + w.y + w.z, 1e-6)

func _initialize() -> void:
	var output := OS.get_cmdline_user_args()[0]
	image = Image.load_from_file(ProjectSettings.globalize_path("res://content/terrain_materials/textures/rock-painted-calm-v2-runtime.png"))
	var scene: Node = load("res://prefabs/voxels/vox_painted_rock_group.tscn").instantiate()
	var shipped := (scene.get_node("Mesh") as MeshInstance3D).mesh as ArrayMesh
	var report := {"legacy": {}, "form": []}
	var base_arrays := shipped.surface_get_arrays(0)
	var verts: PackedVector3Array = base_arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = base_arrays[Mesh.ARRAY_NORMAL]
	# --- legacy: colour mismatch across crease edges (world coordinates, yaw about Y)
	var edges := {}
	for t in range(0, verts.size(), 3):
		for k in 3:
			var a := verts[t + k]; var b := verts[t + (k + 1) % 3]
			var ka := Vector3i((a * 1000.0).round()); var kb := Vector3i((b * 1000.0).round())
			var key := str([ka, kb]) if str(ka) < str(kb) else str([kb, ka])
			if not edges.has(key): edges[key] = {"a": a, "b": b, "n": []}
			edges[key].n.append(norms[t])
	for yaw in [0.0, 22.5]:
		var basis := Basis(Vector3.UP, deg_to_rad(yaw))
		var jump_sum := 0.0; var jump_len := 0.0; var count := 0; var baseline_sum := 0.0
		var jump_gt8 := 0.0
		for key in edges:
			var e = edges[key]
			if e.n.size() != 2 or e.n[0].angle_to(e.n[1]) < deg_to_rad(5.0): continue
			var length: float = e.a.distance_to(e.b)
			var ax0: int = (basis * e.n[0]).abs().max_axis_index(); var ax1: int = (basis * e.n[1]).abs().max_axis_index()
			for s in 8:
				var p: Vector3 = basis * e.a.lerp(e.b, (s + 0.5) / 8.0)
				var c0 := sample_rgb(axis_uv(p, ax0)); var c1 := sample_rgb(axis_uv(p, ax1))
				var d := (c0 - c1).abs().length() / sqrt(3.0)
				jump_sum += d * length / 8.0; jump_len += length / 8.0
				if d > 8.0: jump_gt8 += length / 8.0
				baseline_sum += (sample_rgb(axis_uv(p, ax0)) - sample_rgb(axis_uv(p + Vector3(0.01, 0.01, 0.01), ax0))).abs().length() / sqrt(3.0) * length / 8.0
			count += 1
		report.legacy["yaw_%s" % yaw] = {"crease_edges": count, "mean_rgb8_jump_per_edge_length": snappedf(jump_sum / jump_len, 0.01),
			"neighbouring_1cm_baseline": snappedf(baseline_sum / jump_len, 0.01), "edge_length_with_jump_gt8_pct": snappedf(100.0 * jump_gt8 / jump_len, 0.1)}
	# --- form normal field: blend footprint and projection stretch per smoothing/sharpness
	for smoothing in [0, 1]:
		var mesh := Solid.with_form_normals(shipped, smoothing)
		var arrays := mesh.surface_get_arrays(0)
		var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		var entry := {"smoothing": smoothing}
		for sharp in [8.0, 12.0, 16.0, 24.0]:
			var area := 0.0; var blend_area := 0.0; var stretch_sum := 0.0; var stretch_gt := 0.0
			var gt15 := 0.0; var gt2 := 0.0
			for t in range(0, verts.size(), 3):
				var tri_area := (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).length() * 0.5
				var facet := norms[t]
				for s in 6:
					# fixed interior barycentric samples
					var bc: Vector3 = [Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6), Vector3(0.45, 0.45, 0.1), Vector3(0.1, 0.45, 0.45), Vector3(0.45, 0.1, 0.45)][s]
					var n := Vector3.ZERO
					for k in 3: n += Vector3(custom[(t + k) * 4], custom[(t + k) * 4 + 1], custom[(t + k) * 4 + 2]) * bc[k]
					n = n.normalized()
					var w := weights(n, sharp)
					var sorted := [w.x, w.y, w.z]; sorted.sort()
					if sorted[1] > 0.25: blend_area += tri_area / 6.0
					area += tri_area / 6.0
					# stretch of the dominant projection on the real facet plane
					var st := 1.0 / maxf(absf(facet[w.max_axis_index()]), 0.05)
					stretch_sum += st * tri_area / 6.0
					if st > 1.25: stretch_gt += tri_area / 6.0
					if st > 1.5: gt15 += tri_area / 6.0
					if st > 2.0: gt2 += tri_area / 6.0
					entry["sharp_%d" % int(sharp)] = {"blend_zone_area_pct": snappedf(100.0 * blend_area / area, 0.1), "mean_stretch": snappedf(stretch_sum / area, 0.001), "stretch_gt_1.25_pct": snappedf(100.0 * stretch_gt / area, 0.1), "stretch_gt_1.5_pct": snappedf(100.0 * gt15 / area, 0.1), "stretch_gt_2_pct": snappedf(100.0 * gt2 / area, 0.1)}
		report.form.append(entry)
	var file := FileAccess.open(output.path_join("form-measure.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("ROCK_FORM_MEASURE ", JSON.stringify(report))
	quit()
