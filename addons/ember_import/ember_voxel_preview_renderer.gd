@tool
class_name EmberVoxelPreviewRenderer
extends Node
## Main-thread preview renderer for generated Ember PackedScenes. Godot's stock
## preview service has no 3D scene thumbnail for these resources. This reuses a
## single SubViewport and never writes images or content metadata.

signal preview_ready(model_id: String, texture: Texture2D)

const PREVIEW_SIZE := Vector2i(128, 128)
const BACKGROUND := Color(0.075, 0.08, 0.095, 1.0)

var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _pending: Array[Dictionary] = []
var _queued: Dictionary = {}
var _cache: Dictionary = {}
var _busy := false
var _current: Node3D


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
	_queued[cache_key] = true
	_pending.append({"id": model_id, "path": resolved_path, "cacheKey": cache_key})
	if not _busy:
		_render_pending.call_deferred()


func clear_cache(path := "") -> void:
	if path.is_empty():
		_cache.clear()
		return
	var prefix := path + ":"
	for key in _cache.keys():
		if str(key).begins_with(prefix):
			_cache.erase(key)


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


func _render_pending() -> void:
	if _busy:
		return
	_busy = true
	_ensure_stage()
	while not _pending.is_empty() and is_inside_tree():
		var request := _pending.pop_front()
		var cache_key := str(request.get("cacheKey", ""))
		var model_id := str(request.get("id", ""))
		var path := str(request.get("path", ""))
		_queued.erase(cache_key)
		var prop: Node3D = null
		if not path.is_empty():
			var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
			prop = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D if packed else null
		else:
			prop = EmberVoxelPrefab.make_preview_instance(model_id)
		if prop == null:
			continue
		_current = prop
		_current.process_mode = Node.PROCESS_MODE_DISABLED
		_stage.add_child(_current)
		_disable_authored_lights(_current)
		_frame_model(_current)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_viewport):
			break
		var image := _viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			var texture := ImageTexture.create_from_image(image)
			_cache[cache_key] = texture
			preview_ready.emit(model_id, texture)
		if is_instance_valid(_current):
			_current.queue_free()
		_current = null
		# queue_free is finalized before the next scene is framed/rendered.
		await get_tree().process_frame
	_busy = false


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
		return "%s:%d" % [path, FileAccess.get_modified_time(path)]
	return "source:%s:%s" % [model_id, EmberVoxelPrefab.preview_source_revision(model_id)]
