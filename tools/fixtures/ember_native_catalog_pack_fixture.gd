extends RefCounted
## Shared test-only binary Resource/remap pack writer. Caller owns the guard.


static func build(directory: String, folders: Array[String], excluded_files: Array[String] = []) -> String:
	if not directory.begins_with("user://ember-tests/"): return ""
	var packer := PCKPacker.new()
	var path := directory.path_join("catalogs.pck")
	if packer.pck_start(path) != OK: return ""
	var files: Array[String] = []
	_collect("res://", files)
	for file_path in files:
		if file_path in excluded_files: continue
		var excluded := false
		for folder in folders:
			if file_path.begins_with(folder + "/"): excluded = true
		if not excluded and packer.add_file(file_path, file_path) != OK: return ""
	for index in folders.size():
		var folder := folders[index]
		var staging := directory.path_join("binary-%d" % index)
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging)) != OK: return ""
		for name in DirAccess.get_files_at(folder):
			if not name.ends_with(".tres"): continue
			var source := folder.path_join(name)
			var resource := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE)
			var binary := staging.path_join(name + ".res")
			var target := source.trim_suffix(".tres") + ".res"
			if ResourceSaver.save(resource, binary) != OK or packer.add_file(target, binary) != OK: return ""
			var remap := staging.path_join(name + ".remap")
			var file := FileAccess.open(remap, FileAccess.WRITE)
			if file == null: return ""
			file.store_string('[remap]\npath="%s"\n' % target)
			file.close()
			if packer.add_file(source + ".remap", remap) != OK: return ""
	return ProjectSettings.globalize_path(path) if packer.flush() == OK else ""


static func _collect(directory: String, files: Array[String]) -> void:
	for name in DirAccess.get_files_at(directory): files.append(directory.path_join(name))
	for name in DirAccess.get_directories_at(directory): _collect(directory.path_join(name), files)
