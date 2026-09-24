@tool
class_name EmberVoxelEditorPerfMonitor
extends RefCounted
## Canvas-specific rendering diagnostics.
## Shadow objects are pass submissions, not unique scene nodes: one object may
## appear multiple times for different lights or directional shadow splits.


static func enable_viewport_measurement(viewport: SubViewport) -> void:
	if viewport == null:
		return
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)


static func snapshot(
	viewport: SubViewport,
	render_chunks: int,
	pending_chunks: int,
	context_report: Dictionary,
	studio_shadows_enabled: bool,
) -> Dictionary:
	var result := {
		"fps": Engine.get_frames_per_second(),
		"visible_draw_calls": 0,
		"visible_objects": 0,
		"visible_primitives": 0,
		"shadow_draw_calls": 0,
		"shadow_objects": 0,
		"shadow_primitives": 0,
		"canvas_cpu_ms": 0.0,
		"canvas_gpu_ms": 0.0,
		"frame_setup_cpu_ms": RenderingServer.get_frame_setup_time_cpu(),
		"msaa_3d": 0,
		"msaa_label": "Off",
		"studio_shadows": studio_shadows_enabled,
		"render_chunks": render_chunks,
		"pending_chunks": pending_chunks,
		"context_sources": int(context_report.get("source_count", 0)),
		"context_visuals": int(context_report.get("visual_count", 0)),
		"context_batched": int(context_report.get("batched_instances", 0)),
		"context_culled": int(context_report.get("culled_count", 0)),
	}
	if viewport != null:
		var rid := viewport.get_viewport_rid()
		var visible := _pass_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE)
		var shadow := _pass_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW)
		result.visible_draw_calls = int(visible.draw_calls)
		result.visible_objects = int(visible.objects)
		result.visible_primitives = int(visible.primitives)
		result.shadow_draw_calls = int(shadow.draw_calls)
		result.shadow_objects = int(shadow.objects)
		result.shadow_primitives = int(shadow.primitives)
		result.canvas_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(rid)
		result.canvas_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		result.msaa_3d = int(viewport.msaa_3d)
		result.msaa_label = msaa_label(viewport.msaa_3d)

	# Preserve the v1.3 snapshot keys for existing reports and consumers.
	result.draw_calls = result.visible_draw_calls
	result.objects = result.visible_objects
	result.primitives = result.visible_primitives
	return result


static func _pass_info(rid: RID, pass_type: int) -> Dictionary:
	return {
		"objects": RenderingServer.viewport_get_render_info(
			rid,
			pass_type as RenderingServer.ViewportRenderInfoType,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME,
		),
		"primitives": RenderingServer.viewport_get_render_info(
			rid,
			pass_type as RenderingServer.ViewportRenderInfoType,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME,
		),
		"draw_calls": RenderingServer.viewport_get_render_info(
			rid,
			pass_type as RenderingServer.ViewportRenderInfoType,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,
		),
	}


static func msaa_label(value: int) -> String:
	match value:
		Viewport.MSAA_2X:
			return "2x"
		Viewport.MSAA_4X:
			return "4x"
		Viewport.MSAA_8X:
			return "8x"
		_:
			return "Off"


static func short_text(values: Dictionary, chunk_size: int, mode_label: String) -> String:
	return (
		"FPS %d · V %d/%d · Sh %d/%d · CPU/GPU %.2f/%.2f ms · @%d %s · %s"
		% [
			int(values.get("fps", 0)),
			int(values.get("visible_draw_calls", 0)),
			int(values.get("visible_objects", 0)),
			int(values.get("shadow_draw_calls", 0)),
			int(values.get("shadow_objects", 0)),
			float(values.get("canvas_cpu_ms", 0.0)),
			float(values.get("canvas_gpu_ms", 0.0)),
			chunk_size,
			mode_label,
			str(values.get("msaa_label", "Off")),
		]
	)


static func tooltip_text(values: Dictionary) -> String:
	return (
		"Canvas viewport diagnostics\n"
		+ "Visible pass: %d draw · %d objects · %d primitives\n"
			% [
				int(values.get("visible_draw_calls", 0)),
				int(values.get("visible_objects", 0)),
				int(values.get("visible_primitives", 0)),
			]
		+ "Shadow pass: %d draw · %d submissions · %d primitives\n"
			% [
				int(values.get("shadow_draw_calls", 0)),
				int(values.get("shadow_objects", 0)),
				int(values.get("shadow_primitives", 0)),
			]
		+ "Canvas render CPU: %.3f ms\n" % float(values.get("canvas_cpu_ms", 0.0))
		+ "Canvas render GPU: %.3f ms\n" % float(values.get("canvas_gpu_ms", 0.0))
		+ "Global frame setup CPU: %.3f ms\n" % float(values.get("frame_setup_cpu_ms", 0.0))
		+ "Studio shadows: %s · MSAA: %s\n"
			% [
				"ON" if bool(values.get("studio_shadows", false)) else "OFF",
				str(values.get("msaa_label", "Off")),
			]
		+ "Render chunks: %d · pending: %d\n"
			% [
				int(values.get("render_chunks", 0)),
				int(values.get("pending_chunks", 0)),
			]
		+ "Context: %d sources → %d visuals · batch %d · culled %d"
			% [
				int(values.get("context_sources", 0)),
				int(values.get("context_visuals", 0)),
				int(values.get("context_batched", 0)),
				int(values.get("context_culled", 0)),
			]
	)
