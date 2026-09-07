@tool
class_name EmberCombatAiProfileInspectorPanel
extends VBoxContainer
## Readable authoring summary for a reusable enemy decision profile.

var _profile: EmberCombatAiProfileResource
var _icon: TextureRect
var _swatch: ColorRect
var _summary: Label
var _validation: Label


func setup(profile: EmberCombatAiProfileResource) -> void:
	_profile = profile
	name = "CombatAiProfileOverview"
	add_theme_constant_override("separation", 7)
	var title := Label.new()
	title.text = "ПРОФИЛЬ БОЕВОГО AI"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color("ffc85a")
	add_child(title)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var visual := PanelContainer.new()
	visual.custom_minimum_size = Vector2(88, 88)
	body.add_child(visual)
	_icon = TextureRect.new()
	_icon.name = "CombatAiProfileIcon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.add_child(_icon)
	_swatch = ColorRect.new()
	_swatch.name = "CombatAiProfileSwatch"
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(_swatch)
	_summary = Label.new()
	_summary.name = "CombatAiProfileSummary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_summary)
	_validation = Label.new()
	_validation.name = "CombatAiProfileValidation"
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	var hint := Label.new()
	hint.text = "Профиль только оценивает разрешённые preview-варианты. Дальность, урон, реакции и commit остаются у общего боевого resolver."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.72, 0.82)
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)
	if not _profile.changed.is_connected(_refresh):
		_profile.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _profile != null and _profile.changed.is_connected(_refresh):
		_profile.changed.disconnect(_refresh)


func _refresh() -> void:
	if _profile == null:
		return
	_icon.texture = _profile.icon
	_swatch.color = _profile.accent_color
	_swatch.visible = _profile.icon == null
	var low_hp := (
		"%s при ≤ %d%% HP" % [
			_profile.low_hp_behavior_label(), _profile.low_hp_threshold_percent,
		]
		if _profile.low_hp_threshold_percent > 0
		else "Особого поведения при низком HP нет"
	)
	_summary.text = "%s\n%s\nПозиция: %s\nЦель: %s\nДействие: %s\nРеакции: %s\n%s\n%s" % [
		_profile.display_name,
		_profile.profile_id,
		_profile.positioning_behavior_label(),
		_profile.target_priority_label(),
		_profile.action_priority_label(),
		"приоритет" if _profile.prefer_elemental_reactions else "обычный порядок",
		low_hp,
		_profile.description,
	]
	var errors := _profile.validation_errors()
	_validation.text = "✓ Профиль готов" if errors.is_empty() else "⚠ " + "\n⚠ ".join(errors)
	_validation.modulate = Color("79d99a") if errors.is_empty() else Color("ff8d78")
