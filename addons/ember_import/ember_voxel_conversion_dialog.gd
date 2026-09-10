@tool
extends "res://addons/ember_import/ember_voxel_shape_dialog.gd"
const Conversion = preload("res://addons/ember_import/ember_voxel_primitive_conversion.gd")
var _original: MeshInstance3D
var _original_preview: MeshInstance3D
var _show_original: CheckButton
var _previous_density := 16

func open_conversion(selected: Node, scene: Node, undo: Object, block_size: float) -> bool:
	var data := Conversion.inspect(selected,scene)
	if data.has("error"):
		push_warning(data.error)
		return false
	_original = data.mesh
	_root = scene
	_undo = undo
	_world_size = block_size
	_density.item_selected.connect(_conversion_density_changed)
	title = "Преобразовать форму в voxel"
	get_ok_button().text = "Преобразовать и открыть Canvas"
	_title.text = str(_original.get_parent().name) if _original.name == &"Visual" else str(_original.name)
	_kind.select(["empty","block","cylinder","sphere"].find(data.kind))
	_kind.disabled = true
	_kind.hide()
	_kind_changed()
	_color.color = data.color
	for axis in 3:
		_sizes[axis].value = maxi(1,roundi(data.extent[axis] * 16.0 / block_size))
	_show_original = CheckButton.new()
	_show_original.text = "Показать исходную форму вместо вокселей"
	_show_original.toggled.connect(func(enabled: bool):
		if is_instance_valid(_preview):
			_preview.visible = not enabled
		if is_instance_valid(_original_preview):
			_original_preview.visible = enabled
	)
	var box := _status.get_parent()
	box.add_child(_show_original)
	box.move_child(_show_original,_status.get_index())
	_prepare()
	popup_centered()
	return true

func _conversion_density_changed(_index: int) -> void:
	var density := _density.get_selected_id()
	for control in _sizes:
		control.value = maxi(1,roundi(control.value * float(density) / _previous_density))
	_previous_density = density
	_invalidate()

func _prepare() -> void:
	if not is_instance_valid(_original):
		return
	creation = Conversion.new()
	var dimensions := Vector3i(_sizes[0].value,_sizes[1].value,_sizes[2].value)
	if _kind.selected == 2:
		dimensions.z = dimensions.x
	elif _kind.selected == 3:
		dimensions = Vector3i.ONE * dimensions.x
	if not _check_large_budget(dimensions):
		return
	if not creation.prepare(_original,_root,dimensions,_density.get_selected_id(),_color.color,_title.text,_world_size):
		_status.text = creation.error
		get_ok_button().disabled = true
		return
	if is_instance_valid(_preview):
		_preview.free()
	if is_instance_valid(_original_preview):
		_original_preview.free()
	_preview = creation.packed.instantiate()
	_preview.configure_voxel_scale(creation.source.normalized_density(),_world_size)
	_preview.transform = creation.fit
	_world.add_child(_preview)
	_original_preview = MeshInstance3D.new()
	_original_preview.mesh = _original.mesh
	_original_preview.material_override = _original.get_active_material(0)
	_world.add_child(_original_preview)
	_preview.visible = not _show_original.button_pressed
	_original_preview.visible = _show_original.button_pressed
	var extent: Vector3 = creation.report.dimensions
	var actual: Vector3 = Conversion.inspect(_original,_root).extent
	_camera.size = actual[actual.max_axis_index()] * 1.8
	_camera.position = Vector3(1,0.8,1).normalized() * _camera.size * 2
	_camera.look_at(Vector3.ZERO)
	_status.text = "Габариты: %s · сетка: %s vox\nШаг: %s (локальные единицы).\nПодгонка масштаба сохраняет размер; кривые станут ступенчатыми.\nОдин цвет. %s" % [actual,creation.report.grid,actual / extent,"Коллизия пересобирается." if creation.source.physical else "Без коллизии."]
	_status.tooltip_text = "Применение заменяет исходную модель. Undo возвращает исходник и его коллизию. Файлы создаются только при применении; Undo их не удаляет. Для точной сборки позже потребуется согласованная voxel-сетка."
	get_ok_button().disabled = false

func _commit() -> void:
	var prop: EmberVoxelProp = creation.commit(_undo)
	if prop == null:
		_status.text = creation.error
		return
	hide()
	created.emit(prop)
