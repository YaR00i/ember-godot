@tool
extends RefCounted
## Pointer gesture only. Volume math and all channel remapping stay in Fragment.
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
var workspace: Control
var active := false
var committing := false
var released := false
var source: EmberVoxelModelResource
var baseline: EmberVoxelModelResource
var snapshot: Dictionary
var center: Vector3
var plane: Plane
var anchor: Vector3
var radius: float
var softness: float
var region: Rect2i
var height: int
var camera_transform: Transform3D
var camera_size: float
var pending_position: Vector2
var pending := false
var job: RefCounted
var planned_displacement := Vector3.ZERO
var latest_displacement := Vector3.ZERO
var plan := {}
var preview_dirty := {}

func setup(owner_workspace: Control) -> void:
	workspace = owner_workspace

func _intersection(position: Vector2) -> Variant:
	var pixel: Vector2 = position * Vector2(workspace._viewport.size) / workspace._viewport_container.size.max(Vector2.ONE)
	return plane.intersects_ray(workspace._camera.project_ray_origin(pixel), workspace._camera.project_ray_normal(pixel))

func begin(position: Vector2) -> bool:
	if workspace._resource == null or workspace._selection_panel.busy():
		return false
	if workspace._resource.voxels.size() > Fragment.GrabJob.MAX_CANDIDATES:
		workspace._set_status("Первый срез «Тянуть» ограничен холстом524288 ячеек. Используйте отдельный объект меньшего размера.",true)
		return false
	if workspace._isolation_resource != null or not workspace._hidden_group_indices.is_empty():
		workspace._set_status("Тянуть: сначала покажите все группы и отключите изоляцию.",true)
		return false
	var pick: Dictionary = workspace._pick_at(position)
	if not pick.has("hit"):
		return false
	workspace._finish_palette_gesture()
	source = workspace._resource
	baseline = source.duplicate(true) as EmberVoxelModelResource
	snapshot = source.to_definition().duplicate(true)
	center = Vector3(pick.hit) + Vector3.ONE * 0.5
	radius = float(workspace._radius.get_selected_metadata())
	softness = workspace._grab_softness.value
	region = workspace._edit_region_blocks
	height = workspace._slice_height
	camera_transform = workspace._camera.global_transform
	camera_size = workspace._camera.size
	plane = Plane(camera_transform.basis.z.normalized(), center / source.normalized_density())
	var point = _intersection(position)
	if point == null:
		return false
	anchor = point
	active = true
	released = false
	pending = false
	job = null
	plan = {}
	preview_dirty.clear()
	planned_displacement = Vector3.ZERO
	latest_displacement = Vector3.ZERO
	workspace._cursor.hide()
	workspace._update_workshop_shell()
	workspace._set_status("Тяните ЛКМ · соседняя форма следует мягко · отпускание применяет · Esc отменяет")
	return true

func handle(event: InputEvent) -> bool:
	if active:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				cancel()
				return true
			if event.is_command_or_control_pressed() and event.keycode in [KEY_Z, KEY_Y]:
				cancel()
				return false
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if not event.pressed:
					pending_position = workspace._viewport_container.get_local_mouse_position() if not Rect2(Vector2.ZERO, workspace._viewport_container.size).has_point(event.position) else event.position
					pending = true
					released = true
				return true
			# Freeze the capture plane while LMB is held. Navigation resumes after it.
			return true
		if event is InputEventMouseMotion:
			if not released:
				pending_position = event.position
				pending = true
			return true
		return false
	if workspace._canvas_mode == workspace.CanvasMode.BRUSH and workspace._selected_tool_id() == workspace.Model.TOOL_GRAB and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			workspace._viewport_container.grab_focus()
			begin(event.position)
		return true
	return false

func tick() -> void:
	if not active:
		return
	if source != workspace._resource or region != workspace._edit_region_blocks or height != workspace._slice_height or camera_transform != workspace._camera.global_transform or camera_size != workspace._camera.size:
		cancel("Контекст изменился; перетаскивание отменено.")
		return
	if pending:
		pending = false
		var point = _intersection(pending_position)
		if point != null:
			latest_displacement = (point - anchor) * source.normalized_density()
	if job == null and not latest_displacement.is_equal_approx(planned_displacement):
		planned_displacement = latest_displacement
		job = Fragment.start_grab(baseline, center, radius, planned_displacement, softness, region, height, workspace._clip_bounds)
		workspace._set_status("Тянуть · пересчитываю объём… · Esc отменяет")
	if job != null:
		job.step(8192,4000)
		if not job.done:
			return
		plan = job.result
		job = null
		if plan.has("error"):
			workspace._set_status(plan.error,true)
			_clear_preview()
		else:
			var draft := baseline.duplicate(true) as EmberVoxelModelResource
			for key in plan.properties:
				draft.set(key,plan.properties[key])
			workspace._grab_preview_resource = draft
			for index in plan.changed_indices:
				preview_dirty[index] = true
			workspace._queue_visual_rebuild(PackedInt32Array(preview_dirty.keys()))
			var clipped := int(plan.get("clipped_voxels",0))
			var message := "Тянуть · %.1f vox%s · отпускание применяет · Esc отменяет" % [planned_displacement.length(), " · обрезка: %d исходных vox" % clipped if clipped > 0 else ""]
			workspace._set_status(message)
			workspace._info.text = message
			workspace._info.tooltip_text = message
	if not latest_displacement.is_equal_approx(planned_displacement):
		return
	if released:
		if plan.is_empty() or plan.has("error"):
			cancel("Жест не применён: " + str(plan.get("error","изменений нет.")))
			return
		if source.to_definition() != snapshot:
			cancel("Модель изменилась; жест отменён без записи.")
			return
		committing = true
		_clear_preview()
		var ok: bool = workspace._actions.apply_fragment(source,plan)
		committing = false
		active = false
		baseline = null
		plan = {}
		snapshot.clear()
		preview_dirty.clear()
		workspace._update_workshop_shell()
		workspace._set_status("Мягкая деформация применена · Ctrl+Z отменяет · сохраните Canvas" if ok else "Жест устарел и не применён",not ok)

func _clear_preview() -> void:
	workspace._grab_preview_resource = null
	if not preview_dirty.is_empty():
		workspace._queue_visual_rebuild(PackedInt32Array(preview_dirty.keys()))

func cancel(message := "Перетаскивание отменено · исходная форма сохранена") -> void:
	if not active:
		return
	active = false
	job = null
	baseline = null
	plan = {}
	_clear_preview()
	snapshot.clear()
	preview_dirty.clear()
	workspace._update_workshop_shell()
	workspace._set_status(message)
