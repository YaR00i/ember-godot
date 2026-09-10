@tool
extends RefCounted
## Scoped Ember Workshop theme. It is merged over the active Godot theme so
## editor fonts, icons and DPI remain native while workshop controls share one skin.

const INK := Color("e7edf4")
const MUTED := Color("8998a8")
const CYAN := Color("69b7d5")
const AMBER := Color("f0aa3c")
const ERROR := Color("ef6a61")
const SURFACE := Color("202a35")
const SURFACE_RAISED := Color("293746")
const SURFACE_LOW := Color("171f28")
const BORDER := Color("3a4958")


static func build(base_theme: Theme = null) -> Theme:
	var result := Theme.new()
	if base_theme != null:
		result.merge_with(base_theme)
	_style_button(result, "Button")
	_style_button(result, "OptionButton")
	_style_primary_button(result)
	_style_tool_button(result)
	_style_segment_button(result)
	_style_icon_button(result)
	_style_swatch_button(result)
	_style_card_button(result)
	_style_line_edit(result)
	_style_tabs(result)
	_style_sub_tabs(result)
	_style_item_list(result)
	_style_check_controls(result)
	return result


static func _style_button(theme: Theme, type_name: StringName) -> void:
	theme.set_stylebox("normal", type_name, _box(SURFACE, BORDER))
	theme.set_stylebox("hover", type_name, _box(SURFACE_RAISED, CYAN.darkened(0.18)))
	theme.set_stylebox("pressed", type_name, _box(Color("473722"), AMBER, 4, 2))
	theme.set_stylebox("hover_pressed", type_name, _box(Color("584226"), AMBER.lightened(0.12), 4, 2))
	theme.set_stylebox("disabled", type_name, _box(Color("1a2129"), Color("2b3540")))
	theme.set_stylebox("focus", type_name, _outline(CYAN, 4, 2))
	theme.set_color("font_color", type_name, INK)
	theme.set_color("font_hover_color", type_name, Color.WHITE)
	theme.set_color("font_pressed_color", type_name, Color("fff0cf"))
	theme.set_color("font_hover_pressed_color", type_name, Color.WHITE)
	theme.set_color("font_disabled_color", type_name, MUTED.darkened(0.28))
	theme.set_color("font_focus_color", type_name, Color.WHITE)
	theme.set_constant("h_separation", type_name, 6)


static func _style_primary_button(theme: Theme) -> void:
	var type_name := &"WorkshopPrimaryButton"
	theme.set_type_variation(type_name, &"Button")
	theme.set_stylebox("normal", type_name, _box(Color("76501f"), AMBER, 4, 1))
	theme.set_stylebox("hover", type_name, _box(Color("936526"), AMBER.lightened(0.18), 4, 2))
	theme.set_stylebox("pressed", type_name, _box(Color("b97b29"), Color("ffd27c"), 4, 2))
	theme.set_stylebox("hover_pressed", type_name, _box(Color("c5862d"), Color("ffe0a1"), 4, 2))
	theme.set_stylebox("disabled", type_name, _box(Color("292722"), Color("4c4435")))
	theme.set_stylebox("focus", type_name, _outline(Color("ffd27c"), 4, 2))
	theme.set_color("font_color", type_name, Color("fff2d4"))
	theme.set_color("font_hover_color", type_name, Color.WHITE)
	theme.set_color("font_pressed_color", type_name, Color.WHITE)
	theme.set_color("font_disabled_color", type_name, MUTED.darkened(0.25))


static func _style_tool_button(theme: Theme) -> void:
	var type_name := &"WorkshopToolButton"
	theme.set_type_variation(type_name, &"Button")
	theme.set_stylebox("normal", type_name, _box(Color("1b2530"), Color("344352"), 3))
	theme.set_stylebox("hover", type_name, _box(Color("253747"), CYAN.darkened(0.15), 3, 1))
	theme.set_stylebox("pressed", type_name, _box(Color("4a3821"), AMBER, 3, 2))
	theme.set_stylebox("hover_pressed", type_name, _box(Color("594226"), AMBER.lightened(0.12), 3, 2))
	theme.set_color("font_pressed_color", type_name, Color("fff0cd"))
	theme.set_color("font_hover_pressed_color", type_name, Color.WHITE)


static func _style_segment_button(theme: Theme) -> void:
	var type_name := &"WorkshopSegmentButton"
	theme.set_type_variation(type_name, &"Button")
	theme.set_stylebox("normal", type_name, _compact_box(Color("18212a"), Color("354250")))
	theme.set_stylebox("hover", type_name, _compact_box(Color("223441"), CYAN.darkened(0.15)))
	theme.set_stylebox("pressed", type_name, _compact_box(Color("4a3821"), AMBER, 2))
	theme.set_stylebox("hover_pressed", type_name, _compact_box(Color("5a4225"), AMBER.lightened(0.12), 2))
	theme.set_stylebox("focus", type_name, _outline(CYAN, 3, 1))
	theme.set_color("font_color", type_name, MUTED)
	theme.set_color("font_hover_color", type_name, Color.WHITE)
	theme.set_color("font_pressed_color", type_name, Color("fff0cf"))
	theme.set_color("font_hover_pressed_color", type_name, Color.WHITE)


static func _style_icon_button(theme: Theme) -> void:
	var type_name := &"WorkshopIconButton"
	theme.set_type_variation(type_name, &"Button")
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var inherited := theme.get_stylebox(state, &"Button")
		if inherited != null:
			var compact := inherited.duplicate() as StyleBox
			compact.content_margin_left = 6.0
			compact.content_margin_right = 6.0
			theme.set_stylebox(state, type_name, compact)


static func _style_swatch_button(theme: Theme) -> void:
	var type_name := &"WorkshopSwatchButton"
	theme.set_type_variation(type_name, &"Button")
	# Editor themes tint pressed button icons. Palette textures are data, not UI
	# glyphs, so every state must preserve the exact source color.
	for state in [
		&"icon_normal_color",
		&"icon_hover_color",
		&"icon_pressed_color",
		&"icon_hover_pressed_color",
		&"icon_focus_color",
		&"icon_disabled_color",
	]:
		theme.set_color(state, type_name, Color.WHITE)


static func _style_card_button(theme: Theme) -> void:
	var type_name := &"WorkshopCardButton"
	theme.set_type_variation(type_name, &"Button")
	theme.set_stylebox("normal", type_name, _box(Color("131b23"), BORDER, 5))
	theme.set_stylebox("hover", type_name, _box(Color("1d3040"), CYAN, 5, 2))
	theme.set_stylebox("pressed", type_name, _box(Color("3d3020"), AMBER, 5, 2))
	theme.set_stylebox("hover_pressed", type_name, _box(Color("4c3922"), AMBER.lightened(0.15), 5, 2))
	theme.set_stylebox("focus", type_name, _outline(AMBER, 5, 2))


static func _style_line_edit(theme: Theme) -> void:
	for type_name in [&"LineEdit", &"TextEdit"]:
		theme.set_stylebox("normal", type_name, _box(Color("161f28"), BORDER, 3))
		theme.set_stylebox("focus", type_name, _box(Color("192632"), CYAN, 3, 2))
		theme.set_stylebox("read_only", type_name, _box(Color("1a2027"), Color("2b3540"), 3))
		theme.set_color("font_color", type_name, INK)
		theme.set_color("font_uneditable_color", type_name, MUTED)
		theme.set_color("caret_color", type_name, AMBER)
		theme.set_color("selection_color", type_name, Color(CYAN, 0.38))


static func _style_tabs(theme: Theme) -> void:
	theme.set_stylebox("panel", &"TabContainer", _box(Color("151d26"), Color("2d3946"), 4))
	theme.set_type_variation(&"WorkshopTabBar", &"TabBar")
	var unselected := _box(Color("19222b"), Color("303c49"), 3)
	var hovered := _box(Color("223442"), CYAN.darkened(0.18), 3)
	var selected := _box(Color("2a3743"), AMBER, 3)
	selected.border_width_bottom = 3
	theme.set_stylebox("tab_unselected", &"WorkshopTabBar", unselected)
	theme.set_stylebox("tab_hovered", &"WorkshopTabBar", hovered)
	theme.set_stylebox("tab_selected", &"WorkshopTabBar", selected)
	theme.set_stylebox("tab_disabled", &"WorkshopTabBar", _box(Color("171c22"), Color("262e37"), 3))
	theme.set_stylebox("tab_focus", &"WorkshopTabBar", _outline(CYAN, 3, 2))
	theme.set_color("font_unselected_color", &"WorkshopTabBar", MUTED)
	theme.set_color("font_hovered_color", &"WorkshopTabBar", Color.WHITE)
	theme.set_color("font_selected_color", &"WorkshopTabBar", Color("ffe4ae"))
	theme.set_color("font_disabled_color", &"WorkshopTabBar", MUTED.darkened(0.3))


static func _style_sub_tabs(theme: Theme) -> void:
	var type_name := &"WorkshopSubTabBar"
	theme.set_type_variation(type_name, &"TabBar")
	theme.set_stylebox("tab_unselected", type_name, _compact_box(Color("151d25"), Color("2b3742")))
	theme.set_stylebox("tab_hovered", type_name, _compact_box(Color("20313e"), CYAN.darkened(0.2)))
	var selected := _compact_box(Color("223441"), CYAN, 2)
	selected.border_width_bottom = 2
	theme.set_stylebox("tab_selected", type_name, selected)
	theme.set_stylebox("tab_disabled", type_name, _compact_box(Color("151a20"), Color("252d35")))
	theme.set_stylebox("tab_focus", type_name, _outline(CYAN, 3, 1))
	theme.set_color("font_unselected_color", type_name, MUTED)
	theme.set_color("font_hovered_color", type_name, Color.WHITE)
	theme.set_color("font_selected_color", type_name, Color("d8f3ff"))


static func _style_item_list(theme: Theme) -> void:
	theme.set_stylebox("panel", &"ItemList", _box(Color("141c24"), Color("2c3844"), 3))
	theme.set_stylebox("focus", &"ItemList", _outline(CYAN.darkened(0.2), 3, 1))
	theme.set_stylebox("cursor", &"ItemList", _box(Color("4a3821"), AMBER, 3, 2))
	theme.set_stylebox("cursor_unfocused", &"ItemList", _box(Color("303945"), Color("667789"), 3))
	theme.set_stylebox("selected", &"ItemList", _box(Color("473722"), AMBER, 3, 2))
	theme.set_stylebox("selected_focus", &"ItemList", _box(Color("503b22"), AMBER.lightened(0.12), 3, 2))
	theme.set_color("font_color", &"ItemList", MUTED)
	theme.set_color("font_selected_color", &"ItemList", Color("fff0cf"))
	theme.set_color("guide_color", &"ItemList", Color("34414e"))


static func _style_check_controls(theme: Theme) -> void:
	for type_name in [&"CheckBox", &"CheckButton"]:
		theme.set_color("font_color", type_name, INK)
		theme.set_color("font_hover_color", type_name, Color.WHITE)
		theme.set_color("font_pressed_color", type_name, Color("fff0cf"))
		theme.set_color("font_disabled_color", type_name, MUTED.darkened(0.28))
		theme.set_stylebox("focus", type_name, _outline(CYAN, 3, 1))


static func _box(
	background: Color,
	border: Color,
	radius := 4,
	border_width := 1,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


static func _outline(color: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.draw_center = false
	style.border_color = color
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


static func _compact_box(background: Color, border: Color, border_width := 1) -> StyleBoxFlat:
	var style := _box(background, border, 3, border_width)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style
