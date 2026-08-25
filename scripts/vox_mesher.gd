class_name VoxMesher
extends RefCounted
## MagicaVoxel Z-up → Ember/Godot Y-up: ember(x, y, z) = vox(x, z, y).
## Same mapping as joi-conductor `emberVoxCodec.ts`.

const VOXELS_PER_BLOCK := 16


static func ember_size(vox_size: Vector3i) -> Vector3i:
	return Vector3i(vox_size.x, vox_size.z, vox_size.y)


static func vox_to_ember(vx: int, vy: int, vz: int) -> Vector3i:
	return Vector3i(vx, vz, vy)


static func build_mesh(doc: Dictionary, voxel_size := 1.0) -> ArrayMesh:
	if doc.is_empty() or (doc.get("models", []) as Array).is_empty():
		return ArrayMesh.new()
	var model: Dictionary = doc.models[0]
	var vox_size: Vector3i = model.size
	var sx: int = vox_size.x
	var sy: int = vox_size.z
	var sz: int = vox_size.y
	var filled := PackedByteArray()
	filled.resize(sx * sy * sz)
	filled.fill(0)
	var index_at := PackedInt32Array()
	index_at.resize(sx * sy * sz)
	index_at.fill(0)
	for v in model.voxels:
		if int(v.i) <= 0:
			continue
		var e := vox_to_ember(int(v.x), int(v.y), int(v.z))
		if e.x < 0 or e.y < 0 or e.z < 0 or e.x >= sx or e.y >= sy or e.z >= sz:
			continue
		var i := _idx(e.x, e.y, e.z, sx, sz)
		filled[i] = 1
		index_at[i] = int(v.i)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var palette: PackedByteArray = doc.palette
	var faces := [
		{"n": Vector3.RIGHT, "d": Vector3i(1, 0, 0)},
		{"n": Vector3.LEFT, "d": Vector3i(-1, 0, 0)},
		{"n": Vector3.UP, "d": Vector3i(0, 1, 0)},
		{"n": Vector3.DOWN, "d": Vector3i(0, -1, 0)},
		{"n": Vector3.BACK, "d": Vector3i(0, 0, 1)},
		{"n": Vector3.FORWARD, "d": Vector3i(0, 0, -1)},
	]
	for y in sy:
		for z in sz:
			for x in sx:
				var i := _idx(x, y, z, sx, sz)
				if filled[i] == 0:
					continue
				var color := _palette_color(palette, index_at[i])
				for face in faces:
					var d: Vector3i = face.d
					var nx := x + d.x
					var ny := y + d.y
					var nz := z + d.z
					var exposed := (
						nx < 0 or ny < 0 or nz < 0 or nx >= sx or ny >= sy or nz >= sz
						or filled[_idx(nx, ny, nz, sx, sz)] == 0
					)
					if exposed:
						_emit_face(st, Vector3(x, y, z), face.n, color, voxel_size)
	st.generate_normals()
	st.index()
	return st.commit()


static func _idx(x: int, y: int, z: int, sx: int, sz: int) -> int:
	return x + z * sx + y * sx * sz


static func _palette_color(palette: PackedByteArray, pi: int) -> Color:
	var o := clampi(pi, 0, 255) * 4
	if o + 3 >= palette.size():
		return Color(0.6, 0.6, 0.6)
	return Color(
		palette[o] / 255.0,
		palette[o + 1] / 255.0,
		palette[o + 2] / 255.0,
		palette[o + 3] / 255.0,
	)


static func _emit_face(
	st: SurfaceTool,
	cell: Vector3,
	normal: Vector3,
	color: Color,
	s: float,
) -> void:
	st.set_color(color)
	st.set_normal(normal)
	var o := cell * s
	var quad: PackedVector3Array = _face_quad(o, normal, s)
	st.add_vertex(quad[0])
	st.add_vertex(quad[1])
	st.add_vertex(quad[2])
	st.add_vertex(quad[0])
	st.add_vertex(quad[2])
	st.add_vertex(quad[3])


static func _face_quad(o: Vector3, n: Vector3, s: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if n == Vector3.RIGHT:
		out.append(o + Vector3(s, 0, s))
		out.append(o + Vector3(s, s, s))
		out.append(o + Vector3(s, s, 0))
		out.append(o + Vector3(s, 0, 0))
	elif n == Vector3.LEFT:
		out.append(o + Vector3(0, 0, 0))
		out.append(o + Vector3(0, s, 0))
		out.append(o + Vector3(0, s, s))
		out.append(o + Vector3(0, 0, s))
	elif n == Vector3.UP:
		out.append(o + Vector3(0, s, s))
		out.append(o + Vector3(0, s, 0))
		out.append(o + Vector3(s, s, 0))
		out.append(o + Vector3(s, s, s))
	elif n == Vector3.DOWN:
		out.append(o + Vector3(0, 0, 0))
		out.append(o + Vector3(s, 0, 0))
		out.append(o + Vector3(s, 0, s))
		out.append(o + Vector3(0, 0, s))
	elif n == Vector3.BACK:
		out.append(o + Vector3(0, 0, s))
		out.append(o + Vector3(0, s, s))
		out.append(o + Vector3(s, s, s))
		out.append(o + Vector3(s, 0, s))
	else:
		out.append(o + Vector3(s, 0, 0))
		out.append(o + Vector3(s, s, 0))
		out.append(o + Vector3(0, s, 0))
		out.append(o + Vector3(0, 0, 0))
	return out
