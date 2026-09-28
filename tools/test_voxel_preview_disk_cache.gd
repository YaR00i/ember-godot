extends SceneTree
## Cross-instance thumbnail reuse and exact-source invalidation in user://.

const Renderer = preload("res://addons/ember_import/ember_voxel_preview_renderer.gd")
var errors: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label)

func _run() -> void:
	var fixture := "user://ember-tests/voxel-preview-cache-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var cache_dir := fixture.path_join("cache")
	var prefab_path := fixture.path_join("probe.tscn")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture)) == OK,"fixture directory")
	var root_node := Node3D.new()
	root_node.name = "Probe"
	var packed := PackedScene.new()
	check(packed.pack(root_node) == OK and ResourceSaver.save(packed,prefab_path) == OK,"fixture scene")
	root_node.free()
	var image := Image.create(Renderer.PREVIEW_SIZE.x,Renderer.PREVIEW_SIZE.y,false,Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var first := Renderer.new()
	first.disk_cache_directory = cache_dir
	root.add_child(first)
	first._store_disk_preview("probe",prefab_path,image)
	var old_cache := first._disk_preview_path("probe",prefab_path)
	check(FileAccess.file_exists(old_cache),"first preview was not saved")
	first.free()
	var second := Renderer.new()
	second.disk_cache_directory = cache_dir
	root.add_child(second)
	var ready: Array[Texture2D] = []
	second.preview_ready.connect(func(_id: String, texture: Texture2D): ready.append(texture))
	second.queue_preview("probe",prefab_path)
	check(ready.size() == 1 and second.pending_count() == 0,"second renderer regenerated an unchanged preview")
	if not ready.is_empty():
		check(ready[0].get_image().get_pixel(0,0).r > 0.9,"disk preview pixels changed")
	second.free()
	root_node = Node3D.new()
	root_node.name = "Probe"
	root_node.set_meta("revision_padding","changed-preview-source-with-different-file-length")
	packed = PackedScene.new()
	check(packed.pack(root_node) == OK and ResourceSaver.save(packed,prefab_path) == OK,"changed fixture scene")
	root_node.free()
	var third := Renderer.new()
	third.disk_cache_directory = cache_dir
	root.add_child(third)
	check(third._disk_preview_path("probe",prefab_path) != old_cache,"changed source retained old disk fingerprint")
	third.queue_preview("probe",prefab_path)
	check(third.pending_count() == 1,"changed object reused stale preview")
	third.cancel_pending()
	third.clear_cache(prefab_path)
	check(not FileAccess.file_exists(old_cache),"publication invalidation kept stale disk preview")
	third.free()
	var new_path := fixture.path_join("new_object.tscn")
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(prefab_path),ProjectSettings.globalize_path(new_path)) == OK,"new object fixture")
	var fourth := Renderer.new()
	fourth.disk_cache_directory = cache_dir
	root.add_child(fourth)
	fourth.queue_preview("new_object",new_path)
	check(fourth.pending_count() == 1,"new object did not queue its own preview")
	fourth.cancel_pending()
	fourth._store_disk_preview("probe",prefab_path,Image.create(2,2,false,Image.FORMAT_RGBA8))
	var damaged := Renderer.new()
	damaged.disk_cache_directory = cache_dir
	root.add_child(damaged)
	var damaged_path := damaged._disk_preview_path("probe",prefab_path)
	damaged.queue_preview("probe",prefab_path)
	check(damaged.pending_count() == 1 and not FileAccess.file_exists(damaged_path),"invalid cached image was not regenerated")
	damaged.cancel_pending()
	for renderer in [fourth,damaged]: renderer.free()
	for path in [prefab_path,new_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for name in DirAccess.get_files_at(ProjectSettings.globalize_path(cache_dir)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_dir.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	for error in errors: push_error(error)
	print("test_voxel_preview_disk_cache: %s · %d" % ["PASS" if errors.is_empty() else "FAIL",errors.size()])
	quit(errors.size())
