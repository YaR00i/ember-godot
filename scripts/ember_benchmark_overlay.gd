class_name EmberBenchmarkOverlay
extends Label
## Session-only native rendering diagnostics; never modifies authored materials.

const SHADOW_PROFILES := [0, 2, 4, 8, 12, 16]
const SAMPLE_COUNT := 240

var map: EmberMapLoader
var _samples := PackedFloat32Array()
var _sample_cursor := 0
var _sample_size := 0
var _refresh_left := 0.0
var _profile_index := 2
var _viewport_rid := RID()
var _cutaway_preview := false
var _geometry_view := 0
var _original_debug_draw := Viewport.DEBUG_DRAW_DISABLED
var _original_lod_threshold := 1.0
var _automatic_lod := true
var _owns_geometry_view := false


func _ready() -> void:
	_samples.resize(SAMPLE_COUNT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(14, 52)
	add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	add_theme_constant_override("shadow_offset_x", 2)
	add_theme_constant_override("shadow_offset_y", 2)
	if map:
		_profile_index = SHADOW_PROFILES.find(map.omni_shadow_count)
		if _profile_index < 0:
			_profile_index = 2
	var viewport := get_viewport()
	if viewport:
		_automatic_lod = viewport.mesh_lod_threshold > 0.0
		_viewport_rid = viewport.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)


func _exit_tree() -> void:
	if _owns_geometry_view and is_instance_valid(get_viewport()):
		get_viewport().debug_draw = _original_debug_draw
		get_viewport().mesh_lod_threshold = _original_lod_threshold
	if _viewport_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F2:
		if key.shift_pressed:
			set_geometry_lod_enabled(not _automatic_lod)
		else:
			set_geometry_view((_geometry_view + 1) % 3)
		visible = true
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F4:
		_profile_index = (_profile_index + 1) % SHADOW_PROFILES.size()
		if map:
			map.set_lighting_test_profile(SHADOW_PROFILES[_profile_index])
		visible = true
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F7 and map and map.cutaway_section_count() > 0:
		_cutaway_preview = not _cutaway_preview
		map.set_cutaway_preview(_cutaway_preview)
		visible = true
		get_viewport().set_input_as_handled()

func _remember_geometry_view() -> void:
	if _owns_geometry_view:
		return
	var viewport := get_viewport()
	_original_debug_draw = viewport.debug_draw
	_original_lod_threshold = viewport.mesh_lod_threshold
	_automatic_lod = _original_lod_threshold > 0.0
	_owns_geometry_view = true


func set_geometry_view(mode: int) -> void:
	_remember_geometry_view()
	_geometry_view = clampi(mode, 0, 2)
	get_viewport().debug_draw = [
		_original_debug_draw, Viewport.DEBUG_DRAW_LIGHTING, Viewport.DEBUG_DRAW_WIREFRAME,
	][_geometry_view]
	_reset_samples()


func set_geometry_lod_enabled(enabled: bool) -> void:
	_remember_geometry_view()
	_automatic_lod = enabled
	var restored_threshold := _original_lod_threshold if _original_lod_threshold > 0.0 else 1.0
	get_viewport().mesh_lod_threshold = restored_threshold if enabled else 0.0
	_reset_samples()


func _reset_samples() -> void:
	_sample_cursor = 0
	_sample_size = 0
	_refresh_left = 0.0


func _process(delta: float) -> void:
	_samples[_sample_cursor] = delta * 1000.0
	_sample_cursor = (_sample_cursor + 1) % SAMPLE_COUNT
	_sample_size = mini(_sample_size + 1, SAMPLE_COUNT)
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.25
	text = _summary()


func _summary() -> String:
	var cpu_ms := 0.0
	var gpu_ms := 0.0
	var visible_draws := 0
	var shadow_draws := 0
	var visible_primitives := 0
	var shadow_primitives := 0
	if _viewport_rid.is_valid():
		cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid)
		gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
		visible_draws = RenderingServer.viewport_get_render_info(
			_viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,
		)
		shadow_draws = RenderingServer.viewport_get_render_info(
			_viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,
		)
		visible_primitives=RenderingServer.viewport_get_render_info(_viewport_rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		shadow_primitives=RenderingServer.viewport_get_render_info(_viewport_rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var budget := map.omni_shadow_count if map else 0
	var atlas := map.lamp_shadow_size if map else 0
	return "\n".join([
		"ДИАГНОСТИКА · F2 вид · Shift+F2 LOD · F3 скрыть · F4 свет · F7 крыша",
		"Вид: %s · LOD: %s" % [["обычный","без материалов (свет прежний)","сетка фактической геометрии"][_geometry_view],"автоматически по камере" if _automatic_lod else "полная геометрия, LOD выключены"],
		"Служебный вид меняет alpha/vertex эффекты; это диагностика, не игровой FPS PASS." if _geometry_view>0 else "Плотность, дальность, физика и исходные материалы сохраняются.",
		"локальные тени: %d/%d · budget %d · atlas %d" % [
			map.omni_shadow_active_count() if map else 0,
			map.omni_shadow_candidate_count() if map else 0,
			budget,
			atlas,
		],
		"cutaway: %d/%d открыто" % [
			map.cutaway_active_count() if map else 0,
			map.cutaway_section_count() if map else 0,
		],
		"FPS окна %.0f · frame p95 %.2f ms" % [_window_fps(), _p95_ms()],
		"render CPU %.2f ms · GPU %.2f ms" % [cpu_ms, gpu_ms],
		"draw calls visible %d · shadow %d" % [visible_draws, shadow_draws],
		"примитивы проходов visible %d · shadow %d" % [visible_primitives,shadow_primitives],
	])


func _window_fps() -> float:
	var total_ms := 0.0
	for i in _sample_size:
		total_ms += _samples[i]
	return 1000.0 * _sample_size / total_ms if total_ms > 0.0 else 0.0


func _p95_ms() -> float:
	if _sample_size == 0:
		return 0.0
	var sorted := PackedFloat32Array()
	sorted.resize(_sample_size)
	for i in _sample_size:
		sorted[i] = _samples[i]
	sorted.sort()
	var index := clampi(ceili(_sample_size * 0.95) - 1, 0, _sample_size - 1)
	return sorted[index]
