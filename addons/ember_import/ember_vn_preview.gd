@tool
class_name EmberVnPreview
extends Control
## Live editor preview of the existing Ember dialogue/VN scene dictionary.
## It reads the unsaved Graph draft and never writes content by itself.

const VnSceneState = preload("res://scripts/ember_vn_scene_state.gd")
const VnAssets = preload("res://scripts/ember_vn_assets.gd")

var _document: Dictionary = {}
var _steps: Dictionary = {}
var _current_step_id := ""
var _history: Array[String] = []
var _assets: EmberVnAssets

var _stage: Control
var _background: TextureRect
var _fallback: ColorRect
var _actors: Control
var _title: Label
var _body: Label
var _choices: VBoxContainer
var _step_label: Label
var _asset_status: Label
var _back: Button
var _next: Button


func _ready() -> void:
	if get_child_count() == 0:
		_build()
	if _assets == null:
		_assets = VnAssets.new()
	_render()


func set_document(document: Dictionary, preferred_step_id := "") -> void:
	_document = document.duplicate(true)
	_steps.clear()
	for raw_step in _document.get("steps", []):
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		var step_id := str(step.get("id", ""))
		if not step_id.is_empty():
			_steps[step_id] = step
	var preferred := preferred_step_id.strip_edges()
	if not preferred.is_empty() and _steps.has(preferred):
		if preferred != _current_step_id:
			_history.clear()
		_current_step_id = preferred
	elif not _steps.has(_current_step_id):
		_current_step_id = str(_document.get("startStepId", ""))
		_history.clear()
	if not _steps.has(_current_step_id) and not _steps.is_empty():
		_current_step_id = str(_steps.keys()[0])
	_render()


func set_asset_resolver(assets: EmberVnAssets) -> void:
	_assets = assets
	_render()


func current_step_id() -> String:
	return _current_step_id


func view_state() -> Dictionary:
	var step: Dictionary = _steps.get(_current_step_id, {})
	var visual := VnSceneState.visual_state(_document, step)
	return {
		"stepId": _current_step_id,
		"kind": str(step.get("type", "")),
		"body": _step_text(step),
		"bgArtId": str(visual.get("bgArtId", "")),
		"actorCount": (visual.get("actors", []) as Array).size(),
		"choiceCount": (step.get("options", []) as Array).size() if typeof(step.get("options", [])) == TYPE_ARRAY else 0,
		"backgroundLoaded": _background != null and _background.texture != null,
	}


func restart() -> void:
	_history.clear()
	_current_step_id = str(_document.get("startStepId", ""))
	_render()


func advance() -> void:
	var step: Dictionary = _steps.get(_current_step_id, {})
	if step.is_empty() or str(step.get("type", "")) in ["choice", "end"]:
		return
	_go(str(step.get("next", "")))


func choose(index: int) -> void:
	var step: Dictionary = _steps.get(_current_step_id, {})
	if str(step.get("type", "")) != "choice":
		return
	var options: Variant = step.get("options", [])
	if typeof(options) != TYPE_ARRAY or index < 0 or index >= options.size():
		return
	var option: Variant = options[index]
	if typeof(option) == TYPE_DICTIONARY:
		_go(str((option as Dictionary).get("next", "")))


func back() -> void:
	if _history.is_empty():
		return
	_current_step_id = _history.pop_back()
	_render()


func reload_assets() -> void:
	if _assets == null:
		_assets = VnAssets.new()
	else:
		_assets.reload()
	_render()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root_box := VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 6)
	add_child(root_box)
	var toolbar := HBoxContainer.new()
	root_box.add_child(toolbar)
	var heading := Label.new()
	heading.text = "LIVE VN PREVIEW"
	heading.modulate = Color(0.96, 0.72, 0.32)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(heading)
	var reload := Button.new()
	reload.name = "VnPreviewReloadAssets"
	reload.text = "↻ Арты"
	reload.tooltip_text = "Перечитать arts/portraits registry и внешние изображения."
	reload.pressed.connect(reload_assets)
	toolbar.add_child(reload)

	_stage = Control.new()
	_stage.name = "VnPreviewStage"
	_stage.custom_minimum_size = Vector2(800.0, 450.0)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	_stage.resized.connect(_layout_actors)
	root_box.add_child(_stage)
	_fallback = ColorRect.new()
	_fallback.color = Color(0.055, 0.05, 0.09)
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_fallback)
	_background = TextureRect.new()
	_background.name = "VnPreviewBackground"
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.z_index = -100
	_stage.add_child(_background)
	var veil := ColorRect.new()
	veil.color = Color(0.03, 0.02, 0.07, 0.15)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(veil)
	_actors = Control.new()
	_actors.name = "VnPreviewActors"
	_actors.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_actors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Actors occupy the stage, but may never cover dialogue text. Authored actor
	# z only orders portraits inside this bounded layer.
	_actors.z_index = 10
	_stage.add_child(_actors)

	var dialogue_panel := PanelContainer.new()
	dialogue_panel.name = "VnPreviewDialoguePanel"
	dialogue_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_panel.offset_top = -188.0
	dialogue_panel.offset_left = 24.0
	dialogue_panel.offset_right = -24.0
	dialogue_panel.offset_bottom = -18.0
	dialogue_panel.z_index = 1000
	dialogue_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(dialogue_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	dialogue_panel.add_child(margin)
	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 7)
	margin.add_child(text_box)
	_title = Label.new()
	_title.name = "VnPreviewTitle"
	_title.add_theme_font_size_override("font_size", 20)
	_title.modulate = Color(1.0, 0.78, 0.34)
	text_box.add_child(_title)
	_body = Label.new()
	_body.name = "VnPreviewBody"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("font_size", 17)
	text_box.add_child(_body)
	_choices = VBoxContainer.new()
	_choices.name = "VnPreviewChoices"
	text_box.add_child(_choices)

	var navigation := HBoxContainer.new()
	root_box.add_child(navigation)
	_back = Button.new()
	_back.name = "VnPreviewBack"
	_back.text = "← Назад"
	_back.pressed.connect(back)
	navigation.add_child(_back)
	var reset := Button.new()
	reset.name = "VnPreviewRestart"
	reset.text = "↺ С начала"
	reset.pressed.connect(restart)
	navigation.add_child(reset)
	_next = Button.new()
	_next.name = "VnPreviewNext"
	_next.text = "Далее →"
	_next.pressed.connect(advance)
	navigation.add_child(_next)
	_step_label = Label.new()
	_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	navigation.add_child(_step_label)
	_asset_status = Label.new()
	_asset_status.name = "VnPreviewAssetStatus"
	_asset_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_asset_status.modulate = Color(0.76, 0.69, 0.82)
	root_box.add_child(_asset_status)


func _render() -> void:
	if _stage == null or _assets == null:
		return
	var step: Dictionary = _steps.get(_current_step_id, {})
	var visual := VnSceneState.visual_state(_document, step)
	var bg_id := str(visual.get("bgArtId", ""))
	# Editor preview only needs a display-sized texture. Creating a full-size
	# ImageTexture from an external SVG can crash Godot 4.7.2's Vulkan editor
	# process before GDScript receives an error (native 0xc0000005).
	_background.texture = _assets.art_thumbnail(bg_id, 256)
	_fallback.visible = _background.texture == null
	for child in _actors.get_children():
		child.queue_free()
	var missing_portraits: Array[String] = []
	var raw_actors: Variant = visual.get("actors", [])
	if typeof(raw_actors) == TYPE_ARRAY:
		for raw_actor in raw_actors:
			if typeof(raw_actor) == TYPE_DICTIONARY:
				_add_actor(raw_actor as Dictionary, missing_portraits)
	_title.text = _step_title(step)
	_body.text = _step_text(step)
	for child in _choices.get_children():
		child.queue_free()
	if str(step.get("type", "")) == "choice":
		var options: Variant = step.get("options", [])
		if typeof(options) == TYPE_ARRAY:
			for index in options.size():
				var option: Dictionary = options[index] if typeof(options[index]) == TYPE_DICTIONARY else {}
				var choice := Button.new()
				choice.name = "VnPreviewChoice_%d" % index
				choice.text = "%d. %s" % [index + 1, option.get("labelRu", option.get("id", "Ответ"))]
				choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
				choice.pressed.connect(choose.bind(index))
				_choices.add_child(choice)
	_step_label.text = "%s · %s" % [_current_step_id, step.get("type", "—")]
	_back.disabled = _history.is_empty()
	_next.disabled = step.is_empty() or str(step.get("type", "")) in ["choice", "end"]
	var status: Array[String] = []
	if not bg_id.is_empty() and _background.texture == null:
		status.append("фон не найден: %s" % bg_id)
	for missing in missing_portraits:
		status.append("портрет не найден: %s" % missing)
	_asset_status.text = "Live draft · без записи JSON" if status.is_empty() else "Live draft · ⚠ %s" % "; ".join(status)
	_layout_actors.call_deferred()


func _add_actor(actor: Dictionary, missing: Array[String]) -> void:
	var holder := Control.new()
	holder.name = "Actor_%s" % str(actor.get("id", _actors.get_child_count()))
	holder.set_meta("actor", actor.duplicate(true))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = clampi(int(actor.get("z", 1)), -100, 100)
	var speaker := str(actor.get("speaker", ""))
	var portrait := str(actor.get("portraitKey", "neutral"))
	var texture := _assets.portrait_thumbnail(speaker, portrait, 256)
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.flip_h = bool(actor.get("flipX", false))
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(image)
	else:
		missing.append("%s:%s" % [speaker, portrait])
		var placeholder := Label.new()
		placeholder.text = "%s\n%s" % [speaker, portrait]
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(placeholder)
	_actors.add_child(holder)


func _layout_actors() -> void:
	if _stage == null or _actors == null or _stage.size.x <= 0.0 or _stage.size.y <= 0.0:
		return
	for child in _actors.get_children():
		var actor: Dictionary = child.get_meta("actor", {})
		var scale := maxf(0.01, float(actor.get("scale", 1.0)))
		var height := _stage.size.y * 0.62 * scale
		var width := height * 0.62
		child.size = Vector2(width, height)
		child.position = Vector2(
			_stage.size.x * float(actor.get("x", 50.0)) / 100.0 - width * 0.5,
			_stage.size.y * float(actor.get("y", 96.0)) / 100.0 - height,
		)


func _go(step_id: String) -> void:
	var target := step_id.strip_edges()
	if target.is_empty() or not _steps.has(target):
		return
	_history.append(_current_step_id)
	_current_step_id = target
	_render()


func _step_title(step: Dictionary) -> String:
	match str(step.get("type", "")):
		"dialogue": return str(step.get("nameRu", step.get("speaker", _document.get("nameRu", "Сцена"))))
		"choice": return str(_document.get("nameRu", "Выбор"))
		"splash": return str(_document.get("nameRu", "Заставка"))
		"grant_cinders": return "Награда"
		"set_flag": return "Изменение состояния"
		"end": return "Конец сцены"
	return str(_document.get("nameRu", "Сцена"))


func _step_text(step: Dictionary) -> String:
	match str(step.get("type", "")):
		"dialogue": return str(step.get("textRu", ""))
		"choice": return str(step.get("promptRu", ""))
		"splash": return str(step.get("captionRu", "…"))
		"grant_cinders": return "+%s угольков" % step.get("amount", 0)
		"set_flag": return "%s = %s" % [step.get("flag", step.get("flagId", "—")), step.get("value", true)]
		"end": return "Сцена завершена."
	return "Неподдерживаемая нода."
