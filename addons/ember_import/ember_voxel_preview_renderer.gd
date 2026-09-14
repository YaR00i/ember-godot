@tool
class_name EmberVoxelPreviewRenderer
extends Node
## Background resource loading, main-thread scene/viewport work. Godot's stock
## preview service has no 3D scene thumbnail for these resources. This reuses a
## single SubViewport and never writes images or content metadata.

signal preview_ready(model_id: String, texture: Texture2D)
signal preview_failed(model_id: String, reason: String)

const PREVIEW_SIZE := Vector2i(128, 128)
const BACKGROUND := Color(0.075, 0.08, 0.095, 1.0)
const MAX_LOADING_REQUESTS := 2

var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _pending: Array[Dictionary] = []
var _queued: Dictionary = {}
var _cache: Dictionary = {}
var _busy := false
var _current: Node3D
var _epoch := 0
var _failures: Dictionary = {}
var _load_fraction := 0.0
var _cache_epoch := 0
var _path_revisions: Dictionary = {}
var _source_revisions: Dictionary = {}
enum Phase { IDLE, LOAD, DRAW, CLEANUP }
var _phase := Phase.IDLE
var _request: Dictionary = {}
var _loading_path := ""
var _prefetched_paths: Dictionary = {}
static var _abandoned_loads: Dictionary = {}


func _ready() -> void:
	set_process(not _pending.is_empty())


func queue_preview(model_id: String, path := "") -> void:
	if model_id.is_empty():
		return
	var resolved_path := path if not path.is_empty() and ResourceLoader.exists(path) else ""
	var cache_key := _cache_key(model_id, resolved_path)
	if _cache.has(cache_key):
		preview_ready.emit(model_id, _cache[cache_key] as Texture2D)
		return
	if _queued.has(cache_key):
		return
	_failures.erase(cache_key)
	_queued[cache_key] = _epoch
	_pending.append({"id": model_id, "path": resolved_path, "cacheKey": cache_key, "epoch": _epoch, "revision": _cache_revision(resolved_path, model_id)})
	set_process(true)


func clear_cache(path := "") -> void:
	if path.is_empty():
		_cache_epoch += 1
		_cache.clear()
		_failures.clear()
		return
	var prefix := path + ":"
	var model_id := path.get_file().get_basename()
	var source_prefix := "source:%s:" % model_id
	_path_revisions[path] = int(_path_revisions.get(path, 0)) + 1
	_source_revisions[model_id] = int(_source_revisions.get(model_id, 0)) + 1
	for key in _cache.keys():
		if str(key).begins_with(prefix) or str(key).begins_with(source_prefix):
			_cache.erase(key)
	for key in _failures.keys():
		if str(key).begins_with(prefix) or str(key).begins_with(source_prefix):
			_failures.erase(key)


func cancel_pending() -> void:
	_epoch += 1 # In-flight loads finish safely, but cancelled requests publish nothing.
	_pending.clear()
	_queued.clear()
	_load_fraction = 0.0
	_release_loading_path()
	for path in _prefetched_paths.values():
		_abandon_load(str(path))
	_prefetched_paths.clear()
	if RenderingServer.frame_post_draw.is_connected(_read_preview):
		RenderingServer.frame_post_draw.disconnect(_read_preview)
	if is_instance_valid(_current):
		_current.queue_free()
	_current = null
	if not _request.is_empty():
		_phase = Phase.CLEANUP


func pending_count() -> int:
	return _pending.size() + (1 if _busy else 0)


func failure_count() -> int:
	return _failures.size()


func loading_fraction() -> float:
	return _load_fraction


func _exit_tree() -> void:
	cancel_pending()
	set_process(false)
	_phase = Phase.IDLE
	_request = {}
	_busy = false


func _release_loading_path() -> void:
	if not _loading_path.is_empty():
		# No coroutine resumes on a deleted Node. Transfer only disposal of the
		# existing loader token; this never instantiates or publishes a preview.
		_abandon_load(_loading_path)
		_loading_path = ""


static func _abandon_load(path: String) -> void:
	_abandoned_loads[path] = int(_abandoned_loads.get(path, 0)) + 1
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_drain_abandoned_loads):
		tree.process_frame.connect(_drain_abandoned_loads)


func _prefetch_pending() -> void:
	# Only resource loading overlaps. Instantiation/render/readback remain ordered
	# on the same viewport; completed loader tokens retain at most this window.
	var slots := MAX_LOADING_REQUESTS - _prefetched_paths.size() - (0 if _loading_path.is_empty() else 1)
	if slots <= 0:
		return
	for request in _pending:
		var path := str(request.path)
		var key := str(request.cacheKey)
		if path.is_empty() or _prefetched_paths.has(key) or not _request_is_current(request):
			continue
		# A replacement revision must wait for this renderer's old token to be
		# consumed, otherwise ResourceLoader would join the obsolete same-path job.
		if path == _loading_path or _prefetched_paths.values().has(path):
			continue
		if ResourceLoader.load_threaded_request(path, "PackedScene", false, ResourceLoader.CACHE_MODE_REUSE) == OK:
			_prefetched_paths[key] = path
			slots -= 1
			if slots == 0:
				break


func _ensure_stage() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.name = "VoxelPreviewViewport"
	_viewport.size = PREVIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	_stage = Node3D.new()
	_stage.name = "PreviewStage"
	_viewport.add_child(_stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.88, 1.0)
	environment.ambient_light_energy = 0.72
	environment_node.environment = environment
	_stage.add_child(environment_node)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 1.3
	key.shadow_enabled = false
	_stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(28.0, 146.0, 0.0)
	fill.light_color = Color(0.56, 0.7, 1.0)
	fill.light_energy = 0.62
	fill.shadow_enabled = false
	_stage.add_child(fill)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.01
	_camera.far = 10000.0
	_stage.add_child(_camera)
	_camera.current = true


func _process(_delta: float) -> void:
	_prefetch_pending()
	if _phase == Phase.DRAW:
		return
	if _phase == Phase.CLEANUP:
		_finish_request(_request)
		_request = {}
		_busy = false
		_phase = Phase.IDLE
	if _phase == Phase.LOAD:
		_poll_load()
		return
	if _pending.is_empty():
		_load_fraction = 0.0
		set_process(false)
		return
	_request = _pending.pop_front()
	_busy = true
	_load_fraction = 0.0
	_ensure_stage()
	var key := str(_request.cacheKey)
	if _prefetched_paths.has(key):
		_loading_path = str(_prefetched_paths[key])
		_prefetched_paths.erase(key)
		_phase = Phase.LOAD
		_poll_load()
		return
	if not _request_is_current(_request):
		_phase = Phase.CLEANUP
		return
	var path := str(_request.path)
	if path.is_empty():
		_stage_model(EmberVoxelPrefab.make_preview_instance(str(_request.id)))
		return
	var error := ResourceLoader.load_threaded_request(path, "PackedScene", false, ResourceLoader.CACHE_MODE_REUSE)
	if error != OK:
		_fail_current("Не удалось начать загрузку миниатюры.")
		return
	_loading_path = path
	_phase = Phase.LOAD
	_poll_load()


func _poll_load() -> void:
	# Never retrieve an unfinished load: load_threaded_get would block the editor.
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_loading_path, progress)
	_load_fraction = float(progress[0]) if not progress.is_empty() else 0.0
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var packed: PackedScene = null
	if status in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		packed = ResourceLoader.load_threaded_get(_loading_path) as PackedScene
	_loading_path = ""
	if not _request_is_current(_request):
		_phase = Phase.CLEANUP
		return
	if packed == null:
		_fail_current("Не удалось загрузить объект для миниатюры.")
		return
	_load_fraction = 1.0
	var instance := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if instance is Node3D:
		_stage_model(instance)
	else:
		if instance != null: instance.free()
		_fail_current("Не удалось загрузить объект для миниатюры.")


func _stage_model(prop: Node3D) -> void:
	if prop == null:
		_fail_current("Не удалось загрузить объект для миниатюры.")
		return
	_current = prop
	_current.process_mode = Node.PROCESS_MODE_DISABLED
	_stage.add_child(_current)
	_disable_authored_lights(_current)
	_frame_model(_current)
	_phase = Phase.DRAW
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.frame_post_draw.connect(_read_preview, CONNECT_ONE_SHOT)


func _read_preview() -> void:
	if not is_inside_tree() or not is_instance_valid(_viewport):
		return
	var request := _request
	var texture: ImageTexture = null
	if _request_is_current(request):
		var image := _viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
			_cache[str(request.cacheKey)] = texture
	if is_instance_valid(_current):
		_current.queue_free()
	_current = null
	# queue_free completes before _process starts another model next frame.
	_phase = Phase.CLEANUP
	# Signal receivers may close/free their renderer. Publish last.
	if texture != null:
		preview_ready.emit(str(request.id), texture)
	elif _request_is_current(request):
		_fail_request(request, "Не удалось получить изображение миниатюры.")


func _fail_current(reason: String) -> void:
	_phase = Phase.CLEANUP
	_fail_request(_request, reason)


static func _drain_abandoned_loads() -> void:
	for path in _abandoned_loads.keys():
		var status := ResourceLoader.load_threaded_get_status(str(path))
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
			for token in int(_abandoned_loads[path]):
				ResourceLoader.load_threaded_get(str(path))
		_abandoned_loads.erase(path)
	var tree := Engine.get_main_loop() as SceneTree
	if _abandoned_loads.is_empty() and tree != null and tree.process_frame.is_connected(_drain_abandoned_loads):
		tree.process_frame.disconnect(_drain_abandoned_loads)


func _finish_request(request: Dictionary) -> void:
	var key := str(request.cacheKey)
	if _queued.get(key, -1) == int(request.epoch):
		_queued.erase(key)


func _fail_request(request: Dictionary, reason: String) -> void:
	_finish_request(request)
	if not _request_is_current(request):
		return
	_failures[str(request.cacheKey)] = reason
	preview_failed.emit(str(request.id), reason)


func _frame_model(prop: Node3D) -> void:
	var mesh := prop.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		_camera.position = Vector3(3.0, 2.5, 3.0)
		_camera.size = 4.0
		_camera.look_at(Vector3.ZERO)
		return
	var bounds := mesh.mesh.get_aabb()
	var center := mesh.transform * bounds.get_center()
	var size := bounds.size * mesh.transform.basis.get_scale().abs()
	var horizontal := Vector2(size.x, size.z).length() * 0.72
	_camera.size = maxf(maxf(size.y, horizontal) * 1.32, 0.5)
	var distance := maxf(size.length() * 1.8, 2.0)
	var direction := Vector3(1.0, 0.78, 1.0).normalized()
	_camera.position = center + direction * distance
	_camera.look_at(center, Vector3.UP)


func _disable_authored_lights(node: Node) -> void:
	if node is Light3D:
		(node as Light3D).visible = false
	for child in node.get_children():
		_disable_authored_lights(child)


func _cache_key(model_id: String, path: String) -> String:
	if not path.is_empty():
		return "%s:%d:%s" % [path, FileAccess.get_modified_time(path), _cache_revision(path, model_id)]
	return "source:%s:%s:%s" % [model_id, EmberVoxelPrefab.preview_source_revision(model_id), _cache_revision(path, model_id)]


func _cache_revision(path: String, model_id: String) -> String:
	return "%d:%d:%d" % [_cache_epoch, int(_path_revisions.get(path, 0)), int(_source_revisions.get(model_id, 0))]


func _request_is_current(request: Dictionary) -> bool:
	return int(request.epoch) == _epoch and str(request.revision) == _cache_revision(str(request.path), str(request.id))
