extends SceneTree
## Opt-in diagnostic. Raises the generator guard ONLY in an in-memory script.
## Production sources/maps are never written. Timings are synchronous CPU work.
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var generator := GDScript.new()
	generator.source_code = FileAccess.get_file_as_string("res://addons/ember_import/ember_voxel_shapes.gd").replace("const MAX_CELLS := 524288", "const MAX_CELLS := 1048576")
	assert(generator.reload() == OK)
	var folder := "user://ember-tests/budget-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for size in [Vector3i(64,32,64), Vector3i(64,64,64), Vector3i(192,10,256), Vector3i(128,32,128), Vector3i(128,64,128)]:
		for repeat in 2:
			var row := {"size": str(size), "cells": size.x*size.y*size.z, "repeat": repeat}
			var start := Time.get_ticks_usec()
			var report: Dictionary = generator.build("block",size,16,Color.BROWN,"budget", "Budget")
			assert(report.ok)
			var source: EmberVoxelModelResource = report.source
			row.generate_ms = (Time.get_ticks_usec()-start)/1000.0
			assert(source.validation_errors().is_empty())
			start = Time.get_ticks_usec()
			var packed := EmberVoxelPrefab.prepare_resource(source)
			assert(packed != null)
			row.prefab_with_collision_ms = (Time.get_ticks_usec()-start)/1000.0
			var undo := UndoRedo.new()
			var canvas := Workspace.new()
			canvas.setup(null,undo)
			root.add_child(canvas)
			start = Time.get_ticks_usec()
			canvas.open_surface(source, "")
			row.canvas_open_ms = (Time.get_ticks_usec()-start)/1000.0
			while not canvas._pending_preview_chunks.is_empty():
				canvas._drain_preview_chunk()
			row.canvas_all_chunks_cpu_ms = (Time.get_ticks_usec()-start)/1000.0
			start = Time.get_ticks_usec()
			source.voxels[0] = 0
			canvas._rebuild_visual(PackedInt32Array([0]),false)
			row.local_rebuild_ms = (Time.get_ticks_usec()-start)/1000.0
			start = Time.get_ticks_usec()
			var path := folder.path_join("%d-%d.tres" % [row.cells,repeat])
			assert(ResourceSaver.save(source,path) == OK)
			row.source_save_ms = (Time.get_ticks_usec()-start)/1000.0
			start = Time.get_ticks_usec()
			var reopened := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
			assert(reopened != null and reopened.voxels == source.voxels)
			row.source_reopen_ms = (Time.get_ticks_usec()-start)/1000.0
			row.static_memory_mb = Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0
			print("BUDGET ", JSON.stringify(row))
			canvas.free()
			undo.free()
			await process_frame
	print("BUDGET PASS; fixtures: ",folder)
	quit()
