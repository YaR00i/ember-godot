@tool
class_name EmberVoxelSurfaceInspectorPanel
extends VBoxContainer
## Navigation card for external Surface Resources. Visual voxels and gameplay
## rules intentionally have different owners, but authors should never need to
## remember the parallel content paths.

const SculptModel = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")

var _surface: EmberVoxelModelResource
var _editor_interface: EditorInterface
var _open_surface_callback: Callable
var _battlefield_path := ""


func setup(
	surface: EmberVoxelModelResource,
	editor_interface: EditorInterface,
	open_surface_callback := Callable(),
) -> void:
	_surface = surface
	_editor_interface = editor_interface
	_open_surface_callback = open_surface_callback
	name = "VoxelSurfaceInspectorNavigation"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "EMBER SURFACE"
	title.modulate = Color("62d7e6")
	add_child(title)
	var identity := Label.new()
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.text = "Сейчас выбран визуальный voxel-слой. Форма и вода редактируются здесь; игровые правила принадлежат карте или полю боя."
	identity.modulate = Color(0.67, 0.72, 0.8)
	add_child(identity)

	var edit_surface := Button.new()
	edit_surface.name = "OpenSurfaceCanvasFromInspector"
	edit_surface.text = "Редактировать в Surface Canvas"
	edit_surface.disabled = not _open_surface_callback.is_valid()
	edit_surface.pressed.connect(_open_surface)
	add_child(edit_surface)

	if "battlefield" not in surface.tags:
		return
	_battlefield_path = battlefield_path_for(surface)
	var rules_hint := Label.new()
	rules_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_hint.text = (
		"Wet и реакции находятся в Battlefield Resource. Откройте его, затем используйте "
		+ "блок «Visual Surface → правила воды»."
	)
	rules_hint.modulate = Color("e2b85b")
	add_child(rules_hint)
	var open_rules := Button.new()
	open_rules.name = "OpenBattlefieldRulesFromSurface"
	open_rules.text = (
		"Открыть правила боя · %s" % _owner_id()
		if not _battlefield_path.is_empty()
		else "Battlefield Resource не найден"
	)
	open_rules.disabled = _battlefield_path.is_empty()
	open_rules.pressed.connect(_open_battlefield_rules)
	add_child(open_rules)


static func battlefield_path_for(surface: EmberVoxelModelResource) -> String:
	return SculptModel.battlefield_resource_path_for_surface(surface)


func _owner_id() -> String:
	return str(_surface.material.get("semanticOwner", "")).strip_edges()


func _open_surface() -> void:
	if _open_surface_callback.is_valid():
		_open_surface_callback.call(_surface)


func _open_battlefield_rules() -> void:
	if _editor_interface == null or _battlefield_path.is_empty():
		return
	var battlefield := load(_battlefield_path) as EmberBattlefieldResource
	if battlefield != null:
		_editor_interface.edit_resource(battlefield)
