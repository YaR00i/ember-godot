@tool
extends VBoxContainer
## Common native-editor creation workflow; no private viewport or tree renderer.
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Session = preload("res://addons/ember_import/ember_voxel_generation_session.gd")
const Presets = preload("res://addons/ember_import/ember_voxel_generator_presets.gd")
signal assets_changed(model_id: String)
signal edit_requested(model_id: String)
signal close_requested
signal studio_requested

var session := Session.new()
var presets := Presets.new()
var recipe: Resource
var history := UndoRedo.new()
var controls := {}
var context := {}
var _preview_root: Node3D
var _title: LineEdit
var _seed: SpinBox
var _count: SpinBox
var _status: Label
var _generate: Button
var _cancel: Button
var _save: Button
var _preset: OptionButton
var _preset_name: LineEdit
var _preset_entries: Array[Dictionary] = []
var _candidates: VBoxContainer
var _fields: VBoxContainer
var _advanced: VBoxContainer
var _syncing := false
var _step_queued := false
var candidate_controls := {}
var active_id := ""
var candidate_recipe: Resource
var suspended := false
var solo := false
var _candidate_title: Label
var _candidate_fields: VBoxContainer
var _apply: Button
var _discard: Button
var _selecting_preview := false
var _history_filter: OptionButton
var _history_filter_code := 0
var _history_page := 0
var _history_label: Label
var _page_label: Label
var _pending_previews: Array[String] = []
var _pending_saves: Array[String] = []
var _saved_in_pass := 0
var _scan_lease: RefCounted
const HISTORY_PAGE_SIZE := 40


func _ready() -> void:
	name = "EmberGenerationWorkspace"
	custom_minimum_size.x = 280
	var head := HBoxContainer.new()
	add_child(head)
	var label := Label.new()
	label.text = "Мастерская генерации · Дерево"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	_button(head, "Открыть вкладку 3D", func(): studio_requested.emit())
	var close_button := _button(head, "Закрыть набор", request_close)
	close_button.tooltip_text = "Несохранённые варианты будут удалены после подтверждения; объекты в библиотеке останутся."
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(340, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fields)
	var batch_label := Label.new()
	batch_label.text = "СОЗДАНИЕ · НАСТРОЙКИ НОВОЙ ПАРТИИ"
	_fields.add_child(batch_label)
	_preset = OptionButton.new()
	_preset.item_selected.connect(_use_preset)
	_fields.add_child(_preset)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "Имя нового пресета"
	_preset_name.max_length = 80
	var preset_toggle := CheckButton.new()
	preset_toggle.text = "Сохранить свой пресет…"
	_fields.add_child(preset_toggle)
	var preset_save := VBoxContainer.new()
	_fields.add_child(preset_save)
	preset_save.add_child(_preset_name)
	_button(preset_save, "Сохранить настройки как пресет", _save_preset)
	preset_save.hide()
	preset_toggle.toggled.connect(func(value: bool): preset_save.visible = value)
	_title = LineEdit.new()
	_title.text = "Большое лиственное дерево"
	_title.max_length = 160
	_title.tooltip_text = "Название семейства. Другое название начинает новое семейство; отмеченные прежние варианты остаются."
	_fields.add_child(_title)
	recipe = Generator.default_recipe(Generator.LARGE_TREE)
	for field in Generator.creation_fields(recipe.generator_id):
		if not field.get("advanced", false): _make_field(_fields, field)
	var advanced_toggle := CheckButton.new()
	advanced_toggle.text = "Дополнительные настройки"
	_fields.add_child(advanced_toggle)
	_advanced = VBoxContainer.new()
	_fields.add_child(_advanced)
	_advanced.hide()
	advanced_toggle.toggled.connect(func(value: bool): _advanced.visible = value)
	for field in Generator.creation_fields(recipe.generator_id):
		if field.get("advanced", false): _make_field(_advanced, field)
	_seed = _number(_fields, "Начальный seed", 0, 2147483647, 1)
	_seed.value_changed.connect(func(value: float):
		if _syncing or recipe.seed == int(value): return
		var next := recipe.duplicate(true)
		next.seed = int(value)
		_change_recipe(next)
	)
	_count = _number(_fields, "Вариантов за проход", 1, 4, 4)
	var buttons := HBoxContainer.new()
	_fields.add_child(buttons)
	_button(buttons, "↶ Настройки", undo_local)
	_button(buttons, "↷", redo_local)
	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(actions)
	var command_row := HBoxContainer.new()
	actions.add_child(command_row)
	_generate = _button(command_row, "Сгенерировать варианты в 3D", generate)
	_cancel = _button(command_row, "Остановить", cancel)
	_cancel.tooltip_text = "Остановка между полностью собранными вариантами"
	_cancel.disabled = true
	var views := HBoxContainer.new()
	actions.add_child(views)
	_button(views, "Последняя партия в 3D", _show_last_batch)
	_button(views, "Показать сравнение · F", _select_all_previews)
	_history_label = Label.new()
	actions.add_child(_history_label)
	_history_filter = OptionButton.new()
	_history_filter.item_selected.connect(func(index: int):
		_history_filter_code = _history_filter.get_item_id(index)
		_history_page = 0
		_rebuild_candidates()
	)
	actions.add_child(_history_filter)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(_status)
	var candidate_scroll := ScrollContainer.new()
	candidate_scroll.custom_minimum_size.y = 150
	candidate_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	candidate_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	actions.add_child(candidate_scroll)
	_candidates = VBoxContainer.new()
	_candidates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	candidate_scroll.add_child(_candidates)
	_save = _button(actions, "Сохранить выбранные в Объекты", save_chosen)
	_save.disabled = true
	var pages := HBoxContainer.new()
	actions.add_child(pages)
	_button(pages, "←", func(): _history_page = maxi(0, _history_page - 1); _rebuild_candidates())
	_page_label = Label.new()
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(_page_label)
	_button(pages, "→", func(): _history_page += 1; _rebuild_candidates())
	var edit_scroll := ScrollContainer.new()
	edit_scroll.custom_minimum_size = Vector2(310, 260)
	edit_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	edit_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(edit_scroll)
	var edit_box := VBoxContainer.new()
	edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_scroll.add_child(edit_box)
	_candidate_title = Label.new()
	_candidate_title.text = "НАСТРОЙКА · ВЫБЕРИТЕ ВАРИАНТ"
	edit_box.add_child(_candidate_title)
	var edit_commands := HBoxContainer.new()
	edit_box.add_child(edit_commands)
	_apply = _button(edit_commands, "Применить", apply_candidate)
	_discard = _button(edit_commands, "Сбросить правки", discard_candidate)
	_button(edit_box, "Показать только выбранное", _show_solo)
	_candidate_fields = VBoxContainer.new()
	edit_box.add_child(_candidate_fields)
	for descriptor in Generator.editing_fields(recipe):
		var field: Dictionary = descriptor.duplicate()
		field["title"] = field.label
		_make_field(_candidate_fields, field, true)
	var edit_history := HBoxContainer.new()
	edit_box.add_child(edit_history)
	_button(edit_history, "↶ Изменения", undo_local)
	_button(edit_history, "↷", redo_local)
	_button(edit_box, "Настройки дерева → новая партия", _candidate_to_batch)
	_button(edit_box, "Новый каркас из настроек партии", regenerate_candidate)
	_sync_candidate_controls()
	_sync_controls()
	_reload_presets()
	set_process(true)
	if Engine.is_editor_hint():
		EditorInterface.get_selection().selection_changed.connect(_native_selection_changed)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _number(parent: Node, title: String, low: float, high: float, value: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.value = value
	row.add_child(spin)
	return spin


func _make_field(parent: Node, field: Dictionary, candidate_field := false) -> void:
	var key := str(field.key)
	var control: Control
	if field.has("options"):
		var option := OptionButton.new()
		for title in field.options: option.add_item(title)
		parent.add_child(option)
		option.tooltip_text = str(field.title)
		option.item_selected.connect(func(index: int): _field_changed(key, field.values[index] if field.has("values") else index + int(field.get("offset", 0)), candidate_field))
		control = option
	elif str(field.get("type", "")) == "bool":
		var toggle := CheckButton.new()
		toggle.text = str(field.title)
		parent.add_child(toggle)
		toggle.toggled.connect(func(value: bool): _field_changed(key, value, candidate_field))
		control = toggle
	elif str(field.get("type", "")) == "color":
		var color := ColorPickerButton.new()
		color.text = str(field.title)
		color.edit_alpha = false
		parent.add_child(color)
		color.color_changed.connect(func(value: Color): _field_changed(key, value, candidate_field))
		control = color
	else:
		var spin := _number(parent, str(field.title), field.min, field.max, 0)
		spin.value_changed.connect(func(value: float): _field_changed(key, int(value), candidate_field))
		control = spin
	if candidate_field: candidate_controls[key] = control
	else: controls[key] = control


func _field_changed(key: String, value: Variant, candidate_field: bool) -> void:
	if candidate_field: _change_candidate_parameter(key, value)
	else: _change_parameter(key, value)


func _change_parameter(key: String, value: Variant) -> void:
	if _syncing: return
	# Explicit type choice uses today's profile; opening saved recipes does not.
	if recipe.parameters.get(key) == value and not (key == "tree_type" and int(recipe.parameters.generation_version) != int(Generator.LargeTreeProvider.LATEST_VERSIONS[int(value)])) and not (key == "foliage_style" and Generator.LargeTreeProvider.FoliagePattern.needs_style_upgrade(recipe.parameters, int(value))): return
	var next := recipe.duplicate(true)
	next.parameters[key] = value
	# A new type choice opts into its latest form; loading old recipes does not.
	if key == "tree_type": next.parameters.generation_version = Generator.LargeTreeProvider.LATEST_VERSIONS[int(value)]
	if key == "tree_type" and int(next.parameters.foliage_style) == 2 and not Generator.LargeTreeProvider.FoliagePattern.supports_style(next.parameters, 2):
		next.parameters.foliage_style = 0
	if key == "foliage_style" and int(value) == 1 and int(recipe.parameters.get("foliage_style", 0)) == 1 and int(recipe.parameters.get("foliage_pattern_version", 1)) < 2:
		next.parameters.foliage_geometry_detail = recipe.parameters.foliage_detail
	if key == "foliage_style" and int(value) == 1: next.parameters.foliage_pattern_version = 2
	if key == "foliage_style" and int(value) == 3: next.parameters.foliage_cloud_version = 2
	if key == "bark_pattern" and bool(value): next.parameters.bark_pattern_version = 2
	next.parameters = Generator.normalized_parameters(next.generator_id, next.parameters)
	_change_recipe(next)


func _change_recipe(next: Resource) -> void:
	history.create_action("Настройки генератора")
	history.add_do_method(_apply_recipe.bind(next))
	history.add_undo_method(_apply_recipe.bind(recipe))
	history.commit_action()


func _apply_recipe(next: Resource) -> void:
	recipe = next.duplicate(true)
	_sync_controls()
	_status.text = "Настройки для следующего прохода. Уже собранные варианты не меняются."


func _sync_controls() -> void:
	if recipe == null: return
	_syncing = true
	for field in Generator.creation_fields(recipe.generator_id):
		var control: Control = controls[field.key]
		var value: Variant = recipe.parameters.get(field.key)
		control.set_block_signals(true)
		if control is SpinBox: control.value = value
		elif control is ColorPickerButton: control.color = value
		elif control is CheckButton: control.button_pressed = bool(value)
		elif control is OptionButton: control.select(field.values.find(value) if field.has("values") else int(value) - int(field.get("offset", 0)))
		if field.key == "tree_type" and control is OptionButton:
			for index in field.options.size(): control.set_item_text(index, field.options[index])
			if int(recipe.parameters.generation_version) != int(Generator.LargeTreeProvider.LATEST_VERSIONS[int(value)]):
				control.set_item_text(int(value), "%s · прежняя форма" % field.options[int(value)])
		control.set_block_signals(false)
		if field.key == "leaf_density": control.get_parent().visible = int(recipe.parameters.generation_version) == 1
		if field.key == "structure_diversity": control.get_parent().visible = Generator.LargeTreeProvider.TreeVariation.supported(recipe.parameters)
		if field.key == "foliage_amount": control.get_parent().visible = int(recipe.parameters.generation_version) >= 2
		if field.key == "foliage_style":
			control.visible = Generator.LargeTreeProvider.FoliagePattern.supported(recipe.parameters)
			control.set_item_disabled(2, not Generator.LargeTreeProvider.FoliagePattern.supports_style(recipe.parameters, 2))
		if field.key == "foliage_leaf_size":
			control.get_parent().visible = Generator.LargeTreeProvider.FoliagePattern.supported(recipe.parameters) and int(recipe.parameters.foliage_style) in [2, 3]
			control.get_parent().get_child(0).text = "Размер деталей · vox" if int(recipe.parameters.foliage_style) == 3 else "Размер листика · vox"
		if field.key == "foliage_leaf_accents": control.get_parent().visible = Generator.LargeTreeProvider.FoliagePattern.supported(recipe.parameters) and int(recipe.parameters.foliage_style) == 3
		if field.key == "foliage_detail": control.get_parent().visible = Generator.LargeTreeProvider.FoliagePattern.supported(recipe.parameters) and (int(recipe.parameters.foliage_style) == 1 or (int(recipe.parameters.foliage_style) == 3 and int(recipe.parameters.foliage_cloud_version) >= 2))
		if field.key == "foliage_pattern_strength": control.get_parent().visible = Generator.LargeTreeProvider.FoliagePattern.supported(recipe.parameters) and ((int(recipe.parameters.foliage_style) == 1 and int(recipe.parameters.foliage_pattern_version) >= 2) or (int(recipe.parameters.foliage_style) == 3 and int(recipe.parameters.foliage_cloud_version) >= 2))
		if str(field.key) in ["branch_thickness", "branch_taper", "branch_curve", "branch_start", "cluster_size", "cluster_flatten", "canopy_cohesion", "root_flare"]:
			control.get_parent().visible = int(recipe.parameters.generation_version) >= 2
		if field.key == "crown_shape": control.visible = int(recipe.parameters.generation_version) >= 2
		if field.key == "foliage_along": control.get_parent().visible = int(recipe.parameters.get("tree_type", 0)) > 0 or int(recipe.parameters.generation_version) in [9, 14]
	_count.max_value = Generator.candidate_limit(recipe)
	_seed.set_block_signals(true)
	_seed.value = recipe.seed
	_seed.set_block_signals(false)
	_syncing = false


func open_for(next_context: Dictionary, base_recipe: Resource = null) -> void:
	close_session()
	context = next_context
	suspended = false
	recipe = Session.preset_recipe(base_recipe) if base_recipe != null else Generator.creation_presets(Generator.LARGE_TREE)[0].recipe.duplicate(true)
	_title.text = str(base_recipe.family_title) if base_recipe != null and not str(base_recipe.family_title).is_empty() else "Дерево"
	_sync_controls()
	_reload_presets()
	_status.text = "Мастерская 3D: номера над деревьями совпадают со списком. Настройки партии — слева, выбранного дерева — справа."


func _reload_presets() -> void:
	_preset.clear()
	_preset.add_item("Пресет · текущие настройки")
	_preset_entries = Generator.creation_presets(recipe.generator_id)
	_preset_entries.append_array(presets.list_presets(recipe.generator_id))
	for entry in _preset_entries: _preset.add_item(str(entry.name))


func _use_preset(index: int) -> void:
	if index <= 0: return
	var next := Session.preset_recipe(_preset_entries[index - 1].recipe)
	_change_recipe(next)


func _save_preset() -> void:
	var next := recipe.duplicate(true)
	next.seed = int(_seed.value)
	var path := presets.save_preset(next, _preset_name.text)
	_status.text = presets.error if path.is_empty() else "Пресет сохранён: только настройки, без каркаса и объектов."
	if not path.is_empty():
		_reload_presets()
		if Engine.is_editor_hint(): preload("res://addons/ember_import/ember_editor_filesystem.gd").request()


func generate() -> void:
	if suspended or _busy() or not _draft_resolved(): return
	if not is_instance_valid(context.get("root")):
		_status.text = "Откройте 3D-сцену."
		return
	if not session.begin(recipe, _title.text, int(_count.value), int(_seed.value)):
		_status.text = session.error
		_rebuild_candidates()
		return
	_ensure_preview_root()
	active_id = ""
	candidate_recipe = null
	solo = false
	_history_filter_code = 0
	_history_page = maxi(0, floori(session.candidates.size() / float(HISTORY_PAGE_SIZE)))
	_generate.disabled = true
	_cancel.disabled = false
	_save.disabled = true
	_rebuild_candidates()
	_status.text = "Генерация по очереди · 0/%d. Отмена — между вариантами." % session.requested


func _process(_delta: float) -> void:
	if _busy() and not suspended and not _step_queued:
		_step_queued = true
		if session.running: _build_next.call_deferred()
		else: _process_work.call_deferred()


func _busy() -> bool:
	return session.running or not _pending_previews.is_empty() or not _pending_saves.is_empty()


func _ensure_preview_root() -> void:
	if is_instance_valid(_preview_root): return
	_preview_root = Node3D.new()
	_preview_root.name = "EmberGenerationPreview"
	_preview_root.set_meta(Session.PREVIEW_META, true)
	_preview_root.process_mode = Node.PROCESS_MODE_DISABLED
	context.root.add_child(_preview_root)


func _process_work() -> void:
	_step_queued = false
	if suspended or not is_instance_valid(context.get("root")): return
	if not _pending_saves.is_empty():
		var candidate := session.find_candidate(_pending_saves.pop_front())
		if not candidate.is_empty() and not candidate.saved:
			if not session.ensure_loaded(candidate):
				cancel()
				_status.text = session.error
				return
			if not candidate.creation.save_to_library(context.root, context.undo):
				var error: String = candidate.creation.error
				cancel()
				_status.text = error
				return
			_saved_in_pass += 1
			if not session.preview_ids.has(str(candidate.creation.source.model_id)):
				candidate.creation.unload_prepared_geometry()
		if _pending_saves.is_empty():
			_scan_lease = null
			if Engine.is_editor_hint(): preload("res://addons/ember_import/ember_editor_filesystem.gd").request()
		_status.text = "Сохранено %d лучших из истории · осталось %d. Размещение — отдельно." % [_saved_in_pass, _pending_saves.size()]
	elif not _pending_previews.is_empty():
		var candidate := session.find_candidate(_pending_previews.pop_front())
		if not candidate.is_empty():
			_ensure_preview_root()
			if session.make_preview(candidate, _preview_root, Vector3.ZERO, float(context.get("world_size", 1.0))) == null:
				cancel()
				_status.text = session.error
				return
			_arrange_previews(float(context.get("world_size", 1.0)))
		_status.text = "В 3D %d моделей · история содержит %d вариантов. F — центрировать выбранные." % [session.preview_ids.size(), session.candidates.size()]
	_rebuild_candidates()


func _show_last_batch() -> void:
	if suspended or _busy() or not _draft_resolved(): return
	session.clear_previews()
	active_id = ""
	candidate_recipe = null
	solo = false
	var latest: Array[Dictionary] = []
	var limit := 4
	for candidate in session.candidates:
		if candidate.batch != session.batch_number: continue
		latest.append(candidate)
		limit = mini(limit, Generator.candidate_limit(candidate.creation.recipe))
	for candidate in latest.slice(0, limit):
		_pending_previews.append(str(candidate.creation.source.model_id))
	_rebuild_candidates()


func _compare_candidate(candidate: Dictionary, value: bool) -> void:
	if suspended or _busy(): return
	var id := str(candidate.creation.source.model_id)
	if value:
		if session.preview_ids.has(id): return
		if session.preview_ids.size() >= session.compare_limit(candidate):
			_rebuild_candidates()
			_status.text = "Лимит сравнения: до 4 моделей, если есть крупные — до 2. Снимите 3D с другой модели или откройте выбранную отдельно."
			return
		_pending_previews.append(id)
	else:
		if id == active_id and not _draft_resolved():
			_rebuild_candidates()
			return
		session.unload_candidate(candidate)
		if id == active_id:
			active_id = ""
			candidate_recipe = null
		_arrange_previews(float(context.get("world_size", 1.0)))
	_rebuild_candidates()


func _build_next() -> void:
	_step_queued = false
	if not session.running: return
	if not is_instance_valid(context.get("root")) or not is_instance_valid(_preview_root):
		close_session()
		return
	var candidate := session.step()
	if not candidate.is_empty():
		var size := float(context.get("world_size", 16.0))
		session.make_preview(candidate, _preview_root, Vector3.ZERO, size)
		_arrange_previews(size)
		candidate.creation.asset_changed.connect(_asset_changed)
		candidate.creation.library_state_changed.connect(_on_library_state_changed.bind(str(candidate.creation.source.model_id)))
	recipe = recipe.duplicate(true)
	recipe.seed = session.next_seed
	_sync_controls()
	_rebuild_candidates()
	_status.text = session.error if not session.error.is_empty() else "%s %d/%d · всего %d в 3D. Отметьте лучшие; новые настройки не меняют готовые деревья." % [
		"Собрано" if session.running else "Готово", session.requested - session._remaining, session.requested, session.preview_ids.size()]
	_generate.disabled = session.running
	_cancel.disabled = not session.running


func _rebuild_candidates() -> void:
	if not active_id.is_empty() and session.find_candidate(active_id).is_empty():
		active_id = ""
		candidate_recipe = null
		solo = false
	for child in _candidates.get_children():
		_candidates.remove_child(child)
		child.queue_free()
	var chosen := 0
	_history_filter.set_block_signals(true)
	_history_filter.clear()
	_history_filter.add_item("Все партии", 0)
	_history_filter.add_item("Только лучшие", 1)
	for batch in range(1, session.batch_number + 1): _history_filter.add_item("Партия %d" % batch, batch + 1)
	for index in _history_filter.item_count:
		if _history_filter.get_item_id(index) == _history_filter_code: _history_filter.select(index)
	_history_filter.set_block_signals(false)
	var filtered: Array[Dictionary] = []
	for candidate in session.candidates:
		if candidate.chosen and not candidate.saved: chosen += 1
		if _history_filter_code == 1 and not candidate.chosen: continue
		if _history_filter_code > 1 and candidate.batch != _history_filter_code - 1: continue
		filtered.append(candidate)
	var page_count := maxi(1, ceili(filtered.size() / float(HISTORY_PAGE_SIZE)))
	_history_page = clampi(_history_page, 0, page_count - 1)
	_history_label.text = "История: %d вариантов · %d партий · в 3D: %d. ✓ Лучший — для сохранения." % [session.candidates.size(), session.batch_number, session.preview_ids.size()]
	_page_label.text = "Страница %d/%d · найдено %d" % [_history_page + 1, page_count, filtered.size()]
	for candidate in filtered.slice(_history_page * HISTORY_PAGE_SIZE, (_history_page + 1) * HISTORY_PAGE_SIZE):
		var row := HBoxContainer.new()
		_candidates.add_child(row)
		var check := CheckButton.new()
		check.text = "№ %d · партия %d · seed %d%s" % [candidate.number, candidate.batch, candidate.seed, " · сохранён" if candidate.saved else ""]
		var description := Generator.creation_description(candidate.creation.recipe)
		if not description.is_empty(): check.text += " · " + description
		check.tooltip_text = "%s · отметить для сохранения в библиотеку" % candidate.name
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.button_pressed = candidate.chosen
		check.disabled = candidate.saved or _busy() or suspended
		check.toggled.connect(func(value: bool): _choose(candidate, value))
		row.add_child(check)
		var buttons := HBoxContainer.new()
		row.add_child(buttons)
		var select_button := _button(buttons, "Настроить", func(): _select_preview(candidate))
		select_button.disabled = _busy() or suspended
		var compare := CheckBox.new()
		compare.text = "3D"
		compare.tooltip_text = "Добавить/убрать из сравнения. До 4 моделей, для крупных до 2."
		compare.button_pressed = session.preview_ids.has(str(candidate.creation.source.model_id))
		compare.disabled = _busy() or suspended
		compare.toggled.connect(func(value: bool): _compare_candidate(candidate, value))
		buttons.add_child(compare)
		if candidate.saved:
			_button(buttons, "Редактировать", func(): edit_requested.emit(candidate.creation.source.model_id))
	_save.disabled = chosen == 0 or _busy() or suspended
	_generate.disabled = _busy() or suspended
	_cancel.disabled = not _busy() or suspended
	_sync_candidate_controls()
	_refresh_visibility()


func _arrange_previews(size: float) -> void:
	var spacing := size
	for candidate in session.preview_candidates():
		var grid: Vector3i = candidate.creation.report.grid
		spacing = maxf(spacing, maxf(grid.x, grid.z) * size / candidate.creation.source.normalized_density() + size)
	var origin: Vector3 = context.get("position", Vector3.ZERO)
	origin = context.parent.to_global(origin) if is_instance_valid(context.get("parent")) else origin
	origin = context.root.to_local(origin)
	var previews := session.preview_candidates()
	for index in previews.size():
		var candidate: Dictionary = previews[index]
		if is_instance_valid(candidate.node):
			candidate.node.position = origin + Vector3(index % 2, 0, floori(index / 2.0)) * spacing + Vector3(candidate.get("pivot", Vector3.ZERO))


func _choose(candidate: Dictionary, value: bool) -> void:
	if bool(candidate.chosen) == value: return
	history.create_action("Выбор варианта")
	# History holds identity, not a discarded candidate's potentially huge mesh.
	var id := str(candidate.creation.source.model_id)
	history.add_do_method(_apply_choice.bind(id, value))
	history.add_undo_method(_apply_choice.bind(id, not value))
	history.commit_action()


func _apply_choice(model_id: String, value: bool) -> void:
	for candidate in session.candidates:
		if str(candidate.creation.source.model_id) == model_id: candidate.chosen = value
	_rebuild_candidates()


func _asset_changed(model_id: String) -> void:
	assets_changed.emit(model_id)


func _on_library_state_changed(present: bool, model_id: String) -> void:
	# Avoid a signal closure -> candidate dictionary -> Creation refcount cycle.
	for candidate in session.candidates:
		if str(candidate.creation.source.model_id) == model_id:
			candidate.saved = present
			# File Redo restores the exact published source. Never let local recipe
			# history mutate its preview after Save -> file Undo -> local edits.
			candidate.publication_locked = true
	_rebuild_candidates()


func _select_preview(candidate: Dictionary) -> void:
	if suspended or _busy(): return
	var id := str(candidate.creation.source.model_id)
	if id != active_id and not _draft_resolved(): return
	if not is_instance_valid(candidate.node):
		session.clear_previews()
		_ensure_preview_root()
		if session.make_preview(candidate, _preview_root, Vector3.ZERO, float(context.get("world_size", 1.0))) == null:
			_status.text = session.error
			return
		_arrange_previews(float(context.get("world_size", 1.0)))
	if id != active_id or candidate_recipe == null:
		active_id = id
		candidate_recipe = candidate.creation.recipe.duplicate(true)
	_sync_candidate_controls()
	_refresh_visibility()
	_rebuild_candidates()
	if not is_instance_valid(candidate.node) or not Engine.is_editor_hint(): return
	_selecting_preview = true
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(candidate.node)
	_selecting_preview = false
	_status.text = "Выбрано дерево № %d. Справа — только его параметры. F в 3D — центрировать, колесо — масштаб." % candidate.number


func _select_all_previews() -> void:
	if suspended: return
	solo = false
	_refresh_visibility()
	if not Engine.is_editor_hint(): return
	_selecting_preview = true
	EditorInterface.get_selection().clear()
	for candidate in session.candidates:
		if not is_instance_valid(candidate.node): continue
		EditorInterface.get_selection().add_node(candidate.node)
	_selecting_preview = false
	_status.text = "Набор выбран. В 3D нажмите F — центрировать; отдалитесь колесом, чтобы сравнить все варианты."


func save_chosen() -> void:
	if suspended or _busy() or not _draft_resolved() or not is_instance_valid(context.get("root")): return
	_saved_in_pass = 0
	for candidate in session.candidates:
		if not candidate.chosen or candidate.saved: continue
		_pending_saves.append(str(candidate.creation.source.model_id))
	_scan_lease = preload("res://addons/ember_import/ember_editor_filesystem.gd").defer_scans()
	_rebuild_candidates()
	_status.text = "Сохранение лучших из истории по очереди · %d вариантов." % _pending_saves.size()


func cancel() -> void:
	session.cancel()
	_pending_previews.clear()
	_pending_saves.clear()
	_scan_lease = null
	_generate.disabled = false
	_cancel.disabled = true
	_rebuild_candidates()
	_status.text = "Генерация остановлена. Готовые варианты доступны для выбора и сохранения."


func close_session() -> void:
	_pending_previews.clear()
	_pending_saves.clear()
	_scan_lease = null
	session.clear()
	if is_instance_valid(_preview_root): _preview_root.free()
	_preview_root = null
	history.clear_history()
	context = {}
	active_id = ""
	candidate_recipe = null
	solo = false
	suspended = false
	_history_filter_code = 0
	_history_page = 0
	if _candidates != null: _rebuild_candidates()
	if _generate != null: _generate.disabled = false
	if _cancel != null: _cancel.disabled = true
	_sync_candidate_controls()


func request_close() -> void:
	var unsaved := 0
	for candidate in session.candidates:
		if not candidate.saved: unsaved += 1
	if unsaved == 0 and not session.running:
		close_session()
		close_requested.emit()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Закрыть набор генерации?"
	dialog.dialog_text = "Несохранённых вариантов: %d. Они и черновик будут удалены. Уже сохранённые объекты останутся в библиотеке." % unsaved
	dialog.ok_button_text = "Удалить временный набор"
	add_child(dialog)
	dialog.confirmed.connect(func():
		dialog.hide()
		close_session()
		close_requested.emit()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.hide(); dialog.queue_free())
	dialog.popup_centered()


func _draft_dirty() -> bool:
	var candidate := session.find_candidate(active_id)
	return candidate_recipe != null and not candidate.is_empty() and candidate_recipe.parameters != candidate.creation.recipe.parameters


func _draft_resolved() -> bool:
	if not _draft_dirty(): return true
	_status.text = "У выбранного дерева есть черновик. Примените или сбросьте правки перед другой операцией."
	return false


func _sync_candidate_controls() -> void:
	if _candidate_title == null: return
	if candidate_recipe != null:
		var descriptors := Generator.editing_fields(candidate_recipe)
		var next_keys: Array[String] = []
		for descriptor in descriptors: next_keys.append(str(descriptor.key))
		var changed := next_keys.size() != candidate_controls.size()
		for key in next_keys:
			if not candidate_controls.has(key): changed = true
		if changed:
			for child in _candidate_fields.get_children():
				_candidate_fields.remove_child(child)
				child.queue_free()
			candidate_controls.clear()
			for descriptor in descriptors:
				var field: Dictionary = descriptor.duplicate()
				field["title"] = field.label
				_make_field(_candidate_fields, field, true)
	var candidate := session.find_candidate(active_id)
	var editable: bool = not candidate.is_empty() and not candidate.saved and not bool(candidate.get("publication_locked", false)) and not suspended and not _busy()
	editable = editable and candidate_recipe != null and not Generator.editing_fields(candidate_recipe).is_empty()
	_candidate_title.text = "НАСТРОЙКА · ВЫБЕРИТЕ ВАРИАНТ" if candidate.is_empty() else "НАСТРОЙКА · ДЕРЕВО № %d%s" % [candidate.number, " · сохранено" if candidate.saved else ""]
	if not candidate.is_empty() and not candidate.saved and bool(candidate.get("publication_locked", false)):
		_candidate_title.text = "ДЕРЕВО № %d · СОХРАНЕНИЕ ОТМЕНЕНО" % candidate.number
	_candidate_fields.visible = editable
	for key in candidate_controls:
		var control: Control = candidate_controls[key]
		if candidate_recipe == null: continue
		control.set_block_signals(true)
		var value: Variant = candidate_recipe.parameters.get(key)
		if control is SpinBox: control.value = value
		elif control is ColorPickerButton: control.color = value
		elif control is CheckButton: control.button_pressed = bool(value)
		elif control is OptionButton: control.select(int(value))
		if key == "foliage_style": control.set_item_disabled(2, not Generator.LargeTreeProvider.FoliagePattern.supports_style(candidate_recipe.parameters, 2))
		control.set_block_signals(false)
	_apply.disabled = not editable or not _draft_dirty()
	_discard.disabled = not _draft_dirty() or suspended


func _change_candidate_parameter(key: String, value: Variant) -> void:
	var candidate := session.find_candidate(active_id)
	if candidate.is_empty() or candidate.saved or bool(candidate.get("publication_locked", false)) or suspended or _busy() or candidate_recipe == null: return
	if candidate_recipe.parameters.get(key) == value and not (key == "foliage_style" and Generator.LargeTreeProvider.FoliagePattern.needs_style_upgrade(candidate_recipe.parameters, int(value))): return
	var next := candidate_recipe.duplicate(true)
	next.parameters[key] = value
	if key == "foliage_style" and int(value) == 1 and int(candidate_recipe.parameters.get("foliage_style", 0)) == 1 and int(candidate_recipe.parameters.get("foliage_pattern_version", 1)) < 2:
		next.parameters.foliage_geometry_detail = candidate_recipe.parameters.foliage_detail
	if key == "bark_pattern" and bool(value): next.parameters.bark_pattern_version = 2
	if key == "foliage_style" and int(value) == 1: next.parameters.foliage_pattern_version = 2
	if key == "foliage_style" and int(value) == 3: next.parameters.foliage_cloud_version = 2
	next.parameters = Generator.normalized_parameters(next.generator_id, next.parameters)
	history.create_action("Черновик дерева № %d" % candidate.number)
	history.add_do_method(_apply_candidate_draft.bind(active_id, next))
	history.add_undo_method(_apply_candidate_draft.bind(active_id, candidate_recipe))
	history.commit_action()


func _apply_candidate_draft(id: String, next: Resource) -> void:
	var candidate := session.find_candidate(id)
	if candidate.is_empty() or candidate.saved or bool(candidate.get("publication_locked", false)):
		_status.text = "Опубликованный вариант изменяется через Canvas. Ctrl+Redo восстанавливает его точные файлы; параметры можно перенести в новую партию."
		return
	active_id = id
	candidate_recipe = next.duplicate(true)
	if not session.preview_ids.has(id): solo = false
	_sync_candidate_controls()
	_refresh_visibility()
	_status.text = "Черновик дерева № %d · примените, чтобы обновить только его геометрию." % candidate.number


func discard_candidate() -> void:
	var candidate := session.find_candidate(active_id)
	if candidate.is_empty() or candidate_recipe == null or suspended: return
	var next: Resource = candidate.creation.recipe.duplicate(true)
	history.create_action("Сбросить черновик дерева")
	history.add_do_method(_apply_candidate_draft.bind(active_id, next))
	history.add_undo_method(_apply_candidate_draft.bind(active_id, candidate_recipe))
	history.commit_action()


func apply_candidate() -> void:
	if suspended or not _draft_dirty(): return
	_commit_revision(candidate_recipe)


func regenerate_candidate() -> void:
	if suspended or not _draft_resolved(): return
	var candidate := session.find_candidate(active_id)
	if candidate.is_empty() or candidate.saved: return
	var next := recipe.duplicate(true)
	next.structure = {}
	next.family_id = candidate.creation.recipe.family_id
	next.family_title = candidate.creation.recipe.family_title
	next.variation_name = candidate.creation.recipe.variation_name
	_commit_revision(next)


func _commit_revision(next: Resource) -> void:
	var candidate := session.find_candidate(active_id)
	if candidate.is_empty(): return
	var prepared := session.prepare_revision(candidate, next)
	if prepared == null:
		_status.text = session.error
		return
	var previous: Resource = candidate.creation.recipe.duplicate(true)
	var applied: Resource = prepared.recipe.duplicate(true)
	_replace_candidate(candidate, prepared)
	history.create_action("Применить настройку дерева № %d" % candidate.number)
	history.add_do_method(_rebuild_candidate.bind(active_id, applied))
	history.add_undo_method(_rebuild_candidate.bind(active_id, previous))
	history.commit_action(false)
	_status.text = "Обновлено только дерево № %d. Остальные варианты не изменены." % candidate.number


func _rebuild_candidate(id: String, next: Resource) -> void:
	var candidate := session.find_candidate(id)
	var prepared := session.prepare_revision(candidate, next)
	if prepared == null:
		_status.text = session.error
		return
	active_id = id
	_replace_candidate(candidate, prepared)


func _replace_candidate(candidate: Dictionary, prepared: RefCounted) -> void:
	if not session.preview_ids.has(str(candidate.creation.source.model_id)) or session.preview_ids.size() > Generator.candidate_limit(prepared.recipe): session.clear_previews()
	if is_instance_valid(candidate.node): candidate.node.free()
	candidate.creation = prepared
	candidate.seed = int(prepared.recipe.seed)
	candidate_recipe = prepared.recipe.duplicate(true)
	var size := float(context.get("world_size", 1.0))
	if is_instance_valid(_preview_root):
		session.make_preview(candidate, _preview_root, Vector3.ZERO, size)
		_arrange_previews(size)
	prepared.asset_changed.connect(_asset_changed)
	prepared.library_state_changed.connect(_on_library_state_changed.bind(str(prepared.source.model_id)))
	_rebuild_candidates()


func _candidate_to_batch() -> void:
	if candidate_recipe == null or not _draft_resolved(): return
	_change_recipe(Session.preset_recipe(candidate_recipe))
	_status.text = "Параметры выбранного дерева перенесены в новую партию. Теперь их можно сохранить как пресет."


func _show_solo() -> void:
	if suspended: return
	if session.find_candidate(active_id).is_empty(): return
	solo = true
	_refresh_visibility()
	var candidate := session.find_candidate(active_id)
	if Engine.is_editor_hint() and is_instance_valid(candidate.node):
		_selecting_preview = true
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(candidate.node)
		_selecting_preview = false


func _native_selection_changed() -> void:
	if _selecting_preview or suspended or _busy(): return
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.size() != 1: return
	var node: Node = selected[0]
	while node != null:
		if node.has_meta("ember_generation_candidate"):
			var candidate := session.find_candidate(str(node.get_meta("ember_generation_candidate")))
			if not candidate.is_empty() and str(candidate.creation.source.model_id) != active_id:
				if not _draft_resolved():
					var active := session.find_candidate(active_id)
					if not active.is_empty() and is_instance_valid(active.node):
						_selecting_preview = true
						EditorInterface.get_selection().clear()
						EditorInterface.get_selection().add_node(active.node)
						_selecting_preview = false
					return
				_select_preview(candidate)
			return
		node = node.get_parent()


func _refresh_visibility() -> void:
	for candidate in session.candidates:
		if not is_instance_valid(candidate.node): continue
		var selected := str(candidate.creation.source.model_id) == active_id
		candidate.node.visible = not solo or selected
		var label := candidate.node.get_node_or_null("CandidateNumber") as Label3D
		if label != null: label.modulate = Color(1.0, 0.72, 0.25) if selected else Color.WHITE


func undo_local() -> void:
	if suspended or _busy():
		_status.text = "Для истории генерации вернитесь во вкладку мастерской. История карты не затрагивается."
		return
	history.undo()


func redo_local() -> void:
	if suspended or _busy(): return
	history.redo()


## Switching native scene tabs suspends the session, rather than losing drafts.
func scene_context_changed(root: Node, undo: Object) -> void:
	if root == null or root.scene_file_path != Session.STUDIO_PATH:
		suspended = true
		session.cancel()
		_pending_previews.clear()
		_pending_saves.clear()
		_scan_lease = null
		_generate.disabled = true
		_cancel.disabled = true
		_rebuild_candidates()
		_status.text = "Мастерская приостановлена. Варианты и черновик сохранены в памяти; «Открыть вкладку 3D» — вернуться."
		return
	suspended = false
	context = {"root": root, "parent": root, "undo": undo, "world_size": 1.0, "position": Vector3.ZERO}
	if not session.candidates.is_empty() and not is_instance_valid(_preview_root):
		_preview_root = Node3D.new()
		_preview_root.name = "EmberGenerationPreview"
		_preview_root.set_meta(Session.PREVIEW_META, true)
		_preview_root.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(_preview_root)
		for candidate in session.preview_candidates(): session.make_preview(candidate, _preview_root, Vector3.ZERO, 1.0)
		_arrange_previews(1.0)
	_generate.disabled = false
	_rebuild_candidates()
	_status.text = "Мастерская активна. Выберите дерево по номеру; справа — его индивидуальные настройки."


func _exit_tree() -> void:
	close_session()
	history.free()
