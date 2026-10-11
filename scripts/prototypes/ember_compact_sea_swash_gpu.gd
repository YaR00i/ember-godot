@tool
extends RefCounted
## RenderingDevice bridge for the existing coast field, not another renderer.
## Static records are uploaded once. Updates send only the shared profile table.

var state_texture := Texture2DRD.new()
var foam_texture := Texture2DRD.new()
var ready := false
var error := ""
var dispatches := 0
var full_dispatches := 0
var border_dispatches := 0
var processed_records := 0
var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _uniforms := RID()
var _table := RID()
var _state := RID()
var _foam := RID()
var _resources: Array[RID] = []
var _released := false
var _count := 0
var _border_count := 0
var _border_uniforms := RID()


func initialize(size: Vector2i, records: PackedFloat32Array, initial_state: PackedByteArray, initial_foam: PackedByteArray) -> void:
	_count = records.size() / 8
	RenderingServer.call_on_render_thread(_initialize.bind(size, records.to_byte_array(), initial_state, initial_foam))


func update(table: PackedByteArray, constants: PackedByteArray, border_only := false) -> void:
	if not _released:
		RenderingServer.call_on_render_thread(_dispatch.bind(table, constants, border_only))


func configure_border(records: PackedFloat32Array) -> void:
	if _released: return
	_border_count = records.size() / 8
	if _border_count > 0:
		RenderingServer.call_on_render_thread(_initialize_border.bind(records.to_byte_array()))


func _initialize_border(records: PackedByteArray) -> void:
	if not ready: return
	var buffer := _rd.storage_buffer_create(records.size(), records)
	_resources.append(buffer)
	_border_uniforms = _make_uniforms(buffer)
	_resources.append(_border_uniforms)


func release() -> void:
	if _released: return
	_released = true
	# The same array is populated by queued initialization before queued cleanup.
	RenderingServer.call_on_render_thread(_free_resources.bind(_resources, state_texture, foam_texture))


func inherit_region(previous: RefCounted, source_offset: Vector2i, target_offset: Vector2i, size: Vector2i) -> void:
	if _released or previous._released: return
	# Initialization, copy and first dispatch are ordered on the render thread.
	# Old owner disposal can set its release flag before this queued copy runs,
	# but its queued RID cleanup comes after the copy and must not cancel it.
	RenderingServer.call_on_render_thread(_copy_region.bind(previous, source_offset, target_offset, size))


func _copy_region(previous: RefCounted, source_offset: Vector2i, target_offset: Vector2i, size: Vector2i) -> void:
	if not ready or not previous.ready: return
	for pair in [[previous._state, _state], [previous._foam, _foam]]:
		_rd.texture_copy(pair[0], pair[1], Vector3(source_offset.x, source_offset.y, 0),
			Vector3(target_offset.x, target_offset.y, 0), Vector3(size.x, size.y, 1), 0, 0, 0, 0)


func _initialize(size: Vector2i, records: PackedByteArray, initial_state: PackedByteArray, initial_foam: PackedByteArray) -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null: error = "Coast compute requires Forward+."; return
	var path := "res://shaders/ember_compact_sea_swash_compute.glsl"
	var spirv: RDShaderSPIRV
	if ResourceLoader.exists(path, "RDShaderFile"):
		# Imported bytecode also works when source GLSL is remapped in an export.
		var imported := load(path) as RDShaderFile
		if imported == null: error = "Coast compute shader is unavailable."; push_error(error); return
		error = imported.base_error
		if not error.is_empty(): push_error(error); return
		spirv = imported.get_spirv()
	else:
		# Standalone native fixtures can run before an editor import.
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string(path).replace("#[compute]", "")
		spirv = _rd.shader_compile_spirv_from_source(source)
	error = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty(): push_error(error); return
	_shader = _rd.shader_create_from_spirv(spirv)
	_resources.append(_shader)
	_pipeline = _rd.compute_pipeline_create(_shader)
	_resources.append(_pipeline)
	var record_buffer := _rd.storage_buffer_create(records.size(), records)
	_resources.append(record_buffer)
	_table = _rd.storage_buffer_create((2600 + 65) * 8)
	_resources.append(_table)
	_state = _texture(size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, initial_state)
	_foam = _texture(size, RenderingDevice.DATA_FORMAT_R32_SFLOAT, initial_foam)
	_uniforms = _make_uniforms(record_buffer)
	_resources.append(_uniforms)
	state_texture.texture_rd_rid = _state
	foam_texture.texture_rd_rid = _foam
	ready = _pipeline.is_valid() and _uniforms.is_valid()


func _make_uniforms(record_buffer: RID) -> RID:
	var bindings: Array[RDUniform] = []
	for spec in [[0, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, record_buffer],
		[1, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, _table],
		[2, RenderingDevice.UNIFORM_TYPE_IMAGE, _state], [3, RenderingDevice.UNIFORM_TYPE_IMAGE, _foam]]:
		var uniform := RDUniform.new()
		uniform.binding = spec[0]
		uniform.uniform_type = spec[1]
		uniform.add_id(spec[2])
		bindings.append(uniform)
	return _rd.uniform_set_create(bindings, _shader, 0)


func _texture(size: Vector2i, format: int, bytes: PackedByteArray) -> RID:
	var spec := RDTextureFormat.new()
	spec.format = format
	spec.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	spec.width = size.x
	spec.height = size.y
	spec.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var texture := _rd.texture_create(spec, RDTextureView.new(), [bytes])
	_resources.append(texture)
	return texture


func _dispatch(table: PackedByteArray, constants: PackedByteArray, border_only: bool) -> void:
	if not ready: return
	var count := _border_count if border_only else _count
	if count == 0: return
	_rd.buffer_update(_table, 0, table.size(), table)
	var commands := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(commands, _pipeline)
	_rd.compute_list_bind_uniform_set(commands, _border_uniforms if border_only else _uniforms, 0)
	_rd.compute_list_set_push_constant(commands, constants, constants.size())
	_rd.compute_list_dispatch(commands, ceili(float(count) / 64.0), 1, 1)
	_rd.compute_list_end()
	dispatches += 1
	processed_records += count
	if border_only: border_dispatches += 1
	else: full_dispatches += 1


static func _free_resources(resources: Array[RID], state: Texture2DRD, foam: Texture2DRD) -> void:
	state.texture_rd_rid = RID()
	foam.texture_rd_rid = RID()
	var device := RenderingServer.get_rendering_device()
	if device == null: return
	# Uniforms/pipeline before their dependencies; no dangling derived resources.
	for i in range(resources.size() - 1, -1, -1):
		if resources[i].is_valid(): device.free_rid(resources[i])
	resources.clear()
