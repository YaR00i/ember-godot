@tool
extends ConfirmationDialog
## Owns only a pending navigation request. Surface data and save/restore stay
## with the workspace; a failed save must leave both the draft and dialog open.

var _pending: Callable
var _save: Callable
var _discard: Callable
var _cancel: Callable
var _discard_button: Button


func configure(save: Callable, discard: Callable) -> void:
	name = "SurfaceUnsavedNavigation"
	title = "Несохранённая поверхность"
	ok_button_text = "Сохранить и открыть"
	cancel_button_text = "Остаться"
	dialog_hide_on_ok = false
	_discard_button = add_button("Отбросить и открыть", false, "discard")
	_save = save
	_discard = discard
	confirmed.connect(_save_and_continue)
	custom_action.connect(_custom_action)
	canceled.connect(_cancel_request)


func request(display_name: String, continuation: Callable) -> void:
	_pending = continuation
	_cancel = Callable()
	ok_button_text = "Сохранить и открыть"
	cancel_button_text = "Остаться"
	_discard_button.text = "Отбросить и открыть"
	dialog_text = "«%s» содержит несохранённые правки. Что сделать перед открытием другой поверхности?" % display_name
	popup_centered(Vector2i(620, 160))


func request_close(display_name: String, continuation: Callable, cancel: Callable) -> void:
	_pending = continuation
	_cancel = cancel
	ok_button_text = "Сохранить и закрыть"
	cancel_button_text = "Остаться в Canvas"
	_discard_button.text = "Отбросить и закрыть"
	dialog_text = "«%s» содержит несохранённые правки. Что сделать перед выходом из Surface Canvas?" % display_name
	popup_centered(Vector2i(620, 160))


func clear_request() -> void:
	_pending = Callable()
	_cancel = Callable()


func _cancel_request() -> void:
	var cancel := _cancel
	clear_request()
	if cancel.is_valid():
		cancel.call()


func _save_and_continue() -> void:
	if _save.is_valid() and bool(_save.call()):
		_continue()
	else:
		dialog_text = "Сохранение не завершено. Подробности — в строке состояния Canvas. Правки остаются открытыми."


func _custom_action(action: StringName) -> void:
	if action == &"discard" and _discard.is_valid():
		_discard.call()
		_continue()


func _continue() -> void:
	var continuation := _pending
	clear_request()
	hide()
	if continuation.is_valid():
		continuation.call()
