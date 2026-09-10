@tool
extends VBoxContainer
## Small bridge for the migration test: light profiles and targeted voxel-prefab rebuilds.

signal reimport_requested
signal duplicate_requested(prop: EmberVoxelProp)
signal standalone_trigger_requested(anchor: Node3D)
signal voxel_prop_requested(model_id: String, anchor: Node3D)
signal voxel_library_requested
signal voxel_migrate_requested(model_id: String)
signal voxel_batch_migrate_requested(model_ids: Array[String])
signal close_requested

const SHADOW_PROFILES := [0, 2, 4, 8, 12, 16]
const VisualLibraryPicker = preload("res://addons/ember_import/ember_visual_library_picker.gd")
const VoxelVisuals = preload("res://scripts/ember_voxel_visuals.gd")
const VoxelPreviewRenderer = preload("res://addons/ember_import/ember_voxel_preview_renderer.gd")
const ContentMigrationReport = preload("res://addons/ember_import/ember_content_migration_report.gd")
const ContentMigrationDashboard = preload("res://addons/ember_import/ember_content_migration_dashboard.gd")
const VoxelMigrationParity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
const CONTENT_REPORT_PATH := "user://ember_content_migration_report.json"

var _map_label: Label
var _profile: OptionButton
var _selection_label: Label
var _source_label: Label
var _prefab_label: Label
var _status: Label
var _open_native_voxel: Button
var _migrate_selected_voxel: Button
var _open_vox: Button
var _open_json: Button
var _show_source: Button
var _rebuild: Button
var _duplicate: Button
var _voxel_library: Button
var _add_standalone_trigger: Button
var _voxel_popup: PopupPanel
var _voxel_picker: EmberVisualLibraryPicker
var _voxel_preview_renderer: EmberVoxelPreviewRenderer
var _voxel_queue_label: Label
var _voxel_owner_label: Label
var _voxel_popup_migrate: Button
var _voxel_popup_open: Button
var _voxel_popup_entries: Array[Dictionary] = []
var _content_migration_summary: Label
var _content_migration_issues: Label
var _content_migration_report: Dictionary = {}
var _content_migration_popup: PopupPanel
var _content_migration_dashboard: PanelContainer
var _selected_prop: EmberVoxelProp
var _selected_anchor: Node3D
var _source_path := ""
var _vox_path := ""
var _json_path := ""
var _source_owner := ""


func _ready() -> void:
	name = "EmberMigrationWorkflow"
	custom_minimum_size = Vector2(310, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	var selection := EditorInterface.get_selection()
	if selection and not selection.selection_changed.is_connected(_refresh_selection):
		selection.selection_changed.connect(_refresh_selection)
	refresh()


func _exit_tree() -> void:
	var selection := EditorInterface.get_selection()
	if selection and selection.selection_changed.is_connected(_refresh_selection):
		selection.selection_changed.disconnect(_refresh_selection)


func _build_ui() -> void:
	var header := HBoxContainer.new()
	header.name = "WorkflowHeader"
	add_child(header)
	var title := Label.new()
	title.text = "EMBER MIGRATION"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := _button("Закрыть", func() -> void: close_requested.emit())
	close.name = "CloseMigrationPanel"
	close.tooltip_text = "Скрыть нижнюю панель и вернуть полный 3D viewport."
	header.add_child(close)

	_status = Label.new()
	_status.name = "WorkflowStatus"
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.tooltip_text = "Статус последней операции"
	_status.visible = false
	add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.name = "WorkflowScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "WorkflowContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	_map_label = Label.new()
	_map_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_map_label)

	var light_body := _section(content, "Свет и производительность", true)
	var light_title := Label.new()
	light_title.text = "Свет: одинаковый кадр, разный бюджет"
	light_body.add_child(light_title)
	_profile = OptionButton.new()
	for count in SHADOW_PROFILES:
		_profile.add_item(_profile_name(count))
		_profile.set_item_metadata(_profile.item_count - 1, count)
	light_body.add_child(_profile)
	light_body.add_child(_button("Применить профиль", _apply_profile))

	var light_hint := Label.new()
	light_hint.text = "В Play: F3 — метрики, F4 — следующий профиль.\n8 = production; 12/16 = stress. Fill не отключается."
	light_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	light_body.add_child(light_hint)

	var voxel_body := _section(content, "Voxel-префабы", true)
	var voxel_title := Label.new()
	voxel_title.text = "Выбранный voxel-проп"
	voxel_body.add_child(voxel_title)
	_voxel_library = _button("Открыть полку объектов", _open_voxel_library)
	_voxel_library.tooltip_text = "Открыть постоянную нижнюю библиотеку с поиском, превью и понятным местом добавления."
	voxel_body.add_child(_voxel_library)
	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voxel_body.add_child(_selection_label)
	_source_label = Label.new()
	_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voxel_body.add_child(_source_label)
	_prefab_label = Label.new()
	_prefab_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voxel_body.add_child(_prefab_label)
	_open_native_voxel = _button("Открыть модель в Godot", _open_selected_native_voxel)
	_open_native_voxel.name = "OpenNativeVoxelModel"
	voxel_body.add_child(_open_native_voxel)
	_migrate_selected_voxel = _button("Перенести модель в Godot", _migrate_selected_voxel_model)
	_migrate_selected_voxel.name = "MigrateSelectedVoxelModel"
	_migrate_selected_voxel.tooltip_text = "Создаёт Godot Resource, пересобирает prefab и поддерживает Ctrl+Z. Старые файлы JOI не меняются."
	voxel_body.add_child(_migrate_selected_voxel)
	_open_vox = _button("Legacy .vox · диагностика", _open_selected_vox)
	voxel_body.add_child(_open_vox)
	_open_json = _button("Legacy .json · диагностика", _open_selected_json)
	_open_json.tooltip_text = "Read-only источник миграции. Новый content сохраняется только в Godot Resource."
	voxel_body.add_child(_open_json)
	_show_source = _button("Показать в папке", _show_selected_source)
	voxel_body.add_child(_show_source)
	_rebuild = _button("Пересобрать только этот prefab", _rebuild_selected_prefab)
	voxel_body.add_child(_rebuild)
	_duplicate = _button("Дублировать безопасно · +X", _duplicate_selected_prop)
	_duplicate.tooltip_text = "Создаёт scene-owned копию с новым placement_id; поддерживает Undo/Redo."
	voxel_body.add_child(_duplicate)

	var voxel_hint := Label.new()
	voxel_hint.text = "Godot Resource — единственный writer. Legacy .vox/.json нужны только до одноразового переноса и не редактируются."
	voxel_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voxel_body.add_child(voxel_hint)

	var migration_body := _section(content, "Миграция контента · G1/G2", true)
	var migration_hint := Label.new()
	migration_hint.text = "Read-only инвентаризация владельцев, validation и производных prefab. Ничего не переносит и не меняет legacy-файлы."
	migration_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	migration_body.add_child(migration_hint)
	var migration_actions := HBoxContainer.new()
	migration_actions.add_theme_constant_override("separation", 6)
	migration_body.add_child(migration_actions)
	var refresh_report := _button("Измерить G1/G2", _refresh_content_migration_report)
	refresh_report.name = "RefreshContentMigrationReport"
	refresh_report.tooltip_text = "Проверяет все каталоги и prefab без записи в проект. На текущем объёме занимает около 1–2 секунд."
	migration_actions.add_child(refresh_report)
	var save_report := _button("Сохранить JSON", _save_content_migration_report)
	save_report.name = "SaveContentMigrationReport"
	save_report.tooltip_text = "Записывает последнюю read-only инвентаризацию только в user://."
	migration_actions.add_child(save_report)
	var open_dashboard := _button("Подробности…", _open_content_migration_dashboard)
	open_dashboard.name = "OpenContentMigrationDashboard"
	open_dashboard.tooltip_text = "Фильтруемый список всех записей и безопасной sandbox-партии. Миграцию не запускает."
	migration_actions.add_child(open_dashboard)
	_content_migration_summary = Label.new()
	_content_migration_summary.name = "ContentMigrationSummary"
	_content_migration_summary.text = "Нажмите «Измерить G1/G2», чтобы увидеть фактический остаток."
	_content_migration_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	migration_body.add_child(_content_migration_summary)
	_content_migration_issues = Label.new()
	_content_migration_issues.name = "ContentMigrationIssues"
	_content_migration_issues.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_migration_issues.modulate = Color(0.94, 0.70, 0.38)
	migration_body.add_child(_content_migration_issues)

	var trigger_body := _section(content, "Триггеры и цепочки", false)
	var trigger_title := Label.new()
	trigger_title.text = "Самостоятельные F-зоны"
	trigger_body.add_child(trigger_title)
	_add_standalone_trigger = _button("+ Зона-триггер с цепочкой", _request_standalone_trigger)
	_add_standalone_trigger.tooltip_text = "Создаёт scene-owned BoxShape3D у выбранного 3D-объекта или у player_start. Полный reimport Map её не удаляет."
	trigger_body.add_child(_add_standalone_trigger)
	var trigger_hint := Label.new()
	trigger_hint.text = "Зона появится в AuthoredTriggers. Перемещайте её обычным gizmo; размер и цепочка редактируются в EMBER OBJECT."
	trigger_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trigger_body.add_child(trigger_hint)

	var maintenance_body := _section(content, "Обслуживание карты", false)
	var full_import := _button("Полный reimport карты…", _request_reimport)
	full_import.tooltip_text = "Заменяет Look / Terrain / Props / Regions данными из Ember pack."
	maintenance_body.add_child(full_import)
	maintenance_body.add_child(_button("Открыть план тестовой миграции", _open_plan))


func _section(parent: VBoxContainer, title_text: String, expanded: bool) -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	parent.add_child(wrapper)
	var body := VBoxContainer.new()
	body.visible = expanded
	body.add_theme_constant_override("separation", 4)
	var toggle := Button.new()
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.text = ("▼ " if expanded else "▶ ") + title_text
	toggle.tooltip_text = "Свернуть или развернуть раздел."
	toggle.pressed.connect(func() -> void:
		body.visible = not body.visible
		toggle.text = ("▼ " if body.visible else "▶ ") + title_text
	)
	wrapper.add_child(toggle)
	wrapper.add_child(body)
	return body


func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	return button


func refresh() -> void:
	var map := _find_map()
	if map:
		_map_label.text = "Карта: %s · viewport-тени: %s" % [
			map.map_id,
			"включены" if map.preview_local_shadows_in_editor else "выключены",
		]
		_select_profile(map.omni_shadow_count)
	else:
		_map_label.text = "Откройте сцену с узлом Map (EmberMapLoader)."
	_refresh_selection()


func show_status(message: String, error := false) -> void:
	_set_status(message, error)


func rebuild_prop(prop: EmberVoxelProp) -> void:
	if not is_instance_valid(prop):
		_set_status("Inspector: voxel owner больше не существует.", true)
		return
	_selected_prop = prop
	_rebuild_selected_prefab()


func _find_map() -> EmberMapLoader:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	if root is EmberMapLoader:
		return root
	return root.find_child("Map", true, false) as EmberMapLoader


func _apply_profile() -> void:
	var map := _find_map()
	if map == null:
		_set_status("Нет открытой Ember-карты.", true)
		return
	var count := int(_profile.get_selected_metadata())
	map.set_lighting_test_profile(count)
	EditorInterface.mark_scene_as_unsaved()
	_set_status("Профиль %d применён. Для viewport включите preview на Map; в Play нажмите F3." % count)


func _select_profile(count: int) -> void:
	var index := SHADOW_PROFILES.find(count)
	if index < 0:
		index = 2
	_profile.select(index)


func _profile_name(count: int) -> String:
	match count:
		0: return "Только fill · 0 теней"
		2: return "Быстро · 2 тени"
		4: return "Баланс · 4 тени"
		8: return "Production · 8 теней"
		12: return "Расширенный · 12 теней"
		_: return "Stress · 16 теней"


func _refresh_selection() -> void:
	_selected_prop = null
	_selected_anchor = null
	_source_path = ""
	_vox_path = ""
	_json_path = ""
	_source_owner = ""
	var selection := EditorInterface.get_selection()
	if selection:
		for node in selection.get_selected_nodes():
			if _selected_anchor == null and node is Node3D:
				_selected_anchor = node as Node3D
			var current := node as Node
			while current:
				if current is EmberVoxelProp:
					_selected_prop = current
					break
				current = current.get_parent()
			if _selected_prop:
				_selected_anchor = _selected_prop
				break
	if _selected_prop:
		var paths := EmberVoxelPrefab.source_paths(_selected_prop.model_id)
		_json_path = str(paths["json"])
		_vox_path = str(paths["vox"])
		_source_owner = str(paths.get("owner", "legacy_import"))
		_source_path = _vox_path if not _vox_path.is_empty() else _json_path
		var instance_count := _matching_props(_selected_prop.model_id).size()
		_selection_label.text = "%s\nmodel_id: %s" % [_selected_prop.name, _selected_prop.model_id]
		_source_label.text = (
			"Источник: Godot Resource\n%s" % _json_path
			if _source_owner == "godot"
			else "Источник: ожидает одноразового импорта\n.vox: %s\n.json: %s" % [
				_vox_path if not _vox_path.is_empty() else "нет — форма хранится в JSON",
				_json_path if FileAccess.file_exists(_json_path) else "не найден",
			]
		)
		_prefab_label.text = "На открытой сцене: %d instance\nPrefab: %s" % [
			instance_count,
			_prefab_state(_selected_prop.model_id),
		]
	else:
		_selection_label.text = "Выберите проп внутри Map/Props."
		_source_label.text = ""
		_prefab_label.text = ""
	_open_vox.disabled = _source_owner != "legacy_import" or _vox_path.is_empty()
	_open_json.disabled = _source_owner != "legacy_import" or not FileAccess.file_exists(_json_path)
	_open_native_voxel.disabled = _source_owner != "godot"
	_migrate_selected_voxel.disabled = _source_owner != "legacy_import"
	_show_source.disabled = _source_path.is_empty()
	_rebuild.disabled = _selected_prop == null
	_duplicate.disabled = _selected_prop == null
	_voxel_library.disabled = false
	_add_standalone_trigger.disabled = _find_map() == null


func _request_standalone_trigger() -> void:
	standalone_trigger_requested.emit(_selected_anchor)


func _refresh_content_migration_report() -> void:
	_content_migration_report = ContentMigrationReport.build()
	if _content_migration_dashboard != null:
		_content_migration_dashboard.set_report(_content_migration_report)
	if _content_migration_summary == null or _content_migration_issues == null:
		return
	var domains: Dictionary = _content_migration_report.get("domains", {})
	var voxel_counts := _domain_counts(domains, "voxel")
	var lines := PackedStringArray([
		"Voxel: %d native · %d legacy · prefab %d готовы / %d устарели / %d отсутствуют" % [
			int(voxel_counts.get("native", 0)),
			int(voxel_counts.get("legacy_remaining", 0)),
			int(voxel_counts.get("derived_ready", 0)),
			int(voxel_counts.get("derived_stale", 0)),
			int(voxel_counts.get("derived_missing", 0)),
		],
	])
	for domain_name in ["action", "dialogue", "item", "shop", "vn"]:
		var counts := _domain_counts(domains, domain_name)
		lines.append("%s: %d native · %d legacy · %d ошибок" % [
			_domain_title(domain_name),
			int(counts.get("native", 0)),
			int(counts.get("legacy_remaining", 0)),
			int(counts.get("invalid", 0)),
		])
	_content_migration_summary.text = "\n".join(lines)
	var issues: Array[String] = []
	var missing_references: Array = (domains.get("voxel", {}) as Dictionary).get("missing_references", [])
	if not missing_references.is_empty():
		issues.append("Ссылки без voxel owner: %s" % ", ".join(missing_references))
	for domain_name in ["voxel", "action", "dialogue", "item", "shop", "vn"]:
		var domain: Dictionary = domains.get(domain_name, {})
		for raw_entry in domain.get("entries", []):
			var entry: Dictionary = raw_entry
			var entry_errors: Array = entry.get("errors", [])
			if not entry_errors.is_empty():
				issues.append("%s · %s: %s" % [
					_domain_title(domain_name), entry.get("id", ""), entry_errors[0],
				])
			if issues.size() >= 6:
				break
		if issues.size() >= 6:
			break
	if int(voxel_counts.get("derived_stale", 0)) > 0:
		issues.append("Устаревшие prefab: %d — пересобирать только после выбора migration-партии." % int(
			voxel_counts.get("derived_stale", 0)
		))
	_content_migration_issues.text = (
		"Проблем не найдено."
		if issues.is_empty()
		else "Требуют внимания:\n• %s" % "\n• ".join(issues)
	)
	_set_status("G1/G2 измерены за %d мс · проект и JOI не изменены." % int(
		_content_migration_report.get("duration_ms", 0)
	))


func _save_content_migration_report() -> void:
	if _content_migration_report.is_empty():
		_refresh_content_migration_report()
	var absolute := ProjectSettings.globalize_path(CONTENT_REPORT_PATH)
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		_set_status("Не удалось сохранить G1/G2 JSON.", true)
		return
	file.store_string(JSON.stringify(_content_migration_report, "  ", false) + "\n")
	file.close()
	_set_status("G1/G2 JSON сохранён только в user:// · %s" % absolute)


func _open_content_migration_dashboard() -> void:
	if _content_migration_report.is_empty():
		_refresh_content_migration_report()
	if _content_migration_popup == null:
		_content_migration_popup = PopupPanel.new()
		_content_migration_popup.name = "ContentMigrationDashboardPopup"
		add_child(_content_migration_popup)
		_content_migration_dashboard = ContentMigrationDashboard.new()
		_content_migration_popup.add_child(_content_migration_dashboard)
		_content_migration_dashboard.refresh_requested.connect(_refresh_content_migration_report)
		_content_migration_dashboard.save_requested.connect(_save_content_migration_report)
		_content_migration_dashboard.close_requested.connect(_content_migration_popup.hide)
		_content_migration_dashboard.preflight_requested.connect(_preflight_voxel_batch)
		_content_migration_dashboard.migrate_batch_requested.connect(
			func(model_ids: Array[String]) -> void: voxel_batch_migrate_requested.emit(model_ids)
		)
	_content_migration_dashboard.set_report(_content_migration_report)
	_content_migration_popup.popup_centered(Vector2i(1120, 680))


func _preflight_voxel_batch(model_ids: Array[String]) -> void:
	var report := VoxelMigrationParity.inspect_batch(model_ids)
	_content_migration_dashboard.set_preflight(report)
	if bool(report.get("ok", false)):
		_set_status("Dry-run: %d/%d voxel-моделей совпали · файлы не изменены." % [
			int(report.get("passed", 0)), int(report.get("total", 0)),
		])
	else:
		_set_status("Dry-run не пройден · перенос партии заблокирован.", true)


func _domain_counts(domains: Dictionary, domain_name: String) -> Dictionary:
	var domain: Dictionary = domains.get(domain_name, {})
	return domain.get("counts", {})


func _domain_title(domain_name: String) -> String:
	match domain_name:
		"action": return "Цепочки"
		"dialogue": return "Диалоги"
		"item": return "Предметы"
		"shop": return "Магазины"
		"vn": return "VN-арт"
		_: return "Voxel"


func _open_selected_vox() -> void:
	_open_path(_vox_path, ".vox")


func _open_selected_native_voxel() -> void:
	if _selected_prop != null:
		_open_native_voxel_resource(_selected_prop.model_id)


func _migrate_selected_voxel_model() -> void:
	if _selected_prop != null:
		voxel_migrate_requested.emit(_selected_prop.model_id)


func _open_selected_json() -> void:
	_open_path(_json_path, "metadata .json")


func _open_path(path: String, label: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		_set_status("%s не найден." % label, true)
		return
	var err := OS.shell_open(path)
	_set_status("%s открыт." % label if err == OK else "Не удалось открыть %s (%s)." % [label, err], err != OK)


func _show_selected_source() -> void:
	if _source_path.is_empty():
		return
	var err := OS.shell_show_in_file_manager(_source_path)
	_set_status("Исходник показан в папке." if err == OK else "Не удалось открыть папку (%s)." % err, err != OK)


func _rebuild_selected_prefab() -> void:
	if _selected_prop == null:
		return
	var model_id := _selected_prop.model_id
	var map := _find_map()
	var tile_size := map.imported_tile_size if map and map.imported_tile_size > 0.0 else 16.0
	var scene_root := EditorInterface.get_edited_scene_root()
	var scene_hash_before := _scene_file_hash(scene_root)
	var placements_before := _placement_snapshot(model_id)
	var stats := {}
	EmberVoxelPrefab.begin_import()
	var packed := EmberVoxelPrefab.ensure_saved(model_id, tile_size, stats, true)
	if packed == null:
		_set_status("Prefab %s не собран: проверьте исходник." % model_id, true)
		return
	var report := EmberVoxelPrefab.validate_packed(model_id, packed)
	if not bool(report["ok"]):
		_set_status("Prefab %s собран, но проверка не прошла: %s" % [model_id, "; ".join(report["errors"])], true)
		return
	EditorInterface.get_resource_filesystem().scan()
	var scene_unchanged := scene_hash_before == _scene_file_hash(scene_root)
	var placements_unchanged := placements_before == _placement_snapshot(model_id)
	if not scene_unchanged or not placements_unchanged:
		_set_status("Prefab проверен, но защита карты не прошла: file=%s, placements=%s" % [scene_unchanged, placements_unchanged], true)
		return
	_set_status("%s пересобран · %s · %d instance · viewport обновлён, файл карты и transforms не изменены." % [
		model_id,
		" + ".join(report["checks"]),
		placements_before.size(),
	])
	_refresh_selection()


func _duplicate_selected_prop() -> void:
	if _selected_prop == null:
		return
	duplicate_requested.emit(_selected_prop)


func _open_voxel_library() -> void:
	voxel_library_requested.emit()


func _ensure_voxel_popup() -> void:
	if _voxel_popup != null:
		return
	_voxel_popup = PopupPanel.new()
	_voxel_popup.name = "VoxelVisualLibraryPopup"
	add_child(_voxel_popup)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_voxel_popup.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	_voxel_queue_label = Label.new()
	_voxel_queue_label.name = "VoxelMigrationQueueSummary"
	_voxel_queue_label.modulate = Color(0.72, 0.78, 0.88)
	body.add_child(_voxel_queue_label)
	_voxel_picker = VisualLibraryPicker.new()
	_voxel_picker.value_chosen.connect(_choose_voxel_model)
	_voxel_picker.selection_changed.connect(_refresh_voxel_library_selection)
	body.add_child(_voxel_picker)
	_voxel_owner_label = Label.new()
	_voxel_owner_label.name = "VoxelMigrationOwner"
	_voxel_owner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_voxel_owner_label)
	var migration_actions := HBoxContainer.new()
	migration_actions.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(migration_actions)
	_voxel_popup_open = _button("Открыть Godot Resource", _open_popup_native_voxel)
	migration_actions.add_child(_voxel_popup_open)
	_voxel_popup_migrate = _button("Перенести в Godot", _migrate_popup_voxel)
	_voxel_popup_migrate.tooltip_text = "Создаёт native .tres и prefab. Ctrl+Z возвращает модель в очередь; legacy-файлы не меняются."
	migration_actions.add_child(_voxel_popup_migrate)
	_voxel_preview_renderer = VoxelPreviewRenderer.new()
	_voxel_preview_renderer.preview_ready.connect(_on_voxel_preview_ready)
	add_child(_voxel_preview_renderer)


func _on_voxel_preview_ready(model_id: String, texture: Texture2D) -> void:
	if _voxel_picker == null:
		return
	_voxel_picker.set_entry_texture(model_id, texture)


func _choose_voxel_model(model_id: String) -> void:
	if _find_map() == null:
		_set_status("Для добавления откройте Ember Map. Переносить и открывать модели можно без карты.", true)
		return
	if _voxel_popup != null:
		_voxel_popup.hide()
	voxel_prop_requested.emit(model_id, _selected_anchor)


func _refresh_voxel_queue_stats() -> void:
	if _voxel_queue_label == null:
		return
	var native_count := 0
	for entry in _voxel_popup_entries:
		if str(entry.get("owner", "")) == "godot":
			native_count += 1
	_voxel_queue_label.text = "Godot: %d · ожидают импорт: %d · всего: %d" % [
		native_count,
		_voxel_popup_entries.size() - native_count,
		_voxel_popup_entries.size(),
	]


func _refresh_voxel_library_selection(_model_id: String) -> void:
	if _voxel_picker == null or _voxel_owner_label == null:
		return
	var entry := _voxel_picker.selected_entry()
	var owner := str(entry.get("owner", ""))
	_voxel_owner_label.text = (
		"Godot Resource — редактируется и собирается без JOI."
		if owner == "godot"
		else "Legacy import queue — перенос создаст .tres, не меняя старые .vox/.json."
	)
	_voxel_owner_label.modulate = Color(0.50, 0.86, 0.62) if owner == "godot" else Color(0.94, 0.70, 0.38)
	_voxel_popup_open.disabled = owner != "godot"
	_voxel_popup_migrate.disabled = owner != "legacy_import"


func _migrate_popup_voxel() -> void:
	if _voxel_picker != null and not _voxel_picker.selected_id().is_empty():
		voxel_migrate_requested.emit(_voxel_picker.selected_id())


func _open_popup_native_voxel() -> void:
	if _voxel_picker != null:
		_open_native_voxel_resource(_voxel_picker.selected_id())


func _open_native_voxel_resource(model_id: String) -> void:
	var resource := EmberVoxelCatalog.native_resource(model_id)
	if resource == null:
		_set_status("Godot Resource для %s ещё не создан." % model_id, true)
		return
	EditorInterface.edit_resource(resource)
	_set_status("Открыт %s · сейчас доступны свойства Resource; визуальный sculpt workspace — следующий срез." % model_id)


func accept_voxel_migration_change(model_id: String) -> void:
	if _voxel_picker != null and _voxel_popup != null and _voxel_popup.visible:
		_voxel_popup_entries = VoxelVisuals.entries()
		_voxel_picker.set_entries(_voxel_popup_entries, model_id)
		_voxel_picker.set_choose_text("Добавить в сцену")
		_refresh_voxel_queue_stats()
		_refresh_voxel_library_selection(model_id)
		for entry in _voxel_popup_entries:
			_voxel_preview_renderer.queue_preview(str(entry.get("id", "")), str(entry.get("previewPath", "")))
	_set_status("Voxel ownership обновлён: %s · Ctrl+Z/Redo поддерживаются." % model_id)
	_refresh_selection()


func _prefab_state(model_id: String) -> String:
	var path := EmberVoxelPrefab.prefab_path(model_id)
	if not ResourceLoader.exists(path):
		return "не создан"
	# Read-only inspection must not clear the SceneState of live instances.
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var report := EmberVoxelPrefab.validate_packed(model_id, packed)
	if bool(report["ok"]):
		return "актуален · %s" % " + ".join(report["checks"])
	return "нужна пересборка · %s" % "; ".join(report["errors"])


func _matching_props(model_id: String) -> Array[EmberVoxelProp]:
	var result: Array[EmberVoxelProp] = []
	var root := EditorInterface.get_edited_scene_root()
	if root:
		_collect_matching_props(root, model_id, result)
	return result


func _collect_matching_props(node: Node, model_id: String, result: Array[EmberVoxelProp]) -> void:
	if node is EmberVoxelProp and (node as EmberVoxelProp).model_id == model_id:
		result.append(node as EmberVoxelProp)
	for child in node.get_children():
		_collect_matching_props(child, model_id, result)


func _placement_snapshot(model_id: String) -> Dictionary:
	var result := {}
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return result
	for prop in _matching_props(model_id):
		result[str(root.get_path_to(prop))] = [prop.transform, prop.placement_id]
	return result


func _scene_file_hash(root: Node) -> String:
	if root == null or root.scene_file_path.is_empty() or not FileAccess.file_exists(root.scene_file_path):
		return ""
	return FileAccess.get_sha256(root.scene_file_path)


func _request_reimport() -> void:
	reimport_requested.emit()


func _open_plan() -> void:
	var path := ProjectSettings.globalize_path("res://MIGRATION_TEST_PLAN.md")
	var err := OS.shell_open(path)
	_set_status("План открыт." if err == OK else "Не удалось открыть план (%s)." % err, err != OK)


func _set_status(message: String, error := false) -> void:
	_status.text = message
	_status.tooltip_text = message
	_status.visible = not message.is_empty()
	_status.modulate = Color(1.0, 0.55, 0.5) if error else Color(0.65, 1.0, 0.72)
