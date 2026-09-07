@tool
class_name EmberVnPortrait
extends Resource
## Godot-owned metadata for one character expression portrait.

@export var speaker_id := ""
@export var portrait_key := "neutral"
@export var display_name := ""
@export_file var image_path := ""
@export var tags: PackedStringArray = []


func normalized_speaker_id() -> String:
	return speaker_id.strip_edges()


func normalized_portrait_key() -> String:
	return portrait_key.strip_edges()


func caption() -> String:
	var clean := display_name.strip_edges()
	return clean if not clean.is_empty() else normalized_portrait_key()
