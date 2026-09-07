@tool
class_name EmberCameraRigPreview
extends VBoxContainer
## Editor-only live preview for an OrbitCamera rig. The SubViewport shares the
## edited scene's World3D and owns only a display camera, never gameplay data.

const PREVIEW_SIZE := Vector2i(640, 360)

var _rig: OrbitCamera
var _editor_interface: EditorInterface
var _viewport: SubViewport
var _preview_camera: Camera3D
var _preview_container: SubViewportContainer
var _toggle: Button
var _select_camera: Button
var _status: Label
var _hint: Label
var _last_signature := ""


func setup(rig: OrbitCamera, editor_interface: EditorInterface = null) -> void:
	_rig = rig
	_editor_interface = editor_interface
	_build_ui()
	_sync_from_source(true)
	set_process(true)


func _process(_delta: float) -> void:
	_sync_from_source()


func source_camera() -> Camera3D:
	if not is_instance_valid(_rig):
		return null
	var camera := _rig.get_node_or_null(_rig.camera_path) as Camera3D
	if camera != null:
		return camera
	return _rig.find_child("*", true, false) as Camera3D


func preview_camera() -> Camera3D:
	return _preview_camera


func preview_viewport() -> SubViewport:
	return _viewport


func sync_now() -> void:
	_sync_from_source(true)


func _build_ui() -> void:
	name = "CameraRigInspectorPreview"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	_toggle = Button.new()
	_toggle.name = "CameraRigPreviewToggle"
	_toggle.text = "▾  Предварительный просмотр CameraRig"
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.toggle_mode = true
	_toggle.button_pressed = true
	_toggle.pressed.connect(_on_toggle_pressed)
	add_child(_toggle)

	_preview_container = SubViewportContainer.new()
	_preview_container.name = "CameraRigPreviewSurface"
	_preview_container.custom_minimum_size = Vector2(320.0, 180.0)
	_preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_container.stretch = true
	_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview_container)

	_viewport = SubViewport.new()
	_viewport.name = "CameraRigPreviewViewport"
	_viewport.size = PREVIEW_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_preview_container.add_child(_viewport)

	_preview_camera = Camera3D.new()
	_preview_camera.name = "CameraRigPreviewCamera"
	_preview_camera.current = true
	_viewport.add_child(_preview_camera)

	var actions := HBoxContainer.new()
	actions.name = "CameraRigPreviewActions"
	add_child(actions)

	_status = Label.new()
	_status.name = "CameraRigPreviewStatus"
	_status.text = "Ожидаю дочернюю Camera3D…"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	actions.add_child(_status)

	_select_camera = Button.new()
	_select_camera.name = "SelectCameraRigChild"
	_select_camera.text = "Выбрать Camera3D"
	_select_camera.tooltip_text = "Перейти к штатным свойствам дочерней камеры."
	_select_camera.pressed.connect(_on_select_camera_pressed)
	actions.add_child(_select_camera)

	_hint = Label.new()
	_hint.name = "CameraRigPreviewHint"
	_hint.text = "Live-preview использует открытую арену и настройки этого CameraRig."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.modulate = Color(0.67, 0.72, 0.8)
	add_child(_hint)


func _sync_from_source(force := false) -> void:
	if not is_instance_valid(_viewport) or not is_instance_valid(_preview_camera):
		return
	var source := source_camera()
	if source == null or not source.is_inside_tree():
		_status.text = "Дочерняя Camera3D не найдена"
		_select_camera.disabled = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_select_camera.disabled = false
	var world := source.get_world_3d()
	var signature := "%s|%s|%d|%.4f|%.4f|%.4f|%.4f|%.4f|%d" % [
		source.get_instance_id(),
		source.global_transform,
		source.projection,
		source.size,
		source.fov,
		source.near,
		source.far,
		source.h_offset,
		source.cull_mask,
	]
	if not force and signature == _last_signature and _viewport.world_3d == world:
		return
	_last_signature = signature
	_viewport.world_3d = world
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_camera.global_transform = source.global_transform
	_preview_camera.projection = source.projection
	_preview_camera.keep_aspect = source.keep_aspect
	_preview_camera.fov = source.fov
	_preview_camera.size = source.size
	_preview_camera.frustum_offset = source.frustum_offset
	_preview_camera.h_offset = source.h_offset
	_preview_camera.v_offset = source.v_offset
	_preview_camera.near = source.near
	_preview_camera.far = source.far
	_preview_camera.cull_mask = source.cull_mask
	_preview_camera.current = true
	var orthographic := source.projection == Camera3D.PROJECTION_ORTHOGONAL
	_status.text = "%s · %s" % [
		source.name,
		("ортографическая · Size %.1f" % source.size)
		if orthographic
		else ("перспективная · FOV %.1f°" % source.fov),
	]
	_hint.text = (
		"В ортографическом режиме масштаб меняет Size; FOV не используется."
		if orthographic
		else "В перспективном режиме угол обзора меняет FOV; Orthographic Size не используется."
	)


func _on_toggle_pressed() -> void:
	var expanded := _toggle.button_pressed
	_toggle.text = "%s  Предварительный просмотр CameraRig" % ("▾" if expanded else "▸")
	_preview_container.visible = expanded
	var actions := get_node_or_null("CameraRigPreviewActions") as Control
	if actions != null:
		actions.visible = expanded
	if _hint != null:
		_hint.visible = expanded
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if expanded else SubViewport.UPDATE_DISABLED
	)


func _on_select_camera_pressed() -> void:
	var source := source_camera()
	if source == null or _editor_interface == null:
		return
	var selection := _editor_interface.get_selection()
	if selection == null:
		return
	selection.clear()
	selection.add_node(source)
