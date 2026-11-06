@tool
extends RefCounted
## Disposable geometry. Authored Resources remain authoritative. Runtime meshes
## and editor CPU surfaces use distinct content keys in the same bounded store.
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Storage = preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const Mesher = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Surface = preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const ROOT := "user://ember-terrain-geometry-cache"
const VERSION := 2 # Bump for mesher, topology or LOD algorithm changes.
const TILE_SIZE := 64
const BUDGET_BYTES := 512 * 1024 * 1024
const PREPARE_TILES := 32
const PREPARE_BYTES := 64 * 1024 * 1024 # Soft batch limit; one validated record is at most 16 MiB.
var directory := ROOT
var _fingerprints := {}
var _revision := -1
var disk := Storage.new()
static var _editor_trim_mutex := Mutex.new()
static var _editor_trim_at: Dictionary = {}

## The editor caches CPU inputs before mesh packing. Re-uploading decoded GPU
## normals changes their quantization, and runtime entries lack brush layouts.
class EditorFingerprintMemo extends RefCounted:
	# The projection replaces this memo with its immutable terrain snapshot.
	# Workers keep separate disk state but can reuse neighbouring tile keys.
	var _mutex := Mutex.new()
	var _values := {}
	func read(key: Vector2i) -> String:
		_mutex.lock()
		var value: String = _values.get(key, "")
		_mutex.unlock()
		return value
	func remember(key: Vector2i, value: String) -> void:
		_mutex.lock()
		_values[key] = value
		_mutex.unlock()


func editor_job(snapshot: Terrain, tile: Vector2i, blend: bool, water_options:Dictionary={}, memo: EditorFingerprintMemo = null) -> EditorSurfaceJob:
	return EditorSurfaceJob.new(self,snapshot,tile,blend,water_options,memo)

class EditorSurfaceJob extends RefCounted:
	var result: Dictionary = {}
	var tile_data:Dictionary={}
	var _water_options:Dictionary
	var cache_hit := false
	var elapsed_us := 0
	var invalid := 0
	var _cache: RefCounted
	var _source: Terrain
	var _tile: Vector2i
	var _blend: bool
	var _memo: EditorFingerprintMemo
	func _init(cache:RefCounted,snapshot:Terrain,tile:Vector2i,blend:bool,water_options:Dictionary,memo: EditorFingerprintMemo)->void:
		_cache=cache;_source=snapshot;_tile=tile;_blend=blend;_water_options=water_options;_memo=memo
	func run(cancelled:Callable)->void:
		var started:=Time.get_ticks_usec()
		if cancelled.call():return
		var input:=Mesher.editor_surface_input(_source,_tile.x*64,_tile.y*64,64)
		var stride:int=int(_water_options.get("far_stride",1))
		var policy:Array=["editor-top-native-lod-v1",_blend]
		var key: String = "" if _cache.directory.is_empty() else _cache.tile_key(_source,_tile,0,policy,PackedVector4Array(),{},_memo)
		if cancelled.call():return
		result=_cache.read_editor_surface(key,input.bounds)
		cache_hit=not result.is_empty()
		if not cache_hit:
			result=Surface.build_arrays(input.source,input.bounds,_blend,true,{},true,cancelled,stride)
			if result.is_empty() or cancelled.call():result={};return
			_cache.write_editor_surface(key,input.bounds,result,cancelled)
		if cancelled.call():result={};return
		if not _water_options.is_empty():
			tile_data=Mesher.prepare_editor_tile(input,result,_water_options,_source.is_sectioned(),cancelled)
			if cancelled.call():result={};tile_data={};return
		invalid=_cache.disk.invalid
		elapsed_us=Time.get_ticks_usec()-started
		_source=null

func read_editor_surface(key:String,bounds:Rect2i)->Dictionary:
	if key.is_empty():return {}
	disk.directory=directory
	var data:=disk.read(key)
	if data.is_empty():return {}
	if not _valid_editor_surface(data,bounds):disk.invalid+=1;return {}
	var layout:Dictionary=data.layout.duplicate()
	layout.arrays=data.arrays
	return {"arrays":data.arrays,"collision_faces":data.get("collision_faces",data.arrays[Mesh.ARRAY_VERTEX]),"smooth_field":data.field,"layout":layout,"separate_collision":data.editor_version==2,"render_detail":data.get("render_detail",{})}

static func _valid_editor_surface(data:Dictionary,bounds:Rect2i)->bool:
	if data.get("editor_version") not in [1,2,3] or data.get("bounds")!=bounds:return false
	var arrays:Variant=data.get("arrays")
	if not arrays is Array or arrays.size()!=Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:return false
	var count:int=arrays[Mesh.ARRAY_VERTEX].size()
	if count>65536 or count%3!=0:return false
	if data.editor_version==2:
		var faces:Variant=data.get("collision_faces")
		if not faces is PackedVector3Array or faces.size()>65536 or faces.size()%3!=0:return false
		for point in faces:
			if not point.is_finite():return false
	if not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array or not arrays[Mesh.ARRAY_COLOR] is PackedColorArray or not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array or not arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array:return false
	for channel in range(Mesh.ARRAY_MAX):
		if channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
			if arrays[channel].size()!=count:return false
		else:
			if arrays[channel]!=null:return false
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		for value in arrays[channel]:
			if not value.is_finite():return false
	for color:Color in arrays[Mesh.ARRAY_COLOR]:
		if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a):return false
	if data.editor_version==3 and not _valid_render_detail(data.get("render_detail"),count):return false
	var field:Variant=data.get("field")
	var border:=Vector2i.ONE*Surface.FIELD_BORDER
	if not field is Dictionary or field.get("start")!=bounds.position-border or field.get("size")!=bounds.size+border*2+Vector2i.ONE:return false
	if not field.get("heights") is PackedFloat32Array or field.heights.size()!=field.size.x*field.size.y:return false
	for height in field.heights:
		if not is_finite(height):return false
	var layout:Variant=data.get("layout")
	if not layout is Dictionary or not layout.get("key") is PackedByteArray or layout.key.size()!=32 or not layout.get("kinds") is PackedByteArray or layout.kinds.size()!=count:return false
	for kind in layout.kinds:
		if kind>2:return false
	return true

func write_editor_surface(key:String,bounds:Rect2i,data:Dictionary,cancelled:Callable)->void:
	if key.is_empty():return
	disk.directory=directory
	var layout:Dictionary=data.layout.duplicate();layout.erase("arrays")
	var record:Dictionary={"editor_version":3,"bounds":bounds,"arrays":data.arrays,"field":data.smooth_field,"layout":layout,"render_detail":data.get("render_detail",{"indices":PackedInt32Array(),"lods":{}})}
	if data.get("separate_collision",false):
		record.editor_version=2;record.collision_faces=data.collision_faces
	disk.write(key,record,cancelled)
	# Rate-limit shared-directory maintenance across the private workers.
	var now:=Time.get_ticks_msec()
	_editor_trim_mutex.lock()
	var due:bool=now-int(_editor_trim_at.get(directory,-10000))>=10000
	if due:
		if _editor_trim_at.size()>32:_editor_trim_at.clear()
		_editor_trim_at[directory]=now
	_editor_trim_mutex.unlock()
	if due and not cancelled.call():disk.trim(BUDGET_BYTES)

func _init() -> void:
	disk.max_bytes = 16 * 1024 * 1024
	disk.packaged_directory = Storage.PACKAGED_ROOT.path_join("geometry")
	disk.packaged_for_directory = ROOT

func tile_key(source: Terrain, tile: Vector2i, revision: int, policy: Array, swash: PackedVector4Array, sheet: Dictionary, memo: EditorFingerprintMemo = null) -> String:
	if _revision != revision:
		_fingerprints.clear()
		_revision = revision
	var dependencies := []
	# A conservative 3x3 tile halo contains all eight-column neighbour/group
	# tests and shared water-depth samples, without invalidating the whole map.
	for z in range(tile.y - 1, tile.y + 2):
		for x in range(tile.x - 1, tile.x + 2):
			var key := Vector2i(x, z)
			if not _fingerprints.has(key):
				var fingerprint := memo.read(key) if memo != null else ""
				if fingerprint.is_empty():
					fingerprint = _tile_fingerprint(source, key)
					if memo != null:
						memo.remember(key, fingerprint)
				_fingerprints[key] = fingerprint
			dependencies.append([key, _fingerprints[key]])
	var inputs := [VERSION, Engine.get_version_info().hex, source.is_sectioned(), tile,
		source.origin_y, source.palette, policy, dependencies, swash, sheet]
	# Only the formerly nonadaptive smooth consumer changed. Preserve the
	# accepted blended cache identity, including its exact native LOD indices.
	var nonblend_editor:bool=policy.size()>=2 and policy[0] is String and policy[0]=="editor-top-native-lod-v1" and policy[1]==false
	var nonblend_runtime:bool=policy.size()>=6 and policy[5] is int and policy[5]==1 and not policy.has("material-blend-v1")
	if nonblend_editor or nonblend_runtime:inputs.append("uniform-palette-lod-v1")
	# Only tiles containing run-up change topology. Preserve all other warm
	# geometry/LOD entries instead of invalidating the entire landscape.
	if not swash.is_empty(): inputs.append("shore-grid-1")
	return Storage.digest(inputs)


func _tile_fingerprint(source: Terrain, key: Vector2i) -> String:
	var bounds := Rect2i(key * TILE_SIZE, Vector2i(TILE_SIZE, TILE_SIZE)).intersection(Rect2i(0, 0, source.width, source.depth))
	if not bounds.has_area():
		return "outside"
	var part := source.dense_window(bounds)
	var values: Array = [bounds.size, part.heights, part.top_materials, part.base_materials,
		part.cap_depths, part.water_levels, part.water_materials, part.column_material_overrides]
	if not part.surface_rules.is_empty():
		values.append(part.surface_rules)
	if not part.column_material_overrides.is_empty():
		values.append("side-paint-2")
	return Storage.digest(values)

static func lod_key(geometry_key: String, kind: String) -> String:
	return Storage.digest([VERSION, geometry_key, kind, "lod"])

static func mesh_arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0) if mesh.get_surface_count() > 0 else []

static func _valid_indices(indices: Variant, count: int) -> bool:
	if not indices is PackedInt32Array or indices.size() % 3 != 0: return false
	for index in indices:
		if index < 0 or index >= count: return false
	return true

static func _valid_render_detail(detail:Variant,count:int)->bool:
	if not detail is Dictionary:return false
	if detail.is_empty():return true
	if not _valid_indices(detail.get("indices"),count) or not detail.get("lods") is Dictionary:return false
	for error in detail.lods:
		if not (error is float or error is int) or not is_finite(error) or error<=0 or not _valid_indices(detail.lods[error],count):return false
	return true

static func _valid_arrays(arrays: Variant) -> bool:
	if not arrays is Array: return false
	if arrays.is_empty(): return true
	if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return false
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	if count == 0: return false
	if not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array or not arrays[Mesh.ARRAY_COLOR] is PackedColorArray or not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array: return false
	for channel in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
		if arrays[channel].size() != count: return false
	var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
	if uv2 != null and (not uv2 is PackedVector2Array or (not uv2.is_empty() and uv2.size() != count)): return false
	for point in arrays[Mesh.ARRAY_VERTEX]:
		if not point.is_finite(): return false
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	return count % 3 == 0 if indices == null or (indices is PackedInt32Array and indices.is_empty()) else _valid_indices(indices, count)

func read_geometry(key: String) -> Dictionary:
	var data := read_geometry_arrays(key)
	return {} if data.is_empty() else publish_geometry(data)

func read_geometry_arrays(key: String) -> Dictionary:
	disk.directory = directory
	var started := Time.get_ticks_usec()
	var data := disk.read(key)
	var decode_us := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	if data.is_empty(): return {}
	if data.get("version") != VERSION or not _valid_arrays(data.get("ground")) or not _valid_arrays(data.get("water")) or not data.get("collision_faces") is PackedVector3Array:
		disk.invalid += 1
		return {}
	var faces: PackedVector3Array = data.collision_faces
	if data.get("smooth_ground",false) and not data.ground.is_empty():
		var uv2: Variant = data.ground[Mesh.ARRAY_TEX_UV2]
		if not uv2 is PackedVector2Array or uv2.size()!=data.ground[Mesh.ARRAY_VERTEX].size():
			disk.invalid+=1
			return {}
	if faces.size() % 3 != 0: disk.invalid += 1; return {}
	var ground: Array = data.ground
	if ground.is_empty():
		if not faces.is_empty(): disk.invalid += 1; return {}
	else:
		var vertices: PackedVector3Array = ground[Mesh.ARRAY_VERTEX]
		var indices: Variant = ground[Mesh.ARRAY_INDEX]
		if indices == null or indices.is_empty():
			if vertices != faces: disk.invalid += 1; return {}
		else:
			if indices.size() != faces.size(): disk.invalid += 1; return {}
			for i in indices.size():
				if vertices[indices[i]] != faces[i]: disk.invalid += 1; return {}
	if data.has("render_detail") and not ground.is_empty() and not _valid_render_detail(data.render_detail,ground[Mesh.ARRAY_VERTEX].size()):
		disk.invalid+=1;return {}
	var validate_us := Time.get_ticks_usec() - started
	return {"ground_arrays": ground, "water_arrays": data.water, "collision_faces": faces,
		"water_source_vertices": int(data.get("water_source_vertices", 0)),"render_detail":data.get("render_detail",{}),
		"cache_decode_us": decode_us, "cache_validate_us": validate_us}

static func publish_geometry(data: Dictionary) -> Dictionary:
	# Scene/RenderingServer publication stays on the caller's main thread.
	var started := Time.get_ticks_usec()
	var terrain := ArrayMesh.new()
	var water := ArrayMesh.new()
	if not data.ground_arrays.is_empty():terrain=Surface.publish_render_mesh(data.ground_arrays,data.get("render_detail",{}))
	if not data.water_arrays.is_empty(): water.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.water_arrays)
	var result := data.duplicate()
	result.merge({"terrain": terrain, "water": water,
		"cache_upload_us": Time.get_ticks_usec() - started,
		"water_vertices": water.surface_get_array_len(0) if water.get_surface_count() > 0 else 0,
		"water_indices": water.surface_get_array_index_len(0) if water.get_surface_count() > 0 else 0})
	return result

static func prepared_bytes(data: Dictionary) -> int:
	if data.is_empty(): return 0
	var size: int = data.collision_faces.size() * 12
	for arrays: Array in [data.ground_arrays, data.water_arrays]:
		if arrays.is_empty(): continue
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
			if arrays[channel] != null:
				size += arrays[channel].size() * (16 if channel == Mesh.ARRAY_COLOR else 8 if channel == Mesh.ARRAY_TEX_UV else 4 if channel == Mesh.ARRAY_INDEX else 12)
	return size

func prepare_batch(snapshot: Terrain, jobs: Array, revision: int, cancelled: Callable) -> Array:
	# Exclusive ownership of this cache instance while the projection's one CPU
	# worker runs. Snapshot payloads are persistent; no Nodes or GPU APIs here.
	var results := []
	var bytes := 0
	for job: Dictionary in jobs:
		if cancelled.call() or results.size() >= PREPARE_TILES or bytes >= PREPARE_BYTES: break
		var started := Time.get_ticks_usec()
		var key := tile_key(snapshot, job.key, revision, job.policy, job.swash, job.sheet)
		var key_us := Time.get_ticks_usec() - started
		if cancelled.call(): break
		started = Time.get_ticks_usec()
		var invalid_before := disk.invalid
		var failures_before := disk.failures
		var data := read_geometry_arrays(key)
		if cancelled.call(): break
		bytes += prepared_bytes(data)
		results.append({"kind": "geometry", "key": job.key, "request": job.request,
			"cache_key": key, "data": data, "key_us": key_us,
			"read_us": Time.get_ticks_usec() - started,
			"cache_invalid": disk.invalid - invalid_before, "cache_failures": disk.failures - failures_before})
	return results

func write_geometry(key: String, generated: Dictionary) -> Dictionary:
	disk.directory = directory
	var ground:Array=generated.get("smooth_arrays",mesh_arrays(generated.terrain))
	if not ground.is_empty() and ground[Mesh.ARRAY_VERTEX].is_empty():ground=[]
	var water := mesh_arrays(generated.water)
	disk.write(key, {"version": VERSION, "ground": ground, "water": water,"render_detail":generated.get("render_detail",{"indices":PackedInt32Array(),"lods":{}}),
		"collision_faces": generated.collision_faces, "smooth_ground": generated.has("smooth_field"), "water_source_vertices": generated.get("water_source_vertices", generated.get("water_vertices", 0))}, func() -> bool: return false)
	# Cold/I-O fallback keeps the same serialized representation and can reuse
	# the serialization readback for LOD. No CPU arrays remain in the tile cache.
	return {"ground_arrays": ground, "water_arrays": water}

static func _lod_disk(directory_path: String) -> Storage:
	var store := Storage.new()
	store.directory = directory_path
	store.max_bytes = 16 * 1024 * 1024
	store.packaged_directory = Storage.PACKAGED_ROOT.path_join("geometry")
	store.packaged_for_directory = ROOT
	return store

static func build_lod(job: Dictionary, cancelled: Callable) -> Dictionary:
	var store := _lod_disk(job.cache_directory)
	var started := Time.get_ticks_usec()
	var saved := store.read(job.cache_key)
	var arrays: Array = job.arrays
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var result := {}
	var valid: bool = not saved.is_empty() and saved.get("version") == VERSION and saved.get("lods") is Dictionary and _valid_indices(saved.get("base"), count)
	if valid:
		var original: Variant = arrays[Mesh.ARRAY_INDEX]
		if original == null or original.is_empty():
			valid = saved.base.size() == count
			if valid:
				for i in count:
					if saved.base[i] != i: valid = false; break
		else: valid = saved.base == original
	if valid:
		for error in saved.lods:
			if not (error is float or error is int) or not is_finite(float(error)) or float(error) <= 0 or not _valid_indices(saved.lods[error], count): valid = false; break
	if valid:
		var base_count: int = saved.base.size()
		result = {"cpu_us": 0, "base_indices": base_count, "far_indices": base_count, "levels": saved.lods.size(), "extra_index_bytes": 0}
		if not saved.lods.is_empty():
			var derived := arrays.duplicate()
			derived[Mesh.ARRAY_INDEX] = saved.base
			result.arrays = derived
			result.lods = saved.lods
			for indices: PackedInt32Array in saved.lods.values():
				result.far_indices = mini(int(result.far_indices), indices.size())
				result.extra_index_bytes += indices.size() * 4
			if arrays[Mesh.ARRAY_INDEX] == null: result.extra_index_bytes += base_count * 4
		result.cache_hit = true
	else:
		result = job.builder.call(arrays, job.bounds)
		result.cache_hit = false
		var base := PackedInt32Array()
		if int(result.levels) > 0: base = result.arrays[Mesh.ARRAY_INDEX]
		elif arrays[Mesh.ARRAY_INDEX] != null: base = arrays[Mesh.ARRAY_INDEX]
		else:
			base.resize(count)
			for i in count: base[i] = i
		store.write(job.cache_key, {"version": VERSION, "base": base, "lods": result.get("lods", {})}, cancelled)
	result.cache_us = Time.get_ticks_usec() - started - int(result.cpu_us)
	result.cache_invalid = store.invalid + (1 if not saved.is_empty() and not valid else 0)
	result.cache_failures = store.failures
	result.cache_written_bytes = store.written_bytes
	return result

static func trim(directory_path: String) -> int:
	var started := Time.get_ticks_usec()
	_lod_disk(directory_path).trim(BUDGET_BYTES)
	return Time.get_ticks_usec() - started
