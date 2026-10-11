extends SceneTree
## Native reference gate: fixtures are saved in user://; scene scripts never run.

var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value: errors.append(message)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _run() -> void:
	var directory := "user://ember-tests/native-maps-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var marker := directory.path_join("scene-ran.txt")
	var probe := directory.path_join("region_probe.gd")
	_write(probe, 'extends "res://scripts/ember_region.gd"\nfunc _init() -> void:\n\tFileAccess.open("%s", FileAccess.WRITE).store_string("ran")\n' % marker)
	var fragment := directory.path_join("entry.tscn")
	var fragment_text := '[gd_scene format=3]\n[ext_resource type="Script" path="%s" id="1"]\n[node name="Entry" type="Area3D"]\nscript = ExtResource("1")\nregion_id = "native_entry"\nkind = "player_start"\nscript_id = "native_chain"\n' % probe
	_write(fragment, fragment_text)
	var path := directory.path_join("native_map.tscn")
	_write(path, '[gd_scene format=3]\n[ext_resource type="Script" path="res://scripts/ember_map_loader.gd" id="1"]\n[ext_resource type="PackedScene" path="%s" id="2"]\n[node name="NativeMap" type="Node3D"]\n[node name="Map" type="Node3D" parent="."]\nscript = ExtResource("1")\nmap_id = "native_map"\nauthored_size_blocks = Vector2i(3, 2)\nposition = Vector3(20, 0, 30)\n[node name="Regions" type="Node3D" parent="Map"]\nposition = Vector3(3, 0, 5)\nrotation = Vector3(0, 1.570796327, 0)\nscale = Vector3(2, 1, 3)\n[node name="Spawn" parent="Map/Regions" instance=ExtResource("2")]\nposition = Vector3(1, 0, 2)\n' % fragment)
	_write(directory.path_join("unrelated.tscn"), '[gd_scene format=3]\n[node name="Unrelated" type="Node3D"]\n')
	var previous_pack: Variant = ProjectSettings.get_setting("ember/pack_path", "")
	ProjectSettings.set_setting("ember/pack_path", directory.path_join("missing-joi"))
	var original := FileAccess.get_sha256(path)
	check(EmberInteractionContent.map_ids(directory) == ["native_map"], "catalog must exclude unrelated scenes")
	check(not ResourceLoader.has_cached(path), "catalog discovery eagerly loaded the whole map scene")
	check(EmberInteractionContent.region_ids("native_map", directory) == ["native_entry"], "instance region ID must resolve without JOI")
	var region := EmberInteractionContent.region_definition("native_map", "native_entry", directory)
	check(region.get("scriptId") == "native_chain" and region.get("kind") == "player_start", "native region fields lost")
	check((region.get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(9, 0, 3)), "instance/parent transforms must be map-local")
	region["scriptId"] = "poison"
	check(EmberInteractionContent.region_definition("native_map", "native_entry", directory).get("scriptId") == "native_chain", "returned metadata must not mutate cache")
	check(EmberInteractionContent.map_snapshot("../native_map", directory).is_empty(), "path traversal accepted")
	check(EmberInteractionContent.map_snapshot("missing", directory).is_empty(), "missing scene fabricated")
	check(EmberInteractionContent.region_definition("native_map", "missing", directory).is_empty(), "missing region fabricated")
	# A runtime/editor-held PackedScene may still hold the previous version.
	# Saved metadata refresh must not mutate that live cached Resource.
	var cached_fragment := ResourceLoader.load(fragment, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	# Same-second external scene changes invalidate the parent snapshot too.
	_write(fragment, fragment_text.replace("native_entry", "renamed_entry"))
	check(EmberInteractionContent.region_ids("native_map", directory) == ["renamed_entry"], "instance scene edit did not invalidate cache")
	var cached_state := cached_fragment.get_state()
	for property in cached_state.get_node_property_count(0):
		if cached_state.get_node_property_name(0, property) == &"region_id":
			check(cached_state.get_node_property_value(0, property) == "native_entry", "metadata refresh replaced the live cached scene")
	var inherited := directory.path_join("inherited_map.tscn")
	_write(inherited, '[gd_scene format=3]\n[ext_resource type="PackedScene" path="%s" id="1"]\n[node name="InheritedMap" instance=ExtResource("1")]\n[node name="Map" parent="."]\nmap_id = "inherited_map"\n[node name="Spawn" parent="Map/Regions"]\nregion_id = "overridden_entry"\n' % path)
	check(EmberInteractionContent.region_ids("inherited_map", directory) == ["overridden_entry"], "inherited region override lost")
	check(not FileAccess.file_exists(marker), "metadata query instantiated/executed a scene script")
	check(FileAccess.get_sha256(path) == original, "metadata query wrote the scene")
	# Runtime lookup uses the same nested region and accumulated local transform.
	var runtime_scene := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	var runtime_map := runtime_scene.get_node("Map") as EmberMapLoader
	check(runtime_map.find_region("renamed_entry") != null, "runtime cannot find the instanced nested entry")
	check(runtime_map.region_world("renamed_entry").is_equal_approx(Vector3(9, 0, 3)), "runtime and metadata disagree about nested entry position")
	check(runtime_map.spawn_world().is_equal_approx(Vector3(9, 0, 3)), "default entrance skipped the nested player_start")
	var interact := EmberInteract.new()
	interact.kind = "quest_marker"
	interact.trigger_id = "renamed_entry"
	runtime_map.add_child(interact)
	check(interact.resolved_action_script_id() == "native_chain", "interaction skipped the nested native region binding")
	runtime_scene.free()
	check(EmberInteractionContent.map_exists("landscape_compact"), "current native map missing")
	check(EmberInteractionContent.region_ids("landscape_compact").has("landscape_compact_start"), "current native entrance missing without JOI")
	check(not EmberInteractionContent.map_exists("combat_lab"), "non-map lab offered as a transition map")
	ProjectSettings.set_setting("ember/pack_path", previous_pack)
	if not errors.is_empty():
		printerr("FAIL native map references: ", "; ".join(errors))
		quit(1)
		return
	print("PASS native map references: native scenes, instances/inheritance, fresh detached metadata, missing IDs, no script execution/JOI")
	quit(0)
