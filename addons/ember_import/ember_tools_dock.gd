@tool
extends VBoxContainer
## Small bridge for the migration test: light profiles and targeted voxel-prefab rebuilds.

signal duplicate_requested(prop: EmberVoxelProp)
signal standalone_trigger_requested(anchor: Node3D)
signal voxel_library_requested
signal close_requested
signal voxel_assets_refreshed

const SHADOW_PROFILES := [0, 2, 4, 8, 12, 16]
const ContentMigrationReport = preload("res://addons/ember_import/ember_content_migration_report.gd")
const ContentMigrationDashboard = preload("res://addons/ember_import/ember_content_migration_dashboard.gd")
const CONTENT_REPORT_PATH := "user://ember_content_migration_report.json"

var _map_label: Label
var _profile: OptionButton
var _selection_label: Label
var _source_label: Label
var _prefab_label: Label
var _status: Label
var _open_native_voxel: Button
var _show_source: Button
var _rebuild: Button
var _duplicate: Button
var _voxel_library: Button
var _add_standalone_trigger: Button
var _content_migration_summary: Label
var _content_migration_issues: Label
var _content_migration_report: Dictionary = {}
var _content_migration_popup: PopupPanel
var _content_migration_dashboard: PanelContainer
var _selected_prop: EmberVoxelProp
var _selected_anchor: Node3D
var _source_path := ""
var _json_path := ""
var _source_owner := ""
var _refreshing_voxels := false
var voxel_undo: Object
var refresh_guard: Callable
var _library_operation: RefCounted
var _library_progress: ProgressBar
var _library_cancel: Button
var _library_retry: Button
var _library_skipped_ids: Array[String] = []
var library_ids_provider: Callable # Optional fixture provider; default is full catalog.


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
	title.text = "EMBER · СЕРВИС"
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
	_show_source = _button("Показать в папке", _show_selected_source)
	voxel_body.add_child(_show_source)
	_rebuild = _button("Пересобрать только этот prefab", _rebuild_selected_prefab)
	voxel_body.add_child(_rebuild)
	var refresh_scene := _button("Обновить воксели сцены", refresh_scene_voxels)
	refresh_scene.name = "RefreshSceneVoxels"
	refresh_scene.tooltip_text = "Обновить устаревшие экземпляры и Surface прямо в 3D. Source/рецепты не меняются; ручные mesh-правки пропускаются. Undo/Redo для экземпляров."
	voxel_body.add_child(refresh_scene)
	voxel_body.add_child(_button("Пересобрать всю библиотеку", rebuild_library_voxels))
	_library_progress = ProgressBar.new()
	_library_progress.visible = false
	voxel_body.add_child(_library_progress)
	_library_cancel = _button("Остановить после текущей модели", func():
		if _library_operation != null: _library_operation.cancel_library()
	)
	_library_cancel.visible = false
	voxel_body.add_child(_library_cancel)
	_library_retry = _button("Повторить пропущенные модели", func(): rebuild_library_voxels(true))
	_library_retry.name = "RetryVoxelLibrary"
	_library_retry.visible = false
	voxel_body.add_child(_library_retry)
	_duplicate = _button("Дублировать безопасно · +X", _duplicate_selected_prop)
	_duplicate.tooltip_text = "Создаёт scene-owned копию с новым placement_id; поддерживает Undo/Redo."
	voxel_body.add_child(_duplicate)

	var voxel_hint := Label.new()
	voxel_hint.text = "Godot Resource — единственный writer. Полка, Canvas и пересборка используют native source."
	voxel_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voxel_body.add_child(voxel_hint)

	var migration_body := _section(content, "Диагностика native-контента", true)
	var migration_hint := Label.new()
	migration_hint.text = "Проверка native Resources, ссылок и готовых объектов. Файлы не изменяются."
	migration_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	migration_body.add_child(migration_hint)
	var migration_actions := HBoxContainer.new()
	migration_actions.add_theme_constant_override("separation", 6)
	migration_body.add_child(migration_actions)
	var refresh_report := _button("Проверить контент", _refresh_content_migration_report)
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
	_content_migration_summary.text = "Нажмите «Проверить контент», чтобы увидеть фактический остаток."
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
		_source_owner = str(paths.get("owner", ""))
		_source_path = _json_path
		var instance_count := _matching_props(_selected_prop.model_id).size()
		_selection_label.text = "%s\nmodel_id: %s" % [_selected_prop.name, _selected_prop.model_id]
		_source_label.text = "Источник: Godot Resource\n%s" % _source_path if _source_owner == "godot" else "Native source отсутствует; готовый объект сохранён."
		_prefab_label.text = "На открытой сцене: %d instance\nPrefab: %s" % [
			instance_count,
			_prefab_state(_selected_prop.model_id),
		]
	else:
		_selection_label.text = "Выберите проп внутри Map/Props."
		_source_label.text = ""
		_prefab_label.text = ""
	_open_native_voxel.disabled = _source_owner != "godot"
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
	_content_migration_dashboard.set_report(_content_migration_report)
	_content_migration_popup.popup_centered(Vector2i(1120, 680))


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


func _open_selected_native_voxel() -> void:
	if _selected_prop != null:
		_open_native_voxel_resource(_selected_prop.model_id)


func _show_selected_source() -> void:
	if _source_path.is_empty():
		return
	var err := OS.shell_show_in_file_manager(_source_path)
	_set_status("Исходник показан в папке." if err == OK else "Не удалось открыть папку (%s)." % err, err != OK)


func _rebuild_selected_prefab() -> void:
	if is_instance_valid(_selected_prop):
		await _refresh_voxels(_selected_prop.model_id, false)


func refresh_scene_voxels() -> void:
	await _refresh_voxels("", true)


func rebuild_library_voxels(retry_skipped := false) -> void:
	if _refreshing_voxels: return
	if retry_skipped and _library_skipped_ids.is_empty(): return
	if refresh_guard.is_valid():
		var guard_error: String = refresh_guard.call()
		if not guard_error.is_empty():
			_set_status(guard_error, true)
			return
	_refreshing_voxels = true
	_library_progress.visible = true
	_library_cancel.visible = true
	_library_retry.visible = false
	_library_operation = preload("res://addons/ember_import/ember_voxel_scene_refresh.gd").new()
	_library_operation.library_progress.connect(func(done: int, total: int, id: String):
		_library_progress.max_value = maxi(1, total)
		_library_progress.value = done
		_set_status("Библиотека: %d/%d · %s" % [done, total, id])
	)
	var ids: Array[String] = library_ids_provider.call() if library_ids_provider.is_valid() else EmberVoxelCatalog.ids()
	if retry_skipped: ids = _library_skipped_ids.duplicate()
	var result: Dictionary = await _library_operation.rebuild_library(ids, self, EditorInterface.get_edited_scene_root(), voxel_undo)
	_library_operation = null
	_refreshing_voxels = false
	_library_progress.visible = false
	_library_cancel.visible = false
	_library_skipped_ids.assign(result.skipped_ids)
	_library_retry.visible = not _library_skipped_ids.is_empty()
	voxel_assets_refreshed.emit()
	_set_status("%s: %d/%d · пересобрано %d · пропущено %d. Undo — по моделям.\n%s" % ["Остановлено" if result.cancelled else "Готово", result.completed, result.total, result.rebuilt, result.skipped.size(), "\n".join(result.skipped)], not result.skipped.is_empty())


func _refresh_voxels(model_id: String, stale_only: bool) -> void:
	if _refreshing_voxels: return
	if refresh_guard.is_valid():
		var guard_error: String = refresh_guard.call()
		if not guard_error.is_empty():
			_set_status(guard_error, true)
			return
	_refreshing_voxels = true
	var operation := preload("res://addons/ember_import/ember_voxel_scene_refresh.gd").new()
	operation.progress.connect(func(message: String): _set_status(message))
	operation.assets_changed.connect(func(): voxel_assets_refreshed.emit())
	var result: Dictionary = await operation.refresh(EditorInterface.get_edited_scene_root(), voxel_undo, model_id, stale_only)
	_refreshing_voxels = false
	if not result.ok:
		_set_status(str(result.error), true)
		return
	var message := "3D обновлён: %d моделей, %d экземпляров, %d Surface · Ctrl+Z отменяет замену экземпляров." % [result.models, result.instances, result.surfaces]
	if not result.skipped.is_empty():
		message += "\nПропущены (правки сохранены):\n" + "\n".join(result.skipped)
	_set_status(message, not result.skipped.is_empty())
	_status.tooltip_text = message
	_refresh_selection()


func _duplicate_selected_prop() -> void:
	if _selected_prop == null:
		return
	duplicate_requested.emit(_selected_prop)


func _open_voxel_library() -> void:
	voxel_library_requested.emit()


func _open_native_voxel_resource(model_id: String) -> void:
	var resource := EmberVoxelCatalog.native_resource(model_id)
	if resource == null:
		_set_status("Godot Resource для %s ещё не создан." % model_id, true)
		return
	EditorInterface.edit_resource(resource)
	_set_status("Открыт %s · сейчас доступны свойства Resource; визуальный sculpt workspace — следующий срез." % model_id)


func accept_voxel_migration_change(model_id: String) -> void:
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


func _open_plan() -> void:
	var path := ProjectSettings.globalize_path("res://MIGRATION_TEST_PLAN.md")
	var err := OS.shell_open(path)
	_set_status("План открыт." if err == OK else "Не удалось открыть план (%s)." % err, err != OK)


func _set_status(message: String, error := false) -> void:
	_status.text = message
	_status.tooltip_text = message
	_status.visible = not message.is_empty()
	_status.modulate = Color(1.0, 0.55, 0.5) if error else Color(0.65, 1.0, 0.72)
