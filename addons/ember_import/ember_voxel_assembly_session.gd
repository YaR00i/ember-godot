@tool
extends RefCounted
## Coordinates existing object sessions; the joined Resource is an unsaved draft,
## never a second persistent source. Sections remain ordinary native Resources.
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Split = preload("res://addons/ember_import/ember_voxel_object_split.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const WalkSurface = preload("res://addons/ember_import/ember_walk_surface.gd")
const CHANNELS := ["voxels","emissive","shine","transparency","transmittance","collision_voxels"]
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var draft: EmberVoxelModelResource
var error := ""
var _baseline: EmberVoxelModelResource
var _target: WeakRef
var _root: WeakRef
var _undo: Object
var _slots: Array[Dictionary] = []
var _frame := Transform3D.IDENTITY

func _voxel_children(group: Node3D) -> Array:
	return group.get_children().filter(func(node): return not WalkSurface.is_surface(node))

func open(group: Node3D, scene: Node, undo: Object) -> bool:
	error = ""
	_slots.clear()
	if group == null or scene == null or not scene.is_ancestor_of(group) or group.owner != scene or _voxel_children(group).size() < 2 or _voxel_children(group).size() > 32:
		return _fail("Выберите группу из 2–32 voxel-секций.")
	_target = weakref(group)
	_root = weakref(scene)
	_undo = undo
	var minimum := Vector3i.ZERO
	var maximum := Vector3i.ZERO
	var density := 0
	var palette := PackedColorArray([Color.TRANSPARENT])
	for node in _voxel_children(group):
		var prop := node as EmberVoxelProp
		if prop == null or prop.owner != scene or prop.get_script() != preload("res://scripts/ember_voxel_prop.gd"):
			return _fail("В группе есть не-voxel узлы. Выберите группу секций без дополнительных объектов.")
		if not FileAccess.file_exists(source_directory.path_join(prop.model_id+".tres")):
			return _fail("Сначала сохраните каждую секцию как native voxel-модель через отдельный Canvas.")
		var edit := Session.new()
		edit.source_directory = source_directory
		edit.prefab_directory = prefab_directory
		if not edit.open(prop,scene,undo):
			return _fail("%s: %s" % [prop.name,edit.error])
		var source: EmberVoxelModelResource = edit.draft
		if not source.surface_fill_levels.is_empty() or not source.surface_fill_materials.is_empty() or not source.surface_fill_palette.is_empty():
			return _fail("Сборка с водной заливкой пока не поддерживается.")
		var frame: Transform3D = prop.transform * prop.get_node("Mesh").transform
		if _slots.is_empty():
			_frame = frame
			density = source.normalized_density()
		if absf(_frame.basis.determinant()) < 0.000001 or density != source.normalized_density() or not frame.basis.is_equal_approx(_frame.basis):
			return _fail("Секции должны иметь одну плотность, масштаб и ориентацию. Отдельное выравнивание не выполняется скрыто.")
		var offset: Vector3 = (_frame.affine_inverse() * frame).origin * density
		var origin := Vector3i(offset.round())
		if not offset.is_equal_approx(Vector3(origin)) or origin.y != 0 or (not _slots.is_empty() and source.grid_size().y != _slots[0].size.y):
			return _fail("Секции не совпадают с общей voxel-сеткой или имеют разную высоту.")
		var remap := PackedByteArray()
		remap.resize(source.palette.size())
		for index in range(1,source.palette.size()):
			var mapped := -1
			# Palette index zero means empty, even if a solid color equals it.
			for candidate in range(1,palette.size()):
				if palette[candidate] == source.palette[index]:
					mapped = candidate
					break
			if mapped < 0:
				if palette.size() == 256:
					return _fail("Общая палитра превышает 255 цветов. Цвета не будут потеряны или округлены.")
				mapped = palette.size()
				palette.append(source.palette[index])
			remap[index] = mapped
		_slots.append({"session":edit,"target":weakref(prop),"pose":prop.transform,"mesh_pose":prop.get_node("Mesh").transform,"origin":origin,"size":source.grid_size(),"remap":remap})
		minimum = minimum.min(origin)
		maximum = maximum.max(origin+source.grid_size())
	var size := maximum-minimum
	var cells := size.x*size.y*size.z
	if size.x > 256 or size.z > 256 or cells > 524288 or size.x % density != 0 or size.z % density != 0:
		return _fail("Общий холст должен укладываться в 256×256 по XZ, сетку плотности и 524 288 ячеек.")
	_frame = _frame * Transform3D(Basis.IDENTITY,Vector3(minimum)/density)
	draft = _slots[0].session.draft.duplicate(true)
	draft.model_id = "assembly_draft"
	draft.display_name = str(group.name)
	draft.size_blocks = Vector3i(size.x/density,ceili(float(size.y)/density),size.z/density)
	draft.height_voxels = size.y
	draft.palette = palette
	draft.voxel_groups = []
	draft.merge_parts = PackedStringArray()
	draft.voxel_part_ids = PackedInt32Array()
	for slot in _slots:
		var names: PackedStringArray = slot.session.draft.merge_parts
		if names.is_empty():
			continue
		if not draft.merge_parts.is_empty() and draft.merge_parts != names:
			return _fail("У секций разные части склейки. Откройте их отдельно.")
		draft.merge_parts = names.duplicate()
	if not draft.merge_parts.is_empty():
		draft.voxel_part_ids.resize(cells)
	var has_collision_channel := false
	for slot in _slots:
		has_collision_channel = has_collision_channel or not (slot.session.draft as EmberVoxelModelResource).collision_voxels.is_empty()
	for channel in CHANNELS:
		var values := PackedByteArray()
		if channel != "collision_voxels" or has_collision_channel:
			values.resize(cells)
		draft.set(channel,values)
	var coverage := PackedByteArray()
	coverage.resize(cells)
	var groups := {}
	for slot in _slots:
		slot.origin -= minimum
		var source: EmberVoxelModelResource = slot.session.draft
		var mapping := PackedInt32Array()
		mapping.resize(source.voxels.size())
		for y in slot.size.y:
			for z in slot.size.z:
				for x in slot.size.x:
					var local := VoxMesher.cell_index(x,y,z,slot.size.x,slot.size.z)
					var global := VoxMesher.cell_index(x+slot.origin.x,y,z+slot.origin.z,size.x,size.z)
					if coverage[global] != 0:
						return _fail("Секции перекрываются. Откройте их отдельно или восстановите стыковку.")
					coverage[global] = 1
					mapping[local] = global
		for channel in CHANNELS:
			var values: PackedByteArray = source.get(channel)
			var joined: PackedByteArray = draft.get(channel)
			if channel == "collision_voxels" and has_collision_channel and values.is_empty():
				for index in source.voxels.size():
					if source.voxels[index] != 0:
						joined[mapping[index]] = 1
				draft.set(channel,joined)
				continue
			for index in values.size():
				if channel == "voxels" and values[index] >= slot.remap.size():
					return _fail("В секции есть индекс вне палитры; автоматическое исправление не выполняется.")
				joined[mapping[index]] = slot.remap[values[index]] if channel == "voxels" else values[index]
			draft.set(channel,joined)
		for index in source.voxel_part_ids.size():
			draft.voxel_part_ids[mapping[index]] = source.voxel_part_ids[index]
		for entry in source.voxel_groups:
			var id: String = entry.id
			var metadata: Dictionary = entry.duplicate(true)
			metadata.erase("indices")
			if groups.has(id) and groups[id].metadata != metadata:
				return _fail("Группы вокселей с одинаковым ID имеют разные настройки. Переименуйте конфликтующие группы перед общим редактированием.")
			if not groups.has(id):
				groups[id] = {"metadata":metadata,"indices":PackedInt32Array()}
			for index in entry.get("indices",[]):
				groups[id].indices.append(mapping[index])
	if coverage.count(0) > 0:
		return _fail("Между секциями есть пустой промежуток без объекта-владельца. Общий Canvas пока требует сплошную стыковку секций.")
	for entry in groups.values():
		var group_data: Dictionary = entry.metadata
		entry.indices.sort()
		group_data.indices = entry.indices
		draft.voxel_groups.append(group_data)
	_baseline = draft.duplicate(true)
	return true

func label() -> String:
	return "Сборка · %d секций · сохраняются только изменённые" % _slots.size()

func can_grow_canvas() -> bool:
	return false

func release_projection_cache() -> void:
	for slot in _slots:
		slot.session.release_projection_cache()

func refresh_before_open() -> bool:
	return open(_target.get_ref(),_root.get_ref(),_undo)

func context_projection(_resource: EmberVoxelModelResource) -> Dictionary:
	var group := _target.get_ref() as Node3D
	var scene := _root.get_ref() as Node
	if group == null or scene == null or not scene.is_ancestor_of(group):
		return {"error":"Сборка удалена или сцена закрыта."}
	return {"scene":scene,"target":group,"frame":group.global_transform*_frame}

func _piece(resource: EmberVoxelModelResource, slot: Dictionary) -> EmberVoxelModelResource:
	var cutter := Split.new()
	cutter.source = resource
	var sliced: EmberVoxelModelResource = cutter._extract(slot,slot.session._expected_id)
	var result: EmberVoxelModelResource = slot.session._baseline.duplicate(true)
	result.palette = sliced.palette
	result.voxel_groups = sliced.voxel_groups
	result.merge_parts = sliced.merge_parts
	result.voxel_part_ids = sliced.voxel_part_ids
	for channel in CHANNELS:
		var values: PackedByteArray = sliced.get(channel)
		if channel != "voxels" and slot.session._baseline.get(channel).is_empty() and values.count(0) == values.size():
			values = PackedByteArray()
		result.set(channel,values)
	return result

func save(resource: EmberVoxelModelResource, prepare_only := false) -> Dictionary:
	error = ""
	var group := _target.get_ref() as Node3D
	var scene := _root.get_ref() as Node
	if group == null or scene == null or not scene.is_ancestor_of(group) or _voxel_children(group).size() != _slots.size():
		return _failure("Состав сборки изменён. Черновик сохранён; откройте сборку заново.")
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != scene:
		return _failure("Активная сцена изменилась. Вернитесь к сцене сборки перед сохранением.")
	if resource.normalized_density() != _baseline.normalized_density() or resource.grid_size() != _baseline.grid_size() or not resource.validation_errors().is_empty() or resource.surface_fill_levels != _baseline.surface_fill_levels or resource.surface_fill_materials != _baseline.surface_fill_materials or resource.surface_fill_palette != _baseline.surface_fill_palette:
		return _failure("Размеры, вода или данные общего холста не поддерживают сохранение в эти секции.")
	for value in resource.voxels:
		if value >= resource.palette.size():
			return _failure("В черновике есть индекс вне палитры. Сборка не изменена.")
	var plans: Array[Dictionary] = []
	var palette_only := resource.voxels == _baseline.voxels and resource.palette != _baseline.palette
	for slot in _slots:
		var prop := slot.target.get_ref() as EmberVoxelProp
		var edit: RefCounted = slot.session
		if prop == null or prop.get_parent() != group or prop.transform != slot.pose or prop.get_node("Mesh").transform != slot.mesh_pose or prop.model_id != edit._expected_id or FileAccess.get_sha256(edit._source_path) != edit._source_hash or not edit._same_data(edit._source,edit._baseline):
			return _failure("Секция перемещена или изменена вне общего Canvas. Обновление сборки остановлено.")
		var next := _piece(resource,slot)
		if _piece_equal(next,_piece(_baseline,slot),palette_only):
			continue
		# Fresh immutable assets let batch Undo restore references without disk I/O.
		var plan: Dictionary = edit.save(next,true,true)
		if not plan.ok:
			return _failure(plan.error)
		plan.session = edit
		plans.append(plan)
	if prepare_only:
		return {"ok":true,"plans":plans}
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for plan in plans:
		var result := Store.install_prepared_asset(plan.next,plan.packed,plan.path,plan.prefab)
		if not result.ok:
			return _failure("Сборка не изменена. Не удалось записать все секции; уже созданные копии оставлены для восстановления: " + str(result.error))
		for state in plan.new_states:
			state.signature = result.signature
		before.append_array(plan.old_states)
		after.append_array(plan.new_states)
	if not plans.is_empty():
		_apply(after)
		if _undo is EditorUndoRedoManager:
			_undo.create_action("Canvas · сохранить сборку",UndoRedo.MERGE_DISABLE,scene)
			_undo.add_do_method(self,"_apply",after)
			_undo.add_undo_method(self,"_apply",before)
		else:
			_undo.create_action("Canvas · сохранить сборку")
			_undo.add_do_method(_apply.bind(after))
			_undo.add_undo_method(_apply.bind(before))
		_undo.add_do_reference(self)
		_undo.commit_action(false)
		for plan in plans:
			plan.session.accept_prepared_save(plan.next,plan.path,false)
	_baseline = resource.duplicate(true)
	return {"ok":true,"path":"%d секций обновлено" % plans.size(),"changed":plans.size()}

func _apply(states: Array[Dictionary]) -> void:
	_slots[0].session._apply(states,{})

func _piece_equal(a: EmberVoxelModelResource, b: EmberVoxelModelResource, palette_only: bool) -> bool:
	if a.merge_parts != b.merge_parts or a.voxel_part_ids != b.voxel_part_ids:
		return false
	if a.voxel_groups != b.voxel_groups:
		return false
	for channel in ["emissive","shine","transparency","transmittance","collision_voxels"]:
		if a.get(channel) != b.get(channel):
			return false
	if palette_only:
		return a.palette == b.palette and a.voxels == b.voxels
	if a.palette == b.palette:
		return a.voxels == b.voxels
	# Adding a brush color does not modify every other section merely because
	# the temporary joined palette gained an unused entry.
	for index in a.voxels.size():
		var left := int(a.voxels[index])
		var right := int(b.voxels[index])
		if left == 0 or right == 0:
			if left != right:
				return false
		elif a.palette[left] != b.palette[right]:
			return false
	return true

func _fail(message: String) -> bool:
	error = message
	return false

func _failure(message: String) -> Dictionary:
	error = message
	return {"ok":false,"error":message}
