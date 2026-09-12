@tool
extends Resource
## Editor-only preset. Geometry is the existing canonical voxel Resource.
const KIND_VOLUME := 0
const KIND_PATTERN := 1
const KIND_GENERATED_VOLUME := 2

@export var display_name := "Штамп"
@export var geometry: EmberVoxelModelResource
@export_range(0,2) var anchor := 1
@export_enum("Объёмный штамп", "Плоский паттерн", "Процедурный объём") var kind := KIND_VOLUME
@export var pattern_size := Vector2i(8,8)
@export_range(1,32,1) var pattern_depth := 1
@export var generator_recipe: Resource

# Transient derived cache. Only the recipe and primary geometry are serialized.
var generated_variants: Array[EmberVoxelModelResource] = []
var generated_variants_key := ""
