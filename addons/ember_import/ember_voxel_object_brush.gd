@tool
extends Node
## Scene input controller. Existing authoring helpers own instances/IDs;
## existing placement math owns transforms. No voxel resources are modified.

signal changed
signal stroke_committed(count: int)

const PlacementMath = preload("res://addons/ember_import/ember_voxel_placement_math.gd")
const MAX_STROKE := 256

var spacing_blocks := 1.0
var yaw_degrees := 0.0
var scale_factor := 1.0
var bury_vox := 0.0
var model_id := ""
var active := false
var _scene: Node3D
var _parent: Node3D
var _packed: PackedScene
var _undo: Object
var _tile_size := 16.0
var _density := 16
var _pivot := Vector3.ZERO
var _visuals: Array[Dictionary] = []
var _preview: Node3D
var _hover: Node3D
var _stroke: Node3D
var _transforms: Array[Transform3D] = []
var _dragging := false
var _last_point := Vector3.ZERO
var _remaining := 1.0


func activate(scene: Node3D, parent: Node3D, packed: PackedScene, id: String, undo: Object, tile_size: float) -> bool:
	deactivate()
	if scene == null or parent == null or packed == null or undo == null or not scene.is_ancestor_of(parent) or is_zero_approx(parent.global_basis.determinant()):
		return false
	var template := packed.instantiate() as EmberVoxelProp
	if template == null:
		return false
	template.configure_voxel_scale(template.voxels_per_block, tile_size)
	var mesh := template.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		template.free()
		return false
	var bounds := mesh.transform * mesh.mesh.get_aabb()
	_pivot = bounds.position + Vector3(bounds.size.x * 0.5, 0, bounds.size.z * 0.5)
	_density = template.voxels_per_block
	_visuals.clear()
	# Geometry is shared with the prefab. Preview has no scripts or collision.
	for child in template.get_children():
		if child is MeshInstance3D and child.mesh != null:
			_visuals.append({"mesh": child.mesh, "transform": child.transform})
	template.free()
	_scene = scene
	_parent = parent
	_packed = packed
	_undo = undo
	_tile_size = tile_size
	model_id = id
	_preview = Node3D.new()
	_preview.name = "EmberObjectBrushPreview"
	scene.add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	_hover = _make_ghost()
	_preview.add_child(_hover)
	_hover.hide()
	_stroke = Node3D.new()
	_preview.add_child(_stroke)
	active = true
	changed.emit()
	return true


func deactivate() -> void:
	cancel_stroke()
	active = false
	if is_instance_valid(_preview):
		_preview.free()
	_preview = null
	_hover = null
	_stroke = null
	_packed = null
	_visuals.clear()
	changed.emit()


func cancel_stroke() -> void:
	_dragging = false
	_transforms.clear()
	if is_instance_valid(_stroke):
		for child in _stroke.get_children():
			child.free()


func _exit_tree() -> void:
	deactivate()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_stroke()
		if is_instance_valid(_hover):
			_hover.hide()


func forward_input(camera: Camera3D, event: InputEvent) -> int:
	if not active:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not is_instance_valid(_scene) or not is_instance_valid(_parent) or not is_instance_valid(_preview):
		deactivate()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		deactivate()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode in [KEY_Z, KEY_Y]:
		cancel_stroke()
		_hover.hide()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouse and (event.alt_pressed or event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)):
		cancel_stroke()
		_hover.hide()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		cancel_stroke()
		_hover.hide()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not event is InputEventMouseMotion and not event is InputEventMouseButton:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var hit := pick(camera, event.position)
	_hover.visible = not hit.is_empty()
	if not hit.is_empty():
		_hover.global_transform = transform_at(hit.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			cancel_stroke()
			if not hit.is_empty():
				_dragging = true
				_last_point = hit.position
				_remaining = maxf(0.01, spacing_blocks) * _tile_size
				_append(hit.position)
		else:
			commit_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		if _dragging and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			cancel_stroke() # A release outside the viewport must not leave a stuck stroke.
		elif _dragging:
			if hit.is_empty():
				cancel_stroke() # Do not bridge an unpaintable gap with floating instances.
			else:
				var samples := PlacementMath.stroke_samples(_last_point, hit.position, spacing_blocks * _tile_size, _remaining)
				_remaining = samples.remaining
				for point in samples.points:
					var surface := _project_surface(point)
					if not surface.is_empty():
						_append(surface.position)
				_last_point = hit.position
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func pick(camera: Camera3D, position: Vector2) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {}
	var origin := camera.project_ray_origin(position)
	return _ray(origin, origin + camera.project_ray_normal(position) * camera.far)


func _project_surface(point: Vector3) -> Dictionary:
	return _ray(point + Vector3.UP * _tile_size, point - Vector3.UP * _tile_size * 2.0)


func _ray(first: Vector3, last: Vector3) -> Dictionary:
	var world := _scene.get_world_3d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(first, last, 1)
	var hit := world.direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.dot(Vector3.UP) > 0.05:
		return hit
	return {}


func transform_at(point: Vector3) -> Transform3D:
	var initial := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_factor), Vector3.ZERO)
	return PlacementMath.place_world(initial, _pivot, point - Vector3.UP * bury_vox * _tile_size / _density, Vector3(0, yaw_degrees, 0))


func _make_ghost() -> Node3D:
	var ghost := Node3D.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.3, 0.85, 1.0, 0.38)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for visual in _visuals:
		var mesh := MeshInstance3D.new()
		mesh.mesh = visual.mesh
		mesh.transform = visual.transform
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(mesh)
	return ghost


func _append(point: Vector3) -> void:
	if _transforms.size() >= MAX_STROKE:
		return
	var pose := transform_at(point)
	_transforms.append(pose)
	var ghost := _make_ghost()
	_stroke.add_child(ghost)
	ghost.global_transform = pose


func commit_stroke() -> int:
	_dragging = false
	if _transforms.is_empty() or not is_instance_valid(_scene) or not is_instance_valid(_parent) or not _scene.is_ancestor_of(_parent) or is_zero_approx(_parent.global_basis.determinant()):
		cancel_stroke()
		return 0
	var props: Array[EmberVoxelProp] = []
	var reserved := {}
	for pose in _transforms:
		var prop := EmberSceneAuthoring.make_model_instance(_scene, _packed, model_id, Vector3.ZERO, reserved)
		if prop == null:
			for prepared in props:
				prepared.free()
			cancel_stroke()
			return 0
		prop.configure_voxel_scale(prop.voxels_per_block, _tile_size)
		reserved[prop.placement_id] = true
		prop.transform = _parent.global_transform.affine_inverse() * pose
		props.append(prop)
	if _undo is EditorUndoRedoManager:
		_undo.create_action("Мазок кисти объектов", UndoRedo.MERGE_DISABLE, _scene)
	else:
		_undo.create_action("Мазок кисти объектов")
	for prop in props:
		if _undo is EditorUndoRedoManager:
			_undo.add_do_method(self, "_attach", prop, _scene, _parent)
			_undo.add_undo_method(self, "_detach", prop, _scene)
		else:
			_undo.add_do_method(_attach.bind(prop, _scene, _parent))
			_undo.add_undo_method(_detach.bind(prop, _scene))
		_undo.add_do_reference(prop)
	_undo.commit_action()
	var count := props.size()
	cancel_stroke()
	stroke_committed.emit(count)
	return count


func _attach(prop: EmberVoxelProp, scene: Node, parent: Node) -> void:
	EmberSceneAuthoring.attach_model_instance(scene, parent, prop)
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == scene:
		EditorInterface.mark_scene_as_unsaved()


func _detach(prop: EmberVoxelProp, scene: Node) -> void:
	if prop.get_parent() != null:
		prop.get_parent().remove_child(prop)
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == scene:
		EditorInterface.mark_scene_as_unsaved()
