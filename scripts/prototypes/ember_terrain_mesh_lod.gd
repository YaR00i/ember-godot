extends RefCounted
## Geometry helpers shared by ground, water and object presentation. Their
## existing owners hold resources/queues; this leaf never holds a scene Node.
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

## A shared derived mesh for native distance LOD. Indexing welds only identical
## vertex attributes: the base triangles, UVs, pigment and custom channels stay
## exact. Godot selects index levels by projected error, including shadow views.
class ObjectJob extends RefCounted:
	var surfaces: Array = []
	var importer: ImporterMesh
	var levels := 0
	var us := 0
	var stale := false # Main-thread publication guard; worker never reads it.
	func run() -> void:
		var started := Time.get_ticks_usec()
		importer = ImporterMesh.new()
		for surface: Dictionary in surfaces:
			var tool := SurfaceTool.new()
			tool.create_from_arrays(surface.arrays)
			tool.index()
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, tool.commit_to_arrays(), [], {}, null, surface.name, surface.format)
		importer.generate_lods(60.0, 0.0, [])
		for surface in importer.get_surface_count(): levels += importer.get_surface_lod_count(surface)
		us = Time.get_ticks_usec() - started

## Snapshot on the main thread, CPU-only indexing/simplification on the worker.
static func object_job(source: ArrayMesh) -> ObjectJob:
	var job := ObjectJob.new()
	for surface in source.get_surface_count():
		if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: return null
		job.surfaces.append({"arrays": source.surface_get_arrays(surface).duplicate(true), "name": source.surface_get_name(surface), "format": source.surface_get_format(surface)})
	return job

## Publish GPU resources and original material bindings only on the main thread.
static func publish_object(job: ObjectJob, source: ArrayMesh) -> Dictionary:
	for surface in source.get_surface_count(): job.importer.set_surface_material(surface, source.surface_get_material(surface))
	var mesh := job.importer.get_mesh()
	for key in source.get_meta_list(): mesh.set_meta(key, source.get_meta(key))
	mesh.custom_aabb = source.custom_aabb
	return {"mesh": mesh, "levels": job.levels, "us": job.us}

static func object_mesh(source: ArrayMesh) -> Dictionary:
	var job := object_job(source)
	if job == null: return {"mesh": source, "levels": 0, "us": 0}
	job.run()
	return publish_object(job, source)
