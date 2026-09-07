@tool
class_name EmberContentMigrationDashboard
extends PanelContainer
## Filterable view over EmberContentMigrationReport. A bounded batch action is
## disabled until the exact current candidates pass strict in-memory parity.

signal refresh_requested
signal save_requested
signal close_requested
signal preflight_requested(model_ids: Array[String])
signal migrate_batch_requested(model_ids: Array[String])

const Report = preload("res://addons/ember_import/ember_content_migration_report.gd")
const VoxelBatches = preload("res://addons/ember_import/ember_voxel_migration_batches.gd")
const ACTIVE_BATCH_ID := "fan_town_ready"
const DOMAIN_FILTERS := [
	{"id": "all", "label": "Все разделы"},
	{"id": "voxel", "label": "Voxel"},
	{"id": "action", "label": "Цепочки"},
	{"id": "dialogue", "label": "Диалоги"},
	{"id": "item", "label": "Предметы"},
	{"id": "shop", "label": "Магазины"},
	{"id": "vn", "label": "VN-арт"},
]
const STATE_FILTERS := [
	{"id": "all", "label": "Все состояния"},
	{"id": "legacy", "label": "Осталось в legacy"},
	{"id": "native", "label": "Уже в Godot"},
	{"id": "attention", "label": "Требует внимания"},
	{"id": "scene_used", "label": "Используется сценой"},
	{"id": "sandbox_batch", "label": "Sandbox-партия"},
	{"id": "fan_town_ready_batch", "label": "fan_town: готовые prefab"},
]

var _report: Dictionary = {}
var _visible_entries: Array[Dictionary] = []
var _built := false
var _domain_filter: OptionButton
var _state_filter: OptionButton
var _search: LineEdit
var _rows_summary: Label
var _items: ItemList
var _detail_title: Label
var _detail: RichTextLabel
var _preflight_status: Label
var _preflight: Button
var _migrate_batch: Button
var _approved_batch_ids: Array[String] = []


func _ready() -> void:
	_ensure_ui()


func set_report(report: Dictionary) -> void:
	_ensure_ui()
	_report = report.duplicate(true)
	_approved_batch_ids.clear()
	_migrate_batch.disabled = true
	var candidate_count := _active_candidate_ids().size()
	_preflight.disabled = candidate_count == 0
	if candidate_count == 0:
		_preflight_status.text = "%s уже перенесена в Godot; повторный перенос не требуется." % _active_batch_label()
		_preflight_status.modulate = Color(0.55, 0.84, 0.70)
	else:
		_preflight_status.text = "Dry-run ещё не выполнен; до него перенос недоступен."
		_preflight_status.modulate = Color.WHITE
	_refresh_rows()


func set_filter(domain_id: String, state_id: String, query := "") -> void:
	_ensure_ui()
	_select_option(_domain_filter, domain_id)
	_select_option(_state_filter, state_id)
	_search.text = query
	_refresh_rows()


func visible_entries() -> Array[Dictionary]:
	return _visible_entries.duplicate(true)


func set_preflight(parity_report: Dictionary) -> void:
	_ensure_ui()
	var candidate_ids := _active_candidate_ids()
	var reported_ids: Array[String] = []
	for raw_entry in parity_report.get("entries", []):
		reported_ids.append(str((raw_entry as Dictionary).get("id", "")))
	var approved := (
		bool(parity_report.get("ok", false))
		and int(parity_report.get("passed", 0)) == candidate_ids.size()
		and reported_ids == candidate_ids
	)
	if approved:
		_approved_batch_ids = candidate_ids
		_migrate_batch.disabled = false
		_preflight_status.text = "Dry-run: %d/%d прошли за %d мс · файлы не изменены." % [
			int(parity_report.get("passed", 0)),
			int(parity_report.get("total", 0)),
			int(parity_report.get("duration_ms", 0)),
		]
		_preflight_status.modulate = Color(0.55, 0.84, 0.70)
	else:
		_approved_batch_ids.clear()
		_migrate_batch.disabled = true
		_preflight_status.text = "Dry-run не пройден: %d ошибок. Перенос заблокирован." % int(
			parity_report.get("failed", 0)
		)
		_preflight_status.modulate = Color(0.96, 0.55, 0.42)


func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	name = "ContentMigrationDashboard"
	custom_minimum_size = Vector2(900.0, 560.0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)

	var header := HBoxContainer.new()
	body.add_child(header)
	var title := Label.new()
	title.text = "МИГРАЦИЯ КОНТЕНТА · G1/G2"
	title.add_theme_font_size_override("font_size", 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var safety_badge := Label.new()
	safety_badge.text = "СНАЧАЛА DRY-RUN"
	safety_badge.modulate = Color(0.55, 0.84, 0.70)
	header.add_child(safety_badge)

	var hint := Label.new()
	hint.text = "Фильтры ничего не меняют. Перенос доступен только для точной проверенной партии, одной операцией Ctrl+Z/Redo; schema остаётся прежней."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	body.add_child(filters)
	_domain_filter = _option(DOMAIN_FILTERS)
	_domain_filter.name = "MigrationDomainFilter"
	_domain_filter.tooltip_text = "Ограничить список одним видом контента."
	_domain_filter.item_selected.connect(func(_index: int) -> void: _refresh_rows())
	filters.add_child(_domain_filter)
	_state_filter = _option(STATE_FILTERS)
	_state_filter.name = "MigrationStateFilter"
	_state_filter.tooltip_text = "Показать ownership, проблемы или одну из проверяемых партий."
	_state_filter.item_selected.connect(func(_index: int) -> void: _refresh_rows())
	filters.add_child(_state_filter)
	_search = LineEdit.new()
	_search.name = "MigrationSearch"
	_search.placeholder_text = "Поиск по ID, ошибке или сцене…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _refresh_rows())
	filters.add_child(_search)
	var sandbox := _button("Показать sandbox-партию", func() -> void:
		set_filter("voxel", "sandbox_batch")
	)
	sandbox.name = "ShowSandboxMigrationBatch"
	sandbox.tooltip_text = "Legacy voxel-модели, которые уже используются только в проверочных agent_sandbox сценах."
	filters.add_child(sandbox)
	var fan_town := _button("Показать fan_town-партию", func() -> void:
		set_filter("voxel", "fan_town_ready_batch")
	)
	fan_town.name = "ShowFanTownReadyMigrationBatch"
	fan_town.tooltip_text = "Семь scene-used моделей с уже актуальными prefab; список партии зафиксирован."
	filters.add_child(fan_town)

	var split := HSplitContainer.new()
	split.name = "MigrationDashboardSplit"
	split.split_offset = 560
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	var list_side := VBoxContainer.new()
	list_side.custom_minimum_size.x = 500.0
	split.add_child(list_side)
	_rows_summary = Label.new()
	_rows_summary.name = "MigrationRowsSummary"
	list_side.add_child(_rows_summary)
	_items = ItemList.new()
	_items.name = "MigrationEntryList"
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items.allow_reselect = true
	_items.item_selected.connect(_on_item_selected)
	list_side.add_child(_items)

	var detail_side := VBoxContainer.new()
	detail_side.custom_minimum_size.x = 330.0
	split.add_child(detail_side)
	_detail_title = Label.new()
	_detail_title.name = "MigrationDetailTitle"
	_detail_title.text = "Выберите запись"
	_detail_title.add_theme_font_size_override("font_size", 16)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_side.add_child(_detail_title)
	_detail = RichTextLabel.new()
	_detail.name = "MigrationEntryDetail"
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_side.add_child(_detail)

	_preflight_status = Label.new()
	_preflight_status.name = "MigrationPreflightStatus"
	_preflight_status.text = "Dry-run ещё не выполнен; до него перенос недоступен."
	_preflight_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_preflight_status)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	body.add_child(footer)
	var refresh := _button("Обновить измерение", func() -> void: refresh_requested.emit())
	refresh.name = "RefreshMigrationDashboard"
	footer.add_child(refresh)
	var save := _button("Сохранить JSON", func() -> void: save_requested.emit())
	save.name = "SaveMigrationDashboardJson"
	footer.add_child(save)
	_preflight = _button("Проверить fan_town-партию", func() -> void:
		preflight_requested.emit(_active_candidate_ids())
	)
	_preflight.name = "PreflightVoxelMigrationBatch"
	_preflight.tooltip_text = "Сравнивает legacy и будущий Godot mesh в памяти, ничего не записывая."
	footer.add_child(_preflight)
	_migrate_batch = _button("Перенести проверенную партию", func() -> void:
		if not _approved_batch_ids.is_empty():
			migrate_batch_requested.emit(_approved_batch_ids.duplicate())
	)
	_migrate_batch.name = "MigrateVoxelBatch"
	_migrate_batch.disabled = true
	_migrate_batch.tooltip_text = "Создаёт только проверенные Resources и prefab одной операцией Ctrl+Z/Redo."
	footer.add_child(_migrate_batch)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var reset := _button("Сбросить фильтры", func() -> void: set_filter("all", "all"))
	reset.name = "ResetMigrationDashboardFilters"
	footer.add_child(reset)
	var close := _button("Закрыть", func() -> void: close_requested.emit())
	close.name = "CloseMigrationDashboard"
	footer.add_child(close)


func _refresh_rows() -> void:
	if not _built:
		return
	_visible_entries = Report.filtered_entries(
		_report,
		_selected_id(_domain_filter),
		_selected_id(_state_filter),
		_search.text,
	)
	_items.clear()
	for entry in _visible_entries:
		var index := _items.add_item(_row_label(entry))
		_items.set_item_metadata(index, entry)
		_items.set_item_custom_fg_color(index, _row_color(entry))
	var all_count := Report.filtered_entries(_report).size()
	_rows_summary.text = "%d из %d записей" % [_visible_entries.size(), all_count]
	if _selected_id(_state_filter) == "sandbox_batch" and not _visible_entries.is_empty():
		_rows_summary.text += (
			" · партия уже перенесена в Godot"
			if _sandbox_candidate_ids().is_empty()
			else " · безопасный первый кандидат, перенос отдельно"
		)
	if _selected_id(_state_filter) == "fan_town_ready_batch" and not _visible_entries.is_empty():
		_rows_summary.text += (
			" · партия уже перенесена в Godot"
			if _active_candidate_ids().is_empty()
			else " · 7 готовых prefab, требуется dry-run"
		)
	if _visible_entries.is_empty():
		_detail_title.text = "Ничего не найдено"
		_detail.text = "Измените раздел, состояние или строку поиска."
	else:
		_items.select(0)
		_show_detail(_visible_entries[0])


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _items.item_count:
		return
	var entry: Dictionary = _items.get_item_metadata(index)
	_show_detail(entry)


func _show_detail(entry: Dictionary) -> void:
	_detail_title.text = str(entry.get("id", "Без ID"))
	var lines := PackedStringArray([
		"Раздел: %s" % _domain_title(str(entry.get("domain", ""))),
		"Владелец: %s" % _owner_title(str(entry.get("owner", ""))),
		"Состояние: %s" % _status_title(str(entry.get("status", ""))),
	])
	if str(entry.get("domain", "")) == "voxel":
		lines.append("Тип: %s" % ("Surface" if entry.get("kind", "model") == "surface" else "Voxel-модель"))
		lines.append("Prefab: %s" % _derived_title(str(entry.get("derived_status", ""))))
		lines.append("Используется сценами: %d" % int(entry.get("reference_count", 0)))
		var prefab_path := str(entry.get("prefab_path", ""))
		if not prefab_path.is_empty():
			lines.append("\nПроизводный файл:\n%s" % prefab_path)
	_append_list(lines, "\nValidation:", entry.get("errors", []))
	_append_list(lines, "\nPrefab:", entry.get("derived_errors", []))
	_append_list(lines, "\nСцены:", entry.get("referenced_in", []))
	if lines.size() <= 3:
		lines.append("\nДополнительных проблем не найдено.")
	_detail.text = "\n".join(lines)


func _append_list(lines: PackedStringArray, heading: String, values: Array) -> void:
	if values.is_empty():
		return
	lines.append(heading)
	for value in values:
		lines.append("• %s" % str(value))


func _row_label(entry: Dictionary) -> String:
	var parts := PackedStringArray([
		_domain_title(str(entry.get("domain", ""))),
		str(entry.get("id", "")),
		_owner_title(str(entry.get("owner", ""))),
	])
	var derived := str(entry.get("derived_status", ""))
	if not derived.is_empty() and derived != "not_required":
		parts.append("prefab %s" % _derived_title(derived).to_lower())
	var references := int(entry.get("reference_count", 0))
	if references > 0:
		parts.append(_scene_count_title(references))
	return "  ·  ".join(parts)


func _row_color(entry: Dictionary) -> Color:
	if Report.entry_needs_attention(entry):
		return Color(0.96, 0.70, 0.38)
	if str(entry.get("owner", "")) == "native":
		return Color(0.62, 0.88, 0.70)
	return Color(0.82, 0.82, 0.84)


func _option(definitions: Array) -> OptionButton:
	var option := OptionButton.new()
	for definition in definitions:
		option.add_item(str((definition as Dictionary).get("label", "")))
		option.set_item_metadata(option.item_count - 1, str((definition as Dictionary).get("id", "")))
	return option


func _button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	return button


func _selected_id(option: OptionButton) -> String:
	if option.selected < 0:
		return "all"
	return str(option.get_item_metadata(option.selected))


func _select_option(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
	option.select(0)


func _sandbox_candidate_ids() -> Array[String]:
	var result: Array[String] = []
	for entry in Report.filtered_entries(_report, "voxel", "sandbox_pending"):
		result.append(str(entry.get("id", "")))
	return result


func _active_candidate_ids() -> Array[String]:
	var result: Array[String] = []
	for entry in Report.filtered_entries(_report, "voxel", "%s_pending" % ACTIVE_BATCH_ID):
		result.append(str(entry.get("id", "")))
	return result


func _active_batch_label() -> String:
	return VoxelBatches.label(ACTIVE_BATCH_ID)


func _domain_title(domain_name: String) -> String:
	match domain_name:
		"action": return "Цепочки"
		"dialogue": return "Диалоги"
		"item": return "Предметы"
		"shop": return "Магазины"
		"vn": return "VN-арт"
		_: return "Voxel"


func _owner_title(owner: String) -> String:
	match owner:
		"native": return "Godot"
		"legacy": return "legacy"
		_: return "нет владельца"


func _status_title(status: String) -> String:
	match status:
		"native": return "готово в Godot"
		"legacy": return "ожидает переноса"
		"invalid": return "ошибка validation"
		_: return "не найдено"


func _derived_title(status: String) -> String:
	match status:
		"ready": return "готов"
		"stale": return "устарел"
		"missing": return "отсутствует"
		"invalid": return "повреждён"
		_: return "не требуется"


func _scene_count_title(count: int) -> String:
	var last_two := count % 100
	var last := count % 10
	if last == 1 and last_two != 11:
		return "%d сцена" % count
	if last in [2, 3, 4] and not last_two in [12, 13, 14]:
		return "%d сцены" % count
	return "%d сцен" % count
