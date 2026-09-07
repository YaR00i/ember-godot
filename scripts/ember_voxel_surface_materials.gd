@tool
class_name EmberVoxelSurfaceMaterials
extends RefCounted
## Surface-only material ownership. Generic transparent voxel props keep using
## EmberVoxelPrefab; terrain water gets a world-locked stylized shader.

const VoxelPrefab = preload("res://scripts/ember_voxel_prefab.gd")
const WATER_MATERIAL_PATH := "res://materials/ember_voxel_surface_water.tres"
const FOAM_MATERIAL_PATH := "res://materials/ember_voxel_surface_foam.tres"
const CONTACT_MATERIAL_PATH := "res://materials/ember_water_contact.tres"
const WAKE_MATERIAL_PATH := "res://materials/ember_water_wake.tres"


static func opaque_material() -> ShaderMaterial:
	return VoxelPrefab.voxel_material()


static func water_material() -> ShaderMaterial:
	var material := load(WATER_MATERIAL_PATH) as ShaderMaterial
	if material != null:
		return material
	push_warning("Ember Surface: water material is missing; using generic transparency")
	return VoxelPrefab.voxel_transparent_material()


static func foam_material() -> ShaderMaterial:
	var material := load(FOAM_MATERIAL_PATH) as ShaderMaterial
	if material != null:
		return material
	push_warning("Ember Surface: foam material is missing; using water material")
	return water_material()


static func contact_material() -> ShaderMaterial:
	var material := load(CONTACT_MATERIAL_PATH) as ShaderMaterial
	if material != null:
		return material
	push_warning("Ember Surface: contact material is missing; using foam material")
	return foam_material()


static func wake_material() -> ShaderMaterial:
	var material := load(WAKE_MATERIAL_PATH) as ShaderMaterial
	if material != null:
		return material
	push_warning("Ember Surface: water wake material is missing; using contact material")
	return contact_material()
