extends RefCounted
## CPU-only helpers shared by ground and water. The projection owns the single
## worker and publishes meshes; this leaf never holds a scene Node.
const GeometryCache = preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")

class Cancellation extends RefCounted:
	var mutex := Mutex.new()
	var cancelled := false
	func set_cancelled(value: bool) -> void:
		mutex.lock()
		cancelled = value
		mutex.unlock()
	func is_cancelled() -> bool:
		mutex.lock()
		var value := cancelled
		mutex.unlock()
		return value

static func build_batch(jobs: Array, cancellation: Cancellation) -> Array:
	var results: Array = []
	var trim_directories := {}
	for job: Dictionary in jobs:
		if cancellation.is_cancelled(): break
		if job.kind == "cache_maintenance":
			trim_directories[job.directory] = true
			continue
		var result: Dictionary
		if job.has("cache_directory"):
			result = GeometryCache.build_lod(job, cancellation.is_cancelled)
			if int(result.cache_written_bytes) > 0: trim_directories[job.cache_directory] = true
		else: result = job.builder.call(job.arrays, job.bounds)
		result.key = job.key
		result.kind = job.kind
		result.mesh = job.mesh
		result.revision = job.revision
		results.append(result)
	for directory: String in trim_directories:
		if cancellation.is_cancelled(): break
		results.append({"kind": "cache_maintenance", "cpu_us": GeometryCache.trim(directory)})
	return results

static func boundary(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var edges := {}
	for i in range(0, indices.size(), 3):
		for j in 3:
			var a := vertices[indices[i + j]]
			var b := vertices[indices[i + (j + 1) % 3]]
			var key := [a, b] if a < b else [b, a]
			edges[key] = int(edges.get(key, 0)) + 1
	var border := {}
	for edge in edges:
		if edges[edge] == 1: border[edge] = true
	return border
