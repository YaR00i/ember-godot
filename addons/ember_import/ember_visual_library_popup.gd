@tool
class_name EmberVisualLibraryPopup
extends PopupPanel
## Thin popup host for the shared ID picker. Content-specific adapters provide
## entries; this node owns no catalog, selection schema or preview cache.

signal value_chosen(value: String)

const Picker = preload("res://addons/ember_import/ember_visual_library_picker.gd")

var _picker: EmberVisualLibraryPicker


func open_library(
	title_text: String,
	entries: Array[Dictionary],
	current_id: String,
	icon_size := Vector2i(88, 88),
	column_width := 148,
) -> void:
	_ensure_picker()
	_picker.setup(title_text, entries, current_id)
	_picker.set_tile_layout(icon_size, column_width)
	popup_centered(Vector2i(760, 610))


func _ensure_picker() -> void:
	if _picker != null:
		return
	name = "EmberVisualLibraryPopup"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	_picker = Picker.new() as EmberVisualLibraryPicker
	_picker.value_chosen.connect(func(value: String) -> void:
		hide()
		value_chosen.emit(value)
	)
	margin.add_child(_picker)
