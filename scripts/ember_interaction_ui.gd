class_name EmberInteractionUi
extends Control
signal dialogue_closed(completed: bool)
## One runtime owner for talk/shop presentation. Reads JOI content through
## EmberInteractionContent; EmberExploreState owns inventory and persistence.

const MODE_DIALOGUE := "dialogue"
const MODE_SHOP := "shop"
const MODE_REWARD := "reward"
const MODE_NOTICE := "notice"
const MODE_WAIT := "wait"
const MODE_PRESENTATION := "presentation"
const StoryBinding = preload("res://scripts/ember_story_binding.gd")
const SHOP_BUY := "buy"
const SHOP_SELL := "sell"

var economy_state: EmberExploreState
var _mode := ""
var _pending_shop_id := ""
var _selected_choice := 0
var _shop_side := SHOP_BUY
var _shop_index := 0
var _shop_feedback := ""
var _script_queue: Array[Dictionary] = []
var _script_active := false
var _script_mutated := false
var _source_interact: EmberInteract
var _source_is_primary := false
var _wait_serial := 0
var _wait_seconds := 0.0
var _dialogue := EmberDialogueSession.new()
var _shop: Dictionary = {}
var _panel: ColorRect
var _title: Label
var _body: RichTextLabel
var _choices: Label
var _help: Label
var _choice_buttons: VBoxContainer
var _dialogue_controls: HBoxContainer
var _history_panel: PanelContainer
var _history_text: RichTextLabel
var _standalone_dialogue := false
var _standalone_completed := false
var _presentation: Node
var _presentation_callback: Callable
var _presentation_serial := 0


func _ready() -> void:
	if economy_state == null:
		economy_state = get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	visible = false


func activate(area: EmberInteract) -> String:
	if area == null:
		return ""
	var flags := economy_state.flags if economy_state != null else {}
	var route := area.runtime_route(flags)
	if not bool(route.get("available", false)):
		return "Условие не выполнено"
	_source_interact = area
	_source_is_primary = bool(route.get("primary", false))
	var routed_script := str(route.get("scriptId", ""))
	_pending_shop_id = (
		area.shop_id
		if area.kind == "shop" and _source_is_primary
		else ""
	)
	if not routed_script.is_empty():
		return _start_script(routed_script)
	if area.kind == "shop":
		return _open_shop(_pending_shop_id)
	return ""


func activate_script(script_id: String) -> String:
	_clear_source_interact()
	return _start_script(script_id)


func activate_dialogue(dialogue_id: String) -> String:
	## Presentation may wait on the existing dialogue UI without replacing Action's queue.
	if is_open() or _script_active:
		return "Сначала заверши текущий разговор"
	var error := _open_dialogue(dialogue_id)
	if error.is_empty():
		_standalone_dialogue = true
		_standalone_completed = false
	return error


func conversation_session() -> EmberDialogueSession:
	return _dialogue


func set_conversation_session(session: EmberDialogueSession) -> void:
	assert(not is_open() and session != null)
	_dialogue = session


func activate_script_with_steps(script_id: String, appended_steps: Array) -> String:
	## The transition has already saved combat loot. Its private receipt steps
	## display it without granting it again; authored give_item keeps its route.
	_clear_source_interact()
	var steps: Array[Dictionary] = []
	if not script_id.strip_edges().is_empty():
		var built := EmberActionScript.queue_for(script_id)
		if not bool(built.get("ok", false)):
			return str(built.get("error", "Сценарий не найден"))
		for raw_step in built.get("steps", []):
			if typeof(raw_step) == TYPE_DICTIONARY:
				steps.append((raw_step as Dictionary).duplicate(true))
	for raw_step in appended_steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		if str(step.get("type", "")) not in ["give_item", "show_item_reward"]:
			continue
		var item_id := str(step.get("itemId", "")).strip_edges()
		if not item_id.is_empty() and not EmberItemCatalog.definition(item_id).is_empty():
			steps.append(step.duplicate(true))
	return _start_steps(steps)


func _start_script(script_id: String) -> String:
	var built := EmberActionScript.queue_for(script_id)
	if not bool(built.get("ok", false)):
		return str(built.get("error", "Сценарий не найден"))
	var steps: Array[Dictionary] = []
	for raw_step in built.get("steps", []):
		if typeof(raw_step) == TYPE_DICTIONARY:
			steps.append((raw_step as Dictionary).duplicate(true))
	return _start_steps(steps)


func _start_steps(steps: Array[Dictionary]) -> String:
	_script_queue.clear()
	_wait_serial += 1
	_wait_seconds = 0.0
	for step in steps:
		_script_queue.append(step.duplicate(true))
	_script_active = true
	_script_mutated = false
	return _advance_script_queue()


func advance() -> void:
	if is_history_open():
		return
	match _mode:
		MODE_DIALOGUE:
			if _dialogue.current_kind() == "choice":
				_dialogue.choose(_selected_choice)
			else:
				_dialogue.advance()
			if _dialogue.is_finished():
				var blocked_message := _apply_dialogue_flags()
				if not blocked_message.is_empty():
					_show_notice(blocked_message)
					return
				_standalone_completed = _standalone_dialogue
				if _script_active:
					_advance_script_queue()
				elif not _pending_shop_id.is_empty():
					_open_shop(_pending_shop_id)
				else:
					close()
			else:
				_selected_choice = 0
				_refresh_dialogue()
		MODE_SHOP:
			_transact_shop_selection()
		MODE_REWARD:
			_advance_script_queue()
		MODE_NOTICE:
			if _script_active:
				_advance_script_queue()
			else:
				close()
		MODE_WAIT:
			# A wait step represents authored timing. F cannot accidentally skip it.
			pass
		MODE_PRESENTATION:
			if is_instance_valid(_presentation):
				_presentation.advance_dialogue()


func choose(index: int) -> void:
	if is_history_open() or _mode != MODE_DIALOGUE or _dialogue.current_kind() != "choice":
		return
	var labels := _dialogue.choice_labels()
	if index < 0 or index >= labels.size():
		return
	_selected_choice = index
	advance()


func close() -> void:
	_cancel_presentation()
	if _mode == MODE_SHOP and _script_active:
		_mode = ""
		_shop.clear()
		_shop_feedback = ""
		visible = false
		_advance_script_queue()
		return
	if _mode == MODE_SHOP and not _script_active:
		_complete_source_interact()
	if _script_mutated and economy_state:
		economy_state.save_autosave()
	_wait_serial += 1
	_wait_seconds = 0.0
	_mode = ""
	_pending_shop_id = ""
	_script_queue.clear()
	_script_active = false
	_script_mutated = false
	_shop.clear()
	visible = false
	_clear_source_interact()
	if _history_panel:
		_history_panel.hide()
	var notify := _standalone_dialogue
	var completed := _standalone_completed
	_standalone_dialogue = false
	_standalone_completed = false
	if notify:
		dialogue_closed.emit(completed)


func is_open() -> bool:
	return not _mode.is_empty()


func blocks_movement() -> bool:
	return is_open()


func view_state() -> Dictionary:
	return {
		"mode": _mode,
		"title": _title.text if _title else "",
		"body": _body.text if _body else "",
		"choices": _choices.text if _choices else "",
		"shopId": str(_shop.get("id", "")),
		"shopSide": _shop_side,
		"shopIndex": _shop_index,
		"wallet": int(_shop.get("wallet", 0)),
		"feedback": _shop_feedback,
		"visual": _dialogue.current_visual_state() if _mode == MODE_DIALOGUE else {},
		"scriptActive": _script_active,
		"scriptRemaining": _script_queue.size(),
		"waitSeconds": _wait_seconds,
		"historyOpen": is_history_open(),
		"history": _dialogue.history_entries(),
	}


func _advance_script_queue() -> String:
	var feedback := ""
	while not _script_queue.is_empty():
		var step: Dictionary = _script_queue.pop_front()
		match str(step.get("type", "")):
			"play_cutscene":
				return _begin_presentation(str(step.get("presentationId", "")))
			"show_item_reward":
				var item_id := str(step.get("itemId", ""))
				var item := EmberItemCatalog.definition(item_id)
				_show_item_reward(item, int(step.get("before", 0)), int(step.get("after", 0)))
				return ""
			"talk":
				var result := _open_dialogue(str(step.get("dialogueId", "")))
				if result.is_empty():
					return ""
				feedback = result
			"give_item":
				if economy_state == null:
					feedback = "Состояние игры недоступно"
					continue
				var item_id := str(step.get("itemId", ""))
				var before := int(economy_state.inventory.get(item_id, 0))
				var granted := economy_state.grant_item(
					item_id,
					int(step.get("count", 1)),
					false,
				)
				if bool(granted.get("ok", false)):
					_script_mutated = true
					var after := int(economy_state.inventory.get(item_id, before))
					_show_item_reward(granted, before, after)
					return ""
				else:
					feedback = "Предмет не найден"
			"exchange_items", "handover_quest_items":
				var exchange := {"ok": false, "reason": "missing_state"}
				if economy_state != null:
					exchange = economy_state.handover_quest_items(str(step.get("questId", "")), str(step.get("objectiveId", "")), step.get("rewards", {}), false) if str(step.get("type", "")) == "handover_quest_items" else economy_state.exchange_items(step.get("costs", {}), step.get("rewards", {}), false)
				if not exchange.ok:
					_script_queue.clear()
					_source_is_primary = false
					var message := "Не удалось передать предметы. Содержимое сумки сохранено."
					if exchange.reason == "missing_items":
						var item := EmberItemCatalog.definition(str(exchange.itemId))
						message = "%s: нужно %d, в сумке %d" % [str(item.get("nameRu",exchange.itemId)),exchange.required,exchange.owned]
					_show_notice(message)
					return ""
				_script_mutated = true
			"set_flag":
				if economy_state:
					var transition := economy_state.apply_authored_flag(
						str(step.get("flag", "")),
						step.get("value", null),
						false,
					)
					if bool(transition.get("changed", false)):
						_script_mutated = true
					elif not bool(transition.get("allowed", true)):
						_show_notice(str(transition.get("message", "Цель пока недоступна")))
						return ""
			"wait":
				var seconds := maxf(0.0, float(step.get("sec", 0.0)))
				if seconds > 0.0:
					_begin_wait(seconds)
					return ""
			"open_shop":
				var shop_result := _open_shop(str(step.get("shopId", "")))
				if shop_result.is_empty():
					return ""
				feedback = shop_result
			"change_map":
				return _change_map_from_script(
					str(step.get("targetMapId", "")),
					str(step.get("targetRegionId", "")),
				)
			"start_battle":
				return _start_battle_from_script(str(step.get("encounterId", "")))
	if _script_mutated and economy_state:
		economy_state.save_autosave()
	_script_active = false
	_script_mutated = false
	if not _pending_shop_id.is_empty():
		return _open_shop(_pending_shop_id)
	_complete_source_interact()
	close()
	return feedback if not feedback.is_empty() else "Сценарий выполнен"


func _begin_presentation(id: String) -> String:
	var scene := get_tree().current_scene
	if scene == null:
		scene = owner if owner != null else get_tree().root
	var resolved := StoryBinding.resolve(scene, id)
	if not resolved.ok:
		_abort_presentation(str(resolved.error))
		return str(resolved.error)
	_presentation = resolved.node
	_presentation_serial += 1
	_presentation_callback = _on_presentation_finished.bind(_presentation_serial)
	_presentation.finished.connect(_presentation_callback)
	_mode = MODE_PRESENTATION
	visible = false
	var error := str(_presentation.start_for_action(self))
	if not error.is_empty():
		_detach_presentation()
		_abort_presentation(error)
	return error


func _on_presentation_finished(outcome: String, serial: int) -> void:
	if serial != _presentation_serial or not _script_active or _mode != MODE_PRESENTATION:
		return
	_detach_presentation()
	if outcome not in ["completed", "skipped"]:
		_source_is_primary = false
		close()
		return
	_mode = ""
	_advance_script_queue()


func _detach_presentation() -> Node:
	var previous := _presentation
	if is_instance_valid(previous) and previous.finished.is_connected(_presentation_callback):
		previous.finished.disconnect(_presentation_callback)
	_presentation = null
	_presentation_serial += 1
	return previous


func _cancel_presentation() -> void:
	var previous := _detach_presentation()
	if is_instance_valid(previous):
		_source_is_primary = false
		previous.restore()


func _abort_presentation(error: String) -> void:
	_script_queue.clear()
	_script_active = false
	_source_is_primary = false
	_show_notice(error)


func _exit_tree() -> void:
	_cancel_presentation()


func _show_item_reward(granted: Dictionary, before: int, after: int) -> void:
	_mode = MODE_REWARD
	visible = true
	_set_panel_visual(MODE_REWARD)
	var added := maxi(0, after - before)
	var item_name := str(granted.get("nameRu", granted.get("itemId", "Предмет")))
	_title.text = "ПОЛУЧЕНО"
	_body.text = "%s  +%d\nТеперь в сумке: %d" % [item_name, added, after]
	_choices.text = "◆ Награда добавлена в инвентарь" if added > 0 else "◆ В сумке уже максимум"
	_help.text = "F — продолжить · Esc — закрыть"


func _show_notice(message: String) -> void:
	_mode = MODE_NOTICE
	visible = true
	_set_panel_visual(MODE_REWARD)
	_title.text = "ЦЕЛЬ ПОКА НЕДОСТУПНА"
	_body.text = message
	_choices.text = "◇ Последовательность задания сохранена"
	_help.text = "F — продолжить · Esc — закрыть"


func _begin_wait(seconds: float) -> void:
	_wait_serial += 1
	var serial := _wait_serial
	_wait_seconds = seconds
	_mode = MODE_WAIT
	visible = true
	_set_panel_visual(MODE_WAIT)
	_title.text = "ПАУЗА"
	_body.text = "Продолжение через %.1f с" % seconds
	_choices.text = ""
	_help.text = "Сценарий продолжится автоматически · Esc — закрыть"
	_resume_after_wait(seconds, serial)


func _change_map_from_script(target_map_id: String, target_region_id: String) -> String:
	var clean_map_id := target_map_id.strip_edges()
	if clean_map_id.is_empty():
		return "Целевая карта не указана"
	if _script_mutated and economy_state:
		economy_state.save_autosave()
	_complete_source_interact()
	_script_active = false
	_script_mutated = false
	_script_queue.clear()
	_mode = ""
	visible = false
	var error := EmberMapTransition.change_scene(get_tree(), clean_map_id, target_region_id.strip_edges())
	if error != OK:
		return "Карта не импортирована: %s" % clean_map_id
	return ""


func _start_battle_from_script(encounter_id: String) -> String:
	var clean_id := encounter_id.strip_edges()
	if clean_id.is_empty():
		return "Боевая встреча не указана"
	if _script_mutated and economy_state:
		economy_state.save_autosave()
	elif economy_state:
		# The same save also captures the exact exploration position for return.
		economy_state.save_autosave()
	_complete_source_interact()
	_script_active = false
	_script_mutated = false
	_script_queue.clear()
	_mode = ""
	visible = false
	var error := EmberCombatTransition.change_scene(get_tree(), clean_id, economy_state)
	if error != OK:
		if not EmberCombatTransition.last_start_error.is_empty():
			return EmberCombatTransition.last_start_error
		return (
			"Эта встреча уже завершена"
			if error == ERR_ALREADY_EXISTS
			else "Встреча не готова: %s" % clean_id
		)
	return ""


func _complete_source_interact() -> void:
	if not is_instance_valid(_source_interact) or not _source_is_primary:
		_clear_source_interact()
		return
	var changed := _source_interact.complete_primary_activation(economy_state)
	_clear_source_interact()
	if changed and economy_state != null:
		economy_state.save_autosave()


func _clear_source_interact() -> void:
	_source_interact = null
	_source_is_primary = false


func _resume_after_wait(seconds: float, serial: int) -> void:
	await get_tree().create_timer(seconds).timeout
	if serial != _wait_serial or not _script_active or _mode != MODE_WAIT:
		return
	_wait_seconds = 0.0
	_mode = ""
	_advance_script_queue()


func _apply_dialogue_flags() -> String:
	if economy_state == null:
		return ""
	var blocked_message := ""
	var dialogue_flags := _dialogue.flags()
	for flag_id in dialogue_flags:
		var transition := economy_state.apply_authored_flag(
			str(flag_id), dialogue_flags[flag_id], false
		)
		if bool(transition.get("changed", false)):
			_script_mutated = true
		elif blocked_message.is_empty() and not bool(transition.get("allowed", true)):
			blocked_message = str(transition.get("message", "Цель пока недоступна"))
	return blocked_message


func _open_dialogue(script_id: String) -> String:
	var scene := EmberInteractionContent.dialogue_for_id(script_id)
	if scene.is_empty() or not _dialogue.start(scene):
		return "сцена не найдена: %s" % script_id
	_mode = MODE_DIALOGUE
	_set_panel_visual(MODE_DIALOGUE)
	_selected_choice = 0
	visible = true
	_refresh_dialogue()
	return ""


func _open_shop(shop_id: String) -> String:
	var shop := (
		economy_state.shop_view(shop_id)
		if economy_state != null
		else EmberInteractionContent.shop_view(shop_id)
	)
	if shop.is_empty():
		close()
		return "лавка не найдена: %s" % shop_id
	_shop = shop
	_pending_shop_id = ""
	_mode = MODE_SHOP
	_set_panel_visual(MODE_SHOP)
	_shop_side = SHOP_BUY
	_shop_index = 0
	_shop_feedback = ""
	visible = true
	_refresh_shop()
	return ""


func _refresh_shop() -> void:
	if _mode != MODE_SHOP:
		return
	var shop_id := str(_shop.get("id", ""))
	if economy_state != null:
		_shop = economy_state.shop_view(shop_id)
	_title.text = "%s  ·  %d монет" % [
		str(_shop.get("nameRu", shop_id)),
		int(_shop.get("wallet", 0)),
	]
	var rows := _active_shop_rows()
	if rows.is_empty() and _shop_side == SHOP_SELL:
		_shop_index = 0
	else:
		_shop_index = clampi(_shop_index, 0, maxi(0, rows.size() - 1))
	var lines: Array[String] = []
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var marker := "▶" if index == _shop_index else " "
		if _shop_side == SHOP_BUY:
			var raw_stock: Variant = row.get("stock", null)
			var stock_text := "∞" if raw_stock == null else str(int(raw_stock))
			lines.append("%s %s  ·  %d мон.  ·  остаток %s" % [
				marker,
				str(row.get("nameRu", row.get("itemId", "?"))),
				int(row.get("buyPrice", 0)),
				stock_text,
			])
		else:
			lines.append("%s %s ×%d  ·  +%d мон." % [
				marker,
				str(row.get("nameRu", row.get("itemId", "?"))),
				int(row.get("count", 0)),
				int(row.get("sellPrice", 0)),
			])
	if lines.is_empty():
		lines.append("Нечего продавать" if _shop_side == SHOP_SELL else "Товаров нет")
	_body.text = "\n".join(lines)
	var buy_tab := "[КУПИТЬ]" if _shop_side == SHOP_BUY else "Купить"
	var sell_tab := "[ПРОДАТЬ]" if _shop_side == SHOP_SELL else "Продать"
	_choices.text = "%s    %s%s" % [
		buy_tab,
		sell_tab,
		("\n%s" % _shop_feedback) if not _shop_feedback.is_empty() else "",
	]
	_help.text = "A/D — купить/продать · W/S — товар · F — подтвердить · Esc — закрыть"


func _active_shop_rows() -> Array:
	var raw: Variant = _shop.get("sellable" if _shop_side == SHOP_SELL else "listings", [])
	return raw if typeof(raw) == TYPE_ARRAY else []


func _transact_shop_selection() -> void:
	if economy_state == null:
		_shop_feedback = "Состояние игры недоступно"
		_refresh_shop()
		return
	var rows := _active_shop_rows()
	if rows.is_empty() or _shop_index < 0 or _shop_index >= rows.size():
		_shop_feedback = "Нет доступного предмета"
		_refresh_shop()
		return
	var row: Dictionary = rows[_shop_index]
	var item_id := str(row.get("itemId", ""))
	var result := (
		economy_state.sell(str(_shop.get("id", "")), item_id)
		if _shop_side == SHOP_SELL
		else economy_state.buy(str(_shop.get("id", "")), item_id)
	)
	if bool(result.get("ok", false)):
		_shop_feedback = (
			"Продано: %s" if _shop_side == SHOP_SELL else "Куплено: %s"
		) % str(row.get("nameRu", item_id))
	else:
		_shop_feedback = _shop_failure_ru(str(result.get("reason", "")))
	_refresh_shop()


func _shop_failure_ru(reason: String) -> String:
	match reason:
		"stack_full":
			return "Нет места для этого товара"
		"broke":
			return "Не хватает монет"
		"out_of_stock":
			return "Товар закончился"
		"nothing_to_sell":
			return "Этого предмета нет"
		"unsellable":
			return "Этот предмет нельзя продать"
		"unknown_shop":
			return "Лавка не найдена"
		_:
			return "Предмет недоступен"


func _set_shop_side(side: String) -> void:
	if side != SHOP_BUY and side != SHOP_SELL:
		return
	_shop_side = side
	_shop_index = 0
	_shop_feedback = ""
	_refresh_shop()


func _move_shop_selection(delta: int) -> void:
	var rows := _active_shop_rows()
	if rows.is_empty():
		return
	_shop_index = posmod(_shop_index + delta, rows.size())
	_shop_feedback = ""
	_refresh_shop()


func _refresh_dialogue() -> void:
	_title.text = _dialogue.current_title()
	_body.text = _dialogue.current_text()
	_body.call_deferred("scroll_to_line", 0)
	var labels := _dialogue.choice_labels()
	var lines: Array[String] = []
	for index in range(labels.size()):
		var marker := "▶" if index == _selected_choice else " "
		lines.append("%s %d. %s" % [marker, index + 1, labels[index]])
	_choices.text = "\n".join(lines)
	_dialogue_controls.get_child(0).text = "Выбрать ответ · Enter" if not labels.is_empty() else "Продолжить · Enter"
	for child in _choice_buttons.get_children():
		_choice_buttons.remove_child(child)
		child.queue_free()
	for index in labels.size():
		var button := Button.new()
		button.name = "DialogueChoice_%d" % index
		button.text = ("▶ " if index == _selected_choice else "") + labels[index]
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(choose.bind(index))
		_choice_buttons.add_child(button)
	_help.text = "W/S — выбор · F / Enter — продолжить · H — история · Esc — закрыть" if not labels.is_empty() else "F / Enter — продолжить · H — история · Esc — закрыть"


func history_entries() -> Array[Dictionary]:
	return _dialogue.history_entries()


func is_history_open() -> bool:
	return _history_panel != null and _history_panel.visible


func toggle_history() -> void:
	if _mode != MODE_DIALOGUE:
		return
	var opening := not is_history_open()
	if opening:
		var lines: Array[String] = []
		for entry in _dialogue.history_entries():
			lines.append(str(entry.speaker) + "\n" + str(entry.text))
		_history_text.text = "\n\n".join(lines) if not lines.is_empty() else "Пока нет реплик."
		_history_text.call_deferred("scroll_to_line", maxi(0, _history_text.get_line_count() - 1))
	_history_panel.visible = opening
	_panel.visible = not opening


func _input(event: InputEvent) -> void:
	if _mode != MODE_DIALOGUE or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_H or (is_history_open() and key.physical_keycode == KEY_ESCAPE):
		toggle_history()
		get_viewport().set_input_as_handled()
	elif is_history_open() and key.physical_keycode in [KEY_F, KEY_ENTER, KEY_KP_ENTER, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]:
		get_viewport().set_input_as_handled()


func _build_history_panel() -> void:
	_history_panel = PanelContainer.new()
	_history_panel.name = "DialogueHistory"
	_history_panel.anchor_left = 0.08
	_history_panel.anchor_top = 0.10
	_history_panel.anchor_right = 0.92
	_history_panel.anchor_bottom = 0.94
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.045, 0.03, 0.065, 0.99)
	_history_panel.add_theme_stylebox_override("panel", background)
	add_child(_history_panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	_history_panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := Label.new()
	title.text = "История разговора"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var back := Button.new()
	back.text = "Вернуться · H / Esc"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(toggle_history)
	row.add_child(back)
	_history_text = RichTextLabel.new()
	_history_text.name = "Transcript"
	_history_text.bbcode_enabled = false
	_history_text.selection_enabled = true
	_history_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_text.add_theme_font_size_override("normal_font_size", 20)
	column.add_child(_history_text)
	_history_panel.hide()


func _build_panel() -> void:
	_panel = ColorRect.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.08
	_panel.anchor_top = 0.62
	_panel.anchor_right = 0.92
	_panel.anchor_bottom = 0.94
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 25)
	_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.34))
	column.add_child(_title)

	_body = RichTextLabel.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("normal_font_size", 20)
	_body.bbcode_enabled = false
	_body.selection_enabled = true
	column.add_child(_body)

	_choices = Label.new()
	_choices.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choices.add_theme_font_size_override("font_size", 18)
	_choices.add_theme_color_override("font_color", Color(0.85, 0.91, 1.0))
	column.add_child(_choices)
	_choice_buttons = VBoxContainer.new()
	column.add_child(_choice_buttons)
	_dialogue_controls = HBoxContainer.new()
	column.add_child(_dialogue_controls)
	for spec in [["Продолжить · Enter", advance], ["История · H", toggle_history], ["Закрыть", close]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(spec[1])
		_dialogue_controls.add_child(button)

	_help = Label.new()
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(0.68, 0.66, 0.72))
	column.add_child(_help)
	_build_history_panel()
	_set_panel_visual(MODE_DIALOGUE)


func _set_panel_visual(mode: String) -> void:
	if _panel == null or _title == null:
		return
	var talking := mode == MODE_DIALOGUE
	_history_panel.hide()
	_panel.show()
	_dialogue_controls.visible = talking
	_choice_buttons.visible = talking
	_choices.visible = not talking
	_panel.anchor_top = 0.50 if talking else 0.62
	_body.scroll_to_line(0)
	match mode:
		MODE_REWARD:
			_panel.color = Color(0.13, 0.075, 0.015, 0.97)
			_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.32))
		MODE_WAIT:
			_panel.color = Color(0.025, 0.055, 0.095, 0.95)
			_title.add_theme_color_override("font_color", Color(0.56, 0.8, 1.0))
		_:
			_panel.color = Color(0.055, 0.03, 0.085, 0.94)
			_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.34))


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if is_history_open():
		return
	if _mode == MODE_DIALOGUE and key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		advance()
		get_viewport().set_input_as_handled()
		return
	if key.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	if _mode == MODE_SHOP:
		if key.physical_keycode == KEY_W or key.physical_keycode == KEY_UP:
			_move_shop_selection(-1)
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_S or key.physical_keycode == KEY_DOWN:
			_move_shop_selection(1)
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_A or key.physical_keycode == KEY_LEFT:
			_set_shop_side(SHOP_BUY)
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_D or key.physical_keycode == KEY_RIGHT:
			_set_shop_side(SHOP_SELL)
			get_viewport().set_input_as_handled()
		return
	if _mode != MODE_DIALOGUE or _dialogue.current_kind() != "choice":
		return
	var labels := _dialogue.choice_labels()
	if labels.is_empty():
		return
	if key.physical_keycode == KEY_W or key.physical_keycode == KEY_UP:
		_selected_choice = posmod(_selected_choice - 1, labels.size())
		_refresh_dialogue()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_S or key.physical_keycode == KEY_DOWN:
		_selected_choice = posmod(_selected_choice + 1, labels.size())
		_refresh_dialogue()
		get_viewport().set_input_as_handled()
	elif key.unicode >= 49 and key.unicode <= 57:
		choose(int(key.unicode - 49))
		get_viewport().set_input_as_handled()
