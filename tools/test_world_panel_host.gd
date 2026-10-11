extends SceneTree

const PanelHost = preload("res://addons/ember_import/ember_world_panel_host.gd")
var errors: Array[String] = []

class Workspace extends Node:
	var _terrain_workspace := VBoxContainer.new()
	var bars: Array[Control] = [Control.new(),Control.new()]
	var prepared := 0
	var shown: Control
	var restored := false
	func _init() -> void:
		add_child(_terrain_workspace)
		for bar in bars: add_child(bar)
	func _prepare_parameter_panel() -> void: prepared += 1
	func _parameter_toolbars() -> Array: return bars
	func _present_parameter_panel(route: Dictionary) -> void:
		_terrain_workspace.hide(); shown = route.page; shown.show()
	func _hide_parameter_panel(route: Dictionary) -> void: route.page.hide()
	func _restore_parameter_workspace(terrain: bool) -> void:
		restored = terrain; _terrain_workspace.visible = terrain

func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var workspace := Workspace.new(); root.add_child(workspace)
	workspace.bars[1].hide()
	var host := PanelHost.new(); host.configure(workspace)
	var a := Control.new(); var b := Control.new(); workspace.add_child(a); workspace.add_child(b)
	var state := {"pending":false,"blocked":0,"cancelled":0,"keys":0,"closed":0}
	host.register_panel("a",a,{
		"pending":func(): return state.pending,
		"blocked":func(): state.blocked += 1,
		"cancel":func(): state.cancelled += 1; host.close("a"),
		"closed":func(): state.closed += 1})
	host.register_panel("b",b)
	check(not host.open("missing") and not host.any_active(),"unknown route changed state")
	check(host.open("a") and host.blocks_viewport_tools() and workspace.prepared == 1,"open did not own input/preparation")
	check(not workspace.bars[0].visible and not workspace.bars[1].visible,"open did not hide toolbars")
	check(host.open("a") and workspace.prepared == 1 and host.return_terrain,"repeat open reset context")
	state.pending = true
	check(not host.open("b") and host.is_active("a") and state.blocked == 1 and state.cancelled == 0,"switch discarded pending work")
	var key := InputEventKey.new(); key.keycode = KEY_ESCAPE; key.pressed = true
	var field := LineEdit.new(); workspace.add_child(field)
	check(host.forward_input(key,field) == EditorPlugin.AFTER_GUI_INPUT_PASS and host.is_active("a"),"Escape in text cancelled panel")
	var camera := InputEventMouseMotion.new(); camera.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(host.forward_input(camera,null) == EditorPlugin.AFTER_GUI_INPUT_PASS,"panel blocked camera")
	check(host.forward_input(key,null) == EditorPlugin.AFTER_GUI_INPUT_STOP and not host.any_active(),"viewport Escape did not cancel")
	check(state.cancelled == 1 and state.closed == 1 and workspace.restored,"reentrant cancel failed or lost workspace")
	check(workspace.bars[0].visible and not workspace.bars[1].visible,"close changed prior toolbar visibility")
	state.pending = false
	host.open("a"); check(host.open("b") and state.cancelled == 2,"clean switch did not cancel old route")
	check(not a.visible and b.visible,"registered pages overlap after switch")
	host.close("a"); check(host.is_active("b") and b.visible,"late close hid current panel")
	host.scene_changed(); check(not host.any_active(),"scene-bound route survived scene change")
	host.register_panel("material",a,{
		"persist_scene":true,"pending":func(): return true,
		"history_key":func(event): state.keys += 1; return event.ctrl_pressed})
	host.open("material"); host.scene_changed()
	check(host.is_active("material") and not host.return_terrain,"independent draft lost on scene switch")
	key.keycode = KEY_Z; key.ctrl_pressed = true
	check(host.forward_input(key,null) == EditorPlugin.AFTER_GUI_INPUT_STOP and state.keys == 1,"history key not routed")
	host.forward_input(key,field); check(state.keys == 1,"panel stole text history")
	host.cancel_active(); check(not workspace._terrain_workspace.visible,"material restored old scene workspace")
	host.register_panel("objects",b,{"viewport_tools":true,"prepare_tools":false})
	var prepared := workspace.prepared
	host.open("objects")
	check(host.any_active() and not host.blocks_viewport_tools() and workspace.prepared == prepared,"brush did not retain viewport input")
	host.cancel_active(); host.release(); check(not host.any_active() and not host.open("a"),"release retained routes")
	workspace.free()
	print("WORLD_PANEL_HOST ","PASS" if errors.is_empty() else "FAIL"," repeat/pending/cancel/late-close/toolbar/return/scene/input/history/release errors=",errors)
	quit(0 if errors.is_empty() else 1)
