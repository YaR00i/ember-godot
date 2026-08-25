class_name VoxParser
extends RefCounted
## MagicaVoxel .vox (VOX / MAIN / SIZE / XYZI / RGBA). Same layout as
## joi-conductor `src/game/voxel/vox/voxFile.ts`.

var _models: Array = []
var _palette: PackedByteArray = PackedByteArray()
var _pending_size := Vector3i.ZERO
var _has_size := false


static func parse_file(path: String) -> Dictionary:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		push_error("vox: cannot open %s" % path)
		return {}
	var parser := VoxParser.new()
	return parser.parse_bytes(fa.get_buffer(fa.get_length()))


func parse_bytes(bytes: PackedByteArray) -> Dictionary:
	_models = []
	_palette = _default_palette()
	_has_size = false
	if bytes.size() < 20:
		push_error("vox: too small")
		return {}
	if _ascii(bytes, 0, 4) != "VOX ":
		push_error("vox: missing VOX header")
		return {}
	var version := _i32(bytes, 4)
	if _ascii(bytes, 8, 4) != "MAIN":
		push_error("vox: missing MAIN")
		return {}
	var main_content := _i32(bytes, 12)
	var main_children := _i32(bytes, 16)
	_walk(bytes, 20 + main_content, 20 + main_content + main_children)
	if _models.is_empty():
		push_error("vox: no SIZE/XYZI model")
		return {}
	return {"version": version, "models": _models, "palette": _palette}


func _walk(bytes: PackedByteArray, start: int, end: int) -> void:
	var offset := start
	while offset + 12 <= end:
		var id := _ascii(bytes, offset, 4)
		var content := _i32(bytes, offset + 4)
		var children := _i32(bytes, offset + 8)
		var content_start := offset + 12
		var content_end := content_start + content
		var children_end := content_end + children
		if content_end > end or children_end > end:
			break
		if id == "SIZE" and content >= 12:
			_pending_size = Vector3i(
				_i32(bytes, content_start),
				_i32(bytes, content_start + 4),
				_i32(bytes, content_start + 8),
			)
			_has_size = true
		elif id == "XYZI" and content >= 4 and _has_size:
			var n := _i32(bytes, content_start)
			var voxels: Array = []
			var p := content_start + 4
			for i in n:
				if p + 4 > content_end:
					break
				voxels.append({
					"x": bytes[p],
					"y": bytes[p + 1],
					"z": bytes[p + 2],
					"i": bytes[p + 3],
				})
				p += 4
			_models.append({"size": _pending_size, "voxels": voxels})
			_has_size = false
		elif id == "RGBA" and content >= 256 * 4:
			_palette[0] = 0
			_palette[1] = 0
			_palette[2] = 0
			_palette[3] = 0
			for i in 255:
				var src := content_start + i * 4
				var dst := (i + 1) * 4
				_palette[dst] = bytes[src]
				_palette[dst + 1] = bytes[src + 1]
				_palette[dst + 2] = bytes[src + 2]
				_palette[dst + 3] = bytes[src + 3]
		if children > 0:
			_walk(bytes, content_end, children_end)
		offset = children_end


static func _ascii(bytes: PackedByteArray, offset: int, length: int) -> String:
	var s := ""
	for i in length:
		s += char(bytes[offset + i])
	return s


static func _i32(bytes: PackedByteArray, offset: int) -> int:
	return bytes.decode_s32(offset)


static func _default_palette() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(256 * 4)
	out.fill(255)
	out[3] = 0
	return out
