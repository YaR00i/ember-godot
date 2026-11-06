@tool
extends VBoxContainer

signal timeline_requested(motion: AnimationPlayer)
signal workshop_requested

const WorkshopEntry = preload("res://addons/ember_animation/ember_animation_workshop_entry.gd")
const StaffMotion = preload("res://scripts/ember_mira_motion_controls.gd")
const BlenderExchange = preload("res://addons/ember_animation/ember_blender_exchange.gd")
const Action = preload("res://scripts/ember_animation_action.gd")
const ActionModifier = preload("res://scripts/ember_animation_action_modifier.gd")
const STAFF_SEQUENCE := [&"idle_stowed", StaffMotion.DRAW, &"staff_strike", StaffMotion.DRAW]
const STAFF_STAGES := ["Стойка", "Достать", "Каст", "Возврат"]
const INK := Color("141622")
const PANEL := Color("1c2030")
const EDGE := Color("343a50")
const ACCENT := Color("a9a6fc")

const GROUPS := ["Все", "Стойки", "Шаг и бег", "Воздух и вода", "Оружие и бой", "Предметы и двери", "Прочее"]
const TITLES := {
	"idle": "Спокойная стойка", "idle_alt": "Вторая стойка",
	"walk": "Обычный шаг", "walk_adventure": "Походный шаг",
	"jog": "Лёгкий бег", "run": "Спринт",
	"fall": "Падение", "land": "Приземление", "roll": "Кувырок",
	"swim": "Плавание", "swim_idle": "На плаву",
	"staff_draw_transition": "Достать и убрать посох", "staff_draw": "Исходный клип доставания",
	"staff_strike": "Каст посохом", "crate_lift": "Поднять ящик",
	"crate_place": "Поставить ящик", "crate_throw": "Бросить ящик",
	"crate_push": "Толкнуть ящик", "door_reach": "Рука к двери",
	"cable_hang": "Вис на канате", "mantle": "Подъём на уступ",
}

var _motion: AnimationPlayer
var _picked := &""
var _group := 0
var _playing := false
var _reverse := false
var _elapsed := 0.0
var _cards: VBoxContainer
var _filters: OptionButton
var _search: LineEdit
var _caption: Label
var _clock: Label
var _scrub: HSlider
var _play: Button
var _timeline: Button
var _reset: Button
var _fingerprint := PackedStringArray()
var _stage: SubViewport
var _stage_camera: Camera3D
var _stage_player: AnimationPlayer
var _stage_actor: Node3D
var _viewport_box: SubViewportContainer
var _stage_hint: Label
var _source: Label
var _feedback: Label
var _save: Button
var _yaw := 0.32
var _pitch := 0.10
var _distance := 3.0
var _dragging := false
var _sequence: CheckButton
var _sequence_row: HBoxContainer
var _sequence_local := 0.0
var _sequence_stage := 0
var _hand_choice: OptionButton
var _hand_readout: Label
var _hand_marker: MeshInstance3D
var _grip_marker: MeshInstance3D
var undo_history: EditorUndoRedoManager
var _blender_open: Button
var _blender_import: Button
## Explicit host for the standalone, disposable project trial. The editor uses
## its edited scene and EditorUndoRedoManager as before.
var source_root: Node
var preview_scene := WorkshopEntry.SCENE
var local_undo: UndoRedo
var _stage_action: ActionModifier
var _action_row: HBoxContainer
var _action_base: OptionButton
var _fade_in: SpinBox
var _fade_out: SpinBox
var _assign_action: Button
var _add_clip: Button
var _replace_clip: Button

func _source_root() -> Node:
	return source_root if is_instance_valid(source_root) else (EditorInterface.get_edited_scene_root() if Engine.is_editor_hint() else null)

func _ready() -> void:
	name = "EmberAnimationCatalog"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var theme_override := Theme.new()
	theme_override.set_color("font_color", "Label", Color("e7e9f8"))
	theme_override.set_color("font_color", "Button", Color("e7e9f8"))
	theme_override.set_stylebox("normal", "Button", _box(Color("292e43"), EDGE, 7, 9))
	theme_override.set_stylebox("hover", "Button", _box(Color("353b55"), ACCENT, 7, 9))
	theme_override.set_stylebox("pressed", "Button", _box(Color("41426e"), ACCENT, 7, 9))
	theme_override.set_stylebox("disabled", "Button", _box(Color("212434"), EDGE, 7, 9))
	theme = theme_override
	add_theme_constant_override("separation", 0)
	var shell := _panel(self, INK, 0, 16)
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var workspace := VBoxContainer.new()
	workspace.add_theme_constant_override("separation", 12)
	shell.add_child(workspace)
	var header := HBoxContainer.new()
	workspace.add_child(header)
	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_stack)
	_label(title_stack, "EMBER   /   АНИМАЦИИ", 12, ACCENT)
	_label(title_stack, "Мастерская движения", 25)
	_source = _label(title_stack, "", 13, Color("a7acc5"))
	var mira_button := _button(header, "Мира", func() -> void: workshop_requested.emit())
	mira_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mira_button.disabled = not Engine.is_editor_hint()
	_button(header, "Контакт IK", _open_contact_trace).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_save = _button(header, "Сохранить клипы", _save_library)
	_save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timeline = _button(header, "Открыть ключи", _open_timeline)
	_timeline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_blender_open = _button(header, "Открыть в Blender", _open_blender)
	_blender_import = _button(header, "Вернуть из Blender", _return_from_blender)
	for button in [_blender_open, _blender_import]:
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(columns)
	var sidebar := _panel(columns, PANEL, 10, 12)
	sidebar.custom_minimum_size.x = 295
	var library := VBoxContainer.new()
	library.add_theme_constant_override("separation", 8)
	sidebar.add_child(library)
	_label(library, "КЛИПЫ", 12, ACCENT)
	_add_clip = _button(library, "Добавить клип…", _select_action_file.bind(false))
	_replace_clip = _button(library, "Заменить выбранный клип…", _select_action_file.bind(true))
	_search = LineEdit.new()
	_search.placeholder_text = "Название или ID клипа"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_query: String) -> void: _rebuild_cards())
	library.add_child(_search)
	_filters = OptionButton.new()
	_filters.item_selected.connect(_choose_group)
	library.add_child(_filters)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 5)
	scroll.add_child(_cards)

	var stage_panel := _panel(columns, PANEL, 10, 12)
	stage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage_layout := VBoxContainer.new()
	stage_layout.add_theme_constant_override("separation", 8)
	stage_panel.add_child(stage_layout)
	var stage_bar := HBoxContainer.new()
	stage_layout.add_child(stage_bar)
	var stage_title := _label(stage_bar, "ПРОСМОТР", 12, ACCENT)
	stage_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(stage_bar, "Спереди", _set_camera_angle.bind(0.0))
	_button(stage_bar, "Сбоку", _set_camera_angle.bind(PI * 0.5))
	_button(stage_bar, "Сзади", _set_camera_angle.bind(PI))
	_viewport_box = SubViewportContainer.new()
	_viewport_box.stretch = true
	_viewport_box.custom_minimum_size = Vector2(300, 220)
	_viewport_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_box.gui_input.connect(_orbit_input)
	stage_layout.add_child(_viewport_box)
	_stage = SubViewport.new()
	_stage.own_world_3d = true
	_stage.msaa_3d = Viewport.MSAA_2X
	_stage.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport_box.add_child(_stage)
	_stage_hint = _label(stage_layout, "Потяни мышью, чтобы повернуть модель. Колесо — масштаб.", 12, Color("a7acc5"))
	_caption = _label(stage_layout, "", 17)
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_assign_action = _button(stage_layout, "Создать копию: Левая рука → Помахать", _assign_left_action)
	_action_row = HBoxContainer.new()
	stage_layout.add_child(_action_row)
	_label(_action_row, "Основа", 13)
	_action_base = OptionButton.new()
	_action_base.add_item("Стоя · посох справа")
	_action_base.add_item("На ходу · посох справа")
	_action_base.item_selected.connect(func(_id: int) -> void: _seek(_elapsed))
	_action_row.add_child(_action_base)
	_label(_action_row, "Вход, с", 13)
	_fade_in = SpinBox.new(); _fade_in.min_value = 0; _fade_in.max_value = 2; _fade_in.step = 0.05; _fade_in.value = 0.15
	_action_row.add_child(_fade_in)
	_label(_action_row, "Выход, с", 13)
	_fade_out = SpinBox.new(); _fade_out.min_value = 0; _fade_out.max_value = 2; _fade_out.step = 0.05; _fade_out.value = 0.20
	_action_row.add_child(_fade_out)
	_button(_action_row, "Записать переходы", _assign_left_action)
	_sequence = CheckButton.new()
	_sequence.text = "Последовательность посоха"
	_sequence.toggled.connect(_toggle_sequence)
	stage_layout.add_child(_sequence)
	_sequence_row = HBoxContainer.new()
	stage_layout.add_child(_sequence_row)
	for i in STAFF_STAGES.size():
		_button(_sequence_row, STAFF_STAGES[i], _jump_to_stage.bind(i))
	_button(_sequence_row, "Кадр выпуска", _jump_to_impact)
	_hand_choice = OptionButton.new()
	_hand_choice.add_item("Правая кисть")
	_hand_choice.add_item("Левая кисть")
	_sequence_row.add_child(_hand_choice)
	_hand_readout = _label(stage_layout, "", 13, Color("a7acc5"))
	var playback := HBoxContainer.new()
	stage_layout.add_child(playback)
	_play = _button(playback, "Смотреть", _toggle_preview)
	_reset = _button(playback, "С начала", _seek.bind(0.0))
	_button(playback, "−1", _step_frame.bind(-1)).tooltip_text = "На кадр назад (30 кадров/с)"
	_button(playback, "+1", _step_frame.bind(1)).tooltip_text = "На кадр вперёд (30 кадров/с)"
	var time_row := HBoxContainer.new()
	stage_layout.add_child(time_row)
	_scrub = HSlider.new()
	_scrub.step = 0.001
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.value_changed.connect(_scrub_to)
	_scrub.draw.connect(_draw_sequence_ticks)
	time_row.add_child(_scrub)
	_clock = _label(time_row, "—", 13, Color("a7acc5"))
	_clock.custom_minimum_size.x = 112
	_feedback = _label(workspace, "Выбери клип, затем прокрути его или открой штатную шкалу ключей.", 13, Color("a7acc5"))
	visibility_changed.connect(func() -> void:
		if is_instance_valid(_stage_actor):
			_stage_actor.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED
		if not is_visible_in_tree():
			_playing = false
		else:
			_sync_stage_source()
			_rebuild()
	)
	_rebuild()

func _box(fill: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box

func _panel(parent: Control, fill: Color, radius: int, padding: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(fill, EDGE, radius, padding))
	parent.add_child(panel)
	return panel

func _label(parent: Control, caption: String, size_px: int, color := Color("e7e9f8")) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func show_library(motion: AnimationPlayer) -> void:
	_playing = false
	if _motion != motion:
		_sequence.set_pressed_no_signal(false)
		_motion = motion
		_group = 0
		_picked = &""
		_elapsed = 0.0
		_search.clear()
		if motion.has_animation(&"idle_stowed"):
			_picked = &"idle_stowed"
	_setup_stage()
	_rebuild()

func _button(parent: Control, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _live() -> bool:
	if not is_instance_valid(_motion):
		return false
	var root := _source_root()
	return root != null and (root == _motion or root.is_ancestor_of(_motion))

func has_source() -> bool:
	return _live()

func _rebuild() -> void:
	_fingerprint = _motion.get_animation_list() if _live() else PackedStringArray()
	_filters.clear()
	var counts := {}
	for clip_id in _fingerprint:
		var group := category(clip_id)
		counts[group] = int(counts.get(group, 0)) + 1
	for index in GROUPS.size():
		var count := _fingerprint.size() if index == 0 else int(counts.get(index, 0))
		_filters.add_item("%s · %d" % [GROUPS[index], count])
		_filters.set_item_disabled(index, count == 0)
	_filters.select(_group)
	_rebuild_cards()

func _choose_group(group: int) -> void:
	_group = group
	_filters.select(group)
	_rebuild_cards()

func _rebuild_cards() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	if not _live() or not _motion.has_animation(_picked):
		_picked = &""
	var query := _search.text.strip_edges().to_lower()
	var card_group := ButtonGroup.new()
	for clip_id in _fingerprint:
		if _group != 0 and category(clip_id) != _group:
			continue
		var title := str(Action.settings(_motion.get_animation(clip_id)).get("title", display_title(clip_id)))
		if not query.is_empty() and query not in title.to_lower() and query not in clip_id.to_lower():
			continue
		var clip := _motion.get_animation(clip_id)
		var card := _button(_cards, "%s\n%s  ·  %.2f с" % [title, "Цикл" if clip.loop_mode != Animation.LOOP_NONE else "Один проход", clip.length], _choose_clip.bind(StringName(clip_id)))
		card.custom_minimum_size.y = 48
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.tooltip_text = clip_id
		card.toggle_mode = true
		card.button_group = card_group
		card.button_pressed = StringName(clip_id) == _picked
	if _cards.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Нет подходящих клипов." if _live() else "Открой мастерскую или выбери AnimationPlayer на сцене."
		_cards.add_child(empty)
	_update_controls()

func _choose_clip(clip_id: StringName) -> void:
	if not _live() or not _motion.has_animation(clip_id):
		return
	_playing = false
	_sequence.set_pressed_no_signal(false)
	_picked = clip_id
	var data := Action.settings(_motion.get_animation(_picked))
	if not data.is_empty():
		_fade_in.value = data.fade_in
		_fade_out.value = data.fade_out
	_reverse = false
	_seek(0.0)
	_rebuild_cards()
	for card in _cards.get_children():
		if card is Button and card.button_pressed:
			_scroll_to_card.call_deferred(card)

func _scroll_to_card(card: Control) -> void:
	# Undo/Redo or another selection can rebuild cards before deferred layout.
	if is_instance_valid(card) and _cards.is_ancestor_of(card):
		(_cards.get_parent() as ScrollContainer).ensure_control_visible(card)

func _seek(seconds: float) -> void:
	if _sequence.button_pressed:
		_seek_sequence(seconds)
		return
	if not _live() or not _motion.has_animation(_picked):
		return
	var clip := _motion.get_animation(_picked)
	_elapsed = clampf(seconds, 0.0, clip.length)
	if not Action.settings(clip).is_empty() and is_instance_valid(_stage_action):
		_preview_action(clip)
		_update_controls()
		return
	if is_instance_valid(_stage_action):
		_stage_action.clear()
		_stage_actor.set("staff_pose_preview", 0)
	_preview_at(_stage_player if is_instance_valid(_stage_player) else _motion, _elapsed)
	_update_controls()

func _scrub_to(seconds: float) -> void:
	_playing = false
	_reverse = false
	_seek(seconds)

func _toggle_preview() -> void:
	if not _live() or not _motion.has_animation(_picked):
		return
	_playing = not _playing
	var length := _sequence_start(STAFF_SEQUENCE.size()) if _sequence.button_pressed else _motion.get_animation(_picked).length
	if _playing and _elapsed >= length:
		_reverse = false
		_seek(0.0)
	_update_controls()

func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	var clips := _motion.get_animation_list() if _live() else PackedStringArray()
	if clips != _fingerprint:
		_rebuild()
	if not _playing or not _live() or not _motion.has_animation(_picked):
		return
	if _sequence.button_pressed:
		var end := _sequence_start(STAFF_SEQUENCE.size())
		_playing = _elapsed + dt < end
		_seek_sequence(_elapsed + dt)
		return
	var clip := _motion.get_animation(_picked)
	var length := maxf(0.001, clip.length)
	var seconds := _elapsed + (-dt if _reverse else dt)
	match clip.loop_mode:
		Animation.LOOP_NONE:
			if seconds >= length:
				_playing = false
		Animation.LOOP_LINEAR:
			seconds = fposmod(seconds, length)
		Animation.LOOP_PINGPONG:
			if seconds > length or seconds < 0.0:
				_reverse = not _reverse
			seconds = pingpong(seconds, length)
	_seek(seconds)

func _update_controls() -> void:
	var clip := _motion.get_animation(_picked) if _live() and _motion.has_animation(_picked) else null
	_caption.text = "%s  ·  %s" % [str(Action.settings(clip).get("title", display_title(_picked))), _picked] if clip != null else "Выбери клип для просмотра"
	var root := _source_root()
	var is_workshop := _live() and root != null and root.has_method("save_clips")
	var is_action := clip != null and not Action.settings(clip).is_empty()
	_action_row.visible = is_action
	_assign_action.visible = not is_action
	_assign_action.disabled = not is_workshop or clip == null
	_add_clip.disabled = not is_workshop
	_replace_clip.disabled = not is_workshop or not is_action
	_sequence.visible = is_workshop and not is_action
	_sequence.disabled = not _can_preview_sequence()
	if _sequence.disabled:
		_sequence.set_pressed_no_signal(false)
	_sequence_row.visible = _sequence.button_pressed and not _sequence.disabled
	_hand_readout.visible = _sequence_row.visible
	if not _sequence_row.visible and is_instance_valid(_hand_marker):
		_hand_marker.hide()
		_grip_marker.hide()
	_source.text = "Мира   /   %d клипов" % _fingerprint.size() if is_workshop else "%s   /   %d клипов" % [_motion.name if _live() else "Нет источника", _fingerprint.size()]
	_save.disabled = not is_workshop
	_blender_open.visible = is_workshop
	_blender_import.visible = is_workshop
	_blender_open.disabled = not is_workshop or not _can_exchange(root, clip)
	_blender_import.disabled = _blender_open.disabled
	_play.disabled = clip == null
	_play.text = "Пауза" if _playing else ("Помахать" if is_action else "Смотреть")
	_reset.disabled = clip == null
	_timeline.disabled = clip == null or not Engine.is_editor_hint()
	_scrub.editable = clip != null
	_scrub.set_block_signals(true)
	var duration := _sequence_start(STAFF_SEQUENCE.size()) if _sequence_row.visible else (clip.length if clip != null else 1.0)
	_scrub.max_value = duration
	_scrub.set_value_no_signal(_elapsed if clip != null else 0.0)
	_scrub.set_block_signals(false)
	_scrub.queue_redraw()
	_clock.text = "%.2f / %.2f с" % [_elapsed, duration] if clip != null else "—"
	if _sequence_row.visible:
		_caption.text = "%s  ·  %s  ·  %.2f с" % [STAFF_STAGES[_sequence_stage], _picked, _sequence_local]

func _open_timeline() -> void:
	if not _live() or not _motion.has_animation(_picked):
		return
	_playing = false
	var workshop := _source_root()
	if workshop.has_method("reload_staff_poses"):
		workshop.set("staff_pose_preview", 0)
	var seconds := _sequence_local if _sequence.button_pressed else _elapsed
	_motion.assigned_animation = _picked
	timeline_requested.emit(_motion)
	_preview_at(_motion, seconds)

func _preview_at(player: AnimationPlayer, seconds: float) -> void:
	if is_instance_valid(_stage_action):
		_stage_action.clear()
		_stage_actor.set("staff_pose_preview", 0)
	# The draw clip holds control curves. Supply a deterministic body pose
	# before seeking it so scrubbing backwards cannot inherit the strike pose.
	if _sequence.button_pressed and _picked == StaffMotion.DRAW:
		player.play(STAFF_SEQUENCE[0], 0.0, 0.0)
		player.seek(0.0, true, true)
	player.play(_picked, 0.0, 0.0)
	player.seek(seconds, true, true)
	player.pause()

func _preview_action(clip: Animation) -> void:
	var base := &"idle" if _action_base.selected == 0 else &"walk_adventure"
	if not _stage_player.has_animation(base):
		_feedback.text = "Для этого просмотра нужен базовый клип " + String(base)
		return
	_stage_actor.set("staff_pose_preview", 1)
	if _stage_player.assigned_animation != base or not _stage_player.is_playing():
		_stage_player.play(base, 0.18, 1.0)
	_stage_action.preview(clip, _elapsed)

func _step_frame(direction: int) -> void:
	_playing = false
	_seek(_elapsed + direction / 30.0)


func _can_preview_sequence() -> bool:
	if not _live() or not is_instance_valid(_stage_player):
		return false
	for id: StringName in STAFF_SEQUENCE:
		if not _motion.has_animation(id):
			return false
	return true


func _sequence_start(index: int) -> float:
	var seconds := 0.0
	for i in index:
		seconds += _motion.get_animation(STAFF_SEQUENCE[i]).length
	return seconds


func _toggle_sequence(_enabled: bool) -> void:
	_playing = false
	_reverse = false
	_seek(0.0)


func _jump_to_stage(index: int) -> void:
	_playing = false
	_seek_sequence(_sequence_start(index))


func _jump_to_impact() -> void:
	_playing = false
	_seek_sequence(_sequence_start(2) + _impact_time())


func _impact_time() -> float:
	var strike := _motion.get_animation(STAFF_SEQUENCE[2])
	return strike.get_marker_time(&"impact") if strike.has_marker(&"impact") else minf(0.38, strike.length)


func _draw_sequence_ticks() -> void:
	if not _sequence_row.visible or _scrub.max_value <= 0.0:
		return
	var knob := _scrub.get_theme_icon("grabber").get_width() * 0.5
	var length := _scrub.size.x - knob * 2.0
	for i in range(1, STAFF_SEQUENCE.size()):
		var x := knob + length * _sequence_start(i) / _scrub.max_value
		_scrub.draw_line(Vector2(x, 0.0), Vector2(x, 5.0), ACCENT, 2.0)
	var impact := knob + length * (_sequence_start(2) + _impact_time()) / _scrub.max_value
	_scrub.draw_line(Vector2(impact, 0.0), Vector2(impact, 7.0), Color("ffc266"), 2.0)


func _seek_sequence(seconds: float) -> void:
	if not _can_preview_sequence():
		return
	_elapsed = clampf(seconds, 0.0, _sequence_start(STAFF_SEQUENCE.size()))
	_sequence_stage = 0
	while _sequence_stage < STAFF_SEQUENCE.size() - 1 and _elapsed >= _sequence_start(_sequence_stage + 1):
		_sequence_stage += 1
	_picked = STAFF_SEQUENCE[_sequence_stage]
	_sequence_local = _elapsed - _sequence_start(_sequence_stage)
	if _sequence_stage == 3:
		_sequence_local = _motion.get_animation(_picked).length - _sequence_local
	_preview_at(_stage_player, _sequence_local)
	_update_controls()

func _setup_stage() -> void:
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	_stage_actor = null
	_stage_player = null
	_stage_camera = null
	_stage_action = null
	_hand_marker = null
	_grip_marker = null
	var root := _source_root()
	if root == null or not root.has_method("save_clips"):
		_viewport_box.hide()
		_stage_hint.text = "Кадр обновляется в 3D-виде открытой сцены. Открой ключи, чтобы вернуться к модели."
		return
	var packed := load(preview_scene) as PackedScene
	if packed == null:
		return
	_stage_actor = packed.instantiate() as Node3D
	_stage.add_child(_stage_actor)
	_stage_player = _stage_actor.get_node_or_null(_stage_actor.get("player_path")) as AnimationPlayer
	if _stage_player == null:
		return
	_sync_stage_source()
	_stage_player.stop()
	_stage_actor.set("staff_pose_preview", 0)
	var skeleton := _stage_actor.get_node_or_null(_stage_actor.get("skeleton_path")) as Skeleton3D
	if skeleton != null:
		_stage_action = ActionModifier.new()
		_stage_action.name = "AnimationAction"
		skeleton.add_child(_stage_action)
		var correctives := skeleton.get_node_or_null("GarmentPoseCorrectives")
		if correctives != null:
			skeleton.move_child(_stage_action, correctives.get_index())
		_hand_marker = _add_hand_marker(Color("68e9f4"), 0.018)
		_grip_marker = _add_hand_marker(Color("ffc266"), 0.011)
		skeleton.skeleton_updated.connect(_update_hand_preview.bind(skeleton))
	_stage_camera = _stage_actor.find_child("Camera3D", true, false) as Camera3D
	if _stage_camera == null:
		var cameras := _stage_actor.find_children("*", "Camera3D", true, false)
		if cameras.is_empty():
			_stage_camera = Camera3D.new()
			_stage.add_child(_stage_camera)
		else:
			_stage_camera = cameras[0] as Camera3D
	_stage_camera.make_current()
	_stage_camera.fov = 36.0
	var platform := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.85
	mesh.bottom_radius = 0.85
	mesh.height = 0.06
	platform.mesh = mesh
	platform.position.y = -0.031
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color("303650")
	finish.roughness = 0.92
	platform.material_override = finish
	_stage.add_child(platform)
	_viewport_box.show()
	_stage_hint.text = "Потяни мышью, чтобы повернуть модель. Колесо — масштаб."
	_update_camera()
	if not _picked.is_empty() and _stage_player.has_animation(_picked):
		_seek(_elapsed)


func _add_hand_marker(color: Color, radius: float) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	marker.mesh = sphere
	var finish := StandardMaterial3D.new()
	finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	finish.no_depth_test = true
	finish.albedo_color = color
	marker.material_override = finish
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(marker)
	marker.hide()
	return marker


func _open_contact_trace() -> void:
	var traces := ConfigFile.new()
	traces.load(StaffMotion.CONTACT_TRACE_PATH)
	var window := Window.new()
	window.title = "Игровой контакт · покадровый просмотр"
	window.transient = true
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	window.add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var toolbar := HBoxContainer.new()
	layout.add_child(toolbar)
	var action := OptionButton.new()
	action.add_item("Калитка · Мира")
	action.add_item("Ящик · Кай")
	toolbar.add_child(action)
	var hand := OptionButton.new()
	hand.add_item("Правая кисть")
	hand.add_item("Левая кисть")
	toolbar.add_child(hand)
	var plot := Control.new()
	plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(plot)
	_label(layout, "Вид сбоку · фиолетовый — локоть · голубой — кисть · оранжевый — цель", 12, Color("a7acc5"))
	var readout := _label(layout, "", 14)
	var scrub := HSlider.new()
	scrub.step = 1.0
	scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var playback := HBoxContainer.new()
	layout.add_child(playback)
	_button(playback, "−1", func() -> void: scrub.value -= 1.0)
	playback.add_child(scrub)
	_button(playback, "+1", func() -> void: scrub.value += 1.0)
	var selected_frames := func() -> Array:
		return traces.get_value("door" if action.selected == 0 else "crate", "frames", [])
	plot.draw.connect(func() -> void:
		var frames: Array = selected_frames.call()
		if frames.is_empty():
			readout.text = "Сыграй это действие в Godot и снова открой окно."
			return
		var frame: Dictionary = frames[int(scrub.value)]
		var sample: Dictionary = frame.hands[hand.selected]
		readout.text = "%d мс · %s · IK %.0f%% · кисть → цель %.1f см" % [
			frame.ms, frame.phase, sample.ik * 100.0, sample.wrist.distance_to(sample.target) * 100.0]
		var project := func(point: Vector3) -> Vector2:
			return Vector2(plot.size.x * 0.40, plot.size.y * 0.94) + Vector2(point.z, -point.y) * (plot.size.y * 0.48)
		var shoulder: Vector2 = project.call(sample.shoulder)
		var elbow: Vector2 = project.call(sample.elbow)
		var wrist: Vector2 = project.call(sample.wrist)
		var target: Vector2 = project.call(sample.target)
		plot.draw_polyline(PackedVector2Array([shoulder, elbow, wrist]), ACCENT, 3.0, true)
		plot.draw_circle(elbow, 5.0, ACCENT)
		plot.draw_circle(wrist, 5.0, Color.SKY_BLUE)
		if sample.ik > 0.01:
			plot.draw_arc(target, 9.0, 0.0, TAU, 24, Color.ORANGE, 2.0, true)
	)
	var reset := func() -> void:
		scrub.max_value = maxi(0, selected_frames.call().size() - 1)
		scrub.set_value_no_signal(0.0)
		plot.queue_redraw()
	action.item_selected.connect(func(_index: int) -> void: reset.call())
	hand.item_selected.connect(func(_index: int) -> void: plot.queue_redraw())
	scrub.value_changed.connect(func(_value: float) -> void: plot.queue_redraw())
	reset.call()
	window.popup_centered(Vector2i(660, 420))


func _update_hand_preview(skeleton: Skeleton3D) -> void:
	if not _sequence_row.visible or not is_visible_in_tree() or not is_instance_valid(_hand_marker):
		return
	var staff := _stage_actor.get_node_or_null(_stage_actor.get("staff_path")) as Node3D
	if staff == null:
		return
	var left := _hand_choice.selected == 1
	var bones: Dictionary = staff.get_parent().get_meta("hoshi_bones", {})
	var bone := int(bones.get("leftHand" if left else "rightHand", -1))
	var grip := staff.get_node_or_null("LeftGripFrame/LeftGrip/Wrist" if left else "RightGrip/Wrist") as Marker3D
	var ik := skeleton.get_node_or_null("LeftGripIK" if left else "RightGripIK") as SkeletonModifier3D
	if bone < 0 or grip == null or ik == null:
		return
	_hand_marker.global_position = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
	_grip_marker.global_position = grip.global_position
	_hand_marker.show()
	_grip_marker.show()
	_hand_readout.text = "Голубая · кисть    Оранжевая · цель хвата    %.1f см    IK %.0f%%" % [
		_hand_marker.global_position.distance_to(_grip_marker.global_position) * 100.0, ik.influence * 100.0,
	]

func _sync_stage_source() -> void:
	if not is_instance_valid(_stage_player) or not _live():
		return
	for key: StringName in _stage_player.get_animation_library_list():
		if not _motion.has_animation_library(key) or _stage_player.get_animation_library(key) != _motion.get_animation_library(key):
			_stage_player.remove_animation_library(key)
	for key: StringName in _motion.get_animation_library_list():
		if not _stage_player.has_animation_library(key):
			_stage_player.add_animation_library(key, _motion.get_animation_library(key))
	var root := _source_root()
	var poses: Resource = root.get("staff_poses")
	if poses != null:
		_stage_actor.set("staff_poses", poses.duplicate())
	var socket := _stage_actor.get_node_or_null(_stage_actor.get("socket_path")) as Node3D
	var live_socket := root.get_node_or_null(root.get("socket_path")) as Node3D
	if socket != null and live_socket != null:
		socket.transform = live_socket.transform

func _set_camera_angle(yaw: float) -> void:
	_yaw = yaw
	_update_camera()

func _update_camera() -> void:
	if not is_instance_valid(_stage_camera):
		return
	var focus := Vector3(0.0, 0.94, 0.0)
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_stage_camera.look_at_from_position(focus + offset * _distance, focus)

func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_distance = clampf(_distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 1.7, 7.0)
	elif event is InputEventMouseMotion and _dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			_dragging = false
			return
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.008, -0.65, 0.82)
	_update_camera()

func _save_library() -> void:
	var root := _source_root()
	if not _live() or root == null or not root.has_method("save_clips"):
		return
	_feedback.text = "Клипы сохранены в библиотеку." if root.save_clips() else "Сохранение не удалось. Подробности в выводе Godot."


func _can_exchange(workshop: Node, clip: Animation) -> bool:
	if clip == null or "/" in String(_picked) or not workshop.has_method("save_clips"):
		return false
	var skeleton := workshop.get_node_or_null(workshop.get("skeleton_path")) as Skeleton3D
	if skeleton == null:
		return false
	var avatar := _motion.get_node(_motion.root_node)
	for track in clip.get_track_count():
		if BlenderExchange.bone_track(clip, track, skeleton, avatar):
			return true
	return false


func _blender_directory() -> String:
	return ProjectSettings.globalize_path(BlenderExchange.WORK_DIR.path_join(String(_picked).validate_filename()))


func _open_blender() -> void:
	var settings := EditorInterface.get_editor_settings() if Engine.is_editor_hint() else null
	var executable := str(settings.get_setting(BlenderExchange.EDITOR_SETTING)) if settings != null and settings.has_setting(BlenderExchange.EDITOR_SETTING) else ""
	if executable.is_empty():
		executable = OS.get_environment("EMBER_BLENDER_EXE")
	if executable.is_empty() and OS.get_name() == "Windows":
		executable = OS.get_environment("ProgramFiles(x86)").path_join("Steam/steamapps/common/Blender/blender.exe")
	if FileAccess.file_exists(executable):
		_launch_blender(executable)
		return
	var dialog := FileDialog.new()
	dialog.title = "Выбери исполняемый файл Blender"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	if OS.get_name() == "Windows":
		dialog.filters = PackedStringArray(["*.exe ; Программа"])
	add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(func(path: String):
		if settings != null:
			settings.set_setting(BlenderExchange.EDITOR_SETTING, path)
		_launch_blender(path)
		dialog.queue_free())
	dialog.popup_centered_ratio(0.70)


func _launch_blender(executable: String) -> void:
	var workshop := _source_root()
	if not _live() or not _motion.has_animation(_picked):
		return
	var clip := _motion.get_animation(_picked)
	if not _can_exchange(workshop, clip):
		return
	_playing = false
	var dir := _blender_directory()
	var project := dir.path_join("Mira.blend")
	var source := dir.path_join("source.glb")
	var error := DirAccess.make_dir_recursive_absolute(dir)
	if error == OK and not FileAccess.file_exists(project):
		error = BlenderExchange.export_clip(workshop, clip, _picked, source)
	if error != OK:
		_feedback.text = "Не удалось подготовить клип: " + error_string(error)
		return
	var helper := ProjectSettings.globalize_path(BlenderExchange.HELPER)
	var pid := OS.create_process(executable, PackedStringArray([
		"--factory-startup", "--disable-autoexec", "--python", helper, "--",
		source, project, dir.path_join("return.glb"),
	]))
	_feedback.text = "В Blender: N → Ember → Вернуть клип в Ember." if pid > 0 else "Blender не запустился."


func _return_from_blender() -> void:
	var workshop := _source_root()
	if not _live() or not _motion.has_animation(_picked) or (undo_history == null and local_undo == null):
		return
	_playing = false
	var path := _blender_directory().path_join("return.glb")
	if not FileAccess.file_exists(path):
		_feedback.text = "Сначала верни этот клип через панель Ember в Blender."
		return
	var library := _motion.get_animation_library(&"")
	var previous := library.get_animation(_picked)
	var imported := BlenderExchange.import_clip(workshop, previous, _picked, path)
	if imported == null:
		_feedback.text = "Импорт не принят: нужен один клип на совместимом скелете Миры."
		return
	_commit_action_clip(_picked, imported, "Вернуть ключи из Blender", false)
	_feedback.text = "Ключи возвращены. Проверь клип и нажми «Сохранить клипы»."


func _replace_exchange_clip(library: AnimationLibrary, key: StringName, clip: Animation) -> void:
	if library.has_animation(key):
		library.remove_animation(key)
	if clip != null:
		library.add_animation(key, clip)
		_picked = key
	if _live():
		_sync_stage_source()
		_rebuild()
		_seek(_elapsed)

func _commit_action_clip(key: StringName, clip: Animation, label: String, select_result := true) -> String:
	var library := _motion.get_animation_library(&"")
	var previous := library.get_animation(key) if library.has_animation(key) else null
	if undo_history != null:
		undo_history.create_action(label, UndoRedo.MERGE_DISABLE, _source_root())
		undo_history.add_do_method(self, "_replace_exchange_clip", library, key, clip)
		undo_history.add_undo_method(self, "_replace_exchange_clip", library, key, previous)
		undo_history.commit_action()
	elif local_undo != null:
		local_undo.create_action(label)
		local_undo.add_do_method(_replace_exchange_clip.bind(library, key, clip))
		local_undo.add_undo_method(_replace_exchange_clip.bind(library, key, previous))
		local_undo.commit_action()
	else:
		return "Нет истории отмены: изменение не выполнено."
	if select_result:
		_choose_clip(key)
	return ""

func import_action_file(path: String, key: StringName, title: String, replace := false) -> String:
	if not _live() or not String(key).is_valid_identifier():
		return "ID: буквы, цифры и подчёркивание; первая буква не должна быть цифрой."
	var library := _motion.get_animation_library(&"")
	if library == null or library.has_animation(key) != replace:
		return "Для нового клипа нужен свободный ID; замена должна быть выбрана явно."
	if replace and Action.settings(library.get_animation(key)).is_empty():
		return "Здесь заменяются только клипы действий. Для игровых клипов используй возврат из Blender."
	var clip := BlenderExchange.import_new_clip(_source_root(), path)
	if clip == null:
		return "Нужен один GLB-клип на совместимом скелете. Старый клип сохранён."
	var skeleton := _source_root().get_node(_source_root().get("skeleton_path")) as Skeleton3D
	var previous := Action.settings(library.get_animation(key)) if replace else {}
	clip = Action.configure(clip, skeleton, title, previous.get("fade_in", 0.15), previous.get("fade_out", 0.20))
	var error := Action.validate(clip, skeleton)
	return error if not error.is_empty() else _commit_action_clip(key, clip, "Заменить клип действия" if replace else "Добавить клип действия")

func _assign_left_action() -> void:
	if not _live() or not _motion.has_animation(_picked):
		return
	var skeleton := _source_root().get_node(_source_root().get("skeleton_path")) as Skeleton3D
	var previous := _motion.get_animation(_picked)
	var clip := Action.configure(previous, skeleton, str(Action.settings(previous).get("title", "Помахать")), _fade_in.value, _fade_out.value)
	var target := _picked
	if Action.settings(previous).is_empty():
		target = StringName(String(_picked) + "_left_action")
		var suffix := 2
		while _motion.has_animation(target):
			target = StringName(String(_picked) + "_left_action_" + str(suffix))
			suffix += 1
	var error := Action.validate(clip, skeleton)
	if error.is_empty():
		error = _commit_action_clip(target, clip, "Назначить действие левой руки")
	_feedback.text = error if not error.is_empty() else "Назначение записано в клип. «Сохранить клипы» сохраняет его вместе с библиотекой."

func _select_action_file(replace: bool) -> void:
	if not _live():
		return
	var dialog := FileDialog.new()
	dialog.title = "Заменить выбранный клип" if replace else "Добавить новый клип"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.glb ; Один клип на совместимом скелете"])
	add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(func(path: String) -> void:
		dialog.queue_free()
		_show_import_assignment(path, replace))
	dialog.popup_centered_ratio(0.65)

func _show_import_assignment(path: String, replace: bool) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Заменить клип — исходный доступен через Undo" if replace else "Добавить клип → Левая рука"
	dialog.ok_button_text = "Заменить" if replace else "Добавить"
	var box := VBoxContainer.new(); dialog.add_child(box)
	_label(box, path.get_file(), 14)
	_label(box, "ID в библиотеке", 13)
	var id := LineEdit.new(); id.text = String(_picked) if replace else path.get_file().get_basename().replace("-", "_"); id.editable = not replace; box.add_child(id)
	_label(box, "Название действия", 13)
	var title := LineEdit.new(); title.text = "Помахать"; box.add_child(title)
	_label(box, "Слот: Левая рука · Стойка и ходьба · Правая рука сохраняется", 13)
	add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(func() -> void:
		var error := import_action_file(path, StringName(id.text), title.text, replace)
		_feedback.text = error if not error.is_empty() else "Клип добавлен. Проверь стоя/на ходу и сохрани библиотеку."
		dialog.queue_free())
	dialog.popup_centered(Vector2i(600, 250))

static func category(clip_id: String) -> int:
	var id := clip_id.get_slice("/", clip_id.get_slice_count("/") - 1).to_lower().trim_suffix("_stowed")
	if id.begins_with("idle") or "stance" in id:
		return 1
	if id.begins_with("walk") or id.begins_with("jog") or id.begins_with("run") or id.begins_with("sprint"):
		return 2
	if id.begins_with("swim") or id in ["fall", "land", "roll", "jump", "cable_hang"]:
		return 3
	if id.begins_with("staff") or "attack" in id or "strike" in id:
		return 4
	if id.begins_with("crate") or id.begins_with("door") or id.begins_with("carry"):
		return 5
	return 6

static func display_title(clip_id: String) -> String:
	var id := clip_id.get_slice("/", clip_id.get_slice_count("/") - 1)
	var title := str(TITLES.get(id.trim_suffix("_stowed"), id.replace("_", " ")))
	return title + " · посох за спиной" if id.ends_with("_stowed") else title

