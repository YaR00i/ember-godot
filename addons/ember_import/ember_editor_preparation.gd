@tool
extends Window
## Startup gate only; the existing shelf/renderer own catalog and thumbnails.

signal finished(success: bool, elapsed_ms: int, failures: int)

const SETTLE_MSEC := 500
const TIMEOUT_MSEC := 120000
const SurfaceProjection = preload("res://scripts/ember_voxel_surface_projection.gd")

var _shelf: Node
var _filesystem: Object
var _started := 0
var _quiet_since := 0
var _scene_signature := ""
var _catalog_started := false
var _total := 0
var _complete := false
var _waiting_for_choice := false
var _next_check := 0
var _status: Label
var _progress: ProgressBar
var _continue: Button
var _content: MarginContainer


func _init() -> void:
	title = "Подготовка Ember"
	name = "EmberEditorPreparation"
	size = Vector2i(520, 180)
	min_size = size
	unresizable = true
	transient = true
	exclusive = true
	visible = false
	var margin := MarginContainer.new()
	_content = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = "Подготовка Ember…"
	heading.add_theme_font_size_override("font_size", 20)
	box.add_child(heading)
	_status = Label.new()
	_status.text = "Загрузка проекта и открытых сцен…"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_status)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	box.add_child(_progress)
	_continue = Button.new()
	_continue.text = "Продолжить без готовых миниатюр"
	_continue.visible = false
	_continue.pressed.connect(_continue_without_previews)
	box.add_child(_continue)
	# Closing the loading window must not accidentally expose a busy editor.
	close_requested.connect(func():
		if _waiting_for_choice: _continue_without_previews()
	)
	set_process(false)


func begin(shelf: Node, filesystem: Object) -> void:
	_shelf = shelf
	_filesystem = filesystem
	_started = Time.get_ticks_msec()
	_quiet_since = _started
	set_process(true)
	if DisplayServer.get_name() != "headless":
		popup_centered(size)


func _process(_delta: float) -> void:
	if _complete or _waiting_for_choice:
		return
	var now := Time.get_ticks_msec()
	if now < _next_check:
		return
	_next_check = now + 50
	if not is_instance_valid(_shelf) or not is_instance_valid(_filesystem):
		_offer_continue("Подготовка прервана. Можно продолжить работу.")
		return
	if now - _started >= TIMEOUT_MSEC:
		_offer_continue("Подготовка занимает больше двух минут. Можно продолжить и загрузить миниатюры при открытии библиотеки.")
		return
	var scanning: bool = _filesystem.is_scanning() or _filesystem.is_importing()
	var scenes := "\n".join(EditorInterface.get_open_scenes()) if Engine.is_editor_hint() else ""
	if scanning or scenes != _scene_signature:
		_scene_signature = scenes
		_quiet_since = now
	if scanning or now - _quiet_since < SETTLE_MSEC:
		_status.text = "Загрузка проекта и открытых сцен…"
		return
	if not _catalog_started:
		# Let the window draw before synchronous catalog metadata projection.
		_catalog_started = true
		_shelf.prepare_for_startup()
		_total = _shelf.preparation_pending_count()
	var pending: int = _shelf.preparation_pending_count()
	_total = maxi(_total, pending)
	var done := maxi(0, _total - pending)
	_progress.value = 100.0 * (done + _shelf.preparation_loading_fraction()) / maxf(_total, 1)
	_status.text = "Подготовка библиотеки: %d из %d. Пожалуйста, подождите…" % [done, _total]
	if pending > 0:
		return
	if _surface_work_pending():
		_status.text = "Подготовка поверхности открытых сцен…"
		return
	var failures: int = _shelf.preparation_failure_count()
	if failures > 0:
		_offer_continue("Не удалось подготовить миниатюры: %d. Остальные объекты готовы; можно продолжить работу." % failures)
		return
	_finish(true)


func _surface_work_pending() -> bool:
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if node.get_script() == SurfaceProjection:
			if node.pending_chunk_count() > 0 or node.pending_physics_chunk_count() > 0:
				return true
	return false


func _offer_continue(message: String) -> void:
	_waiting_for_choice = true
	_status.text = message
	_continue.show()
	_fit_message.call_deferred()
	_continue.grab_focus()


func _fit_message() -> void:
	# Full-rect containers must not use Window.wrap_controls (size feedback).
	# Fit the error action explicitly after text wrapping/layout has updated.
	if not _waiting_for_choice or _complete:
		return
	var minimum := _content.get_combined_minimum_size().ceil()
	size = Vector2i(maxi(520, int(minimum.x)), maxi(260, int(minimum.y)))


func _continue_without_previews() -> void:
	if _complete:
		return
	if is_instance_valid(_shelf):
		_shelf.cancel_preparation()
		# A timeout before the catalog stage must not permanently disable the shelf.
		_shelf.defer_initial_refresh = false
	_finish(false)


func _finish(success: bool) -> void:
	if _complete:
		return
	_complete = true
	set_process(false)
	var failures: int = _shelf.preparation_failure_count() if is_instance_valid(_shelf) else 0
	finished.emit(success, Time.get_ticks_msec() - _started, failures)
	hide()
	exclusive = false
	transient = false
	_shelf = null
	_filesystem = null
	# Native editor progress dialogs can still reach this completed Window.
	# Keep one hidden controller until the owning plugin's _exit_tree frees it;
	# deleting it here reproduced a crash on the next native scene Save.


func _exit_tree() -> void:
	if not _complete and is_instance_valid(_shelf):
		_shelf.cancel_preparation()
