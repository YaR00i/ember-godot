@tool
extends Resource
## Editor-only preset. Geometry is the existing canonical voxel Resource.
@export var display_name := "Штамп"
@export var geometry: EmberVoxelModelResource
@export_range(0,2) var anchor := 1
