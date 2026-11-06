@tool
extends MeshInstance3D
## A bowl supplies its own waterline while sharing the world's water shader.

const CONTACT_GROUP := &"ember_water_contacts"
const SHARED_WATER := "res://prefabs/items/shared_world_water.tscn"
const RIPPLE_FIELD := preload("res://scripts/prototypes/ember_compact_ripple_field.gd")
const BASIN_WAVE_SCALE := 0.42 / 3.2
const SHARED_PARAMETERS := [
	"shallow_color", "deep_color", "water_color_softness", "water_density", "water_transparency",
	"water_glint_strength", "refraction_strength",
	"object_foam_strength", "object_foam_width_voxels", "object_foam_sharpness",
	"ripple_cell_scale", "ripple_morph_strength", "ripple_morph_speed",
	"foam_width_pulse", "reaction_strength", "reaction_spread_speed", "reaction_opening",
	"reaction_birth_seconds",
]

@export var water_depth := 0.0

var _material: ShaderMaterial
var _bounds: AABB
var _units_per_metre := 16.0
var _uniforms := preload("res://scripts/ember_water_surface_contacts.gd").new()
var _has_contacts := false


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	var source := get_active_material(0) as ShaderMaterial
	if source == null:
		set_process(false)
		return
	_bounds = get_aabb()
	_material = source.duplicate() as ShaderMaterial
	var authored_scale: Variant = _material.get_shader_parameter("world_units_per_metre")
	if authored_scale is float and authored_scale > 0.0:
		_units_per_metre = authored_scale
	var preset: Node = load(SHARED_WATER).instantiate()
	var values: Dictionary = preset.water_settings_snapshot()
	preset.free()
	for key in SHARED_PARAMETERS:
		_material.set_shader_parameter(key, values[key])
	_material.set_shader_parameter("sky_reflection_strength", values.sky_reflection)
	_material.set_shader_parameter("sky_reflection_roughness", values.sky_roughness)
	_material.set_shader_parameter("deep_start_blocks", values.water_color_start_m * _units_per_metre / 16.0)
	_material.set_shader_parameter("deep_end_blocks", values.water_color_end_m * _units_per_metre / 16.0)
	_material.set_shader_parameter("wave_height_voxels", values.wave_height_voxels * BASIN_WAVE_SCALE * _units_per_metre / 16.0)
	_material.set_shader_parameter("water_level_offset_voxels", 0.0)
	_material.set_shader_parameter("ripple_cell_field", RIPPLE_FIELD.texture())
	_material.set_shader_parameter("ripple_field_available", 1.0)
	_material.set_shader_parameter("water_level_world", to_global(_bounds.get_center()).y)
	material_override = _material
	add_to_group(&"ember_water_surface_projection")


func water_surface_sample(point: Vector3) -> Dictionary:
	var local := to_local(point)
	var center := _bounds.get_center()
	var radii := Vector2(_bounds.size.x, _bounds.size.z) * 0.5
	if radii.x <= 0.0 or radii.y <= 0.0 or local.y < center.y - water_depth - 0.1:
		return {"wet": false}
	var relative := Vector2(local.x - center.x, local.z - center.z) / radii
	if relative.length_squared() >= 1.0:
		return {"wet": false}
	return {"wet": true, "position": to_global(Vector3(local.x, center.y, local.z)),
		"block_world_size": _units_per_metre, "flow": Vector2.ZERO}


func water_revision() -> int:
	return 0


func uses_integrated_water_contacts() -> bool:
	return true


func _process(_delta: float) -> void:
	var contacts: Array[EmberWaterContact3D] = []
	for node in get_tree().get_nodes_in_group(CONTACT_GROUP):
		var contact := node as EmberWaterContact3D
		if contact != null and contact._projection == self:
			if contact.is_contact_visible() or contact.wake_sample_count() > 0:
				contacts.append(contact)
	if contacts.is_empty() and not _has_contacts:
		return
	_has_contacts = not contacts.is_empty()
	var level := to_global(_bounds.get_center()).y
	_uniforms.update(contacts, _units_per_metre, false, _footprint.bind(level),
		_has_wake, _set_parameter)


func _footprint(contact: EmberWaterContact3D, level: float) -> Dictionary:
	return contact.water_interaction_shape(level) if contact.is_contact_visible() else {}


func _has_wake(contact: EmberWaterContact3D) -> bool:
	return contact.wake_sample_count() > 0


func _set_parameter(key: String, value: Variant) -> void:
	if _material.get_shader_parameter(key) != value:
		_material.set_shader_parameter(key, value)
