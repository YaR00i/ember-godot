@tool
class_name EmberCombatEffectInspectorPanel
extends VBoxContainer
## Human-readable projection of one reusable effect step. The native Inspector
## remains the writer and this panel explains which fields are active.

var _effect: Resource
var _swatch: ColorRect
var _icon: TextureRect
var _summary: Label
var _validation: Label


func setup(effect: Resource) -> void:
	_effect = effect
	name = "CombatEffectOverview"
	add_theme_constant_override("separation", 7)
	var title := Label.new()
	title.text = "БИБЛИОТЕЧНЫЙ ЭФФЕКТ"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color("ffc85a")
	add_child(title)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var visual := PanelContainer.new()
	visual.custom_minimum_size = Vector2(72, 72)
	visual.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	visual.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(visual)
	_icon = TextureRect.new()
	_icon.name = "CombatEffectIcon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.add_child(_icon)
	_swatch = ColorRect.new()
	_swatch.name = "CombatEffectSwatch"
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(_swatch)
	_summary = Label.new()
	_summary.name = "CombatEffectSummary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_summary)
	_validation = Label.new()
	_validation.name = "CombatEffectValidation"
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	var hint := Label.new()
	hint.text = "Эффект можно назначить нескольким умениям. Правка этого .tres меняет все назначения после сохранения."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.72, 0.82)
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)
	if _effect != null and not _effect.changed.is_connected(_refresh):
		_effect.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _effect != null and _effect.changed.is_connected(_refresh):
		_effect.changed.disconnect(_refresh)


func _refresh() -> void:
	if _effect == null:
		return
	var icon := _effect.get("icon") as Texture2D
	_icon.texture = icon
	_swatch.color = _effect.get("ui_color") as Color
	_swatch.visible = icon == null
	var lines: Array[String] = [
		str(_effect.get("display_name")),
		"%s · %s" % [str(_effect.get("effect_id")), str(_effect.call("operation_label"))],
		str(_effect.get("description")),
	]
	match str(_effect.call("operation_id")):
		"apply_status":
			lines.append("Статус %s · %d ход" % [
				str(_effect.get("status_id")), int(_effect.get("status_duration")),
			])
		"remove_status":
			lines.append("Снять: %s" % ", ".join(_effect.get("remove_status_ids") as PackedStringArray))
		"push":
			lines.append("Сила толчка: %d" % int(_effect.get("force")))
		"cell_patch":
			lines.append("Высота %+d · %s" % [
				int(_effect.get("elevation_delta")), str(_effect.call("block_mode_label")),
			])
			lines.append("Теги +%s / −%s" % [
				", ".join(_effect.get("add_cell_tags") as PackedStringArray),
				", ".join(_effect.get("remove_cell_tags") as PackedStringArray),
			])
		"spread":
			lines.append("Радиус %d · статусы: %s · клетки: %s" % [
				int(_effect.get("spread_radius")),
				", ".join(_effect.get("spread_status_ids") as PackedStringArray),
				", ".join(_effect.get("spread_cell_tags") as PackedStringArray),
			])
		"restore_hp":
			lines.append("Восстановить HP: %d" % int(_effect.get("restore_hp_amount")))
		"move_actor":
			lines.append("Допустимый перепад высоты: %d" % int(
				_effect.get("move_max_height_delta")
			))
		"activate_focus":
			lines.append("Цель: авторский узел поля; повторная активация запрещена")
	_summary.text = "\n".join(lines)
	var errors: Array = _effect.call("validation_errors")
	_validation.text = "✓ Эффект готов" if errors.is_empty() else "⚠ " + "\n⚠ ".join(errors)
	_validation.modulate = Color("79d99a") if errors.is_empty() else Color("ff8d78")
