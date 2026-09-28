@tool
extends RefCounted
## Scoped Ember Workshop theme. It is merged over the active Godot theme so
## editor fonts, icons and DPI remain native while workshop controls share one skin.

const INK := Color("ece9e4")
const MUTED := Color("a39f99")
const HOVER := Color("c27b43")
const AMBER := Color("f18b3b")
const ERROR := Color("ef6a61")
const SURFACE := Color("252527")
const SURFACE_RAISED := Color("323234")
const SURFACE_LOW := Color("19191b")
const BORDER := Color("454347")


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
	_style_slider(result)
	return result


static func _style_slider(theme: Theme) -> void:
	for key in [&"slider",&"grabber_area",&"grabber_area_highlight",&"grabber_area_disabled"]:
		var fill := Color("454347")
		if key == &"grabber_area": fill = HOVER
		if key == &"grabber_area_highlight": fill = AMBER
		var bar := StyleBoxFlat.new()
		bar.bg_color = fill
		bar.set_corner_radius_all(2)
		bar.content_margin_top = 2.0
		bar.content_margin_bottom = 2.0
		theme.set_stylebox(key,&"HSlider",bar)
	theme.set_icon("grabber",&"HSlider",_slider_grabber(INK))
	theme.set_icon("grabber_highlight",&"HSlider",_slider_grabber(AMBER))
	theme.set_icon("grabber_disabled",&"HSlider",_slider_grabber(MUTED.darkened(0.35)))


static func _slider_grabber(color: Color) -> Texture2D:
	var pixels := Image.create(14,14,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	for y in 14:
		for x in 14:
			var squared := Vector2(x-6.5,y-6.5).length_squared()
			if squared <= 42.25:
				pixels.set_pixel(x,y,Color("242426") if squared > 30.25 else color)
	return ImageTexture.create_from_image(pixels)


static func _style_button(theme: Theme, type_name: StringName) -> void:
	theme.set_stylebox("normal", type_name, _box(SURFACE, BORDER))
	theme.set_stylebox("hover", type_name, _box(SURFACE_RAISED, HOVER.darkened(0.18)))
	theme.set_stylebox("pressed", type_name, _box(Color("493021"), AMBER, 4, 2))
	theme.set_stylebox("hover_pressed", type_name, _box(Color("5a3823"), AMBER.lightened(0.12), 4, 2))
	theme.set_stylebox("disabled", type_name, _box(Color("1d1d1f"), Color("353436")))
	theme.set_stylebox("focus", type_name, _outline(HOVER, 4, 2))
	theme.set_color("font_color", type_name, INK)
	theme.set_color("font_hover_color", type_name, Color.WHITE)
	theme.set_color("font_pressed_color", type_name, Color("fff0cf"))
	theme.set_color("font_hover_pressed_color", type_name, Color.WHITE)
	theme.set_color("font_disabled_color", type_name, MUTED.darkened(0.28))
	theme.set_color("font_focus_color", type_name, Color.WHITE)
	theme.set_color("icon_normal_color", type_name, MUTED)
	theme.set_color("icon_hover_color", type_name, INK)
	theme.set_color("icon_pressed_color", type_name, AMBER)
	theme.set_color("icon_hover_pressed_color", type_name, AMBER.lightened(0.16))
	theme.set_color("icon_disabled_color", type_name, MUTED.darkened(0.3))
	theme.set_constant("h_separation", type_name, 6)


static func _style_primary_button(theme: Theme) -> void:
	var type_name := &"WorkshopPrimaryButton"
	theme.set_type_variation(type_name, &"Button")
	theme.set_stylebox("normal", type_name, _box(Color("78421e"), AMBER, 4, 1))
	theme.set_stylebox("hover", type_name, _box(Color("955025"), AMBER.lightened(0.18), 4, 2))
	theme.set_stylebox("pressed", type_name, _box(Color("ad5d2c"), Color("ffbc75"), 4, 2))
	theme.set_stylebox("hover_pressed", type_name, _box(Color("b96731"), Color("ffd09a"), 4, 2))
	theme.set_stylebox("disabled", type_name, _box(Color("292523"), Color("4c3c33")))
	theme.set_stylebox("focus", type_name, _outline(Color("ffbc75"), 4, 2))
	theme.set_color("font_color", type_name, Color("fff2d4"))
	theme.set_color("font_hover_color", type_name, Color.WHITE)
	theme.set_color("font_pressed_color", type_name, Color.WHITE)
	theme.set_color("font_disabled_color", type_name, MUTED.darkened(0.25))


static func _style_tool_button(theme: Theme) -> void:
	var type_name := &"WorkshopToolButton"
	theme.set_type_variation(type_name, &"Button")
	theme.set_stylebox("normal", type_name, _box(Color("222224"), Color("3d3b3e"), 3))
	theme.set_stylebox("hover", type_name, _box(Color("333032"), HOVER.darkened(0.15), 3, 1))
	theme.set_stylebox("pressed", type_name, _box(Color("493021"), AMBER, 3, 2))
	theme.set_stylebox("hover_pressed", type_name, _box(Color("5a3823"), AMBER.lightened(0.12), 3, 2))
	theme.set_color("font_pressed_color", type_name, Color("fff0cd"))
	theme.set_color("font_hover_pressed_color", type_name, Color.WHITE)


static func _style_segment_button(theme: Theme) -> void:
	var type_name := &"WorkshopSegmentButton"
	theme.set_type_variation(type_name, &"Button")
	theme.set_stylebox("normal", type_name, _compact_box(Color("202022"), Color("3d3b3e")))
	theme.set_stylebox("hover", type_name, _compact_box(Color("333032"), HOVER.darkened(0.15)))
	theme.set_stylebox("pressed", type_name, _compact_box(Color("493021"), AMBER, 2))
	theme.set_stylebox("hover_pressed", type_name, _compact_box(Color("5a3823"), AMBER.lightened(0.12), 2))
	theme.set_stylebox("focus", type_name, _outline(HOVER, 3, 1))
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
	theme.set_stylebox("normal", type_name, _box(Color("1c1c1e"), BORDER, 5))
	theme.set_stylebox("hover", type_name, _box(Color("302c2a"), HOVER, 5, 2))
	theme.set_stylebox("pressed", type_name, _box(Color("443023"), AMBER, 5, 2))
	theme.set_stylebox("hover_pressed", type_name, _box(Color("543825"), AMBER.lightened(0.15), 5, 2))
	theme.set_stylebox("focus", type_name, _outline(AMBER, 5, 2))


static func _style_line_edit(theme: Theme) -> void:
	for type_name in [&"LineEdit", &"TextEdit"]:
		theme.set_stylebox("normal", type_name, _box(Color("1c1c1e"), BORDER, 3))
		theme.set_stylebox("focus", type_name, _box(Color("292625"), HOVER, 3, 2))
		theme.set_stylebox("read_only", type_name, _box(Color("202022"), Color("353436"), 3))
		theme.set_color("font_color", type_name, INK)
		theme.set_color("font_uneditable_color", type_name, MUTED)
		theme.set_color("caret_color", type_name, AMBER)
		theme.set_color("selection_color", type_name, Color(HOVER, 0.38))


static func _style_tabs(theme: Theme) -> void:
	theme.set_stylebox("panel", &"TabContainer", _box(Color("1b1b1d"), Color("3b393c"), 4))
	theme.set_type_variation(&"WorkshopTabBar", &"TabBar")
	var unselected := _box(Color("222224"), Color("3d3b3e"), 3)
	var hovered := _box(Color("322e2d"), HOVER.darkened(0.18), 3)
	var selected := _box(Color("403023"), AMBER, 3)
	selected.border_width_bottom = 3
	theme.set_stylebox("tab_unselected", &"WorkshopTabBar", unselected)
	theme.set_stylebox("tab_hovered", &"WorkshopTabBar", hovered)
	theme.set_stylebox("tab_selected", &"WorkshopTabBar", selected)
	theme.set_stylebox("tab_disabled", &"WorkshopTabBar", _box(Color("1d1d1f"), Color("303033"), 3))
	theme.set_stylebox("tab_focus", &"WorkshopTabBar", _outline(HOVER, 3, 2))
	theme.set_color("font_unselected_color", &"WorkshopTabBar", MUTED)
	theme.set_color("font_hovered_color", &"WorkshopTabBar", Color.WHITE)
	theme.set_color("font_selected_color", &"WorkshopTabBar", Color("ffe4ae"))
	theme.set_color("font_disabled_color", &"WorkshopTabBar", MUTED.darkened(0.3))


static func _style_sub_tabs(theme: Theme) -> void:
	var type_name := &"WorkshopSubTabBar"
	theme.set_type_variation(type_name, &"TabBar")
	theme.set_stylebox("tab_unselected", type_name, _compact_box(Color("1d1d1f"), Color("39373a")))
	theme.set_stylebox("tab_hovered", type_name, _compact_box(Color("302d2c"), HOVER.darkened(0.2)))
	var selected := _compact_box(Color("403023"), AMBER, 2)
	selected.border_width_bottom = 2
	theme.set_stylebox("tab_selected", type_name, selected)
	theme.set_stylebox("tab_disabled", type_name, _compact_box(Color("1c1c1e"), Color("303033")))
	theme.set_stylebox("tab_focus", type_name, _outline(HOVER, 3, 1))
	theme.set_color("font_unselected_color", type_name, MUTED)
	theme.set_color("font_hovered_color", type_name, Color.WHITE)
	theme.set_color("font_selected_color", type_name, Color("ffe6cc"))


static func _style_item_list(theme: Theme) -> void:
	theme.set_stylebox("panel", &"ItemList", _box(Color("1c1c1e"), Color("3b393c"), 3))
	theme.set_stylebox("focus", &"ItemList", _outline(HOVER.darkened(0.2), 3, 1))
	theme.set_stylebox("cursor", &"ItemList", _box(Color("493021"), AMBER, 3, 2))
	theme.set_stylebox("cursor_unfocused", &"ItemList", _box(Color("343335"), Color("77716b"), 3))
	theme.set_stylebox("selected", &"ItemList", _box(Color("493021"), AMBER, 3, 2))
	theme.set_stylebox("selected_focus", &"ItemList", _box(Color("573723"), AMBER.lightened(0.12), 3, 2))
	theme.set_color("font_color", &"ItemList", MUTED)
	theme.set_color("font_selected_color", &"ItemList", Color("fff0cf"))
	theme.set_color("guide_color", &"ItemList", Color("454144"))


static func _style_check_controls(theme: Theme) -> void:
	for type_name in [&"CheckBox", &"CheckButton"]:
		theme.set_color("font_color", type_name, INK)
		theme.set_color("font_hover_color", type_name, Color.WHITE)
		theme.set_color("font_pressed_color", type_name, Color("fff0cf"))
		theme.set_color("font_disabled_color", type_name, MUTED.darkened(0.28))
		theme.set_stylebox("focus", type_name, _outline(HOVER, 3, 1))


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
