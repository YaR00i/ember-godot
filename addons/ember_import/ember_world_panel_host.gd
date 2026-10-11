@tool
extends RefCounted
## One UI route for world tool panels. Tool sessions retain their data/preview/commit.
## Routes provide page, pending/cancel and optional open/close/history callbacks.
## The WorldEditor adapter presents the dock/bottom panel and restores its workspace.

var active_id := ""
var return_terrain := false
var _owner: WeakRef
var _routes: Dictionary = {}
var _toolbars: Array[Dictionary] = []

func configure(owner: Node) -> void:
	_owner = weakref(owner)

func register_panel(id: String, page: Control, options: Dictionary = {}) -> void:
	_routes[id] = options.duplicate(); _routes[id]["page"] = page

func is_active(id: String) -> bool:
	return active_id == id

func any_active() -> bool:
	return not active_id.is_empty()

func blocks_viewport_tools() -> bool:
	return any_active() and not bool(_routes[active_id].get("viewport_tools",false))

func can_leave() -> bool:
	if not any_active(): return true
	var route: Dictionary = _routes[active_id]
	var pending: Callable = route.get("pending",Callable())
	if pending.is_valid() and pending.call():
		var blocked: Callable = route.get("blocked",Callable())
		if blocked.is_valid(): blocked.call()
		reveal(); return false
	cancel_active(); return true

func open(id: String) -> bool:
	if not _routes.has(id): return false
	if is_active(id): reveal(); return true
	if not can_leave(): return false
	var owner: Node = _owner.get_ref()
	if owner == null: return false
	return_terrain = owner._terrain_workspace.visible
	var route: Dictionary = _routes[id]
	if bool(route.get("prepare_tools",true)): owner._prepare_parameter_panel()
	if bool(route.get("hide_toolbars",true)):
		for control in owner._parameter_toolbars():
			if is_instance_valid(control):
				_toolbars.append({"node": weakref(control),"visible": control.visible}); control.hide()
	active_id = id
	var opened: Callable = route.get("opened",Callable())
	if opened.is_valid(): opened.call()
	reveal(); return true

func reveal() -> void:
	if not any_active(): return
	var owner: Node = _owner.get_ref()
	if owner == null: return
	for route in _routes.values():
		var page: Control = route.page
		if is_instance_valid(page): page.hide()
	owner._present_parameter_panel(_routes[active_id])

func close(id: String) -> void:
	if not is_active(id): return
	var route: Dictionary = _routes[id]
	active_id = ""
	var closed: Callable = route.get("closed",Callable())
	if closed.is_valid(): closed.call()
	var owner: Node = _owner.get_ref()
	if owner != null: owner._hide_parameter_panel(route)
	for saved in _toolbars:
		var control: Control = saved.node.get_ref()
		if is_instance_valid(control): control.visible = saved.visible
	_toolbars.clear()
	if owner != null: owner._restore_parameter_workspace(return_terrain)

func cancel_active() -> void:
	if not any_active(): return
	var id := active_id
	var cancel: Callable = _routes[id].get("cancel",Callable())
	if cancel.is_valid(): cancel.call()
	if is_active(id): close(id)

func scene_changed() -> void:
	if not any_active(): return
	if bool(_routes[active_id].get("persist_scene",false)): return_terrain = false
	else: cancel_active()

func forward_input(event: InputEvent, focus: Control) -> int:
	if not blocks_viewport_tools(): return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and not event.echo and not (focus is LineEdit or focus is TextEdit):
		var key: Callable = _routes[active_id].get("history_key",Callable())
		if key.is_valid() and key.call(event): return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_ESCAPE:
			cancel_active(); return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func release() -> void:
	_routes.clear(); _toolbars.clear(); _owner = null; active_id = ""
