@tool
extends Resource

@export var skies: Array[Sky] = []
@export var weather: Array[Environment] = []
@export var npc_models: Array[PackedScene] = []
@export_group("Для новых карт")
@export var default_sky: Sky
@export var default_weather: Environment
@export var default_npc_model: PackedScene
