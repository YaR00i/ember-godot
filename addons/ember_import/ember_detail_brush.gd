@tool
extends "res://addons/ember_import/ember_voxel_object_brush.gd"
## Density authoring uses the existing pointer/camera/one-stroke input controller.
const Patch = preload("res://scripts/ember_grass_patch.gd")
const Detail = preload("res://scripts/ember_detail_scatter.gd")
const PatternBake = preload("res://scripts/ember_detail_pattern_bake.gd")
const Cover = preload("res://scripts/ember_flowered_grass.gd")
var cover_pattern: EmberCompactTerrainPattern
var _cover_window: Window
var _cover_dialog
var _cover_button: Button
var _cover_group: VBoxContainer
var radius_m := 0.65
var density_per_m2 := 60.0
var detail_kind := 0
var pattern_preset: Resource
var pattern_variant := -1
var _pattern_ready := false
var _pattern_count := 0
var _selection_epoch := 0
var _variant_group: VBoxContainer
var size_value := 1.0
var jitter := 0.8
var variation := 0.25
var yaw_range := 180.0
var seed_value := 7
var erase := false
var panel: VBoxContainer
var controls: Dictionary = {}
var _map: EmberMapLoader
var _before: Dictionary = {}
var _drafts: Dictionary = {}
var _created: Array[Node] = []
var _status: Label
var _patch_lookup: Dictionary = {}

func build_panel() -> VBoxContainer:
	if panel != null: return panel
	panel = VBoxContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new(); title.text = "Кисть деталей"; panel.add_child(title)
	var hint := Label.new(); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "ЛКМ / протянуть — рисовать. Ctrl+Z — отменить мазок, Ctrl+S — сохранить сцену. Esc выключает кисть.\nЛастик убирает только нарисованные здесь детали."
	panel.add_child(hint)
	var choice := OptionButton.new(); choice.add_item("Трава"); choice.add_item("Камушки на песке"); choice.add_item("Цветущая трава")
	panel.add_child(choice); controls.kind = choice
	choice.item_selected.connect(select_kind)
	_cover_group=VBoxContainer.new();panel.add_child(_cover_group);_cover_group.hide()
	var cover_label:=Label.new();cover_label.text="Набор цветов";_cover_group.add_child(cover_label)
	var cover_choice:=OptionButton.new();_cover_group.add_child(cover_choice);controls.cover=cover_choice
	for entry in Cover.SETS:cover_choice.add_item(entry[0])
	cover_choice.item_selected.connect(select_cover)
	_cover_button = Button.new(); _cover_button.text = "Рисунок цветущей травы…"; _cover_button.hide(); panel.add_child(_cover_button)
	_cover_button.pressed.connect(_edit_cover)
	var refresh := Button.new(); refresh.text = "Обновить библиотеку"; panel.add_child(refresh)
	refresh.tooltip_text = "Сначала сохраните источник в Surface Canvas. Эта кнопка перечитает сохранённые наборы и обновит их экземпляры."
	refresh.pressed.connect(func(): refresh_patterns(true)); controls.refresh = refresh
	_variant_group = VBoxContainer.new(); panel.add_child(_variant_group); _variant_group.hide()
	var variant_label := Label.new(); variant_label.text = "Варианты набора"; _variant_group.add_child(variant_label)
	var variants := OptionButton.new(); _variant_group.add_child(variants); controls.variant = variants
	variants.item_selected.connect(func(index): cancel_stroke(); pattern_variant = index - 1)
	for spec in [["Радиус мазка · м","radius_m",0.15,4.0,0.05],["Плотность · на м²","density_per_m2",0.0,200.0,1.0],["Размер объектов · ×","size_value",0.2,4.0,0.05],["Разброс положения","jitter",0.0,1.0,0.05],["Вариация размера","variation",0.0,0.75,0.05],["Разброс поворота · °","yaw_range",0.0,180.0,5.0],["Вариант · seed","seed_value",0,1000000,1]]:
		var label := Label.new(); label.text = spec[0]; panel.add_child(label)
		var number := SpinBox.new(); number.min_value = spec[2]; number.max_value = spec[3]; number.step = spec[4]; number.value = get(spec[1]); panel.add_child(number)
		var key: String = spec[1]; controls[key] = number
		if key == "size_value": number.tooltip_text = "1 — исходный размер, 2 — вдвое больше. Увеличьте для высокой камеры; площадь мазка задаётся отдельно."
		if key == "radius_m": number.tooltip_text = "Радиус области, в которой кисть размещает детали. Размер самих деталей задаётся ниже."
		number.value_changed.connect(func(value): cancel_stroke(); set(key, int(value) if key == "seed_value" else value); spacing_blocks = maxf(0.05, radius_m * 0.3))
	var eraser := CheckBox.new(); eraser.text = "Стирать плотность"; panel.add_child(eraser); controls.erase = eraser
	eraser.toggled.connect(func(value): cancel_stroke(); erase = value)
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; panel.add_child(_status)
	refresh_patterns()
	return panel

func refresh_patterns(reload_saved := false) -> void:
	cancel_stroke()
	var choice: OptionButton = controls.kind
	var selected := pattern_preset.resource_path if pattern_preset != null else ""
	choice.clear(); choice.add_item("Трава"); choice.add_item("Камушки на песке"); choice.add_item("Цветущая трава")
	var selected_index := 2 if detail_kind == 3 else detail_kind if detail_kind < 2 else 0
	for entry in PatternBake.choices(reload_saved):
		var suffix := "форма" if entry.variant_count == 1 else "формы" if entry.variant_count in [2,3,4] else "форм"
		choice.add_item(entry.name + " · %d %s" % [entry.variant_count,suffix])
		var index := choice.item_count - 1
		choice.set_item_metadata(index,entry.path)
		var rejected_flower: bool = entry.path.get_file() in ["vox_detail_daisy.tres","vox_detail_wildflowers.tres"]
		if rejected_flower:
			entry.supported = false; entry.reason = "Отклонённая воксельная проба. Выберите «Цветущая трава»."
			choice.set_item_text(index,entry.name + " · прежняя воксельная проба")
		choice.set_item_disabled(index,not entry.supported)
		choice.set_item_tooltip(index,entry.path if entry.supported else entry.reason)
		if entry.path == selected and entry.supported: selected_index = index
	choice.select(selected_index)
	if detail_kind == 2: select_kind(selected_index,false)

func select_kind(index: int, reset_density := true) -> void:
	cancel_stroke(); _selection_epoch += 1; _pattern_ready = false
	var epoch := _selection_epoch
	pattern_preset = null; pattern_variant = -1
	_variant_group.visible = index >= 3
	_cover_button.visible = index == 2
	_cover_group.visible = index == 2
	if index < 3:
		detail_kind = 3 if index == 2 else index
		if detail_kind == 3 and cover_pattern == null: cover_pattern = load(Cover.PATTERN_PATH)
		if reset_density: density_per_m2 = 10.0 if detail_kind == 3 else 60.0 if index == 0 else 9.0
		controls.density_per_m2.set_value_no_signal(density_per_m2)
		return
	detail_kind = 2
	controls.variant.disabled = true
	var path: String = controls.kind.get_item_metadata(index)
	pattern_preset = load(path)
	_status.text = "Подготовка трёх обликов набора…"
	var prepared: Dictionary = await PatternBake.prepare(pattern_preset,self)
	if epoch != _selection_epoch: return
	if prepared.has("error"):
		_status.text = prepared.error; return
	_pattern_count = prepared.variants.size()
	_variant_group.visible = _pattern_count > 1
	var variants: OptionButton = controls.variant; variants.clear()
	variants.add_item("Смешивать все %d" % _pattern_count)
	for i in _pattern_count: variants.add_item("Вариант %d" % (i+1))
	variants.select(0); pattern_variant = -1; variants.disabled = false
	_pattern_ready = true
	if reset_density: density_per_m2 = 9.0
	controls.density_per_m2.set_value_no_signal(density_per_m2)
	_status.text = "Набор готов · %d форм, три облика" % _pattern_count

func select_cover(index: int) -> void:
	cancel_stroke()
	if _cover_dialog != null and _cover_dialog.is_dirty():
		for i in Cover.SETS.size():
			if cover_pattern.resource_path==Cover.SETS[i][1]:controls.cover.select(i)
		_status.text="Сначала сохраните или отмените рисунок открытого набора.";return
	if _cover_dialog != null: _cover_dialog.cancel_edit()
	cover_pattern=load(Cover.SETS[index][1]);controls.cover.select(index)

func activate_details(scene: Node3D, map: EmberMapLoader, undo: Object) -> bool:
	deactivate()
	if scene == null or map == null or undo == null or map.get_node_or_null("Props") == null: return false
	_scene = scene; _map = map; _parent = map.get_node("Props"); _undo = undo; _tile_size = map.imported_tile_size
	model_id = "details"; spacing_blocks = maxf(0.05, radius_m * 0.3)
	_preview = Node3D.new(); scene.add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	_hover = _make_ghost(); _preview.add_child(_hover); _hover.hide()
	_stroke = Node3D.new(); _preview.add_child(_stroke)
	active = true; changed.emit(); return true

func transform_at(point: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3(radius_m * _tile_size, 1, radius_m * _tile_size)), point + Vector3.UP * 0.04)

func _make_ghost() -> Node3D:
	var mesh := CylinderMesh.new(); mesh.top_radius = 1; mesh.bottom_radius = 1; mesh.height = 0.04; mesh.radial_segments = 48
	var material := StandardMaterial3D.new(); material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color(0.2, 0.85, 0.8, 0.28)
	var visual := MeshInstance3D.new(); visual.mesh = mesh; visual.material_override = material; visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual

func _snapshot(patch: Node) -> Dictionary:
	return {"cells":patch.density_cells.duplicate(),"size":patch.tuft_size,"seed":patch.scatter_seed,"jitter":patch.detail_jitter,"variation":patch.detail_variation,"yaw":patch.detail_yaw}

func _index_patches() -> void:
	_patch_lookup.clear()
	var frame: Transform3D = _parent.global_transform.affine_inverse() * _map.global_transform
	for node in _parent.get_children():
		if node.get_script() != Patch or not node.painted_only or node.detail_kind != detail_kind: continue
		if detail_kind == 3:
			var wanted: String = cover_pattern.resource_path if cover_pattern != null else Cover.PATTERN_PATH
			var actual: String = node.cover_pattern.resource_path if node.cover_pattern != null else Cover.PATTERN_PATH
			if wanted != actual: continue
		if detail_kind == 2 and (node.detail_preset != pattern_preset or node.detail_mixed != (pattern_variant < 0)): continue
		var origin: Vector3 = frame.affine_inverse() * node.position / (_tile_size * Detail.PATCH_M)
		var address := Vector2i(roundi(origin.x),roundi(origin.z))
		var expected: Transform3D = frame * Transform3D(Basis.IDENTITY,Vector3(address.x,0,address.y)*Detail.PATCH_M*_tile_size)
		if not node.transform.is_equal_approx(expected): continue
		_patch_lookup[Vector3i(address.x,address.y,node.detail_variant if detail_kind == 2 else 0)] = node

func _patch(address: Vector2i, variant := 0) -> Node3D:
	var key := "Detail%s_%d_%d" % ["Grass" if detail_kind == 0 else "Flowers" if detail_kind == 3 else "Pebbles", address.x, address.y]
	if detail_kind == 3 and cover_pattern != null and cover_pattern.resource_path != Cover.PATTERN_PATH:
		key="DetailFlowers_%s_%d_%d" % [cover_pattern.resource_path.sha256_text().substr(0,10),address.x,address.y]
	if detail_kind == 2:
		key = "DetailPattern_%s_%s%d_%d_%d" % [pattern_preset.geometry.model_id,"Mix" if pattern_variant < 0 else "One",variant,address.x,address.y]
	var slot := Vector3i(address.x,address.y,variant if detail_kind == 2 else 0)
	var patch := _patch_lookup.get(slot) as Node3D
	if patch == null and not erase:
		if _created.size() >= 64: return null
		patch = Patch.new(); patch.name = key; patch.painted_only = true; patch.detail_kind = detail_kind
		if detail_kind == 3: patch.cover_pattern = cover_pattern
		if detail_kind == 2:
			patch.detail_preset = pattern_preset; patch.detail_variant = variant; patch.detail_mixed = pattern_variant < 0
		_parent.add_child(patch,true); patch.transform = _parent.global_transform.affine_inverse() * _map.global_transform * Transform3D(Basis.IDENTITY, Vector3(address.x * Detail.PATCH_M * _tile_size, 0, address.y * Detail.PATCH_M * _tile_size))
		_created.append(patch)
		_patch_lookup[slot] = patch
	return patch

func _append(point: Vector3) -> void:
	if not active or not is_instance_valid(_map) or not is_instance_valid(_map._visual_surface_projection): return
	if detail_kind == 2 and not _pattern_ready: return
	var surface: Dictionary = _map.surface_floor_sample(point)
	if not surface.get("solid", false): return
	if surface.has("object") and detail_kind not in [0,3]:return
	if detail_kind in [0,3] and surface.get("material_role") not in ["grass", "soil"]: return
	if detail_kind == 1 and surface.get("material_role") != "sand": return
	if surface.get("submerged",false):return
	# Names remain stable after west/north growth; addresses follow the current frame.
	# Index once per stamp, rather than scanning scene nodes for every density cell.
	_index_patches()
	var local := _map.to_local(point) / _tile_size
	var center := Vector2(local.x, local.z)
	var low := Detail.cell_address(center - Vector2.ONE * radius_m)
	var high := Detail.cell_address(center + Vector2.ONE * radius_m)
	var modified := {}
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var cell := Vector2i(x, z); var p := (Vector2(cell) + Vector2(0.5,0.5)) * Detail.CELL_M
			var weight := clampf((radius_m - p.distance_to(center)) / minf(radius_m * 0.35, Detail.CELL_M), 0, 1)
			if weight <= 0: continue
			var address := Detail.patch_address(p)
			var variants: Array = range(_pattern_count) if detail_kind == 2 and pattern_variant < 0 else [maxi(0,pattern_variant)]
			for variant: int in variants:
				var patch := _patch(address,variant)
				if patch == null: continue
				var key := cell - address * Detail.CELLS
				var cells: Dictionary = _drafts[patch] if _drafts.has(patch) else patch.density_cells.duplicate()
				var density := 0 if erase else clampi(roundi(maxf(float(cells.get(key,0.0)), density_per_m2 * weight)), 0, 200)
				if is_equal_approx(float(cells.get(key,0.0)),density): continue
				if not _before.has(patch): _before[patch] = _snapshot(patch)
				if density == 0: cells.erase(key)
				else: cells[key] = density
				_drafts[patch] = cells
				modified[patch] = true
	for patch in modified:
		patch._detail_preview = {"cells":_drafts[patch],"size":size_value,"seed":seed_value,"jitter":jitter,"variation":variation,"yaw":yaw_range}
		patch._dirty = true
	if _status != null: _status.text = "Предпросмотр · %d плиток" % _drafts.size()

func cancel_stroke() -> void:
	super.cancel_stroke()
	for patch in _drafts:
		if is_instance_valid(patch): patch._detail_preview.clear(); patch._dirty = true
	_drafts.clear(); _before.clear()
	for patch in _created:
		if is_instance_valid(patch): patch.free()
	_created.clear()

func commit_stroke() -> int:
	_dragging = false
	if _drafts.is_empty(): cancel_stroke(); return 0
	if _undo is EditorUndoRedoManager: _undo.create_action("Мазок кисти деталей", UndoRedo.MERGE_DISABLE, _scene)
	else: _undo.create_action("Мазок кисти деталей")
	var count := 0
	for patch in _drafts:
		var after := {"cells":_drafts[patch].duplicate(),"size":size_value,"seed":seed_value,"jitter":jitter,"variation":variation,"yaw":yaw_range}
		if _undo is EditorUndoRedoManager:
			_undo.add_do_method(self,"_apply",patch,after,true)
			_undo.add_undo_method(self,"_apply",patch,_before[patch],not _created.has(patch))
		else:
			_undo.add_do_method(_apply.bind(patch,after,true))
			_undo.add_undo_method(_apply.bind(patch,_before[patch],not _created.has(patch)))
		if patch in _created: _undo.add_do_reference(patch)
		count += _drafts[patch].size()
	_undo.commit_action()
	_created.clear(); _drafts.clear(); _before.clear()
	if _status != null: _status.text = "Мазок применён · Ctrl+Z отменяет целиком"
	stroke_committed.emit(count); return count

func _apply(patch: Node3D, snapshot: Dictionary, attached: bool) -> void:
	if not is_instance_valid(_parent) or not is_instance_valid(_scene): return
	if attached:
		if patch.get_parent() == null: _parent.add_child(patch)
		patch.owner = _scene
	else:
		if patch.get_parent() != null: patch.get_parent().remove_child(patch)
	patch._detail_preview.clear(); patch.density_cells = snapshot.cells.duplicate()
	patch.tuft_size = snapshot.size; patch.scatter_seed = snapshot.seed; patch.detail_jitter = snapshot.jitter; patch.detail_variation = snapshot.variation
	patch.detail_yaw = snapshot.yaw
	patch._dirty = true
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == _scene: EditorInterface.mark_scene_as_unsaved()

func _edit_cover() -> void:
	cancel_stroke()
	if cover_pattern == null: cover_pattern = load(Cover.PATTERN_PATH)
	if _cover_window == null:
		_cover_window=Window.new();_cover_window.title="Цветущая трава · рисунок";_cover_window.size=Vector2i(1020,650)
		_cover_window.transient=true;_cover_window.exclusive=true;add_child(_cover_window)
		var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_cover_window.add_child(margin)
		for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,12)
		var row:=HBoxContainer.new();margin.add_child(row)
		_cover_dialog=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd").new();row.add_child(_cover_dialog)
		_cover_dialog.parameters_panel.custom_minimum_size.x=310
		row.move_child(_cover_dialog,0);row.add_child(_cover_dialog.parameters_panel);row.move_child(_cover_dialog.parameters_panel,0)
		_cover_dialog.configure_texture_cover();_cover_dialog.additional_validation=Cover.validation_errors
		_cover_dialog.light_profile_previewed.connect(func(pattern,_id): _preview_cover(pattern))
		_cover_dialog.pattern_saved.connect(func(_pattern,_id): _reload_cover())
		_cover_dialog.edit_closed.connect(func(): _reload_cover();_cover_window.hide())
		_cover_window.close_requested.connect(func(): _cover_dialog.cancel_edit())
	_cover_dialog.pattern_path_override=cover_pattern.resource_path
	if _cover_dialog.open_variant(cover_pattern.resource_path.get_file().get_basename(),"grass"):
		_cover_window.popup_centered()

func _preview_cover(pattern: EmberCompactTerrainPattern) -> void:
	if get_tree()==null:return
	for patch in get_tree().get_nodes_in_group(&"ember_grass_patches"):
		if patch.detail_kind==3 and patch.cover_pattern==cover_pattern:patch.preview_cover(pattern)

func _reload_cover() -> void:
	if cover_pattern==null:return
	var path:=cover_pattern.resource_path
	cover_pattern=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_REPLACE)
	_preview_cover(null)
	cover_pattern.emit_changed()
