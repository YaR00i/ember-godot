@tool
extends Resource
## Editor-only recipe. Baked geometry remains the canonical voxel source used
## by stamps or ordinary generated objects; runtime never evaluates recipes.

@export var generator_id := ""
@export var seed := 0
@export var parameters: Dictionary = {}
## Provider-owned authoring structure, never evaluated by gameplay.
@export var structure: Dictionary = {}
## Library grouping only. Scene instances still address a concrete model_id.
@export var family_id := ""
@export var family_title := ""
@export var variation_name := "Основной"
