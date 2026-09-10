@tool
class_name EmberVoxelModelResource
extends Resource
## Godot-owned editable source for one Ember voxel model.
## Meshes, collisions, thumbnails and PackedScenes are derived build products.

const SCHEMA_VERSION := 5
const WORLD_SURFACE_DIRECTORY := "res://content/world_surfaces"

@export_category("Identity")
@export var schema_version: int = SCHEMA_VERSION
@export var model_id := ""
@export var display_name := ""
@export var tags := PackedStringArray()

@export_category("Voxel grid")
@export_enum("16 vox/block:16", "32 vox/block:32") var voxels_per_block := 16
@export var size_blocks := Vector3i.ONE
@export_range(1, 256, 1) var height_voxels := 16
@export var palette := PackedColorArray()
@export var voxels := PackedByteArray()

@export_category("Material channels")
@export var emissive := PackedByteArray()
@export var shine := PackedByteArray()
@export var transparency := PackedByteArray()
@export var transmittance := PackedByteArray()
@export var material: Dictionary = {}

@export_category("Surface fill layers")
## Sparse-by-convention column channels for level fills. Empty arrays mean that
## the model predates the feature. A populated set has one value per X/Z column:
## level is the horizontal plane in art-voxel coordinates, material 0 is empty,
## and palette optionally supplies an authored tint (0 uses the material default).
## Terrain voxels remain untouched.
@export var surface_fill_levels := PackedInt32Array()
@export var surface_fill_materials := PackedByteArray()
@export var surface_fill_palette := PackedByteArray()

@export_category("Authoring groups")
## Named selection sets for the Godot authoring workflow. Runtime rendering and
## physics ignore these indices; locked sets are enforced by Surface Canvas.
@export var voxel_groups: Array[Dictionary] = []

@export_category("Merge parts")
## Exclusive provenance, independent of overlapping/optional selection groups.
## Zero means Added; positive values index merge_parts (one based).
## Empty channels keep old resources fully compatible.
@export var merge_parts: PackedStringArray = PackedStringArray()
@export var voxel_part_ids := PackedInt32Array()

@export_category("Physics and light")
@export var physical := true
@export var emissive_casts_light := false
@export_range(0.0, 128.0, 0.1) var emissive_light_range := 18.0
@export var emissive_light_shadows := false
@export var emissive_light_soft_rings := true
@export var emissive_light_soft_shadows := true
@export_range(0.0, 64.0, 0.05) var emissive_strength := 1.0
@export var emissive_suppress_host_shadow := false
@export var emissive_torch_flicker := false
@export var emissive_light_offset := Vector3.ZERO
@export var emissive_lights: Array[Dictionary] = []

@export_category("Migration provenance")
@export var imported_from := ""
@export var imported_source_hash := ""


func normalized_density() -> int:
	return 32 if voxels_per_block == 32 else 16


static func world_surface_path(map_id: String) -> String:
	## Shared by editor authoring and runtime fallback. A saved map Surface can
	## therefore be played before the scene's external-resource link is saved.
	var safe_id := map_id.strip_edges().to_lower().validate_filename().replace(" ", "_")
	if safe_id.is_empty():
		safe_id = "world_map"
	return "%s/%s_surface.tres" % [WORLD_SURFACE_DIRECTORY, safe_id]


func grid_size() -> Vector3i:
	var density := normalized_density()
	return Vector3i(
		maxi(1, size_blocks.x) * density,
		clampi(height_voxels, 1, 8 * density),
		maxi(1, size_blocks.z) * density,
	)


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if model_id.strip_edges().is_empty():
		errors.append("model_id is empty")
	if size_blocks.x < 1 or size_blocks.y < 1 or size_blocks.z < 1:
		errors.append("size_blocks must be positive")
	if palette.size() < 2 or palette.size() > 256:
		errors.append("palette must contain 2..256 colors")
	var expected := grid_size().x * grid_size().y * grid_size().z
	if merge_parts.is_empty() != voxel_part_ids.is_empty():
		errors.append("merge parts and ownership must be populated together")
	if not voxel_part_ids.is_empty():
		if voxel_part_ids.size() != expected:
			errors.append("voxel_part_ids must match the voxel grid")
		else:
			for index in voxel_part_ids.size():
				if voxel_part_ids[index] < 0 or voxel_part_ids[index] > merge_parts.size():
					errors.append("voxel part id is outside the parts library")
					break
				if index < voxels.size() and voxels[index] == 0 and voxel_part_ids[index] != 0:
					errors.append("empty voxels cannot belong to a merge part")
					break
	if voxels.size() != expected:
		errors.append("voxels has %d values; expected %d" % [voxels.size(), expected])
	var channels := {
		"emissive": emissive,
		"shine": shine,
		"transparency": transparency,
		"transmittance": transmittance,
	}
	for channel_name in channels:
		var values: PackedByteArray = channels[channel_name]
		if not values.is_empty() and values.size() != expected:
			errors.append("%s has %d values; expected %d" % [channel_name, values.size(), expected])
	var expected_columns := grid_size().x * grid_size().z
	var fill_channels := {
		"surface_fill_levels": surface_fill_levels,
		"surface_fill_materials": surface_fill_materials,
		"surface_fill_palette": surface_fill_palette,
	}
	for channel_name in fill_channels:
		var values: Variant = fill_channels[channel_name]
		if not values.is_empty() and values.size() != expected_columns:
			errors.append(
				"%s has %d values; expected %d" % [channel_name, values.size(), expected_columns]
			)
	var populated_fill_channels := 0
	for values in fill_channels.values():
		if not values.is_empty():
			populated_fill_channels += 1
	if populated_fill_channels > 0 and populated_fill_channels < fill_channels.size():
		errors.append("surface fill channels must be empty or populated together")
	var group_ids := {}
	for raw_group in voxel_groups:
		var group: Dictionary = raw_group
		var group_id := str(group.get("id", "")).strip_edges()
		if group_id.is_empty() or group_ids.has(group_id):
			errors.append("voxel group ids must be non-empty and unique")
			break
		group_ids[group_id] = true
		var previous := -1
		var indices: PackedInt32Array = group.get("indices", PackedInt32Array())
		for index in indices:
			if index < 0 or index >= expected or index <= previous:
				errors.append("voxel group %s indices must be sorted, unique and in bounds" % group_id)
				break
			previous = index
		if group.has("color") and not group["color"] is Color:
			errors.append("voxel group %s color must be Color" % group_id)
	return errors


func to_definition() -> Dictionary:
	var model := {
		"id": model_id,
		"nameRu": display_name,
		"tags": Array(tags),
		"voxelsPerBlock": normalized_density(),
		"sizeBlocks": {"x": size_blocks.x, "y": size_blocks.y, "z": size_blocks.z},
		"heightVoxels": height_voxels,
		"palette": _palette_hex(),
		"voxels": Array(voxels),
		"emissive": Array(emissive),
		"shine": Array(shine),
		"transparency": Array(transparency),
		"transmittance": Array(transmittance),
		"surfaceFillLevels": Array(surface_fill_levels),
		"surfaceFillMaterials": Array(surface_fill_materials),
		"surfaceFillPalette": Array(surface_fill_palette),
		"voxelGroups": voxel_groups.duplicate(true),
		"mergeParts": Array(merge_parts),
		"voxelPartIds": Array(voxel_part_ids),
		"material": material.duplicate(true),
		"physical": physical,
		"emissiveCastsLight": emissive_casts_light,
		"emissiveLightRange": emissive_light_range,
		"emissiveLightShadows": emissive_light_shadows,
		"emissiveLightSoftRings": emissive_light_soft_rings,
		"emissiveLightSoftShadows": emissive_light_soft_shadows,
		"emissiveStrength": emissive_strength,
		"emissiveSuppressHostShadow": emissive_suppress_host_shadow,
		"emissiveTorchFlicker": emissive_torch_flicker,
		"emissiveLightOffset": {
			"x": emissive_light_offset.x,
			"y": emissive_light_offset.y,
			"z": emissive_light_offset.z,
		},
		"emissiveLights": emissive_lights.duplicate(true),
	}
	return {
		"id": model_id,
		"nameRu": display_name,
		"tags": Array(tags),
		"model": model,
		"_nativeGodotVoxel": true,
		"_resourcePath": resource_path,
	}


func _palette_hex() -> Array:
	var result: Array = []
	for color in palette:
		result.append("#" + (color as Color).to_html(false))
	return result
