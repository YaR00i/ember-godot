@tool
class_name EmberBattlefieldTileLibraryPanel
extends VBoxContainer
## One shared editor-only viewport previews all authored Battlefield tile meshes.

const Contract := preload("res://scripts/prototypes/ember_battlefield_tile_library.gd")
const PREVIEW_SIZE := Vector2i(720, 190)

var _viewport: SubViewport


func setup(library: MeshLibrary) -> void:
	name = "BattlefieldTileLibraryPreview"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "БОЕВЫЕ ТАЙЛЫ · ОБЩАЯ MESHLIBRARY"
	title.modulate = Color("e2b85b")
	add_child(title)

	var path := Label.new()
	path.text = library.resource_path if library != null else "MeshLibrary не назначена"
	path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path.tooltip_text = path.text
	add_child(path)

	var preview := SubViewportContainer.new()
	preview.name = "BattlefieldTilePreviewContainer"
	preview.custom_minimum_size = Vector2(0.0, 142.0)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.stretch = true
	add_child(preview)
	_viewport = SubViewport.new()
	_viewport.name = "BattlefieldTilePreviewViewport"
	_viewport.size = PREVIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_4X
	preview.add_child(_viewport)
	_build_stage(library)

	var labels := HBoxContainer.new()
	labels.name = "BattlefieldTileLabels"
	add_child(labels)
	for raw_item_id in Contract.EXPECTED_NAMES:
		var item_id := int(raw_item_id)
		var label := Label.new()
		label.text = "%d · %s" % [item_id, Contract.EXPECTED_NAMES[item_id]]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		labels.add_child(label)

	var diagnostics := Label.new()
	diagnostics.name = "BattlefieldTileLibraryDiagnostics"
	diagnostics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var errors := Contract.validation_errors(library)
	if errors.is_empty():
		diagnostics.text = "✓ ID 0–4, mesh и collision корректны. GridMap использует этот Resource как visual projection."
		diagnostics.modulate = Color("7bc995")
	else:
		diagnostics.text = "⚠ %s" % "\n⚠ ".join(errors)
		diagnostics.modulate = Color("f08a82")
	add_child(diagnostics)
	_request_preview.call_deferred()


func _build_stage(library: MeshLibrary) -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111827")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.8, 1.0)
	environment.ambient_light_energy = 0.72
	environment_node.environment = environment
	_viewport.add_child(environment_node)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-54.0, -34.0, 0.0)
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 1.35
	key.shadow_enabled = false
	_viewport.add_child(key)

	if library != null:
		for raw_item_id in Contract.EXPECTED_NAMES:
			var item_id := int(raw_item_id)
			if not Contract.has_item(library, item_id) or library.get_item_mesh(item_id) == null:
				continue
			var instance := MeshInstance3D.new()
			instance.name = "BattlefieldTilePreview_%d" % item_id
			instance.mesh = library.get_item_mesh(item_id)
			instance.transform = library.get_item_mesh_transform(item_id)
			instance.position.x += (float(item_id) - 2.0) * 1.55
			_viewport.add_child(instance)

	var camera := Camera3D.new()
	camera.name = "BattlefieldTilePreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	camera.near = 0.05
	camera.far = 100.0
	camera.look_at_from_position(Vector3(5.6, 4.4, 7.2), Vector3.ZERO, Vector3.UP)
	_viewport.add_child(camera)
	camera.current = true


func _request_preview() -> void:
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
