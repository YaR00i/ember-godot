extends Node3D
## Derived presentation of the player's existing F target. Never changes source
## meshes/materials, availability, collision or the interaction command owner.
const OutlineShader = preload("res://shaders/ember_interaction_outline.gdshader")
const MaskShader = preload("res://shaders/ember_interaction_mask.gdshader")
var player: EmberPlayer
var focused: Node3D
var _copies: Array[Dictionary] = []
var _label: Label
var _badge: PanelContainer
var _material: ShaderMaterial
var _mask_material: ShaderMaterial

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = OutlineShader
	_material.render_priority = 101
	_mask_material = ShaderMaterial.new()
	_mask_material.shader = MaskShader
	_mask_material.render_priority = 100
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04,0.055,0.075,0.94)
	style.border_color = Color("ffe4a0")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_badge.add_theme_stylebox_override("panel",style)
	layer.add_child(_badge)
	_label = Label.new()
	_label.name = "InteractionKey"
	_label.add_theme_font_size_override("font_size",18)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 248
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate = Color("ffe4a0")
	_label.visible = false
	_badge.add_child(_label)
	_badge.hide()

func _process(_dt: float) -> void:
	var next: Node3D
	if is_instance_valid(player) and player.is_visible_in_tree() and not player._ui_blocks_movement():
		var progress := player._progress()
		if progress == null or not progress.combat_party_locked: next = player._nearest()
	if is_instance_valid(next) and (next.is_queued_for_deletion() or not next.is_visible_in_tree()): next = null
	if not is_instance_valid(focused) or focused != next:
		_clear()
		focused = next
		if focused != null: _build()
	if not is_instance_valid(focused): return
	var bounds := AABB(focused.global_position, Vector3.ZERO)
	var has_mesh := false
	for entry in _copies:
		if not is_instance_valid(entry.source): continue
		entry.copy.global_transform = entry.source.global_transform
		entry.copy.visible = entry.source.is_visible_in_tree()
		var box: AABB = entry.source.global_transform * entry.source.get_aabb()
		bounds = bounds.merge(box) if has_mesh else box
		has_mesh = true
	var anchor := bounds.position + Vector3(bounds.size.x*0.5, bounds.size.y+3.0, bounds.size.z*0.5)
	_label.text = "[F]  " + focused.prompt()
	_label.visible = true
	var camera := get_viewport().get_camera_3d()
	_badge.visible = camera != null and not camera.is_position_behind(anchor)
	if _badge.visible:
		_badge.reset_size()
		var screen := camera.unproject_position(anchor) - Vector2(_badge.size.x*0.5,_badge.size.y+8)
		var viewport_size := get_viewport().get_visible_rect().size
		screen.x = clampf(screen.x,16,maxf(16,viewport_size.x-_badge.size.x-16))
		screen.y = clampf(screen.y,160,maxf(160,viewport_size.y-_badge.size.y-16))
		_badge.position = screen

func _build() -> void:
	var root := focused
	if focused is EmberInteract:
		var parent := focused.get_parent() as Node3D
		if parent != null and str(parent.name) not in ["Map", "Props", "Regions", "Entries"]: root = parent
	var candidates: Array[Node] = [root]
	candidates.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in candidates:
		if not node is MeshInstance3D or not node.is_visible_in_tree() or node.mesh == null: continue
		var source := node as MeshInstance3D
		for material in [_mask_material,_material]:
			var copy := MeshInstance3D.new()
			copy.name = "InteractionMask" if material == _mask_material else "InteractionOutline"
			copy.mesh = source.mesh
			copy.skin = source.skin
			copy.material_override = material
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(copy)
			var skeleton := source.get_node_or_null(source.skeleton)
			if skeleton is Skeleton3D: copy.skeleton = copy.get_path_to(skeleton)
			copy.global_transform = source.global_transform
			_copies.append({"source":source,"copy":copy})

func _clear() -> void:
	for entry in _copies:
		if is_instance_valid(entry.copy):
			entry.copy.visible = false
			entry.copy.queue_free()
	_copies.clear()
	if is_instance_valid(_label): _label.visible = false
	if is_instance_valid(_badge): _badge.hide()
	focused = null
