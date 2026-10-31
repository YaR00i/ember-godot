@tool
class_name EmberStoryDialogueCue
extends Resource
## Timing only. Dialogue content/choices retain their existing Resource owner.
@export_range(0.0, 3600.0, 0.1) var time := 0.0
@export var dialogue: EmberDialogueResource
