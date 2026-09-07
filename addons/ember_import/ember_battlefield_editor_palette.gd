@tool
class_name EmberBattlefieldEditorPalette
extends RefCounted
## Shared visual metadata for Inspector and native 3D Battlefield authoring.

const ICON_SIZE := 16
static var _icon_cache: Dictionary = {}


static func entries() -> Array:
	return [
		["Обычная", EmberBattlefieldResource.PaintTool.NEUTRAL],
		["Wet", EmberBattlefieldResource.PaintTool.WET],
		["Ember", EmberBattlefieldResource.PaintTool.EMBER],
		["Frozen", EmberBattlefieldResource.PaintTool.FROZEN],
		["Преграда", EmberBattlefieldResource.PaintTool.BLOCKED],
		["Высота +", EmberBattlefieldResource.PaintTool.HEIGHT_UP],
		["Высота −", EmberBattlefieldResource.PaintTool.HEIGHT_DOWN],
		["Фокус", EmberBattlefieldResource.PaintTool.FOCUS],
		["Точка героев", EmberBattlefieldResource.PaintTool.PARTY_DEPLOYMENT],
		["Точка врагов", EmberBattlefieldResource.PaintTool.ENEMY_DEPLOYMENT],
	]


static func populate(button: OptionButton) -> void:
	for entry in entries():
		var tool := int(entry[1])
		button.add_icon_item(tool_icon(tool), str(entry[0]))
		button.set_item_metadata(button.item_count - 1, tool)


static func tool_label(tool: int) -> String:
	for entry in entries():
		if int(entry[1]) == tool:
			return str(entry[0])
	return "Неизвестная кисть"


static func tool_color(tool: int) -> Color:
	var colors := [
		Color("a9bed8"), Color("45bce8"), Color("f19a5b"), Color("9bd7ff"),
		Color("d87888"), Color("ffe17a"), Color("c7b6ff"), Color("ffbf47"),
		Color("62d7e6"), Color("f07883"),
	]
	return colors[clampi(tool, 0, colors.size() - 1)]


static func tool_icon(tool: int) -> Texture2D:
	if _icon_cache.has(tool) and is_instance_valid(_icon_cache[tool]):
		return _icon_cache[tool] as Texture2D
	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var color := tool_color(tool)
	image.fill(color.darkened(0.42))
	for y in range(2, ICON_SIZE - 2):
		for x in range(2, ICON_SIZE - 2):
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[tool] = texture
	return texture
