@tool
class_name EmberCombatStatusInspectorPanel
extends VBoxContainer
## Human-readable projection of one canonical combat status. The native
## Inspector remains the writer; this panel explains the authored contract.

var _status: Resource
var _swatch: ColorRect
var _icon: TextureRect
var _glyph: Label
var _summary: Label
var _validation: Label


func setup(status: Resource) -> void:
	_status = status
	name = "CombatStatusOverview"
	add_theme_constant_override("separation", 7)
	var title := Label.new()
	title.text = "БОЕВОЙ СТАТУС"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color("ffc85a")
	add_child(title)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var visual := PanelContainer.new()
	visual.custom_minimum_size = Vector2(72, 72)
	body.add_child(visual)
	_swatch = ColorRect.new()
	_swatch.name = "CombatStatusSwatch"
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(_swatch)
	_icon = TextureRect.new()
	_icon.name = "CombatStatusIcon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.add_child(_icon)
	_glyph = Label.new()
	_glyph.name = "CombatStatusGlyph"
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph.add_theme_font_size_override("font_size", 30)
	visual.add_child(_glyph)
	_summary = Label.new()
	_summary.name = "CombatStatusSummary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_summary)
	_validation = Label.new()
	_validation.name = "CombatStatusValidation"
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	var hint := Label.new()
	hint.text = "Бой хранит только ID и число оставшихся ходов. Название и вид берутся из этого canonical .tres."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.72, 0.82)
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)
	if _status != null and not _status.changed.is_connected(_refresh):
		_status.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _status != null and _status.changed.is_connected(_refresh):
		_status.changed.disconnect(_refresh)


func _refresh() -> void:
	if _status == null:
		return
	var texture := _status.get("icon") as Texture2D
	var color := _status.get("ui_color") as Color
	_icon.texture = texture
	_icon.visible = texture != null
	_swatch.color = color.darkened(0.55)
	_glyph.text = str(_status.get("glyph"))
	_glyph.modulate = color
	_glyph.visible = texture == null
	_summary.text = "\n".join([
		str(_status.get("display_name")),
		"%s · %s" % [str(_status.get("status_id")), str(_status.call("kind_label"))],
		str(_status.get("description")),
	])
	var errors: Array = _status.call("validation_errors")
	_validation.text = "✓ Статус готов" if errors.is_empty() else "⚠ " + "\n⚠ ".join(errors)
	_validation.modulate = Color("79d99a") if errors.is_empty() else Color("ff8d78")
