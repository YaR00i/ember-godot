@tool
extends RefCounted
## Editor presets reuse Recipe. They never contain a frozen object skeleton or
## family identity and never enter the runtime object catalog.
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Session = preload("res://addons/ember_import/ember_voxel_generation_session.gd")
var directory := "res://content/editor/voxel_generator_presets"
var error := ""


func list_presets(generator_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)): return result
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() != "tres": continue
		var path := directory.path_join(file)
		var recipe := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if recipe == null or not Generator.validation_errors(recipe).is_empty(): continue
		if recipe.generator_id != generator_id: continue
		result.append({"path": path, "name": recipe.resource_name if not recipe.resource_name.is_empty() else file.get_basename(), "recipe": recipe})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return result


func save_preset(recipe: Resource, title: String) -> String:
	error = ""
	title = title.strip_edges().left(80)
	if title.is_empty():
		error = "Введите имя пресета."
		return ""
	var errors := Generator.validation_errors(recipe)
	if not errors.is_empty():
		error = errors[0]
		return ""
	for entry in list_presets(recipe.generator_id):
		if str(entry.name).nocasecmp_to(title) == 0:
			error = "Пресет с таким именем уже есть. Используйте другое имя; существующий не перезаписан."
			return ""
	var path := directory.path_join("preset_%d.tres" % Time.get_ticks_usec())
	while FileAccess.file_exists(path): path = path.get_basename() + "x.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var result := ResourceSaver.save(Session.preset_recipe(recipe, title), path)
	if result != OK:
		error = error_string(result)
		return ""
	return path
