class_name EmberBenchmarkOverlay
extends Label
## Debug-only lighting comparison overlay. F3 toggles data; F4 cycles production and stress profiles.

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
		_viewport_rid = viewport.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)


func _exit_tree() -> void:
	if _viewport_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F3:
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
	var budget := map.omni_shadow_count if map else 0
	var atlas := map.lamp_shadow_size if map else 0
	return "\n".join([
		"LIGHT TEST · F3 скрыть · F4 профиль · F7 крыша",
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
		"FPS %.0f · frame p95 %.2f ms" % [Performance.get_monitor(Performance.TIME_FPS), _p95_ms()],
		"render CPU %.2f ms · GPU %.2f ms" % [cpu_ms, gpu_ms],
		"draw calls visible %d · shadow %d" % [visible_draws, shadow_draws],
	])


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
